//! moenime.com + moeclip.com — signed, short-lived MP4s from
//! `<origin>/v/<media>_<quality>_<post>.html` players.

use super::{Anime, Episode, SourceId, Stream, attr, text_of};
use crate::http::{self, absolute, query_escape, sel};
use anyhow::{Result, anyhow};
use regex::Regex;
use scraper::Html;
use std::collections::HashSet;
use std::sync::LazyLock;

const BASE: &str = "https://moenime.com";
const MOECLIP: &str = "https://moeclip.com";
const LABEL: &str = "Moenime";

static EPISODE_PATH_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"/(\d+?)/?$").unwrap());
static QUALITY_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)(\d{3,4})p").unwrap());
static PLAYER_FILE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"\bfile\s*:\s*['"]([^'"]+)['"]"#).unwrap());
static TITLE_NOISE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\s*(?:\(episode\s*\d+\)\s*)?sub\s+indo\s*$").unwrap());

fn referer() -> String {
    format!("{BASE}/")
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let body = http::page(LABEL, http::get(&format!("{BASE}/?s={}", query_escape(q)), &referer())).await?;
    let doc = Html::parse_document(&body);
    Ok(doc
        .select(&sel("article"))
        .filter_map(|art| {
            let a = art.select(&sel("h1.entry-title a")).next()?;
            let title = TITLE_NOISE_RE.replace(text_of(&a).trim(), "").trim().to_owned();
            let href = absolute(&referer(), &attr(&a, "href"));
            if title.is_empty() || href.is_empty() {
                return None;
            }
            let image = art.select(&sel(".featured-thumb img")).next().map(|i| absolute(&referer(), &attr(&i, "src"))).unwrap_or_default();
            Some(Anime { name: title, url: href, image, source: SourceId::Moenime })
        })
        .collect())
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let body = http::page(LABEL, http::get(anime_url, &referer())).await?;
    Ok(parse_episodes(&body))
}

fn parse_episodes(body: &str) -> Vec<Episode> {
    let doc = Html::parse_document(body);
    let mut seen = HashSet::new();
    doc.select(&sel("a.moe-stream-a"))
        .filter_map(|a| {
            let href = attr(&a, "href");
            let mut row = a
                .ancestors()
                .filter_map(scraper::ElementRef::wrap)
                .find(|e| e.value().name() == "td" && e.value().attr("id").is_some())
                .map(|td| attr(&td, "id"))
                .unwrap_or_default();
            if row.is_empty() {
                row = EPISODE_PATH_RE.captures(&href).map(|c| c[1].to_owned()).unwrap_or_default();
            }
            let num: u32 = row.parse().ok().filter(|&n| n >= 1)?;
            if href.is_empty() || !seen.insert(href.clone()) {
                return None;
            }
            Some(Episode { num, url: href, title: format!("Episode {num}") })
        })
        .collect()
}

struct PlayerInfo {
    media_id: String,
    post_id: String,
    origin: String,
    qualities: Vec<String>,
}

async fn player_info(episode_url: &str) -> Result<PlayerInfo> {
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    let origin = url::Url::parse(episode_url).map(|u| u.origin().ascii_serialization()).unwrap_or_default();
    parse_player(&body, origin)
}

fn parse_player(body: &str, origin: String) -> Result<PlayerInfo> {
    let doc = Html::parse_document(body);
    let media_id = doc.select(&sel("button.mirrorlist.aktif")).next().map(|b| attr(&b, "meta-src")).unwrap_or_default();
    let post_id = http::first_text(&doc, "#down-title");
    let mut heights: Vec<u32> = doc
        .select(&sel("#source option"))
        .filter_map(|o| {
            let v = o.value().attr("value").map(str::to_owned).unwrap_or_else(|| text_of(&o));
            QUALITY_RE.captures(&v)?[1].parse().ok()
        })
        .collect();
    heights.sort_unstable_by(|a, b| b.cmp(a));
    heights.dedup();
    let qualities: Vec<String> = heights.iter().map(|h| format!("{h}p")).collect();
    anyhow::ensure!(
        !media_id.is_empty() && !post_id.is_empty() && origin != "null" && !origin.is_empty() && !qualities.is_empty(),
        "{LABEL}: incomplete Moeclip player data (layout changed?)"
    );
    Ok(PlayerInfo { media_id, post_id, origin, qualities })
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    Ok(player_info(episode_url).await?.qualities.iter().map(|q| super::height_of(q)).collect())
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let mut info = player_info(episode_url).await?;
    super::sort_by_height(&mut info.qualities, super::height_of(quality), |q| super::height_of(q));
    let selected = &info.qualities[0];
    let player = format!("{}/v/{}_{}_{}.html", info.origin, info.media_id, selected, info.post_id);
    let body = http::text(LABEL, http::get(&player, &referer())).await?;
    let url = PLAYER_FILE_RE.captures(&body).ok_or_else(|| anyhow!("{LABEL}: no media file in Moeclip player"))?[1].to_owned();
    anyhow::ensure!(http::playable(&url, Some(&format!("{MOECLIP}/"))).await, "{LABEL}: Moeclip media file is not playable");
    Ok(Stream { url, referer: format!("{}/", info.origin) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_episodes_and_player() {
        let e = parse_episodes(
            r#"<table><tr><td id="3"><a class="moe-stream-a" href="https://moeclip.com/x/3/">S</a></td></tr>
<tr><td><a class="moe-stream-a" href="https://moeclip.com/x/12/">S</a></td></tr>
<tr><td id="3"><a class="moe-stream-a" href="https://moeclip.com/x/3/">dup</a></td></tr></table>"#,
        );
        assert_eq!(e.iter().map(|e| e.num).collect::<Vec<_>>(), [3, 12]);

        let p = parse_player(
            r#"<button class="mirrorlist aktif" meta-src="abc">M</button><span id="down-title">991</span>
<select id="source"><option value="480p">480p</option><option value="720p">720p</option></select>"#,
            "https://moeclip.com".into(),
        )
        .unwrap();
        assert_eq!((p.media_id.as_str(), p.post_id.as_str()), ("abc", "991"));
        assert_eq!(p.qualities, ["720p", "480p"]);
    }
}
