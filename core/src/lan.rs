//! Shares this device's folders with the account's other devices on the same
//! network. The address and key travel as a synced `lanHost:<id>` setting,
//! which the sync server stores without reading.

use crate::sources::{Episode, Stream};
use crate::{db, http, local};
use anyhow::{Context, Result, anyhow, ensure};
use axum::body::Body;
use axum::extract::Request;
use axum::http::{HeaderValue, Method, StatusCode, header};
use axum::response::Response;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

pub const SETTING: &str = "shareLibrary";
pub const RECORD: &str = "lanHost:";
const ID: &str = "lanId";
const KEY: &str = "lanKey";
const PORT: u16 = 47821;
const ASK_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Debug, PartialEq, Serialize, Deserialize)]
struct Host {
    name: String,
    addr: SocketAddr,
    key: String,
}

static SERVER: Mutex<Option<(u16, tokio::task::JoinHandle<()>)>> = Mutex::new(None);
static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn secret() -> String {
    use std::hash::{BuildHasher, Hasher};
    let mut h = Sha256::new();
    for _ in 0..4 {
        h.update(std::collections::hash_map::RandomState::new().build_hasher().finish().to_le_bytes());
    }
    h.update(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos().to_le_bytes());
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

fn own(name: &str) -> String {
    db::setting(name).filter(|v| !v.is_empty()).unwrap_or_else(|| {
        let v = secret();
        let _ = db::set_setting(name, &v);
        v
    })
}

fn device_name() -> String {
    std::env::var("COMPUTERNAME")
        .ok()
        .or_else(|| std::fs::read_to_string("/etc/hostname").ok())
        .map(|n| n.trim().to_owned())
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| "Desktop".into())
}

// shortcut: the default route's interface, so an active VPN can hide the LAN address; list interfaces if users hit it.
fn lan_ip() -> Option<IpAddr> {
    let s = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    s.connect("8.8.8.8:80").ok()?;
    Some(s.local_addr().ok()?.ip()).filter(|ip| !ip.is_unspecified())
}

/// Serves while sharing is on and signed in, and keeps this device's record current.
pub async fn refresh() {
    let _one = ONE.lock().await;
    let on = crate::api::setting(SETTING) == "true" && crate::sync::signed_in();
    let port = if on {
        start().await.map_err(|e| tracing::warn!("lan: couldn't share the library ({e:#})")).ok()
    } else {
        stop();
        None
    };
    let record = port
        .and_then(|port| lan_ip().map(|ip| SocketAddr::new(ip, port)))
        .and_then(|addr| serde_json::to_string(&Host { name: device_name(), addr, key: own(KEY) }).ok())
        .unwrap_or_default();
    let key = format!("{RECORD}{}", own(ID));
    if db::setting(&key).unwrap_or_default() != record
        && let Err(e) = db::set_setting(&key, &record)
    {
        tracing::warn!("lan: couldn't save this device's address ({e:#})");
    }
}

async fn start() -> Result<u16> {
    if let Some((port, task)) = &*SERVER.lock().unwrap()
        && !task.is_finished()
    {
        return Ok(*port);
    }
    let listener = match tokio::net::TcpListener::bind(("0.0.0.0", PORT)).await {
        Ok(l) => l,
        Err(_) => tokio::net::TcpListener::bind(("0.0.0.0", 0)).await?,
    };
    let port = listener.local_addr()?.port();
    let task = tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, axum::Router::new().fallback(serve)).await {
            tracing::error!("lan: library sharing stopped: {e}");
        }
    });
    *SERVER.lock().unwrap() = Some((port, task));
    tracing::info!("lan: sharing the library on port {port}");
    Ok(port)
}

fn stop() {
    if let Some((_, task)) = SERVER.lock().unwrap().take() {
        task.abort();
    }
}

/// At sign-out: a new key next time, and no other devices' addresses kept.
pub fn forget() {
    let _ = db::set_setting(KEY, "");
    let _ = db::delete_settings_with_prefix(RECORD);
}

async fn serve(req: Request) -> Response {
    let q: HashMap<String, String> = url::form_urlencoded::parse(req.uri().query().unwrap_or("").as_bytes()).into_owned().collect();
    let key = db::setting(KEY).unwrap_or_default();
    if key.is_empty() || q.get("key") != Some(&key) {
        return status(StatusCode::FORBIDDEN);
    }
    if req.method() != Method::GET {
        return status(StatusCode::METHOD_NOT_ALLOWED);
    }
    let path = q.get("path").cloned().unwrap_or_default();
    let range = req.headers().get(header::RANGE).and_then(|v| v.to_str().ok()).map(str::to_owned);
    let res = match req.uri().path() {
        "/library" => json(|| Ok(local::library())).await,
        "/episodes" => json(move || local::episodes(&path)).await,
        "/file" => file(path, range.as_deref()).await,
        _ => return status(StatusCode::NOT_FOUND),
    };
    res.unwrap_or_else(|e| {
        let mut r = Response::new(Body::from(e.to_string()));
        *r.status_mut() = StatusCode::NOT_FOUND;
        r
    })
}

async fn json<T: Serialize + Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<Response> {
    let v = tokio::task::spawn_blocking(f).await??;
    let mut r = Response::new(Body::from(serde_json::to_vec(&v)?));
    r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("application/json"));
    Ok(r)
}

async fn file(path: String, range: Option<&str>) -> Result<Response> {
    let checked = path.clone();
    tokio::task::spawn_blocking(move || local::stream(&checked)).await??;
    let mut f = tokio::fs::File::open(&path).await?;
    let size = f.metadata().await?.len();
    let mut r = Response::new(Body::empty());
    r.headers_mut().insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    let (start, end) = match range {
        None => (0, size),
        Some(spec) => match byte_range(spec, size) {
            Some((start, end)) => {
                *r.status_mut() = StatusCode::PARTIAL_CONTENT;
                r.headers_mut().insert(header::CONTENT_RANGE, HeaderValue::from_str(&format!("bytes {start}-{}/{size}", end - 1))?);
                (start, end)
            }
            None => {
                *r.status_mut() = StatusCode::RANGE_NOT_SATISFIABLE;
                r.headers_mut().insert(header::CONTENT_RANGE, HeaderValue::from_str(&format!("bytes */{size}"))?);
                return Ok(r);
            }
        },
    };
    r.headers_mut().insert(header::CONTENT_LENGTH, HeaderValue::from(end - start));
    f.seek(std::io::SeekFrom::Start(start)).await?;
    *r.body_mut() = Body::from_stream(tokio_util::io::ReaderStream::new(f.take(end - start)));
    Ok(r)
}

/// One `bytes=` range as a half-open span; None when it can't be served.
fn byte_range(spec: &str, size: u64) -> Option<(u64, u64)> {
    let (a, b) = spec.strip_prefix("bytes=")?.split_once('-')?;
    let (start, end) = match (a.trim(), b.trim()) {
        ("", n) => (size.saturating_sub(n.parse().ok()?), size),
        (a, "") => (a.parse().ok()?, size),
        (a, b) => (a.parse().ok()?, b.parse::<u64>().ok()?.saturating_add(1).min(size)),
    };
    (start < end).then_some((start, end))
}

fn status(code: StatusCode) -> Response {
    let mut r = Response::new(Body::empty());
    *r.status_mut() = code;
    r
}

/// The sync server hands these addresses over, so only local ones are contacted.
fn on_lan(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => v4.is_private() || v4.is_link_local() || v4.is_loopback(),
        IpAddr::V6(v6) => v6.is_loopback() || v6.is_unique_local() || v6.is_unicast_link_local(),
    }
}

fn hosts() -> Vec<Host> {
    let own = format!("{RECORD}{}", db::setting(ID).unwrap_or_default());
    db::settings_with_prefix(RECORD)
        .unwrap_or_default()
        .into_iter()
        .filter(|(k, _)| *k != own)
        .filter_map(|(_, v)| serde_json::from_str::<Host>(&v).ok())
        .filter(|h| on_lan(h.addr.ip()))
        .collect()
}

fn url(h: &Host, route: &str, path: &str) -> String {
    let mut u = url::Url::parse(&format!("http://{}/{route}", h.addr)).expect("a socket address makes a valid URL");
    u.query_pairs_mut().append_pair("key", &h.key);
    if !path.is_empty() {
        u.query_pairs_mut().append_pair("path", path);
    }
    u.into()
}

async fn ask(h: &Host, route: &str, path: &str) -> Result<Value> {
    let resp = http::PLAIN.get(url(h, route, path)).timeout(ASK_TIMEOUT).send().await.with_context(|| format!("Couldn't reach {}", h.name))?;
    let code = resp.status();
    let text = resp.text().await.with_context(|| format!("Couldn't reach {}", h.name))?;
    ensure!(code.is_success(), "{}: {}", h.name, if text.is_empty() { code.to_string() } else { text });
    Ok(serde_json::from_str(&text)?)
}

/// Series shared by the account's devices on this network, each tagged with its device.
pub async fn library() -> Vec<Value> {
    let hosts = hosts();
    let found = futures_util::future::join_all(hosts.iter().map(|h| ask(h, "library", ""))).await;
    let mut out = Vec::new();
    for (h, res) in hosts.iter().zip(found) {
        match res {
            Ok(mut lib) => out.extend(lib["series"].as_array_mut().map(std::mem::take).unwrap_or_default().into_iter().map(|mut s| {
                s["host"] = h.name.clone().into();
                s
            })),
            Err(e) => tracing::info!("lan: {} isn't sharing right now ({e:#})", h.name),
        }
    }
    out
}

pub async fn episodes(folder: &str) -> Result<Vec<Episode>> {
    let mut last = anyhow!("This folder isn't in this device's library");
    for h in hosts() {
        match ask(&h, "episodes", folder).await {
            Ok(v) => return Ok(serde_json::from_value(v)?),
            Err(e) => last = e,
        }
    }
    Err(last)
}

pub async fn stream(file: &str) -> Result<Stream> {
    let mut last = anyhow!("This file isn't in this device's library");
    for h in hosts() {
        let url = url(&h, "file", file);
        match http::PLAIN.get(&url).header("Range", "bytes=0-0").timeout(ASK_TIMEOUT).send().await {
            Ok(r) if r.status().is_success() => return Ok(Stream { url, referer: String::new() }),
            Ok(r) => {
                let code = r.status();
                let text = r.text().await.unwrap_or_default();
                last = anyhow!("{}: {}", h.name, if text.is_empty() { code.to_string() } else { text });
            }
            Err(e) => last = anyhow!("Couldn't reach {} ({e})", h.name),
        }
    }
    Err(last)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_ranges() {
        assert_eq!(byte_range("bytes=0-", 10), Some((0, 10)));
        assert_eq!(byte_range("bytes=2-5", 10), Some((2, 6)));
        assert_eq!(byte_range("bytes=8-99", 10), Some((8, 10)));
        assert_eq!(byte_range("bytes=-3", 10), Some((7, 10)));
        assert_eq!(byte_range("bytes=10-", 10), None);
        assert_eq!(byte_range("bytes=5-2", 10), None);
        assert_eq!(byte_range("bytes=-0", 10), None);
        assert_eq!(byte_range("bytes=0-1,4-5", 10), None);
        assert_eq!(byte_range("items=0-1", 10), None);
    }

    #[test]
    fn shares_folders_with_the_accounts_devices() {
        let _roots = local::TEST_ROOTS.lock().unwrap_or_else(|e| e.into_inner());
        let root = std::env::temp_dir().join(format!("aikatsu-lan-{}", std::process::id()));
        let show = root.join("Show");
        std::fs::create_dir_all(&show).unwrap();
        let video = show.join("Show - 01.mkv");
        std::fs::write(&video, b"0123456789").unwrap();
        let (show, video) = (show.display().to_string(), video.display().to_string());
        let before: Vec<(&str, String)> = [SETTING, "syncToken"].iter().map(|k| (*k, db::setting(k).unwrap_or_default())).collect();
        db::set_setting(SETTING, "true").unwrap();
        db::set_setting("syncToken", "test").unwrap();
        local::add_root(&root.display().to_string()).unwrap();

        crate::RT.block_on(async {
            refresh().await;
            let port = SERVER.lock().unwrap().as_ref().map(|s| s.0).expect("sharing started");
            let desk = Host { name: "Desk".into(), addr: SocketAddr::from(([127, 0, 0, 1], port)), key: db::setting(KEY).unwrap() };
            let far = Host { name: "Far".into(), addr: SocketAddr::from(([8, 8, 8, 8], port)), key: desk.key.clone() };
            db::set_setting(&format!("{RECORD}test-desk"), &serde_json::to_string(&desk).unwrap()).unwrap();
            db::set_setting(&format!("{RECORD}test-far"), &serde_json::to_string(&far).unwrap()).unwrap();
            assert_eq!(hosts(), [desk], "own record and public addresses are skipped");

            let shared = library().await;
            assert!(shared.iter().any(|s| s["path"] == show.as_str() && s["host"] == "Desk"), "{shared:?}");
            assert_eq!(episodes(&show).await.unwrap().len(), 1);
            let s = stream(&video).await.unwrap();
            let r = http::PLAIN.get(&s.url).header("Range", "bytes=2-5").send().await.unwrap();
            assert_eq!(r.status(), 206);
            assert_eq!(r.headers()["content-range"], "bytes 2-5/10");
            assert_eq!(&r.bytes().await.unwrap()[..], b"2345");
            let wrong = s.url.replace(&format!("key={}", hosts()[0].key), "key=nope");
            assert_eq!(http::PLAIN.get(&wrong).send().await.unwrap().status(), 403);
            assert!(stream(&std::env::temp_dir().join("elsewhere.mkv").display().to_string()).await.is_err(), "outside the shared folders");

            local::remove_root(&root.display().to_string()).unwrap();
            let err = crate::sources::episodes(local::SOURCE, &show).await.unwrap_err().to_string();
            assert!(err.starts_with("Desk:"), "a folder not on this device is asked of the shared one: {err}");

            for (k, v) in &before {
                db::set_setting(k, v).unwrap();
            }
            refresh().await;
            assert!(SERVER.lock().unwrap().is_none(), "sharing stops");
            db::delete_settings_with_prefix(&format!("{RECORD}test-")).unwrap();
        });
        std::fs::remove_dir_all(&root).unwrap();
    }
}
