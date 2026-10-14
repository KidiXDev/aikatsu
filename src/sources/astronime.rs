//! astronime.id — Hydrax/Abyss player. The embed's `const datas` blob is
//! decrypted by the third-party enc-dec.app service.

use super::{Anime, Episode, SourceId, Stream, attr, height_of, text_of};
use crate::http::{self, absolute, query_escape, sel};
use anyhow::{Result, anyhow};
use regex::Regex;
use scraper::Html;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

const BASE: &str = "https://astronime.id";
const DECRYPT: &str = "https://enc-dec.app/api/dec-abyss";
const LABEL: &str = "Astronime";

static EPISODE_NUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)episode[-\s]+(\d+)").unwrap());
static ABYSS_DATA_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"const\s+datas\s*=\s*"([^"]+)""#).unwrap());

#[derive(Clone)]
struct Source {
    file: String,
    label: String,
}

/// Decrypted sources per episode for 2 minutes (qualities → stream reuse them).
type Cached = (Vec<Source>, String, Instant); // sources, embed referer, fetched at
static CACHE: LazyLock<Mutex<HashMap<String, Cached>>> = LazyLock::new(Default::default);

fn referer() -> String {
    format!("{BASE}/")
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let body = http::page(LABEL, http::get(&format!("{BASE}/?s={}", query_escape(q)), &referer())).await?;
    Ok(parse_search(&body))
}

fn parse_search(body: &str) -> Vec<Anime> {
    let doc = Html::parse_document(body);
    doc.select(&sel("article.animpost"))
        .filter_map(|card| {
            let a = card.select(&sel(".animposx > a, a[title]")).next()?;
            let title = a.value().attr("title").map(|t| t.trim().to_owned()).unwrap_or_else(|| text_of(&a));
            let href = absolute(&referer(), &attr(&a, "href"));
            if title.is_empty() || href.is_empty() {
                return None;
            }
            let img = card.select(&sel("img")).next();
            let src = img.map(|i| i.value().attr("data-src").or(i.value().attr("src")).unwrap_or_default().to_owned()).unwrap_or_default();
            Some(Anime { name: title, url: href, image: absolute(&referer(), &src), source: SourceId::Astronime })
        })
        .collect()
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let body = http::page(LABEL, http::get(anime_url, &referer())).await?;
    let doc = Html::parse_document(&body);
    let mut seen = HashSet::new();
    Ok(doc
        .select(&sel(r#"a[href*="-episode-"]"#))
        .filter_map(|a| {
            let href = absolute(&referer(), &attr(&a, "href"));
            let num: u32 = EPISODE_NUM_RE.captures(&format!("{href} {}", text_of(&a)))?[1].parse().ok().filter(|&n| n >= 1)?;
            if href.is_empty() || !seen.insert(href.clone()) {
                return None;
            }
            Some(Episode { num, url: href, title: format!("Episode {num}") })
        })
        .collect())
}

/// Episode page → Hydrax server → admin-ajax iframe → embed `datas` → decrypt.
async fn sources(episode_url: &str) -> Result<(Vec<Source>, String)> {
    if let Some((s, r, at)) = CACHE.lock().unwrap().get(episode_url)
        && at.elapsed() < Duration::from_secs(120)
    {
        return Ok((s.clone(), r.clone()));
    }
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    let (post, nume) = {
        let doc = Html::parse_document(&body);
        doc.select(&sel(".east_player_option"))
            .find(|o| text_of(o).to_lowercase().contains("hydrax"))
            .map(|o| (attr(&o, "data-post"), attr(&o, "data-nume")))
            .unwrap_or_default()
    };
    anyhow::ensure!(!post.is_empty() && !nume.is_empty(), "{LABEL}: Hydrax server not found (page layout changed?)");

    let form = [("action", "player_ajax"), ("post", post.as_str()), ("nume", &nume), ("type", "urliframe")];
    let player = http::CHROME
        .post(format!("{BASE}/wp-admin/admin-ajax.php"))
        .header("Referer", episode_url)
        .header("Origin", BASE)
        .form(&form);
    let player = http::text(LABEL, player).await?;
    let embed_url = {
        let doc = Html::parse_document(&player);
        doc.select(&sel("iframe[src]")).next().map(|i| absolute(&referer(), &attr(&i, "src"))).unwrap_or_default()
    };
    anyhow::ensure!(!embed_url.is_empty(), "{LABEL}: Hydrax iframe not found");

    let embed = http::text(LABEL, http::get(&embed_url, episode_url)).await?;
    let blob = ABYSS_DATA_RE.captures(&embed).ok_or_else(|| anyhow!("{LABEL}: encrypted player data not found"))?[1].to_owned();
    let decrypt = http::CHROME
        .post(DECRYPT)
        .header("Referer", "https://playhydrax.com/")
        .header("Origin", "https://playhydrax.com")
        .json(&serde_json::json!({ "text": blob }));
    let srcs = parse_decrypted(&http::text(LABEL, decrypt).await?)?;
    CACHE.lock().unwrap().insert(episode_url.to_owned(), (srcs.clone(), embed_url.clone(), Instant::now()));
    Ok((srcs, embed_url))
}

fn parse_decrypted(body: &str) -> Result<Vec<Source>> {
    #[derive(Deserialize)]
    struct Src {
        url: String,
        #[serde(rename = "type")]
        kind: String,
        status: bool,
    }
    #[derive(Deserialize)]
    struct Res {
        sources: Vec<Src>,
    }
    #[derive(Deserialize)]
    struct Resp {
        status: u16,
        result: Res,
    }
    let r: Resp = serde_json::from_str(body).map_err(|e| anyhow!("{LABEL} Hydrax decode: invalid decoder response: {e}"))?;
    anyhow::ensure!(r.status == 200, "{LABEL} Hydrax decode: decoder rejected player data");
    let out: Vec<Source> = r
        .result
        .sources
        .into_iter()
        .filter(|s| s.status && height_of(&s.kind) > 0 && url::Url::parse(&s.url).is_ok_and(|u| matches!(u.scheme(), "http" | "https")))
        .map(|s| Source { file: s.url, label: s.kind })
        .collect();
    anyhow::ensure!(!out.is_empty(), "{LABEL} Hydrax decode: no media sources found");
    Ok(out)
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    Ok(sources(episode_url).await?.0.iter().map(|s| height_of(&s.label)).collect())
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let (mut srcs, referer) = sources(episode_url).await?;
    super::sort_by_height(&mut srcs, height_of(quality), |s| height_of(&s.label));
    for s in srcs {
        if http::playable(&s.file, Some(&referer)).await {
            return Ok(Stream { url: s.file, referer });
        }
    }
    Err(anyhow!("{LABEL}: no playable Hydrax media file"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_search_and_decrypted() {
        let s = parse_search(r#"<article class="animpost"><div class="animposx"><a href="/anime/x/" title="Sakamoto Days"><img data-src="/i.jpg" src="lazy.gif"></a></div></article>"#);
        assert_eq!((s[0].name.as_str(), s[0].url.as_str(), s[0].image.as_str()), ("Sakamoto Days", "https://astronime.id/anime/x/", "https://astronime.id/i.jpg"));

        let d = parse_decrypted(r#"{"status":200,"result":{"sources":[{"url":"https://a/720.mp4","type":"720p","status":true},{"url":"https://a/x","type":"auto","status":true},{"url":"https://a/1080.mp4","type":"1080p","status":false}]}}"#).unwrap();
        assert_eq!(d.len(), 1);
        assert!(parse_decrypted(r#"{"status":500,"result":{"sources":[]}}"#).is_err());
    }
}
