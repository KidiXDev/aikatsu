//! The six streaming sites. Each module offers search / episodes / qualities /
//! stream; this one picks the module for a `SourceId`.

mod astronime;
mod moenime;
mod nimegami;
mod otakudesu;
mod samehadaku;
mod ylnime;

pub use samehadaku::is_wibufile;

use anyhow::Result;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SourceId {
    Otakudesu,
    Samehadaku,
    Nimegami,
    Ylnime,
    Moenime,
    Astronime,
}

impl SourceId {
    /// In priority order.
    pub const ALL: [SourceId; 6] = [
        SourceId::Otakudesu,
        SourceId::Samehadaku,
        SourceId::Nimegami,
        SourceId::Ylnime,
        SourceId::Moenime,
        SourceId::Astronime,
    ];

    pub fn name(self) -> &'static str {
        match self {
            SourceId::Otakudesu => "Otakudesu",
            SourceId::Samehadaku => "Samehadaku",
            SourceId::Nimegami => "Nimegami",
            SourceId::Ylnime => "YLnime",
            SourceId::Moenime => "Moenime",
            SourceId::Astronime => "Astronime",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            SourceId::Otakudesu => "otakudesu",
            SourceId::Samehadaku => "samehadaku",
            SourceId::Nimegami => "nimegami",
            SourceId::Ylnime => "ylnime",
            SourceId::Moenime => "moenime",
            SourceId::Astronime => "astronime",
        }
    }

    pub fn from_key(key: &str) -> Option<SourceId> {
        SourceId::ALL.into_iter().find(|s| s.key().eq_ignore_ascii_case(key))
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Anime {
    pub name: String,
    pub url: String,
    pub image: String,
    pub source: SourceId,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Episode {
    pub num: u32,
    pub url: String,
    pub title: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Stream {
    pub url: String,
    pub referer: String,
}

pub async fn search(src: SourceId, query: &str) -> Result<Vec<Anime>> {
    let q = normalize_query(query);
    anyhow::ensure!(!q.is_empty(), "{}: empty query", src.name());
    match src {
        SourceId::Otakudesu => otakudesu::search(&q).await,
        SourceId::Samehadaku => samehadaku::search(&q).await,
        SourceId::Nimegami => nimegami::search(&q).await,
        SourceId::Ylnime => ylnime::search(&q).await,
        SourceId::Moenime => moenime::search(&q).await,
        SourceId::Astronime => astronime::search(&q).await,
    }
}

pub async fn episodes(src: SourceId, anime_url: &str) -> Result<Vec<Episode>> {
    let mut eps = match src {
        SourceId::Otakudesu => otakudesu::episodes(anime_url).await,
        SourceId::Samehadaku => samehadaku::episodes(anime_url).await,
        SourceId::Nimegami => nimegami::episodes(anime_url).await,
        SourceId::Ylnime => ylnime::episodes(anime_url).await,
        SourceId::Moenime => moenime::episodes(anime_url).await,
        SourceId::Astronime => astronime::episodes(anime_url).await,
    }?;
    anyhow::ensure!(!eps.is_empty(), "{}: no episodes found (page layout changed?)", src.name());
    eps.sort_by_key(|e| e.num);
    Ok(eps)
}

/// Offered resolutions, highest first ("1080p", "720p", …).
pub async fn qualities(src: SourceId, episode_url: &str) -> Result<Vec<String>> {
    let heights = match src {
        SourceId::Otakudesu => otakudesu::heights(episode_url).await,
        SourceId::Samehadaku => samehadaku::heights(episode_url).await,
        SourceId::Nimegami => nimegami::heights(episode_url).await,
        SourceId::Ylnime => ylnime::heights(episode_url).await,
        SourceId::Moenime => moenime::heights(episode_url).await,
        SourceId::Astronime => astronime::heights(episode_url).await,
    }?;
    Ok(quality_labels(heights))
}

/// Resolves an episode to a playable URL. `quality` is "best"/"" or e.g. "720p".
pub async fn stream(src: SourceId, episode_url: &str, quality: &str) -> Result<Stream> {
    let res = match src {
        SourceId::Otakudesu => otakudesu::stream(episode_url, quality).await,
        SourceId::Samehadaku => samehadaku::stream(episode_url, quality).await,
        SourceId::Nimegami => nimegami::stream(episode_url, quality).await,
        SourceId::Ylnime => ylnime::stream(episode_url, quality).await,
        SourceId::Moenime => moenime::stream(episode_url, quality).await,
        SourceId::Astronime => astronime::stream(episode_url, quality).await,
    };
    if res.is_err() {
        crate::http::clear_pages(); // the retry should not read a possibly stale page
    }
    res
}


const SEARCH_ALL_TIMEOUT: Duration = Duration::from_secs(15);
const PER_SOURCE_TIMEOUT: Duration = Duration::from_secs(12);

#[derive(Default)]
struct Breaker {
    failures: u32,
    open_until: Option<Instant>,
}

static BREAKERS: LazyLock<Mutex<HashMap<SourceId, Breaker>>> = LazyLock::new(Default::default);

fn breaker_open(src: SourceId) -> bool {
    let mut map = BREAKERS.lock().unwrap();
    let b = map.entry(src).or_default();
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
fn breaker_record(src: SourceId, result: &Result<Vec<Anime>>) {
    let mut map = BREAKERS.lock().unwrap();
    match result {
        Ok(_) => {
            map.remove(&src);
        }
        Err(e) if crate::http::is_unavailable(e) => {
            let b = map.entry(src).or_default();
            b.failures += 1;
            if b.failures >= 3 {
                b.open_until = Some(Instant::now() + Duration::from_secs(600));
                tracing::warn!("search source circuit opened: {}", src.name());
            }
        }
        Err(_) => {}
    }
}

/// Searches every enabled source in parallel; `on_result` fires per source as
/// each finishes (results stream into the UI). Skips sources whose breaker is open.
pub async fn search_all(query: &str, enabled: &[SourceId], on_result: impl Fn(SourceId, Result<Vec<Anime>>)) {
    let mut set = tokio::task::JoinSet::new();
    for &src in enabled {
        if breaker_open(src) {
            tracing::warn!("search source skipped (circuit open): {}", src.name());
            on_result(src, Err(anyhow::anyhow!("{} skipped: too many recent failures", src.name())));
            continue;
        }
        let q = query.to_owned();
        set.spawn(async move {
            let res = match tokio::time::timeout(PER_SOURCE_TIMEOUT, search(src, &q)).await {
                Ok(r) => r,
                Err(_) => Err(crate::http::Unavailable(format!("{} search timed out after 12s", src.name())).into()),
            };
            (src, res)
        });
    }
    let deadline = tokio::time::sleep(SEARCH_ALL_TIMEOUT);
    tokio::pin!(deadline);
    loop {
        tokio::select! {
            next = set.join_next() => match next {
                Some(Ok((src, res))) => {
                    breaker_record(src, &res);
                    on_result(src, res);
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
static IFRAME_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"<iframe[^>]+src="([^"]+)""#).unwrap());
pub static BLOGGER_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"https://www\.blogger\.com/video\.g\?token=[A-Za-z0-9_-]+").unwrap());

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

pub fn iframe_src(markup: &str) -> String {
    IFRAME_RE.captures(markup).map(|c| c[1].to_owned()).unwrap_or_default()
}

pub fn attr(el: &scraper::ElementRef, name: &str) -> String {
    el.value().attr(name).unwrap_or_default().trim().to_owned()
}

pub fn text_of(el: &scraper::ElementRef) -> String {
    el.text().collect::<String>().trim().to_owned()
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

    /// Live smoke: `cargo test live_ -- --ignored --nocapture`. Hits the real sites.
    #[tokio::test]
    #[ignore]
    async fn live_sources() {
        for src in SourceId::ALL {
            let res = async {
                let q = std::env::var("LIVE_Q").unwrap_or_else(|_| "one piece".into());
                let found = search(src, &q).await?;
                let anime = found.first().ok_or_else(|| anyhow::anyhow!("no results"))?;
                let eps = episodes(src, &anime.url).await?;
                let ep = eps.last().ok_or_else(|| anyhow::anyhow!("no episodes"))?;
                let q = qualities(src, &ep.url).await.unwrap_or_default();
                let s = stream(src, &ep.url, "best").await?;
                anyhow::Ok(format!("{} results, {} eps, q={q:?}, ep{} -> {}", found.len(), eps.len(), ep.num, &s.url[..s.url.len().min(80)]))
            }
            .await;
            println!("{:<10} {}", src.name(), match res { Ok(s) => s, Err(e) => format!("FAIL {e:#}") });
        }
    }
}
