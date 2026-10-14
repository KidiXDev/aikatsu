//! ylnime.com — the episode page embeds `const streams = [{reso, link}]`;
//! `reso=<quality>` on the episode URL picks the resolution.

use super::{Anime, Episode, SourceId, Stream, attr, text_of};
use crate::http::{self, absolute, query_escape, sel};
use anyhow::{Result, anyhow};
use regex::Regex;
use scraper::Html;
use serde::Deserialize;
use std::collections::HashSet;
use std::sync::LazyLock;

const BASE: &str = "https://ylnime.com";
const LABEL: &str = "YLnime";

static EPISODE_NUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)episode\s*(\d+)").unwrap());
static QUALITY_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)(\d{3,4})p").unwrap());
static STREAMS_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)\bconst\s+streams\s*=\s*(\[[^;]*\])\s*;").unwrap());

fn referer() -> String {
    format!("{BASE}/")
}

fn abs(raw: &str) -> String {
    absolute(&referer(), raw)
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let body = http::page(LABEL, http::get(&format!("{BASE}/?search={}", query_escape(q)), &referer())).await?;
    Ok(parse_search(&body))
}

fn parse_search(body: &str) -> Vec<Anime> {
    let doc = Html::parse_document(body);
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for a in doc.select(&sel(r#"a[href*="series="]"#)) {
        // Closest ancestor .card
        let Some(card) = a.ancestors().filter_map(scraper::ElementRef::wrap).find(|e| e.value().has_class("card", scraper::CaseSensitivity::CaseSensitive))
        else {
            continue;
        };
        let title = card.select(&sel(".card-title")).next().map(|t| text_of(&t)).unwrap_or_default();
        let href = abs(&attr(&a, "href"));
        if title.is_empty() || href.is_empty() || !seen.insert(href.clone()) {
            continue;
        }
        let image = card.select(&sel("img")).next().map(|i| abs(&attr(&i, "src"))).unwrap_or_default();
        out.push(Anime { name: title, url: href, image, source: SourceId::Ylnime });
    }
    out
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let body = http::page(LABEL, http::get(anime_url, &referer())).await?;
    let doc = Html::parse_document(&body);
    Ok(doc
        .select(&sel(r#"a.list-group-item[href*="episode="]"#))
        .filter_map(|a| {
            let label = a.select(&sel("span")).next().map(|s| text_of(&s)).unwrap_or_default();
            let num = EPISODE_NUM_RE.captures(&label)?[1].parse().ok()?;
            Some(Episode { num, url: abs(&attr(&a, "href")), title: label })
        })
        .collect())
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    let doc = Html::parse_document(&body);
    Ok(doc
        .select(&sel(r#"a[href*="reso="]"#))
        .filter_map(|a| QUALITY_RE.captures(&text_of(&a))?[1].parse().ok())
        .collect())
}

#[derive(Deserialize)]
struct Candidate {
    reso: String,
    link: String,
}

fn parse_streams(body: &str) -> Result<Vec<Candidate>> {
    let raw = STREAMS_RE.captures(body).ok_or_else(|| anyhow!("{LABEL}: no player streams on episode page"))?;
    let mut streams: Vec<Candidate> = serde_json::from_str(&raw[1]).map_err(|e| anyhow!("{LABEL}: invalid stream data: {e}"))?;
    streams.retain(|c| url::Url::parse(&c.link).is_ok_and(|u| matches!(u.scheme(), "http" | "https") && u.host().is_some()));
    anyhow::ensure!(!streams.is_empty(), "{LABEL}: player stream list is empty");
    Ok(streams)
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let mut u = url::Url::parse(episode_url)?;
    if !quality.is_empty() && quality != "best" {
        let pairs: Vec<(String, String)> = u.query_pairs().filter(|(k, _)| k != "reso").map(|(k, v)| (k.into_owned(), v.into_owned())).collect();
        u.query_pairs_mut().clear().extend_pairs(pairs).append_pair("reso", quality);
    }
    let body = http::text(LABEL, http::get(u.as_str(), &referer())).await?;
    let mut streams = parse_streams(&body)?;
    super::sort_by_height(&mut streams, super::height_of(quality), |c| super::height_of(&c.reso));
    for c in streams {
        if http::playable(&c.link, Some(&referer())).await {
            return Ok(Stream { url: c.link, referer: referer() });
        }
    }
    Err(anyhow!("{LABEL}: no playable server for this episode"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_search_and_streams() {
        let s = parse_search(
            r#"<div class="card"><img src="/img/a.jpg"><a href="/?series=frieren"><h5 class="card-title">Frieren</h5></a><a href="/?series=frieren">again</a></div>"#,
        );
        assert_eq!(s.len(), 1);
        assert_eq!((s[0].url.as_str(), s[0].image.as_str()), ("https://ylnime.com/?series=frieren", "https://ylnime.com/img/a.jpg"));

        let streams = parse_streams(r#"<script>const streams = [{"reso":"720p","link":"https://cdn.x/a.mp4"},{"reso":"1080p","link":"javascript:x"}];</script>"#).unwrap();
        assert_eq!(streams.len(), 1);
        assert!(parse_streams("<p>nothing</p>").is_err());
    }
}
