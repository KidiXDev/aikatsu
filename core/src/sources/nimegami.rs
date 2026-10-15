//! nimegami.id — one page holds a whole season; each `li.select-eps[data]`
//! carries base64 JSON `[{format, url:[embeds]}]`. Episode URLs are
//! `<page>#play_eps_<n>`.

use super::{Anime, Episode, SourceId, Stream, attr, height_of, sort_by_height, text_of};
use crate::http::{self, query_escape, sel};
use anyhow::{Result, anyhow};
use base64::{Engine, prelude::BASE64_STANDARD};
use regex::Regex;
use scraper::Html;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::sync::{LazyLock, Mutex};

const BASE: &str = "https://nimegami.id";
const LABEL: &str = "Nimegami";
const FRAGMENT: &str = "#play_eps_";

static EPISODE_ID_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^play_eps_(\d+)$").unwrap());
static SOURCE_SRC_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"<source[^>]+src=["']([^"']+)["']"#).unwrap());
static STREAM_API_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"STREAM_URL_API\s*=\s*["']([^"']+)["']"#).unwrap());
static TITLE_NOISE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\s*(?:sub\s+indo|subtitle\s+indonesia)?\s*(?::\s*episode.*)?$").unwrap());

/// The season page is ~230 KB and every episode lives on it: keep the last one.
static PAGE_CACHE: LazyLock<Mutex<(String, String)>> = LazyLock::new(Default::default);

#[derive(Clone, Deserialize)]
struct Entry {
    format: String,
    url: Vec<String>,
}

fn referer() -> String {
    format!("{BASE}/")
}

fn clean_title(s: &str) -> String {
    TITLE_NOISE_RE.replace(s.trim(), "").trim().to_owned()
}

async fn season_page(page_url: &str) -> Result<String> {
    {
        let cache = PAGE_CACHE.lock().unwrap();
        if cache.0 == page_url {
            return Ok(cache.1.clone());
        }
    }
    let body = http::page(LABEL, http::get(page_url, &referer())).await?;
    *PAGE_CACHE.lock().unwrap() = (page_url.to_owned(), body.clone());
    Ok(body)
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let body = http::page(LABEL, http::get(&format!("{BASE}/?s={}", query_escape(q)), &referer())).await?;
    Ok(parse_search(&body))
}

fn parse_search(body: &str) -> Vec<Anime> {
    let doc = Html::parse_document(body);
    doc.select(&sel("article"))
        .filter_map(|art| {
            let a = art.select(&sel("h2 a")).next()?;
            let (href, title) = (attr(&a, "href"), clean_title(&text_of(&a)));
            if href.is_empty() || title.is_empty() {
                return None;
            }
            let image = art.select(&sel("img")).next().map(|i| attr(&i, "src")).unwrap_or_default();
            Some(Anime { name: title, url: href, image, source: SourceId::Nimegami })
        })
        .collect()
}

/// Episode number → (stream entries, title).
fn payloads(body: &str) -> BTreeMap<u32, (Vec<Entry>, String)> {
    let doc = Html::parse_document(body);
    doc.select(&sel("li.select-eps[data]"))
        .filter_map(|li| {
            let num = EPISODE_ID_RE.captures(&attr(&li, "id"))?[1].parse().ok()?;
            let raw = BASE64_STANDARD.decode(attr(&li, "data")).ok()?;
            let entries: Vec<Entry> = serde_json::from_slice(&raw).ok().filter(|e: &Vec<Entry>| !e.is_empty())?;
            Some((num, (entries, clean_title(&attr(&li, "title")))))
        })
        .collect()
}

fn split_episode_url(u: &str) -> (&str, u32) {
    let (page, frag) = u.trim().split_once('#').unwrap_or((u.trim(), ""));
    (page, EPISODE_ID_RE.captures(frag).and_then(|c| c[1].parse().ok()).unwrap_or(0))
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let (page_url, _) = split_episode_url(anime_url);
    let body = season_page(page_url).await?;
    Ok(payloads(&body)
        .into_iter()
        .map(|(num, (_, title))| Episode { num, url: format!("{page_url}{FRAGMENT}{num}"), title })
        .collect())
}

async fn episode_entries(episode_url: &str) -> Result<Vec<Entry>> {
    let (page_url, num) = split_episode_url(episode_url);
    anyhow::ensure!(num > 0, "{LABEL}: not a nimegami episode URL: {episode_url}");
    let body = season_page(page_url).await?;
    payloads(&body).remove(&num).map(|(e, _)| e).ok_or_else(|| anyhow!("{LABEL}: episode {num} is not on the page"))
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    Ok(episode_entries(episode_url).await?.iter().map(|e| height_of(&e.format)).collect())
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let mut entries = episode_entries(episode_url).await?;
    sort_by_height(&mut entries, height_of(quality), |e| height_of(&e.format));
    let mut last_err = None;
    for e in &entries {
        for embed in &e.url {
            match resolve_embed(embed).await {
                Ok(url) => return Ok(Stream { url, referer: referer() }),
                Err(err) => last_err = Some(err),
            }
        }
    }
    Err(anyhow!("{LABEL}: no playable server for this episode{}", last_err.map(|e| format!(" ({e})")).unwrap_or_default()))
}

async fn resolve_embed(embed: &str) -> Result<String> {
    let body = http::text(LABEL, http::get(embed, &referer())).await?;
    if let Some(c) = STREAM_API_RE.captures(&body) {
        #[derive(Deserialize)]
        struct Api {
            ok: bool,
            url: String,
        }
        let api_url = url::Url::parse(embed)?.join(&c[1])?;
        let api: Api = serde_json::from_str(&http::text(LABEL, http::get(api_url.as_str(), &referer())).await?)
            .map_err(|e| anyhow!("{LABEL} stream API: {e}"))?;
        anyhow::ensure!(api.ok && !api.url.is_empty(), "{LABEL} stream API: no media URL in response");
        anyhow::ensure!(http::playable(&api.url, None).await, "{LABEL}: file not served from here");
        return Ok(api.url);
    }
    // Legacy layout: <source src="…mp4?filename=…">; the filename query has unescaped spaces.
    let src = SOURCE_SRC_RE.captures(&body).ok_or_else(|| anyhow!("{LABEL}: no <source> in streaming page"))?[1].to_owned();
    let file = src.split('?').next().unwrap_or_default().to_owned();
    anyhow::ensure!(http::playable(&file, None).await, "{LABEL}: file not served from here");
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payloads_and_urls() {
        let data = BASE64_STANDARD.encode(r#"[{"format":"720p","url":["https://e/1"]},{"format":"480p","url":["https://e/2"]}]"#);
        let html = format!(
            r#"<ul><li class="select-eps" id="play_eps_2" data="{data}" title="Kimi Sub Indo: Episode 2">2</li>
<li class="select-eps" id="play_eps_x" data="{data}">x</li><li class="select-eps" id="play_eps_3" data="bad">3</li></ul>"#
        );
        let p = payloads(&html);
        assert_eq!(p.keys().copied().collect::<Vec<_>>(), [2]);
        assert_eq!(p[&2].0.len(), 2);
        assert_eq!(p[&2].1, "Kimi");
        assert_eq!(split_episode_url("https://nimegami.id/kimi/#play_eps_12"), ("https://nimegami.id/kimi/", 12));
        assert_eq!(split_episode_url("https://nimegami.id/kimi/").1, 0);
    }
}
