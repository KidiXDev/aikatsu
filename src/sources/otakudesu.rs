//! otakudesu.blog — WordPress. Pixeldrain downloads first (up to 1080p, plain
//! seekable files), then the streaming mirrors via a two-step admin-ajax nonce.

use super::{Anime, BLOGGER_RE, Episode, SourceId, Stream, attr, clean_sub_indo, height_of, iframe_src, sort_by_height, text_of};
use crate::http::{self, query_escape, sel};
use anyhow::{Result, anyhow};
use base64::{Engine, prelude::BASE64_STANDARD};
use regex::Regex;
use scraper::Html;
use serde::Deserialize;
use std::sync::LazyLock;

const BASE: &str = "https://otakudesu.blog";
const PIXELDRAIN: &str = "https://pixeldrain.com";
const LABEL: &str = "Otakudesu";

static EPISODE_NUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)episode[- ](\d+)").unwrap());
// The two ajax action hashes live in the episode page's inline script and may rotate per deploy.
static NONCE_ACTION_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"data:\{action:"([0-9a-f]{32})"\}"#).unwrap());
static EMBED_ACTION_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"nonce:[^,]+,action:"([0-9a-f]{32})""#).unwrap());
static PIXELDRAIN_ID_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^/(?:u|api/file)/([A-Za-z0-9]+)").unwrap());
static SOURCE_SRC_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"<source[^>]+src=["']([^"']+)["']"#).unwrap());
static PLAYER_FILE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""?file"?\s*:\s*["']([^"']+)["']"#).unwrap());

fn referer() -> String {
    format!("{BASE}/")
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let url = format!("{BASE}/?s={}&post_type=anime", query_escape(q));
    let body = http::page(LABEL, http::get(&url, &referer())).await?;
    Ok(parse_search(&body))
}

fn parse_search(body: &str) -> Vec<Anime> {
    let doc = Html::parse_document(body);
    let mut out = Vec::new();
    for li in doc.select(&sel("ul.chivsrc li")) {
        let Some(a) = li.select(&sel("h2 a")).next() else { continue };
        let (href, title) = (attr(&a, "href"), clean_sub_indo(&text_of(&a)));
        if !href.contains("/anime/") || title.is_empty() {
            continue;
        }
        let image = li.select(&sel("img")).next().map(|i| attr(&i, "src")).unwrap_or_default();
        out.push(Anime { name: title, url: href, image, source: SourceId::Otakudesu });
    }
    out
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let body = http::page(LABEL, http::get(anime_url, &referer())).await?;
    Ok(parse_episodes(&body))
}

fn parse_episodes(body: &str) -> Vec<Episode> {
    let doc = Html::parse_document(body);
    doc.select(&sel("div.episodelist ul li a[href]"))
        .filter_map(|a| {
            let href = attr(&a, "href");
            // "pembatas" rows are separators ("episodes 1-900 in progress"), not episodes.
            if !href.contains("/episode/") || href.contains("pembatas") {
                return None;
            }
            let text = text_of(&a);
            let num = [&href, &text]
                .iter()
                .find_map(|s| EPISODE_NUM_RE.captures(s).and_then(|c| c[1].parse().ok()))?;
            Some(Episode { num, url: href, title: clean_sub_indo(&text) })
        })
        .collect()
}

/// One Pixeldrain row of the download section: "<strong>MKV 1080p</strong> … <a>Pdrain</a>".
struct Download {
    height: u32,
    url: String, // link.desustream.com redirector
}

#[derive(Deserialize)]
struct Mirror {
    id: u64,
    i: u64,
    q: String,
}

fn parse_downloads(doc: &Html) -> Vec<Download> {
    let mut out = Vec::new();
    for li in doc.select(&sel("div.download li")) {
        let label = li.select(&sel("strong")).next().map(|s| text_of(&s)).unwrap_or_default();
        let height = height_of(&label);
        if height == 0 {
            continue;
        }
        for a in li.select(&sel("a[href]")) {
            let name = text_of(&a).to_lowercase();
            if name.contains("pdrain") || name.contains("pixeldrain") {
                out.push(Download { height, url: attr(&a, "href") });
            }
        }
    }
    out
}

fn parse_mirrors(doc: &Html) -> Vec<Mirror> {
    doc.select(&sel("div.mirrorstream a[data-content]"))
        .filter_map(|a| {
            let raw = BASE64_STANDARD.decode(attr(&a, "data-content")).ok()?;
            serde_json::from_slice::<Mirror>(&raw).ok().filter(|m| m.id != 0)
        })
        .collect()
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    let doc = Html::parse_document(&body);
    let mut h: Vec<u32> = parse_downloads(&doc).iter().map(|d| d.height).collect();
    h.extend(parse_mirrors(&doc).iter().map(|m| height_of(&m.q)));
    Ok(h)
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let page = http::text(LABEL, http::get(episode_url, &referer())).await?;
    let (mut downloads, mut mirrors) = {
        let doc = Html::parse_document(&page);
        (parse_downloads(&doc), parse_mirrors(&doc))
    };
    let want = height_of(quality);
    let ok = |url: String| Ok(Stream { url, referer: referer() });

    sort_by_height(&mut downloads, want, |d| d.height);
    for d in &downloads {
        if let Some(u) = resolve_pixeldrain(&d.url).await {
            return ok(u);
        }
    }

    sort_by_height(&mut mirrors, want, |m| height_of(&m.q));
    let nonce_action = NONCE_ACTION_RE.captures(&page).map(|c| c[1].to_owned());
    let embed_action = EMBED_ACTION_RE.captures(&page).map(|c| c[1].to_owned());
    let mut last_err = None;
    if let (false, Some(na), Some(ea)) = (mirrors.is_empty(), nonce_action, embed_action) {
        match ajax_data(&[("action", &na)]).await {
            Ok(nonce) => {
                for m in &mirrors {
                    let (id, i) = (m.id.to_string(), m.i.to_string());
                    let form = [("id", id.as_str()), ("i", &i), ("q", &m.q), ("nonce", &nonce), ("action", &ea)];
                    match ajax_data(&form).await {
                        Ok(src) => {
                            let raw = BASE64_STANDARD.decode(src).unwrap_or_default();
                            if let Some(u) = resolve_embed(&iframe_src(&String::from_utf8_lossy(&raw))).await {
                                return ok(u);
                            }
                        }
                        Err(e) => last_err = Some(e),
                    }
                }
            }
            Err(e) => last_err = Some(e),
        }
    }
    // Last resort: the embed the page itself loads by default.
    if let Some(u) = resolve_embed(&iframe_src(&page)).await {
        return ok(u);
    }
    Err(anyhow!("{LABEL}: no resolvable mirror for this episode{}", last_err.map(|e| format!(" ({e})")).unwrap_or_default()))
}

async fn ajax_data(form: &[(&str, &str)]) -> Result<String> {
    #[derive(Deserialize)]
    struct Payload {
        data: String,
    }
    let body = http::text(LABEL, http::post_form(&format!("{BASE}/wp-admin/admin-ajax.php"), &referer(), form)).await?;
    let p: Payload = serde_json::from_str(&body).map_err(|e| anyhow!("{LABEL}: unexpected admin-ajax response: {e}"))?;
    anyhow::ensure!(!p.data.is_empty(), "{LABEL}: empty admin-ajax data");
    Ok(p.data)
}

/// Blogger iframes are returned as-is (the player unwraps them); desustream
/// embeds are fetched and their file/Blogger URL extracted. A direct file is
/// probed first: some embeds carry googlevideo URLs pinned to the embed server's IP.
async fn resolve_embed(embed: &str) -> Option<String> {
    if let Some(m) = BLOGGER_RE.find(embed) {
        return Some(m.as_str().to_owned());
    }
    if !embed.contains("desustream") {
        return None;
    }
    let body = http::text(LABEL, http::get(embed, &referer())).await.ok()?;
    for re in [&*SOURCE_SRC_RE, &*PLAYER_FILE_RE] {
        if let Some(c) = re.captures(&body).filter(|c| c[1].starts_with("http")) {
            let u = html_escape::decode_html_entities(&c[1]).into_owned();
            return http::playable(&u, None).await.then_some(u);
        }
    }
    BLOGGER_RE.find(&body).map(|m| m.as_str().to_owned())
}

/// Follows the redirector one hop, maps pixeldrain.com/u/<id> to its direct
/// file, and probes it.
async fn resolve_pixeldrain(redirect_url: &str) -> Option<String> {
    let resp = http::PLAIN
        .get(redirect_url)
        .header("User-Agent", http::UA)
        .header("Referer", referer())
        .redirect(wreq::redirect::Policy::none())
        .send()
        .await
        .ok()?;
    let loc = resp.headers().get("location")?.to_str().ok()?;
    let u = pixeldrain_file(loc)?;
    http::playable(&u, None).await.then_some(u)
}

/// pixeldrain.com/u/<id> → pixeldrain.com/api/file/<id>; None for other hosts.
fn pixeldrain_file(location: &str) -> Option<String> {
    let path = location.strip_prefix(PIXELDRAIN)?;
    PIXELDRAIN_ID_RE.captures(path).map(|c| format!("{PIXELDRAIN}/api/file/{}", &c[1]))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Fixtures mirror the live markup GonimeId captured 2026-09-18.
    const SEARCH: &str = r#"<ul class="chivsrc"><li><img src="/p.jpg"/><h2><a href="https://otakudesu.blog/anime/borot-sub-indo/">Boruto: Naruto Next Generations Subtitle Indonesia</a></h2></li>
<li><h2><a href="https://otakudesu.blog/genres/action/">Not an anime</a></h2></li></ul>"#;
    const ANIME: &str = r#"<div class="episodelist"><ul><li><span><a href="/batch/btr-batch-sub-indo/">Boruto [BATCH] Subtitle Indonesia</a></span></li></ul></div>
<div class="episodelist"><ul>
<li><span><a href="/episode/btr-ng-episode-293-sub-indo/">Boruto Episode 293 Subtitle Indonesia</a></span></li>
<li><span><a href="/episode/btr-ng-episode-1-sub-indo/">Boruto Episode 1 Subtitle Indonesia</a></span></li>
<li><span><a href="/lengkap/btr-part-6/">Boruto Part 6</a></span></li>
<li><span><a href="/episode/pembatas-episode-episode-1-900-dalam-proses/">Pembatas Episode 1-900</a></span></li>
</ul></div>"#;

    #[test]
    fn search_skips_non_anime_and_strips_suffix() {
        let got = parse_search(SEARCH);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name, "Boruto: Naruto Next Generations");
        assert_eq!(got[0].image, "/p.jpg");
    }

    #[test]
    fn episodes_skip_batch_and_separators() {
        let nums: Vec<u32> = parse_episodes(ANIME).iter().map(|e| e.num).collect();
        assert_eq!(nums, [293, 1]);
    }

    #[test]
    fn downloads_and_mirrors() {
        let m = BASE64_STANDARD.encode(r#"{"id":138366,"i":1,"q":"720p"}"#);
        let html = format!(
            r##"<div class="download"><ul><li><strong>Mp4 720p</strong> <a href="/go?a">Filedon</a> <a href="/go?b">Pdrain</a></li>
<li><strong>MKV 1080p</strong> <a href="/go?c">Pdrain</a></li></ul></div>
<div class="mirrorstream"><a href="#" data-content="{m}">desudrive</a><a data-content="!!">bad</a></div>"##
        );
        let doc = Html::parse_document(&html);
        let d = parse_downloads(&doc);
        assert_eq!(d.iter().map(|d| (d.height, d.url.as_str())).collect::<Vec<_>>(), [(720, "/go?b"), (1080, "/go?c")]);
        let mirrors = parse_mirrors(&doc);
        assert_eq!((mirrors.len(), mirrors[0].id, mirrors[0].i, mirrors[0].q.as_str()), (1, 138366, 1, "720p"));
        let page = r#"$.ajax(u,{data:{...e,nonce:window.__x__nonce,action:"2a3505c93b0035d3f455df82bf976b84"}});$.ajax(u,{data:{action:"aa1208d27f29ca340c92c66d1926f13f"}});"#;
        assert_eq!(&NONCE_ACTION_RE.captures(page).unwrap()[1], "aa1208d27f29ca340c92c66d1926f13f");
        assert_eq!(&EMBED_ACTION_RE.captures(page).unwrap()[1], "2a3505c93b0035d3f455df82bf976b84");
    }

    #[test]
    fn pixeldrain_mapping() {
        assert_eq!(pixeldrain_file("https://pixeldrain.com/u/AbC123").as_deref(), Some("https://pixeldrain.com/api/file/AbC123"));
        assert_eq!(pixeldrain_file("https://mega.nz/file/x"), None);
    }
}
