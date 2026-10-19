//! HTTP helpers. Scraping uses a Chrome-like client because the sites block
//! connections that don't look like a browser.

use anyhow::{Result, anyhow, bail};
use futures_util::StreamExt;
use scraper::{Html, Selector};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};
use wreq::redirect::Policy;

/// Browser user agent for file hosts.
pub const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0";
/// AniList answers browser UAs with 403, so API calls identify as an API client.
pub const API_UA: &str = "Aikatsu/0.1 (+https://github.com/KidiXDev/aikatsu)";
const MAX_BODY: usize = 8 << 20;

pub static CHROME: LazyLock<wreq::Client> = LazyLock::new(|| {
    wreq::Client::builder()
        .emulation(wreq_util::Emulation::Chrome149)
        .cookie_store(true)
        .redirect(Policy::limited(10))
        .timeout(Duration::from_secs(8))
        .build()
        .expect("chrome client")
});

pub static PLAIN: LazyLock<wreq::Client> = LazyLock::new(|| {
    wreq::Client::builder()
        .redirect(Policy::limited(10))
        .connect_timeout(Duration::from_secs(8))
        .build()
        .expect("plain client")
});

/// Provider-side failure (down, blocked, challenged). Counts toward the
/// circuit breaker; parser errors do not.
#[derive(Debug)]
pub struct Unavailable(pub String);

impl std::fmt::Display for Unavailable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Unavailable {}

pub fn is_unavailable(err: &anyhow::Error) -> bool {
    err.downcast_ref::<Unavailable>().is_some()
}

/// A response under 400: the body plus what scripts read besides it (a
/// redirect's `location`, WordPress' `x-wp-totalpages`).
pub struct Fetched {
    pub status: u16,
    /// Lowercase names; the last value of a repeated header wins.
    pub headers: Vec<(String, String)>,
    /// After redirects.
    pub url: String,
    pub body: String,
}

/// Retries twice, 300 ms apart, on server errors and dropped connections.
/// Statuses from 400 are errors; bodies over 8 MiB are rejected.
pub async fn fetch(label: &str, rb: wreq::RequestBuilder) -> Result<Fetched> {
    let mut last = anyhow!("{label}: request failed");
    for attempt in 0..3 {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
        let req = rb.try_clone().ok_or_else(|| anyhow!("{label}: request not cloneable"))?;
        match req.send().await {
            Ok(resp) => {
                let status = resp.status().as_u16();
                if status < 400 {
                    let headers = resp.headers().iter().map(|(k, v)| (k.as_str().to_owned(), String::from_utf8_lossy(v.as_bytes()).into_owned())).collect();
                    let url = resp.uri().to_string();
                    let mut body = Vec::new();
                    let mut stream = resp.bytes_stream();
                    while let Some(chunk) = stream.next().await {
                        let chunk = chunk?;
                        if chunk.len() > MAX_BODY - body.len() {
                            bail!("{label}: response over 8 MiB");
                        }
                        body.extend_from_slice(&chunk);
                    }
                    return Ok(Fetched { status, headers, url, body: String::from_utf8_lossy(&body).into_owned() });
                }
                let err = status_error(label, status);
                if status < 500 {
                    return Err(err);
                }
                last = err;
            }
            Err(e) => last = Unavailable(format!("{label}: {e}")).into(),
        }
    }
    Err(last)
}

/// `fetch`, but only a 2xx body counts.
pub async fn text(label: &str, rb: wreq::RequestBuilder) -> Result<String> {
    let f = fetch(label, rb).await?;
    if !(200..300).contains(&f.status) {
        return Err(status_error(label, f.status));
    }
    Ok(f.body)
}

fn status_error(label: &str, status: u16) -> anyhow::Error {
    match status {
        403 | 429 => Unavailable(format!("{label} blocked the request: HTTP {status}/challenge")).into(),
        s if s >= 500 => Unavailable(format!("{label} temporarily unavailable: HTTP {s}")).into(),
        s => anyhow!("{label}: HTTP {s}"),
    }
}

/// GET pages from the last 10 minutes: the player reads an episode page twice
/// (qualities, then resolve), and reopening a series or repeating a search
/// shouldn't refetch. Only challenge-free pages are kept.
static PAGES: LazyLock<Mutex<HashMap<String, (String, Instant)>>> = LazyLock::new(Default::default);
const PAGE_TTL: Duration = Duration::from_secs(600);

pub fn clear_pages() {
    PAGES.lock().unwrap().clear();
}

/// Fetches an HTML page, rejecting Cloudflare-style challenge pages. Returns
/// the body rather than `Html` because `Html` is !Send and can't cross awaits.
pub async fn page(label: &str, rb: wreq::RequestBuilder) -> Result<String> {
    let key = rb.try_clone().and_then(|r| r.build().ok()).filter(|r| r.method().as_str() == "GET").map(|r| r.uri().to_string());
    let hit = key.as_ref().and_then(|k| PAGES.lock().unwrap().get(k).filter(|(_, at)| at.elapsed() < PAGE_TTL).map(|(b, _)| b.clone()));
    if let Some(body) = hit {
        return Ok(body);
    }
    let body = text(label, rb).await?;
    check_challenge(&Html::parse_document(&body), label)?;
    if let Some(k) = key {
        let mut pages = PAGES.lock().unwrap();
        pages.retain(|_, (_, at)| at.elapsed() < PAGE_TTL);
        pages.insert(k, (body.clone(), Instant::now()));
    }
    Ok(body)
}

const CHALLENGE_PHRASES: [&str; 8] = [
    "cf-error",
    "checking your browser before accessing",
    "ddos protection by cloudflare",
    "please enable cookies and reload",
    "performance & security by cloudflare",
    "ray id:",
    "please complete the security check to access",
    "attention required! | cloudflare",
];

pub fn check_challenge(doc: &Html, label: &str) -> Result<()> {
    let title = first_text(doc, "title").to_lowercase();
    let blocked = ["just a moment", "attention required", "access denied"].iter().any(|p| title.contains(p))
        || ["#cf-wrapper", "#challenge-form", "#cf-error-details", ".cf-browser-verification"]
            .iter()
            .any(|s| doc.select(&sel(s)).next().is_some())
        || {
            let body = doc.root_element().text().collect::<String>().to_lowercase();
            CHALLENGE_PHRASES.iter().any(|p| body.contains(p))
        };
    if blocked {
        Err(Unavailable(format!("{label} blocked the request: captcha/challenge")).into())
    } else {
        Ok(())
    }
}

/// Asks for one byte; true when the host serves the file (200/206). Uses the
/// plain client: file hosts (pixeldrain, googlevideo) don't negotiate h2 ALPN.
pub async fn playable(url: &str, referer: Option<&str>) -> bool {
    let mut rb = PLAIN.get(url).header("User-Agent", UA).header("Range", "bytes=0-0").timeout(Duration::from_secs(10));
    if let Some(r) = referer {
        rb = rb.header("Referer", r);
    }
    matches!(rb.send().await.map(|r| r.status().as_u16()), Ok(200 | 206))
}

pub fn sel(css: &str) -> Selector {
    Selector::parse(css).unwrap_or_else(|e| panic!("bad selector {css}: {e}"))
}

pub fn first_text(doc: &Html, css: &str) -> String {
    doc.select(&sel(css)).next().map(|e| e.text().collect::<String>().trim().to_owned()).unwrap_or_default()
}

/// `raw` resolved against `base`, or "" when either is invalid.
pub fn absolute(base: &str, raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return String::new();
    }
    url::Url::parse(base).and_then(|b| b.join(raw)).map(String::from).unwrap_or_default()
}

pub fn query_escape(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn rejects_oversized_bodies_before_the_response_ends() {
        use axum::{Router, body::{Body, Bytes}, routing::get};
        use futures_util::stream;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app = Router::new()
            .route("/small", get(|| async { "small response" }))
            .route("/large", get(|| async {
                let first = stream::once(async { Ok::<_, std::io::Error>(Bytes::from(vec![b'x'; MAX_BODY + 1])) });
                Body::from_stream(first.chain(stream::pending()))
            }));
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        assert_eq!(text("test", PLAIN.get(format!("http://{addr}/small"))).await.unwrap(), "small response");
        let error = tokio::time::timeout(Duration::from_secs(5), fetch("test", PLAIN.get(format!("http://{addr}/large"))))
            .await.expect("the limit must reject a body without waiting for EOF").err().unwrap();
        assert!(error.to_string().contains("over 8 MiB"));
        server.abort();
    }
}
