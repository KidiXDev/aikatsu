//! Local proxy for the two hosts mpv can't play directly: Blogger video only
//! answers browser-like connections, and Wibufile only streams well over HTTP/3.

use anyhow::{Result, anyhow};
use axum::body::Body;
use axum::extract::{Path, Request};
use axum::http::{HeaderMap, Method, StatusCode};
use axum::response::Response;
use futures_util::StreamExt;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use tokio::sync::OnceCell;

#[derive(Clone)]
enum Upstream {
    /// googlevideo: Chrome fingerprint, forced HTTP/1.1, no whole-request timeout.
    Chrome { url: String },
    /// Wibufile: HTTP/3 with the site's Referer.
    H3 { url: String, referer: String },
    Lan { url: String, key: String, client: reqwest::Client, cancel: tokio_util::sync::CancellationToken },
}

static ROUTES: LazyLock<Mutex<HashMap<String, Upstream>>> = LazyLock::new(Default::default);
static PORT: OnceCell<u16> = OnceCell::const_new();

static CHROME_H1: LazyLock<wreq::Client> = LazyLock::new(|| {
    wreq::Client::builder()
        .emulation(wreq_util::Emulation::Chrome149)
        .http1_only()
        .redirect(wreq::redirect::Policy::limited(10))
        .build()
        .expect("proxy client")
});

pub(crate) static H3: LazyLock<reqwest::Client> = LazyLock::new(|| {
    let builder = reqwest::Client::builder()
        .http3_prior_knowledge()
        // Unread data up to the window sits in RAM once mpv's cache is full;
        // 16 MiB still covers hundreds of Mbit/s at high RTT.
        .http3_stream_receive_window(16 << 20)
        .http3_conn_receive_window(32 << 20);
    // reqwest's default verifier (rustls-platform-verifier) panics on Android without a JNI init.
    #[cfg(target_os = "android")]
    let builder = builder.tls_certs_only(webpki_root_certs::TLS_SERVER_ROOT_CERTS.iter().filter_map(|c| reqwest::Certificate::from_der(c).ok()));
    builder.build().expect("h3 client")
});

async fn port() -> Result<u16> {
    PORT.get_or_try_init(|| async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let port = listener.local_addr()?.port();
        let app = axum::Router::new().route("/stream/{id}", axum::routing::any(serve));
        tokio::spawn(async move {
            if let Err(e) = axum::serve(listener, app).await {
                tracing::error!("stream proxy stopped: {e}");
            }
        });
        anyhow::Ok(port)
    })
    .await
    .copied()
}

async fn register(up: Upstream) -> Result<String> {
    let port = port().await?;
    let id = crate::lan::secret();
    ROUTES.lock().unwrap().insert(id.clone(), up);
    Ok(format!("http://127.0.0.1:{port}/stream/{id}"))
}

pub fn clear() {
    for (_, up) in ROUTES.lock().unwrap().drain() {
        if let Upstream::Lan { cancel, .. } = up { cancel.cancel(); }
    }
}

pub(crate) async fn lan(url: String, key: String, client: reqwest::Client) -> Result<String> {
    register(Upstream::Lan { url, key, client, cancel: tokio_util::sync::CancellationToken::new() }).await
}

/// Blogger page → googlevideo URL → proxied URL. Retries the resolve 3 times
/// unless Blogger says the video is gone, and checks the CDN actually serves it.
pub async fn blogger(blogger_url: &str) -> Result<String> {
    let mut last = anyhow!("blogger: not attempted");
    for attempt in 1..=3u64 {
        match crate::blogger::resolve(blogger_url).await {
            Ok(url) => {
                let status = CHROME_H1.head(&url).send().await.map(|r| r.status().as_u16()).unwrap_or(0);
                if status == 0 || (200..300).contains(&status) {
                    return register(Upstream::Chrome { url }).await;
                }
                last = anyhow!("blogger CDN not serving video (HTTP {status})");
            }
            Err(e) if e.downcast_ref::<crate::blogger::Gone>().is_some() => return Err(e),
            Err(e) => last = e,
        }
        tokio::time::sleep(std::time::Duration::from_millis(500 * attempt)).await;
    }
    Err(last)
}

/// Wibufile video, which streams well only over HTTP/3. A host check, not a
/// plugin's say: the proxy only ever opens these.
pub fn is_wibufile(u: &str) -> bool {
    url::Url::parse(u).is_ok_and(|u| {
        matches!(u.scheme(), "http" | "https")
            && u.host_str().is_some_and(|h| {
                let h = h.to_lowercase();
                h == "wibufile.com" || h.ends_with(".wibufile.com")
            })
    })
}

pub async fn wibufile(url: &str, referer: &str) -> Result<String> {
    anyhow::ensure!(is_wibufile(url), "invalid Wibufile video URL");
    let probe = H3.head(url).header("Referer", referer).timeout(std::time::Duration::from_secs(3)).send().await?;
    anyhow::ensure!(probe.status().is_success(), "wibufile HTTP/3 probe returned {}", probe.status());
    register(Upstream::H3 { url: url.to_owned(), referer: referer.to_owned() }).await
}

const PASS_HEADERS: [&str; 4] = ["content-type", "content-length", "content-range", "accept-ranges"];

async fn serve(Path(id): Path<String>, req: Request) -> Response {
    let Some(up) = ROUTES.lock().unwrap().get(&id).cloned() else {
        return status(StatusCode::NOT_FOUND);
    };
    let head = req.method() == Method::HEAD;
    if !head && req.method() != Method::GET {
        return status(StatusCode::METHOD_NOT_ALLOWED);
    }
    let range = req.headers().get("range").and_then(|v| v.to_str().ok()).map(str::to_owned);
    let (code, headers, body) = match up {
        Upstream::Lan { url, key, client, cancel } => {
            let mut rb = if head { client.head(&url) } else { client.get(&url) }.bearer_auth(key);
            if let Some(r) = &range { rb = rb.header("Range", r); }
            let result = tokio::select! {
                _ = cancel.cancelled() => return status(StatusCode::GONE),
                result = rb.send() => result,
            };
            match result {
                Ok(r) => (r.status().as_u16(), copy_headers(r.headers().iter().map(|(k, v)| (k.as_str(), v.as_bytes()))),
                    Body::from_stream(r.bytes_stream().take_until(cancel.cancelled_owned()))),
                Err(e) => return bad_gateway(e.without_url()),
            }
        }
        Upstream::Chrome { url } => {
            let mut rb = if head { CHROME_H1.head(&url) } else { CHROME_H1.get(&url) };
            if let Some(r) = &range {
                rb = rb.header("Range", r);
            }
            match rb.send().await {
                Ok(r) => (r.status().as_u16(), copy_headers(r.headers().iter().map(|(k, v)| (k.as_str(), v.as_bytes()))), Body::from_stream(r.bytes_stream())),
                Err(e) => return bad_gateway(e),
            }
        }
        Upstream::H3 { url, referer } => {
            let mut rb = if head { H3.head(&url) } else { H3.get(&url) }.header("Referer", referer);
            if let Some(r) = &range {
                rb = rb.header("Range", r);
            }
            match rb.send().await {
                Ok(r) => (r.status().as_u16(), copy_headers(r.headers().iter().map(|(k, v)| (k.as_str(), v.as_bytes()))), Body::from_stream(r.bytes_stream())),
                Err(e) => return bad_gateway(e),
            }
        }
    };
    let mut resp = Response::new(if head { Body::empty() } else { body });
    *resp.status_mut() = StatusCode::from_u16(code).unwrap_or(StatusCode::BAD_GATEWAY);
    *resp.headers_mut() = headers;
    resp
}

fn copy_headers<'a>(src: impl Iterator<Item = (&'a str, &'a [u8])>) -> HeaderMap {
    let mut out = HeaderMap::new();
    for (k, v) in src {
        if PASS_HEADERS.contains(&k.to_ascii_lowercase().as_str())
            && let (Ok(k), Ok(v)) = (axum::http::HeaderName::from_bytes(k.as_bytes()), axum::http::HeaderValue::from_bytes(v))
        {
            out.insert(k, v);
        }
    }
    out
}

fn status(code: StatusCode) -> Response {
    let mut r = Response::new(Body::empty());
    *r.status_mut() = code;
    r
}

fn bad_gateway(e: impl std::fmt::Display) -> Response {
    tracing::debug!("stream proxy upstream error: {e}");
    status(StatusCode::BAD_GATEWAY)
}

#[cfg(test)]
mod tests {
    use crate::sources;

    #[test]
    fn wibufile_host_check() {
        assert!(super::is_wibufile("https://s0.wibufile.com/video01/episode.mp4"));
        assert!(!super::is_wibufile("https://wibufile.com.evil.example/episode.mp4"));
    }

    /// `cargo test live_blogger -- --ignored --nocapture`: resolves Samehadaku's
    /// latest One Piece episode (Blogspot) and reads bytes through the proxy.
    /// Explicitly downloads Kyoko's plugins before the live test.
    #[test]
    #[ignore]
    fn live_blogger_proxy() {
        crate::RT.block_on(async {
            crate::plugins::sync_all().await;
            let src = "kyoko/samehadaku";
            let found = sources::search(src, "one piece").await.unwrap();
            let eps = sources::episodes(src, &found[0].url).await.unwrap();
            let stream = sources::stream(src, &eps.last().unwrap().url, "best").await.unwrap();
            println!("stream: {}", &stream.url[..stream.url.len().min(90)]);
            assert!(crate::blogger::is_blogger(&stream.url), "expected a Blogger stream to exercise the proxy");
            let local = super::blogger(&stream.url).await.unwrap();
            let resp = crate::http::PLAIN.get(&local).header("Range", "bytes=0-1048575").send().await.unwrap();
            let status = resp.status().as_u16();
            let ctype = resp.headers().get("content-type").map(|v| v.to_str().unwrap_or("").to_owned()).unwrap_or_default();
            let body = resp.bytes().await.unwrap();
            println!("proxy {local} -> {status} {ctype} {} bytes", body.len());
            assert_eq!(status, 206);
            assert_eq!(body.len(), 1 << 20);
            assert_eq!(&body[4..8], b"ftyp", "mp4 header");
        });
    }
}
