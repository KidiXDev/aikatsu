//! v2.samehadaku.how — WordPress. Series search via the WP REST API (the
//! HTML search mixes episode/batch posts, newest first, so series often fall
//! off page 1). Players carry their iframe in `data-embed` (admin-ajax
//! `player_ajax` for older pages); Wibufile plays through the HTTP/3 proxy,
//! Pixeldrain downloads and Blogspot are fallbacks.

use super::{Anime, BLOGGER_RE, Episode, SourceId, Stream, attr, clean_sub_indo, height_of, iframe_src, sort_by_height, text_of};
use crate::http::{self, query_escape, sel};
use futures_util::StreamExt;
use anyhow::{Result, anyhow};
use regex::Regex;
use scraper::Html;
use serde::Deserialize;
use std::collections::HashSet;
use std::sync::LazyLock;

const BASE: &str = "https://v2.samehadaku.how";
const LABEL: &str = "Samehadaku";

static EPISODE_NUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)episode[- ]*(\d+)").unwrap());
static PIXELDRAIN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"pixeldrain\.com/(?:u|api/file)/([A-Za-z0-9]+)").unwrap());
static WIBUFILE_API_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"(?i)\burl\s*:\s*["']([^"']+)["']"#).unwrap());

fn referer() -> String {
    format!("{BASE}/")
}

pub async fn search(q: &str) -> Result<Vec<Anime>> {
    let api = format!("{BASE}/wp-json/wp/v2/anime?search={}&per_page=20&_embed=wp:featuredmedia", query_escape(q));
    match http::text(LABEL, http::get(&api, &referer())).await.map(|b| parse_rest(&b)) {
        Ok(Some(mut found)) => {
            rank(&mut found, q);
            Ok(found)
        }
        Ok(None) | Err(_) => {
            tracing::debug!("{LABEL}: REST search unavailable, falling back to the HTML search");
            let body = http::page(LABEL, http::get(&format!("{BASE}/?s={}", query_escape(q)), &referer())).await?;
            Ok(parse_search(&body))
        }
    }
}

/// WP relevance puts "One Piece: Heroines" above "One Piece": exact title
/// first, then titles starting with the query, then the rest (shortest first).
fn rank(found: &mut [Anime], q: &str) {
    let q = q.to_lowercase();
    found.sort_by_cached_key(|a| {
        let name = a.name.to_lowercase();
        (name != q, !name.starts_with(&q), name.len())
    });
}

/// `/wp-json/wp/v2/anime` results; None when the body isn't the expected JSON.
fn parse_rest(body: &str) -> Option<Vec<Anime>> {
    let items: Vec<serde_json::Value> = serde_json::from_str(body).ok()?;
    Some(
        items
            .iter()
            .filter_map(|a| {
                let url = a["link"].as_str()?.to_owned();
                let name = clean_sub_indo(&html_escape::decode_html_entities(a["title"]["rendered"].as_str()?));
                let media = &a["_embedded"]["wp:featuredmedia"][0];
                let image = media["media_details"]["sizes"]["medium"]["source_url"].as_str().or(media["source_url"].as_str()).unwrap_or_default().to_owned();
                (!name.is_empty() && url.contains("/anime/")).then_some(Anime { name, url, image, source: SourceId::Samehadaku })
            })
            .collect(),
    )
}

fn parse_search(body: &str) -> Vec<Anime> {
    let doc = Html::parse_document(body);
    doc.select(&sel("article.animepost div.animposx > a[href], article.animpost div.animposx > a[href]"))
        .filter_map(|a| {
            let href = attr(&a, "href");
            let mut title = clean_sub_indo(&attr(&a, "title"));
            if title.is_empty() {
                title = clean_sub_indo(&a.select(&sel(".title")).map(|t| text_of(&t)).collect::<String>());
            }
            if !href.contains("/anime/") || title.is_empty() {
                return None;
            }
            let image = a.select(&sel("img")).next().map(|i| attr(&i, "src")).unwrap_or_default();
            Some(Anime { name: title, url: href, image, source: SourceId::Samehadaku })
        })
        .collect()
}

pub async fn episodes(anime_url: &str) -> Result<Vec<Episode>> {
    match rest_episodes(anime_url).await {
        Ok(eps) if !eps.is_empty() => return Ok(eps),
        Ok(_) => {}
        Err(e) => tracing::debug!("{LABEL}: REST episode list failed ({e:#}); parsing the page"),
    }
    // The series page itself only lists the newest 100 episodes.
    let body = http::page(LABEL, http::get(anime_url, &referer())).await?;
    Ok(parse_episodes(&body))
}

/// Every episode post shares the series' category:
/// /anime?slug=<slug> → category → /posts?categories=<c> (100 per page, pages fetched 4 at a time).
async fn rest_episodes(anime_url: &str) -> Result<Vec<Episode>> {
    let slug = url::Url::parse(anime_url)?.path_segments().and_then(|mut p| p.rfind(|s| !s.is_empty()).map(str::to_owned)).unwrap_or_default();
    let series: Vec<serde_json::Value> =
        serde_json::from_str(&http::text(LABEL, http::get(&format!("{BASE}/wp-json/wp/v2/anime?slug={slug}&_fields=id,categories"), &referer())).await?)?;
    let category = series.first().and_then(|a| a["categories"][0].as_i64()).ok_or_else(|| anyhow!("{LABEL}: no category for {slug}"))?;
    let page_url = |n: usize| format!("{BASE}/wp-json/wp/v2/posts?categories={category}&per_page=100&page={n}&_fields=link,title");

    let first = http::CHROME.get(page_url(1)).header("Referer", referer()).send().await?;
    let pages: usize = first.headers().get("x-wp-totalpages").and_then(|v| v.to_str().ok()?.parse().ok()).unwrap_or(1);
    let mut bodies = vec![first.text().await?];
    let rest: Vec<Result<String>> = futures_util::stream::iter(2..=pages.min(50))
        .map(|n| async move { http::text(LABEL, http::get(&page_url(n), &referer())).await })
        .buffered(4)
        .collect()
        .await;
    for body in rest {
        bodies.push(body?);
    }
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for body in &bodies {
        for ep in parse_rest_episodes(body)? {
            if seen.insert(ep.num) {
                out.push(ep);
            }
        }
    }
    Ok(out)
}

fn parse_rest_episodes(body: &str) -> Result<Vec<Episode>> {
    let posts: Vec<serde_json::Value> = serde_json::from_str(body).map_err(|e| anyhow!("{LABEL}: unexpected REST posts response: {e}"))?;
    Ok(posts
        .iter()
        .filter_map(|p| {
            let url = p["link"].as_str()?.to_owned();
            let title = html_escape::decode_html_entities(p["title"]["rendered"].as_str()?).trim().to_owned();
            if url.contains("/batch/") || title.to_lowercase().contains("batch") {
                return None;
            }
            let num = [&title, &url].iter().find_map(|s| EPISODE_NUM_RE.captures(s).and_then(|c| c[1].parse().ok())).filter(|&n: &u32| n > 0)?;
            Some(Episode { num, url, title })
        })
        .collect())
}

fn parse_episodes(body: &str) -> Vec<Episode> {
    let doc = Html::parse_document(body);
    // Current Tailwind layout: each row's title is an `h4 > a` ("… Episode 12 [END]").
    let mut seen = HashSet::new();
    let current: Vec<Episode> = doc
        .select(&sel("h4 > a[href]"))
        .filter_map(|a| {
            let (href, title) = (attr(&a, "href"), text_of(&a));
            let num = [&title, &href].iter().find_map(|s| EPISODE_NUM_RE.captures(s).and_then(|c| c[1].parse().ok())).filter(|&n: &u32| n > 0)?;
            seen.insert(href.clone()).then_some(Episode { num, url: href, title })
        })
        .collect();
    if !current.is_empty() {
        return current;
    }
    // Older "eastplay" layout.
    doc.select(&sel("div.lstepsiode ul li"))
        .filter_map(|li| {
            let a = li.select(&sel("span.eps a")).next()?;
            let href = attr(&a, "href");
            let num = text_of(&a)
                .parse()
                .ok()
                .or_else(|| EPISODE_NUM_RE.captures(&href).and_then(|c| c[1].parse().ok()))
                .filter(|&n: &u32| n > 0)?;
            if href.is_empty() {
                return None;
            }
            let title = li.select(&sel("span.lchx a")).next().map(|t| text_of(&t)).unwrap_or_default();
            Some(Episode { num, url: href, title })
        })
        .collect()
}

/// One player entry. `embed` is the iframe/file URL when the page carries it
/// (`data-embed`, or a download-list Pixeldrain link); otherwise it comes from
/// admin-ajax with post/nume/type.
#[derive(Debug, PartialEq)]
struct Server {
    post: String,
    nume: String,
    typ: String,
    embed: String,
    height: u32,
}

/// Keeps only the hosts this provider understands.
fn parse_servers(body: &str) -> Vec<Server> {
    let doc = Html::parse_document(body);
    let mut out = Vec::new();
    for d in doc.select(&sel("#server .east_player_option")) {
        let label = text_of(&d);
        let lower = label.to_lowercase();
        if !["pixel", "blogspot", "wibufile"].iter().any(|h| lower.contains(h)) {
            continue;
        }
        let s = Server {
            post: attr(&d, "data-post"),
            nume: attr(&d, "data-nume"),
            typ: attr(&d, "data-type"),
            embed: iframe_src(&attr(&d, "data-embed")),
            height: height_of(&label),
        };
        if !s.embed.is_empty() || (!s.post.is_empty() && !s.nume.is_empty()) {
            out.push(s);
        }
    }
    // Direct per-resolution Pixeldrain files live in the download list.
    let mut seen = HashSet::new();
    for li in doc.select(&sel(".download-eps li")) {
        let label = li.select(&sel("strong")).next().map(|s| text_of(&s)).unwrap_or_default();
        let height = height_of(&label);
        let href = li.select(&sel(r#"a[href*="pixeldrain.com/"]"#)).next().map(|a| attr(&a, "href")).unwrap_or_default();
        if height > 0 && !href.is_empty() && seen.insert(height) {
            out.push(Server { post: String::new(), nume: String::new(), typ: String::new(), embed: href, height });
        }
    }
    out
}

pub async fn heights(episode_url: &str) -> Result<Vec<u32>> {
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    Ok(parse_servers(&body).iter().map(|s| s.height).collect())
}

pub async fn stream(episode_url: &str, quality: &str) -> Result<Stream> {
    let body = http::page(LABEL, http::get(episode_url, &referer())).await?;
    let mut servers = parse_servers(&body);
    anyhow::ensure!(!servers.is_empty(), "{LABEL}: no player servers on episode page (layout changed?)");
    sort_by_height(&mut servers, height_of(quality), |s| s.height);

    let mut last_err = None;
    let mut dead_hosts = HashSet::new();
    for s in &servers {
        let embed = if s.embed.is_empty() {
            let form = [("action", "player_ajax"), ("post", s.post.as_str()), ("nume", &s.nume), ("type", &s.typ)];
            match http::text(LABEL, http::post_form(&format!("{BASE}/wp-admin/admin-ajax.php"), &referer(), &form)).await {
                Ok(b) => iframe_src(&b),
                Err(e) => {
                    last_err = Some(e);
                    continue;
                }
            }
        } else {
            s.embed.clone()
        };
        let mut u = resolve_embed(&embed);
        if u.is_empty() {
            match resolve_wibufile(&embed).await {
                Ok(w) => u = w,
                Err(e) => {
                    last_err = Some(e);
                    continue;
                }
            }
        }
        // Unknown host, or a removed file: try the next server. A host that
        // failed once is skipped for its other resolutions (dead CDNs time out).
        let host = url::Url::parse(&u).ok().and_then(|x| x.host_str().map(str::to_owned)).unwrap_or_default();
        if u.is_empty() || dead_hosts.contains(&host) {
            continue;
        }
        if !u.contains("blogger.com") && !http::playable(&u, None).await {
            dead_hosts.insert(host);
            continue;
        }
        return Ok(Stream { url: u, referer: referer() });
    }
    Err(anyhow!("{LABEL}: no resolvable server for this episode{}", last_err.map(|e| format!(" ({e})")).unwrap_or_default()))
}

pub fn is_wibufile(u: &str) -> bool {
    url::Url::parse(u).is_ok_and(|u| {
        matches!(u.scheme(), "http" | "https")
            && u.host_str().is_some_and(|h| {
                let h = h.to_lowercase();
                h == "wibufile.com" || h.ends_with(".wibufile.com")
            })
    })
}

async fn fetch_wibufile(url: &str, referer: &str) -> Result<String> {
    let resp = http::PLAIN.get(url).header("User-Agent", http::UA).header("Referer", referer).send().await?;
    anyhow::ensure!(resp.status().as_u16() == 200, "{LABEL} wibufile: HTTP {}", resp.status());
    Ok(resp.text().await?)
}

/// Embed page → `url:"…"` API → JSON `{sources:[{file}]}`, restricted to *.wibufile.com.
async fn resolve_wibufile(src: &str) -> Result<String> {
    let Ok(embed) = url::Url::parse(src) else { return Ok(String::new()) };
    if !is_wibufile(src) {
        return Ok(String::new());
    }
    if embed.path().to_lowercase().ends_with(".mp4") {
        return Ok(src.to_owned());
    }
    let body = fetch_wibufile(src, &referer()).await?;
    let Some(c) = WIBUFILE_API_RE.captures(&body) else { return Ok(String::new()) };
    let api = embed.join(&html_escape::decode_html_entities(&c[1]))?;
    if !is_wibufile(api.as_str()) {
        return Ok(String::new());
    }
    #[derive(Deserialize)]
    struct File {
        file: String,
    }
    #[derive(Deserialize)]
    struct Resp {
        sources: Vec<File>,
    }
    let resp: Resp = serde_json::from_str(&fetch_wibufile(api.as_str(), src).await?)
        .map_err(|e| anyhow!("{LABEL} wibufile API: invalid response: {e}"))?;
    Ok(resp
        .sources
        .iter()
        .filter_map(|f| api.join(&f.file).ok())
        .map(String::from)
        .find(|u| is_wibufile(u))
        .unwrap_or_default())
}

fn resolve_embed(src: &str) -> String {
    if let Some(c) = PIXELDRAIN_RE.captures(src) {
        return format!("https://pixeldrain.com/api/file/{}", &c[1]);
    }
    BLOGGER_RE.find(src).map(|m| m.as_str().to_owned()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Fixtures mirror the live markup of 2026-10 (toumei-na-yoru-ni-kakeru).
    #[test]
    fn rest_search() {
        let body = r#"[{"link":"https:\/\/v2.samehadaku.how\/anime\/toumei-na-yoru-ni-kakeru\/","title":{"rendered":"Kimetsu no Yaiba &#8211; The Movie"},
            "_embedded":{"wp:featuredmedia":[{"source_url":"https://x/full.jpg","media_details":{"sizes":{"medium":{"source_url":"https://x/m.jpg"}}}}]}},
            {"link":"https:\/\/v2.samehadaku.how\/anime\/naruto\/","title":{"rendered":"Naruto"}}]"#;
        let found = parse_rest(body).unwrap();
        assert_eq!(found.len(), 2);
        assert_eq!((found[0].name.as_str(), found[0].image.as_str()), ("Kimetsu no Yaiba – The Movie", "https://x/m.jpg"));
        assert_eq!((found[1].url.as_str(), found[1].image.as_str()), ("https://v2.samehadaku.how/anime/naruto/", ""));
        assert!(parse_rest("<html>blocked</html>").is_none());
    }

    #[test]
    fn ranking_and_rest_episodes() {
        let mk = |n: &str| Anime { name: n.into(), url: String::new(), image: String::new(), source: SourceId::Samehadaku };
        let mut v = vec![mk("One Piece: Heroines"), mk("Monsters"), mk("One Piece Film: Red"), mk("One Piece")];
        rank(&mut v, "one piece");
        assert_eq!(v.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(), ["One Piece", "One Piece: Heroines", "One Piece Film: Red", "Monsters"]);

        let eps = parse_rest_episodes(
            r#"[{"link":"https:\/\/v2.samehadaku.how\/one-piece-episode-1180\/","title":{"rendered":"One Piece Episode 1180"}},
                {"link":"https:\/\/v2.samehadaku.how\/batch\/x-episode-1-12-batch\/","title":{"rendered":"X Episode 1-12 [BATCH]"}},
                {"link":"https:\/\/v2.samehadaku.how\/toumei-na-yoru-ni-kakeru-episode-12-end\/","title":{"rendered":"Toumei &#8211; Episode 12 [END]"}}]"#,
        )
        .unwrap();
        assert_eq!(eps.iter().map(|e| (e.num, e.title.as_str())).collect::<Vec<_>>(), [(1180, "One Piece Episode 1180"), (12, "Toumei – Episode 12 [END]")]);
    }

    #[test]
    fn html_search_keeps_series_only() {
        let s = parse_search(
            r#"<article class="animepost"><div class="animposx"><a href="https://v2.samehadaku.how/toumei-na-yoru-ni-kakeru-episode-1/" title="Toumei na Yoru ni Kakeru Episode 1"></a></div></article>
<article class="animepost"><div class="animposx"><a href="https://v2.samehadaku.how/anime/toumei-na-yoru-ni-kakeru/" title="Toumei na Yoru ni Kakeru"><img src="t.jpg"></a></div></article>"#,
        );
        assert_eq!((s.len(), s[0].name.as_str(), s[0].image.as_str()), (1, "Toumei na Yoru ni Kakeru", "t.jpg"));
    }

    #[test]
    fn episodes_both_layouts() {
        let current = parse_episodes(
            r#"<div class="max-h-[520px]"><div class="flex"><div><a href="https://v2.samehadaku.how/toumei-na-yoru-ni-kakeru-episode-12-end/">12</a></div>
<div><h4><a href="https://v2.samehadaku.how/toumei-na-yoru-ni-kakeru-episode-12-end/">Toumei na Yoru ni Kakeru Episode 12 [END]</a></h4></div></div>
<div class="flex"><div><h4><a href="https://v2.samehadaku.how/toumei-na-yoru-ni-kakeru-kimi-to-me-ni-mienai-koi-wo-shita-episode-6/">Toumei na Yoru ni Kakeru Episode 6</a></h4></div></div></div>"#,
        );
        assert_eq!(current.iter().map(|e| e.num).collect::<Vec<_>>(), [12, 6]);
        assert_eq!(current[0].title, "Toumei na Yoru ni Kakeru Episode 12 [END]");

        let old = parse_episodes(
            r#"<div class="lstepsiode"><ul><li><span class="eps"><a href="/one-piece-episode-1100/">1100</a></span><span class="lchx"><a>One Piece Episode 1100</a></span></li>
<li><span class="eps"><a href="/one-piece-episode-7/">x</a></span></li></ul></div>"#,
        );
        assert_eq!(old.iter().map(|e| e.num).collect::<Vec<_>>(), [1100, 7]);
    }

    #[test]
    fn servers_from_data_embed_and_downloads() {
        let servers = parse_servers(
            r#"<div id="server"><ul>
<li><div class="east_player_option" data-post="52758" data-nume="1" data-type="schtml" data-embed="&lt;iframe src=&quot;https://www.blogger.com/video.g?token=AD6v5dz&quot; class=&quot;w-full&quot;&gt;&lt;/iframe&gt;"><span>Blogspot </span></div></li>
<li><div class="east_player_option" data-post="52758" data-nume="2" data-type="schtml" data-embed="&lt;iframe src=&quot;https://filedon.co/embed/x&quot;&gt;"><span>VIP STREAMING</span></div></li>
<li><div class="east_player_option" data-post="52758" data-nume="4" data-type="schtml" data-embed="&lt;iframe src=&quot;https://s0.wibufile.com/video01/TnYnK-12-END-MP4HD.mp4&quot;&gt;"><span>Wibufile  720p</span></div></li>
<li><div class="east_player_option" data-post="1" data-nume="3" data-type="schtml"><span>Wibufile 480p</span></div></li>
</ul></div>
<div class="download-eps"><ul><li><strong>360p</strong><div class="download-eps-links"><span><a href="https://gofile.io/d/x">Gofile</a></span><span><a href="https://pixeldrain.com/u/PDYSxwh5"> Pixeldrain</a></span></div></li></ul></div>"#,
        );
        let embeds: Vec<(&str, u32)> = servers.iter().map(|s| (s.embed.as_str(), s.height)).collect();
        assert_eq!(
            embeds,
            [
                ("https://www.blogger.com/video.g?token=AD6v5dz", 0),
                ("https://s0.wibufile.com/video01/TnYnK-12-END-MP4HD.mp4", 720),
                ("", 480), // no data-embed: resolved through admin-ajax
                ("https://pixeldrain.com/u/PDYSxwh5", 360),
            ]
        );
        assert_eq!(resolve_embed(&servers[0].embed), "https://www.blogger.com/video.g?token=AD6v5dz");
        assert_eq!(resolve_embed(&servers[3].embed), "https://pixeldrain.com/api/file/PDYSxwh5");
    }

    #[test]
    fn wibufile_host_check() {
        assert!(is_wibufile("https://s0.wibufile.com/video01/episode.mp4"));
        assert!(!is_wibufile("https://wibufile.com.evil.example/episode.mp4"));
    }
}
