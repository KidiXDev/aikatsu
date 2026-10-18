//! Search / episodes / qualities / stream for a source key ("kyoko/otakudesu"),
//! answered by that plugin's script (see `plugins`).

use crate::local;
use crate::plugins::{self, Plugin};
use anyhow::{Result, anyhow};
use regex::Regex;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Anime {
    pub name: String,
    pub url: String,
    #[serde(default)]
    pub image: String,
    /// Filled in from the plugin, not by the script.
    #[serde(default)]
    pub source: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Episode {
    pub num: u32,
    pub url: String,
    #[serde(default)]
    pub title: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Stream {
    pub url: String,
    #[serde(default)]
    pub referer: String,
}

const SEARCH_ALL_TIMEOUT: Duration = Duration::from_secs(15);
const PER_SOURCE_TIMEOUT: Duration = Duration::from_secs(12);
/// Resolving tries server after server, each probed, so it gets longer.
const RESOLVE_TIMEOUT: Duration = Duration::from_secs(60);

fn plugin(src: &str) -> Result<Arc<Plugin>> {
    plugins::find(src).ok_or_else(|| anyhow!("source {src} isn't installed (was its plugin repo removed?)"))
}

/// A script's return value as `T`, with the plugin named when it doesn't fit.
fn decode<T: DeserializeOwned>(p: &Plugin, f: &str, v: rhai::Dynamic) -> Result<T> {
    rhai::serde::from_dynamic(&v).map_err(|e| anyhow!("{}: {f}() returned something unexpected: {e}", p.name))
}

pub async fn search(src: &str, query: &str) -> Result<Vec<Anime>> {
    let p = plugin(src)?;
    let q = normalize_query(query);
    anyhow::ensure!(!q.is_empty(), "{}: empty query", p.name);
    let v = plugins::call(&p, "search", (q,), PER_SOURCE_TIMEOUT).await?;
    let mut found: Vec<Anime> = decode(&p, "search", v)?;
    found.retain(|a| !a.name.is_empty() && !a.url.is_empty());
    for a in &mut found {
        a.source = p.id.clone();
    }
    Ok(found)
}

pub async fn episodes(src: &str, anime_url: &str) -> Result<Vec<Episode>> {
    if src == local::SOURCE {
        let folder = anime_url.to_owned();
        return tokio::task::spawn_blocking(move || local::episodes(&folder)).await?;
    }
    let p = plugin(src)?;
    let v = plugins::call(&p, "episodes", (anime_url.to_owned(),), RESOLVE_TIMEOUT).await?;
    let mut eps: Vec<Episode> = decode(&p, "episodes", v)?;
    anyhow::ensure!(!eps.is_empty(), "{}: no episodes found (page layout changed?)", p.name);
    eps.sort_by_key(|e| e.num);
    Ok(eps)
}

/// Offered resolutions, highest first ("1080p", "720p", …).
pub async fn qualities(src: &str, episode_url: &str) -> Result<Vec<String>> {
    if src == local::SOURCE {
        return Ok(Vec::new());
    }
    let p = plugin(src)?;
    let v = plugins::call(&p, "heights", (episode_url.to_owned(),), RESOLVE_TIMEOUT).await?;
    Ok(quality_labels(decode(&p, "heights", v)?))
}

/// Resolves an episode to a playable URL. `quality` is "best"/"" or e.g. "720p".
pub async fn stream(src: &str, episode_url: &str, quality: &str) -> Result<Stream> {
    if src == local::SOURCE {
        return local::stream(episode_url);
    }
    let p = plugin(src)?;
    let res = async {
        let v = plugins::call(&p, "stream", (episode_url.to_owned(), quality.to_owned()), RESOLVE_TIMEOUT).await?;
        let s: Stream = decode(&p, "stream", v)?;
        // Whatever the script says, the player only gets web URLs.
        anyhow::ensure!(url::Url::parse(&s.url).is_ok_and(|u| matches!(u.scheme(), "http" | "https")), "{}: not a web URL: {}", p.name, s.url);
        Ok(s)
    }
    .await;
    if res.is_err() {
        crate::http::clear_pages(); // the retry should not read a possibly stale page
    }
    res
}

#[derive(Default)]
struct Breaker {
    failures: u32,
    open_until: Option<Instant>,
}

static BREAKERS: LazyLock<Mutex<HashMap<String, Breaker>>> = LazyLock::new(Default::default);

fn breaker_open(src: &str) -> bool {
    let mut map = BREAKERS.lock().unwrap();
    let b = map.entry(src.to_owned()).or_default();
    match b.open_until {
        Some(t) if Instant::now() < t => true,
        Some(_) => {
            *b = Breaker::default();
            false
        }
        None => false,
    }
}

/// Records an outcome; only provider-side failures count (3 opens it for 10 min).
fn breaker_record(p: &Plugin, result: &Result<Vec<Anime>>) {
    let mut map = BREAKERS.lock().unwrap();
    match result {
        Ok(_) => {
            map.remove(&p.id);
        }
        Err(e) if crate::http::is_unavailable(e) => {
            let b = map.entry(p.id.clone()).or_default();
            b.failures += 1;
            if b.failures >= 3 {
                b.open_until = Some(Instant::now() + Duration::from_secs(600));
                tracing::warn!("search source circuit opened: {}", p.id);
            }
        }
        Err(_) => {}
    }
}

/// Searches every enabled source in parallel; `on_result` fires per source as
/// each finishes (results stream into the UI). Skips sources whose breaker is open.
pub async fn search_all(query: &str, enabled: &[Arc<Plugin>], on_result: impl Fn(&Plugin, Result<Vec<Anime>>)) {
    let mut set = tokio::task::JoinSet::new();
    for p in enabled {
        if breaker_open(&p.id) {
            tracing::warn!("search source skipped (circuit open): {}", p.id);
            on_result(p, Err(anyhow!("{} skipped: too many recent failures", p.name)));
            continue;
        }
        let (q, p) = (query.to_owned(), p.clone());
        set.spawn(async move {
            let res = match tokio::time::timeout(PER_SOURCE_TIMEOUT, search(&p.id, &q)).await {
                Ok(r) => r,
                Err(_) => Err(crate::http::Unavailable(format!("{} search timed out after 12s", p.name)).into()),
            };
            (p, res)
        });
    }
    let deadline = tokio::time::sleep(SEARCH_ALL_TIMEOUT);
    tokio::pin!(deadline);
    loop {
        tokio::select! {
            next = set.join_next() => match next {
                Some(Ok((p, res))) => {
                    breaker_record(&p, &res);
                    on_result(&p, res);
                }
                Some(Err(e)) => tracing::error!("search task panicked: {e}"),
                None => break,
            },
            _ = &mut deadline => break,
        }
    }
}

static HEIGHT_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(\d{3,4})").unwrap());
static SUB_INDO_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\s*(?:subtitle|sub)\s+indo(?:nesia)?\s*$").unwrap());

/// "720p"/"Pixel 720"/"720" → 720; "best"/"" → 0.
pub fn height_of(q: &str) -> u32 {
    HEIGHT_RE.captures(q).and_then(|c| c[1].parse().ok()).unwrap_or(0)
}

/// Requested height first, then the nearest higher, then the nearest lower;
/// "best" (0) is plain height descending.
pub fn sort_by_height<T>(items: &mut [T], want: u32, height: impl Fn(&T) -> u32) {
    items.sort_by_key(|x| {
        let h = height(x);
        match h.cmp(&want) {
            _ if want == 0 => (0, u32::MAX - h),
            std::cmp::Ordering::Equal => (0, 0),
            std::cmp::Ordering::Greater => (1, h),
            std::cmp::Ordering::Less => (2, u32::MAX - h),
        }
    });
}

fn quality_labels(mut heights: Vec<u32>) -> Vec<String> {
    heights.retain(|&h| h > 0);
    heights.sort_unstable_by(|a, b| b.cmp(a));
    heights.dedup();
    heights.into_iter().map(|h| format!("{h}p")).collect()
}

/// WordPress reads "-word" as an exclusion, so hyphens/underscores become spaces.
pub fn normalize_query(q: &str) -> String {
    q.split(['-', '_', ' ']).filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" ")
}

/// Drops the sites' "Subtitle Indonesia"/"Sub Indo" suffix.
pub fn clean_sub_indo(s: &str) -> String {
    SUB_INDO_RE.replace(s.trim(), "").trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn height_sorting_prefers_requested() {
        let mut v = vec![360, 1080, 720, 480];
        sort_by_height(&mut v, 720, |h| *h);
        assert_eq!(v, [720, 1080, 480, 360]);
        sort_by_height(&mut v, 0, |h| *h);
        assert_eq!(v, [1080, 720, 480, 360]);
        let mut v = vec![1080, 720, 360];
        sort_by_height(&mut v, 480, |h| *h);
        assert_eq!(v, [720, 1080, 360], "missing height falls back to the nearest higher first");
    }

    #[test]
    fn helpers() {
        assert_eq!(height_of("MKV 1080p"), 1080);
        assert_eq!(height_of("best"), 0);
        assert_eq!(normalize_query("naruto-kecil_x  y"), "naruto kecil x y");
        assert_eq!(clean_sub_indo("Boruto Subtitle Indonesia"), "Boruto");
        assert_eq!(quality_labels(vec![720, 0, 1080, 720]), ["1080p", "720p"]);
    }
}
