//! Episode downloads, 4 at a time. Plain files download in 4 resumable parts;
//! HLS streams in 24 parallel segments (turned into .mp4 when ffmpeg is
//! installed); yt-dlp is the fallback and is fetched when missing. File names
//! follow the Plex/Jellyfin convention so media servers recognize them.

use crate::push;
use crate::meta::Meta;
use crate::sources;
use crate::{blogger, db, http, proxy};
use anyhow::{Context, Result, anyhow, bail};
use bytes::Bytes;
use futures_util::{StreamExt, TryStreamExt, stream::BoxStream};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncSeekExt, AsyncWriteExt, BufReader};
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;

const PARTS: u64 = 4;
const HLS_WORKERS: usize = 24;
const MIN_SIZE: u64 = 10 << 20;

#[derive(Clone, Debug, Deserialize)]
pub struct EpisodeRef {
    pub num: u32,
    pub url: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub source: String,
    pub name: String,
    /// The series page on the source; with the episode URLs it ties a file to
    /// what the player would otherwise stream.
    #[serde(default)]
    pub url: String,
    pub episodes: Vec<EpisodeRef>,
    #[serde(default)]
    pub quality: String,
    #[serde(default)]
    pub meta: Option<Meta>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Job {
    pub id: u64,
    pub title: String,
    pub episode: u32,
    pub path: String,
    pub state: String, // queued | resolving | downloading | remuxing | done | failed | cancelled
    pub method: String,
    pub progress: f64,
    pub bytes: u64,
    pub total: u64,
    pub speed: f64, // bytes/s
    pub error: String,
}

struct Entry {
    job: Job,
    cancel: CancellationToken,
    last_push: Instant,
}

static JOBS: LazyLock<Mutex<BTreeMap<u64, Entry>>> = LazyLock::new(Default::default);
static NEXT: AtomicU64 = AtomicU64::new(1);
static SLOTS: LazyLock<Arc<Semaphore>> = LazyLock::new(|| Arc::new(Semaphore::new(4)));

pub fn jobs() -> Vec<Job> {
    JOBS.lock().unwrap().values().map(|e| e.job.clone()).collect()
}

pub fn cancel(id: u64) {
    if let Some(e) = JOBS.lock().unwrap().get(&id) {
        e.cancel.cancel();
    }
}

pub fn clear_finished() {
    JOBS.lock().unwrap().retain(|_, e| !matches!(e.job.state.as_str(), "done" | "failed" | "cancelled"));
}

/// Updates a job and pushes it to QML (progress pushes throttled to 4/s).
fn update(id: u64, f: impl FnOnce(&mut Job)) {
    let mut map = JOBS.lock().unwrap();
    let Some(e) = map.get_mut(&id) else { return };
    let before = e.job.state.clone();
    f(&mut e.job);
    if e.job.state != before || e.last_push.elapsed() >= Duration::from_millis(250) {
        e.last_push = Instant::now();
        push("download", &serde_json::to_value(&e.job).unwrap_or_default());
    }
}

/// Deletes downloaded episodes, then their season and series folders once
/// empty. Only paths the library recorded are touched.
pub fn delete(paths: &[String]) -> Result<()> {
    for path in paths {
        if !db::remove_download(path)? {
            tracing::warn!("not deleting {path}: not a recorded download");
            continue;
        }
        let file = Path::new(path);
        match std::fs::remove_file(file) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e).with_context(|| format!("couldn't delete {path}")),
        }
        // remove_dir only removes empty folders, so other episodes stay put.
        for dir in file.ancestors().skip(1).take(2) {
            if std::fs::remove_dir(dir).is_err() {
                break;
            }
        }
    }
    Ok(())
}

pub fn base_dir(setting: &str) -> PathBuf {
    if !setting.is_empty() {
        return PathBuf::from(setting);
    }
    crate::dirs().videos.clone()
}

pub fn enqueue(req: Request, base: PathBuf) -> Result<Vec<u64>> {
    anyhow::ensure!(crate::plugins::find(&req.source).is_some(), "source {} isn't installed", req.source);
    let meta = req.meta.clone().unwrap_or_default();
    let title = if meta.title().is_empty() { req.name.clone() } else { meta.title().to_owned() };
    let mut ids = Vec::new();
    for ep in req.episodes {
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = episode_path(&base, &title, &req.name, &meta, ep.num);
        let cancel = CancellationToken::new();
        let job = Job { id, title: title.clone(), episode: ep.num, path: path.display().to_string(), state: "queued".into(), ..Default::default() };
        push("download", &serde_json::to_value(&job)?);
        JOBS.lock().unwrap().insert(id, Entry { job, cancel: cancel.clone(), last_push: Instant::now() });
        let (quality, src) = (req.quality.clone(), req.source.clone());
        let mut record = db::Download {
            source: req.source.clone(),
            series_url: req.url.clone(),
            series_name: req.name.clone(),
            episode_number: ep.num.into(),
            episode_url: ep.url.clone(),
            meta: meta.clone(),
            ..Default::default()
        };
        crate::RT.spawn(async move {
            let Ok(_slot) = SLOTS.clone().acquire_owned().await else { return };
            if cancel.is_cancelled() {
                update(id, |j| j.state = "cancelled".into());
                return;
            }
            let res = tokio::select! {
                r = run(id, &src, &ep.url, &quality, &path) => r,
                _ = cancel.cancelled() => Err(anyhow!("cancelled")),
            };
            match res {
                Ok(final_path) => {
                    record.path = final_path.display().to_string();
                    record.size = tokio::fs::metadata(&final_path).await.map(|m| m.len() as i64).unwrap_or(0);
                    if let Err(e) = db::add_download(&record) {
                        tracing::warn!("download {id}: couldn't record it in the library ({e:#})");
                    }
                    update(id, |j| {
                        j.state = "done".into();
                        j.progress = 1.0;
                        j.path = record.path.clone();
                    })
                }
                Err(e) if cancel.is_cancelled() => {
                    tracing::info!("download {id} cancelled: {e}");
                    update(id, |j| j.state = "cancelled".into());
                }
                Err(e) => {
                    tracing::warn!("download {id} failed: {e:#}");
                    update(id, |j| {
                        j.state = "failed".into();
                        j.error = format!("{e:#}");
                    });
                }
            }
        });
        ids.push(id);
    }
    Ok(ids)
}

async fn run(id: u64, src: &str, episode_url: &str, quality: &str, path: &Path) -> Result<PathBuf> {
    update(id, |j| j.state = "resolving".into());
    let stream = sources::stream(src, episode_url, quality).await?;
    if let Some(dir) = path.parent() {
        tokio::fs::create_dir_all(dir).await?;
    }
    let progress = |done: u64, total: u64, speed: f64| {
        update(id, |j| {
            j.state = "downloading".into();
            j.bytes = done;
            j.total = total;
            j.speed = speed;
            j.progress = if total > 0 { done as f64 / total as f64 } else { 0.0 };
        })
    };
    let url = stream.url.clone();
    let lower = url.to_lowercase();
    let result = if blogger::is_blogger(&url) {
        update(id, |j| j.method = "blogger".into());
        let direct = blogger::resolve(&url).await?;
        ranged(&Fetcher::Chrome, &direct, path, &progress).await.map(|_| path.to_owned())
    } else if proxy::is_wibufile(&url) {
        update(id, |j| j.method = "http3".into());
        ranged(&Fetcher::H3(stream.referer.clone()), &url, path, &progress).await.map(|_| path.to_owned())
    } else if lower.contains(".m3u8") {
        update(id, |j| j.method = "hls".into());
        match hls(&url, &stream.referer, path, id, &progress).await {
            Ok(p) => Ok(p),
            Err(e) if !cfg!(feature = "desktop") => Err(e),
            Err(e) => {
                tracing::info!("native HLS failed ({e:#}); falling back to yt-dlp");
                update(id, |j| j.method = "yt-dlp".into());
                ytdlp(&url, &stream.referer, path, &progress).await.map(|_| path.to_owned())
            }
        }
    } else {
        update(id, |j| j.method = "direct".into());
        match ranged(&Fetcher::Plain(stream.referer.clone()), &url, path, &progress).await {
            Ok(()) => Ok(path.to_owned()),
            Err(e) if !cfg!(feature = "desktop") => Err(e),
            Err(e) => {
                tracing::info!("direct download failed ({e:#}); falling back to yt-dlp");
                update(id, |j| j.method = "yt-dlp".into());
                ytdlp(&url, &stream.referer, path, &progress).await.map(|_| path.to_owned())
            }
        }
    }?;
    let size = tokio::fs::metadata(&result).await.map(|m| m.len()).unwrap_or(0);
    if size < MIN_SIZE {
        let _ = tokio::fs::remove_file(&result).await;
        bail!("download incomplete: file is only {:.1} MB", size as f64 / 1048576.0);
    }
    Ok(result)
}


enum Fetcher {
    /// Plain client with the source's Referer/Origin (pixeldrain, CDNs).
    Plain(String),
    /// Chrome fingerprint over HTTP/1.1 (googlevideo rejects anything else).
    Chrome,
    /// HTTP/3 with Referer (Wibufile).
    H3(String),
}

static CHROME_H1: LazyLock<wreq::Client> = LazyLock::new(|| {
    wreq::Client::builder()
        .emulation(wreq_util::Emulation::Chrome149)
        .http1_only()
        .redirect(wreq::redirect::Policy::limited(10))
        .build()
        .expect("download client")
});
static H3: LazyLock<reqwest::Client> = LazyLock::new(|| reqwest::Client::builder().http3_prior_knowledge().build().expect("h3 client"));

fn origin(referer: &str) -> Option<String> {
    url::Url::parse(referer).ok().map(|u| u.origin().ascii_serialization()).filter(|o| o != "null")
}

impl Fetcher {
    /// GET with an optional inclusive byte range → (status, content-length, body stream).
    async fn open(&self, url: &str, range: Option<(u64, u64)>) -> Result<(u16, u64, BoxStream<'static, Result<Bytes>>)> {
        let range = range.map(|(a, b)| format!("bytes={a}-{b}"));
        if let Fetcher::H3(referer) = self {
            let mut rb = H3.get(url).header("Referer", referer.as_str());
            if let Some(r) = &range {
                rb = rb.header("Range", r);
            }
            let resp = rb.send().await?;
            let len = resp.content_length().unwrap_or(0);
            return Ok((resp.status().as_u16(), len, resp.bytes_stream().map_err(anyhow::Error::from).boxed()));
        }
        let mut rb = match self {
            Fetcher::Chrome => CHROME_H1.get(url),
            _ => http::PLAIN.get(url).header("User-Agent", http::UA),
        };
        if let Fetcher::Plain(referer) = self
            && !referer.is_empty()
        {
            rb = rb.header("Referer", referer.as_str());
            if let Some(o) = origin(referer) {
                rb = rb.header("Origin", o);
            }
        }
        if let Some(r) = &range {
            rb = rb.header("Range", r);
        }
        let resp = rb.send().await?;
        let len = resp.content_length().unwrap_or(0);
        Ok((resp.status().as_u16(), len, resp.bytes_stream().map_err(anyhow::Error::from).boxed()))
    }

    async fn total_size(&self, url: &str) -> Result<u64> {
        let (status, len, _) = self.open(url, Some((0, 0))).await?;
        anyhow::ensure!(status == 206 || status == 200, "HTTP {status} probing file size");
        if status == 200 {
            return Ok(len);
        }
        // 206: real size is in Content-Range, so ask again without a range for the length.
        let (_, full, _) = self.open(url, None).await?;
        Ok(full)
    }
}

/// Speed meter shared by all parts of one file.
struct Meter {
    done: AtomicU64,
    total: u64,
    started: Instant,
}

/// 4 parallel Range parts written to `<dest>.partN` (resuming whatever a
/// previous attempt left), then concatenated. Each part retries a dropped
/// connection from where it stopped, up to 20 times without progress.
async fn ranged(f: &Fetcher, url: &str, dest: &Path, progress: &(impl Fn(u64, u64, f64) + Sync)) -> Result<()> {
    let total = f.total_size(url).await?;
    anyhow::ensure!(total > 0, "content length is zero");
    let chunk = total / PARTS;
    let meter = Meter { done: AtomicU64::new(0), total, started: Instant::now() };
    let parts = (0..PARTS).map(|i| {
        let from = i * chunk;
        let to = if i == PARTS - 1 { total - 1 } else { from + chunk - 1 };
        part(f, url, dest, i, from, to, &meter, progress)
    });
    futures_util::future::try_join_all(parts).await?;
    let mut out = tokio::fs::File::create(dest).await?;
    for i in 0..PARTS {
        let p = part_path(dest, i);
        let mut f = tokio::fs::File::open(&p).await?;
        tokio::io::copy(&mut f, &mut out).await?;
        tokio::fs::remove_file(&p).await?;
    }
    out.flush().await?;
    Ok(())
}

fn part_path(dest: &Path, i: u64) -> PathBuf {
    let mut s = dest.as_os_str().to_owned();
    s.push(format!(".part{i}"));
    PathBuf::from(s)
}

#[allow(clippy::too_many_arguments)]
async fn part(f: &Fetcher, url: &str, dest: &Path, i: u64, from: u64, to: u64, meter: &Meter, progress: &(impl Fn(u64, u64, f64) + Sync)) -> Result<()> {
    let path = part_path(dest, i);
    let have = tokio::fs::metadata(&path).await.map(|m| m.len()).unwrap_or(0).min(to - from + 1);
    let mut file = tokio::fs::OpenOptions::new().create(true).write(true).truncate(false).open(&path).await?;
    file.set_len(have).await?;
    file.seek(std::io::SeekFrom::Start(have)).await?;
    meter.done.fetch_add(have, Ordering::Relaxed);
    let mut current = from + have;
    let mut stale = 0;
    while current <= to {
        anyhow::ensure!(stale < 20, "part {i}: too many retries at {current}/{to}");
        let before = current;
        match f.open(url, Some((current, to))).await {
            Ok((206, _, mut body)) => {
                while let Some(chunk) = body.next().await {
                    let Ok(chunk) = chunk else { break };
                    let take = chunk.len().min((to + 1 - current) as usize);
                    file.write_all(&chunk[..take]).await?;
                    current += take as u64;
                    let done = meter.done.fetch_add(take as u64, Ordering::Relaxed) + take as u64;
                    progress(done, meter.total, done as f64 / meter.started.elapsed().as_secs_f64().max(0.001));
                    if current > to {
                        break;
                    }
                }
            }
            Ok((status, ..)) => bail!("part {i}: HTTP {status} (range not supported or link expired)"),
            Err(e) => tracing::debug!("part {i} request failed: {e}"),
        }
        if current == before {
            stale += 1;
            tokio::time::sleep(Duration::from_millis(500 * stale.min(6))).await;
        } else {
            stale = 0;
        }
    }
    file.flush().await?;
    Ok(())
}


#[derive(Debug, PartialEq)]
enum Playlist {
    Master { best: String, separate_audio: bool },
    Media { segments: Vec<String>, encrypted: bool },
}

static BANDWIDTH_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"BANDWIDTH=(\d+)").unwrap());

fn parse_playlist(text: &str, base: &str) -> Result<Playlist> {
    anyhow::ensure!(text.contains("#EXTM3U") || text.contains("#EXT-X-"), "not an HLS playlist");
    let base = url::Url::parse(base)?;
    let abs = |u: &str| base.join(u.trim()).map(String::from);
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    if lines.iter().any(|l| l.starts_with("#EXT-X-STREAM-INF:")) {
        let mut best: Option<(u64, String)> = None;
        for w in lines.windows(2) {
            if let Some(inf) = w[0].strip_prefix("#EXT-X-STREAM-INF:")
                && !w[1].starts_with('#')
            {
                let bw = BANDWIDTH_RE.captures(inf).and_then(|c| c[1].parse().ok()).unwrap_or(0);
                if best.as_ref().is_none_or(|(b, _)| bw > *b) {
                    best = Some((bw, abs(w[1])?));
                }
            }
        }
        let separate_audio = lines.iter().any(|l| l.starts_with("#EXT-X-MEDIA:") && l.contains("TYPE=AUDIO") && l.contains("URI="));
        return Ok(Playlist::Master { best: best.ok_or_else(|| anyhow!("master playlist has no variants"))?.1, separate_audio });
    }
    let encrypted = lines.iter().any(|l| l.starts_with("#EXT-X-KEY:") && !l.contains("METHOD=NONE"));
    let segments = lines.iter().filter(|l| !l.starts_with('#')).map(|l| abs(l)).collect::<Result<Vec<_>, _>>()?;
    anyhow::ensure!(!segments.is_empty(), "media playlist has no segments");
    Ok(Playlist::Media { segments, encrypted })
}

async fn hls(url: &str, referer: &str, dest: &Path, id: u64, progress: &(impl Fn(u64, u64, f64) + Sync)) -> Result<PathBuf> {
    let f = Fetcher::Plain(referer.to_owned());
    let get_text = |u: String| {
        let f = &f;
        async move {
            let (status, _, body) = f.open(&u, None).await?;
            anyhow::ensure!(status == 200, "playlist HTTP {status}");
            let bytes: Vec<Bytes> = body.try_collect().await?;
            Ok::<_, anyhow::Error>(String::from_utf8_lossy(&bytes.concat()).into_owned())
        }
    };
    let mut current = url.to_owned();
    let segments = loop {
        match parse_playlist(&get_text(current.clone()).await?, &current)? {
            Playlist::Master { best, separate_audio } => {
                anyhow::ensure!(!separate_audio, "separate audio rendition (needs yt-dlp)");
                current = best;
            }
            Playlist::Media { segments, encrypted } => {
                anyhow::ensure!(!encrypted, "encrypted HLS (needs yt-dlp)");
                break segments;
            }
        }
    };
    let ts = dest.with_extension("ts");
    let mut out = tokio::io::BufWriter::with_capacity(512 << 10, tokio::fs::File::create(&ts).await?);
    let count = segments.len() as u64;
    let started = Instant::now();
    let mut bytes = 0u64;
    let mut done = 0u64;
    // `buffered` keeps segment order while 24 downloads run ahead.
    let mut stream = futures_util::stream::iter(segments)
        .map(|seg| {
            let f = &f;
            async move {
                for attempt in 0..3u64 {
                    if let Ok((200 | 206, _, body)) = f.open(&seg, None).await
                        && let Ok(parts) = body.try_collect::<Vec<Bytes>>().await
                    {
                        return Ok(parts.concat());
                    }
                    tokio::time::sleep(Duration::from_millis(400 * (attempt + 1))).await;
                }
                Err(anyhow!("segment failed: {seg}"))
            }
        })
        .buffered(HLS_WORKERS);
    while let Some(seg) = stream.next().await {
        let seg = seg?;
        bytes += seg.len() as u64;
        done += 1;
        out.write_all(&seg).await?;
        // Size estimate from the average segment so far.
        progress(done * (bytes / done.max(1)), count * (bytes / done.max(1)), bytes as f64 / started.elapsed().as_secs_f64().max(0.001));
    }
    out.flush().await?;
    drop(out);
    if which("ffmpeg").is_some() {
        update(id, |j| j.state = "remuxing".into());
        let status = command("ffmpeg")
            .args(["-hide_banner", "-loglevel", "error", "-y", "-i"])
            .arg(&ts)
            .args(["-c", "copy", "-bsf:a", "aac_adtstoasc"])
            .arg(dest)
            .status()
            .await?;
        if status.success() {
            tokio::fs::remove_file(&ts).await?;
            return Ok(dest.to_owned());
        }
        tracing::warn!("ffmpeg remux failed; keeping the .ts");
    }
    Ok(ts)
}


/// The Windows release build has no console, so each console tool it starts
/// would pop up a console window of its own.
fn command(bin: impl AsRef<std::ffi::OsStr>) -> tokio::process::Command {
    #[cfg_attr(not(windows), allow(unused_mut))]
    let mut cmd = tokio::process::Command::new(bin);
    #[cfg(windows)]
    cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    cmd
}

pub fn which(bin: &str) -> Option<PathBuf> {
    let exe = if cfg!(windows) { format!("{bin}.exe") } else { bin.to_owned() };
    std::env::var_os("PATH").and_then(|p| std::env::split_paths(&p).map(|d| d.join(&exe)).find(|p| p.is_file()))
}

fn ytdlp_local() -> PathBuf {
    let name = if cfg!(windows) { "yt-dlp.exe" } else { "yt-dlp" };
    crate::dirs().data.join("bin").join(name)
}

/// System yt-dlp, else a copy fetched from its GitHub releases.
pub async fn ensure_ytdlp() -> Result<PathBuf> {
    if let Some(p) = which("yt-dlp") {
        return Ok(p);
    }
    let local = ytdlp_local();
    if local.is_file() {
        return Ok(local);
    }
    let asset = if cfg!(windows) { "yt-dlp.exe" } else if cfg!(target_os = "macos") { "yt-dlp_macos" } else { "yt-dlp" };
    let body = http::PLAIN
        .get(format!("https://github.com/yt-dlp/yt-dlp/releases/latest/download/{asset}"))
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?;
    tokio::fs::create_dir_all(local.parent().unwrap()).await?;
    tokio::fs::write(&local, body).await?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        tokio::fs::set_permissions(&local, std::fs::Permissions::from_mode(0o755)).await?;
    }
    Ok(local)
}

static YTDLP_PROGRESS_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^AIKATSU\|(\d+|NA)\|(\d+|NA)\|([\d.]+|NA)").unwrap());

async fn ytdlp(url: &str, referer: &str, dest: &Path, progress: &(impl Fn(u64, u64, f64) + Sync)) -> Result<()> {
    let bin = ensure_ytdlp().await?;
    let impersonate = command(&bin)
        .arg("--list-impersonate-targets")
        .output()
        .await
        .map(|o| String::from_utf8_lossy(&o.stdout).to_lowercase().contains("chrome"))
        .unwrap_or(false);
    let mut last_err = anyhow!("yt-dlp did not run");
    for _attempt in 0..2 {
        let mut cmd = command(&bin);
        // A user yt-dlp.conf could move or rename the output (-P, merge format).
        cmd.args(["--ignore-config", "-f", "bestvideo+bestaudio/best", "--concurrent-fragments", "24", "--hls-use-mpegts", "--socket-timeout", "30", "--no-part", "--newline"])
            .args(["--progress-template", "download:AIKATSU|%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s"]);
        if !referer.is_empty() {
            cmd.args(["--add-header", &format!("Referer:{referer}")]);
            if let Some(o) = origin(referer) {
                cmd.args(["--add-header", &format!("Origin:{o}")]);
            }
        }
        if impersonate {
            cmd.args(["--impersonate", "chrome"]);
        }
        // -o is a template, so a literal % in a title must be doubled. `--` keeps
        // a scraped URL like "--exec=..." from being parsed as an option.
        cmd.arg("-o").arg(dest.to_string_lossy().replace('%', "%%")).arg("--").arg(url).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).kill_on_drop(true);
        let mut child = cmd.spawn().context("failed to start yt-dlp")?;
        let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
        let run = async {
            while let Some(line) = lines.next_line().await? {
                if let Some(c) = YTDLP_PROGRESS_RE.captures(&line) {
                    let n = |i: usize| c[i].parse::<f64>().unwrap_or(0.0);
                    progress(n(1) as u64, n(2) as u64, n(3));
                }
            }
            anyhow::Ok(child.wait_with_output().await?)
        };
        match tokio::time::timeout(Duration::from_secs(3600), run).await {
            Ok(Ok(out)) if out.status.success() => return Ok(()),
            Ok(Ok(out)) => last_err = anyhow!("yt-dlp failed: {}", String::from_utf8_lossy(&out.stderr).lines().last().unwrap_or_default()),
            Ok(Err(e)) => last_err = e,
            Err(_) => last_err = anyhow!("yt-dlp timed out after 60 minutes"),
        }
    }
    Err(last_err)
}


pub fn sanitize(name: &str) -> String {
    let cleaned: String = name.chars().filter(|c| !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|')).collect();
    let cleaned = cleaned.trim_end_matches(['.', ' ']).split_whitespace().collect::<Vec<_>>().join(" ");
    if cleaned.is_empty() { "Unknown".into() } else { cleaned }
}

static SEASON_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\bseason\s+(\d+)\b|\b(\d+)\s*(?:st|nd|rd|th)?\s+season\b").unwrap());

/// `<base>/<Title (Year)> {anilist-ID} {mal-ID}/Season XX/<Title (Year)> - SXXEYY.mp4`
pub fn episode_path(base: &Path, title: &str, scraped_name: &str, meta: &Meta, ep: u32) -> PathBuf {
    let mut file_title = sanitize(title);
    if meta.year > 0 {
        file_title += &format!(" ({})", meta.year);
    }
    let mut folder = file_title.clone();
    if meta.anilist_id > 0 {
        folder += &format!(" {{anilist-{}}}", meta.anilist_id);
    }
    if meta.mal_id > 0 {
        folder += &format!(" {{mal-{}}}", meta.mal_id);
    }
    let (season, num) = if meta.season_map.is_empty() {
        let inferred = [scraped_name, &meta.title_english, &meta.title_romaji]
            .iter()
            .find_map(|t| SEASON_RE.captures(t).and_then(|c| c.get(1).or(c.get(2))?.as_str().parse::<u32>().ok()).filter(|&s| s > 1))
            .unwrap_or(1);
        (inferred, ep)
    } else {
        meta.absolute_to_season(ep)
    };
    base.join(folder).join(format!("Season {season:02}")).join(format!("{file_title} - S{season:02}E{num:02}.mp4"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::meta::SeasonRange;

    #[tokio::test]
    async fn parts_start_resume_and_trim() {
        use axum::{Router, http::{HeaderMap, StatusCode}, routing::get};

        const DATA: &[u8] = b"video data";
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let app = Router::new().route("/video", get(|headers: HeaderMap| async move {
            let range = headers["range"].to_str().unwrap().strip_prefix("bytes=").unwrap();
            let (from, to) = range.split_once('-').unwrap();
            let from: usize = from.parse().unwrap();
            let to: usize = to.parse().unwrap();
            (StatusCode::PARTIAL_CONTENT, &DATA[from..=to])
        }));
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let dir = std::env::temp_dir().join(format!("aikatsu-parts-{}-{}", std::process::id(), address.port()));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let dest = dir.join("episode.mp4");
        let path = part_path(&dest, 0);
        for seed in [None, Some(&DATA[..3]), Some(DATA), Some(b"video data stale".as_slice())] {
            if let Some(seed) = seed {
                tokio::fs::write(&path, seed).await.unwrap();
            }
            let meter = Meter { done: AtomicU64::new(0), total: DATA.len() as u64, started: Instant::now() };
            part(&Fetcher::Plain(String::new()), &format!("http://{address}/video"), &dest, 0, 0, meter.total - 1, &meter, &|_, _, _| {})
                .await
                .unwrap();
            assert_eq!(tokio::fs::read(&path).await.unwrap(), DATA);
            assert_eq!(meter.done.load(Ordering::Relaxed), meter.total);
            tokio::fs::remove_file(&path).await.unwrap();
        }
        server.abort();
        tokio::fs::remove_dir(&dir).await.unwrap();
    }

    #[test]
    fn plex_paths() {
        let meta = Meta {
            anilist_id: 21,
            mal_id: 21,
            year: 1999,
            season_map: vec![SeasonRange { season: 1, start: 1, end: 10 }, SeasonRange { season: 2, start: 11, end: 20 }],
            ..Default::default()
        };
        let p = episode_path(Path::new("/dl"), "One Piece: Film?", "x", &meta, 12);
        assert_eq!(p, Path::new("/dl/One Piece Film (1999) {anilist-21} {mal-21}/Season 02/One Piece Film (1999) - S02E02.mp4"));
        let p = episode_path(Path::new("/dl"), "Kimi", "Kimi Season 3", &Meta::default(), 4);
        assert_eq!(p, Path::new("/dl/Kimi/Season 03/Kimi - S03E04.mp4"));
    }

    #[test]
    fn hls_playlists() {
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2400000\nhigh/index.m3u8\n";
        assert_eq!(
            parse_playlist(master, "https://cdn/x/master.m3u8").unwrap(),
            Playlist::Master { best: "https://cdn/x/high/index.m3u8".into(), separate_audio: false }
        );
        let media = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:4,\nseg0.ts\n#EXTINF:4,\nhttps://other/seg1.ts\n";
        let Playlist::Media { segments, encrypted } = parse_playlist(media, "https://cdn/x/high/index.m3u8").unwrap() else { panic!() };
        assert!(encrypted);
        assert_eq!(segments, ["https://cdn/x/high/seg0.ts", "https://other/seg1.ts"]);
        assert!(parse_playlist("<html>", "https://cdn/").is_err());
    }

    /// `cargo test live_download -- --ignored --nocapture` (LIVE_DIR to keep the file).
    #[test]
    #[ignore]
    fn live_download() {
        let dir = std::env::var("LIVE_DIR").map(PathBuf::from).unwrap_or_else(|_| std::env::temp_dir().join("aikatsu-live"));
        let (src, url) = crate::RT.block_on(async {
            crate::plugins::ensure_installed().await;
            let found = sources::search("kyoko/ylnime", "frieren").await.unwrap();
            let eps = sources::episodes("kyoko/ylnime", &found[0].url).await.unwrap();
            (found[0].name.clone(), eps[0].url.clone())
        });
        let req = Request { source: "kyoko/ylnime".into(), name: src, url: String::new(), episodes: vec![EpisodeRef { num: 1, url }], quality: "360p".into(), meta: None };
        let id = enqueue(req, dir).unwrap()[0];
        let start = Instant::now();
        loop {
            std::thread::sleep(Duration::from_secs(2));
            let job = jobs().into_iter().find(|j| j.id == id).unwrap();
            println!("{} {:.0}% {:.1} MB/s {}", job.state, job.progress * 100.0, job.speed / 1e6, job.method);
            if matches!(job.state.as_str(), "done" | "failed") || start.elapsed() > Duration::from_secs(600) {
                assert_eq!(job.state, "done", "{}", job.error);
                println!("saved {}", job.path);
                break;
            }
        }
    }
}
