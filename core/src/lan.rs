//! Shares this device's folders with the account's other devices on the same
//! network. The address and key travel as a synced `lanHost:<id>` setting,
//! which the sync server stores without reading.

use crate::sources::{Episode, Stream};
use crate::{db, local};
use anyhow::{Result, anyhow, ensure};
use axum::body::Body;
use axum::extract::Request;
use axum::http::{HeaderValue, Method, StatusCode, header};
use axum::response::Response;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

pub const SETTING: &str = "shareLibrary";
pub const RECORD: &str = "lanHost:";
/// `lanMiss:<id>`: when a device on the same network last timed out reaching that one.
pub const MISS: &str = "lanMiss:";
/// `lanSeen:<id>`: a device whose shared folders loaded here, kept while it's away. Never synced.
const SEEN: &str = "lanSeen:";
const ID: &str = "lanId";
const KEY: &str = "lanKey";
const PORT: u16 = 47821;
const ASK_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct Host {
    #[serde(skip)]
    id: String,
    name: String,
    addr: SocketAddr,
    key: String,
    #[serde(default)]
    cert: String,
}

struct Server {
    port: u16,
    cert: String,
    handle: axum_server::Handle<SocketAddr>,
    task: tokio::task::JoinHandle<()>,
}

static SERVER: Mutex<Option<Server>> = Mutex::new(None);
static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
static ERROR: Mutex<String> = Mutex::new(String::new());
// Unix times: misses before SINCE or LAST_PEER are old news.
static SINCE: AtomicI64 = AtomicI64::new(0);
static LAST_PEER: AtomicI64 = AtomicI64::new(0);
static LAST_REFRESH: AtomicI64 = AtomicI64::new(0);

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64)
}

pub(crate) fn secret() -> String {
    let mut bytes = [0; 32];
    getrandom::fill(&mut bytes).expect("operating system randomness");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
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
        // macOS has no /etc/hostname; this is the name its sharing settings show.
        .or_else(|| {
            let out = std::process::Command::new("scutil").args(["--get", "ComputerName"]).output().ok()?;
            out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
        })
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

fn sharing() -> bool {
    crate::api::setting(SETTING) == "true" && crate::sync::signed_in()
}

/// Serves while sharing is on and signed in, and keeps this device's record current.
pub async fn refresh() {
    {
        let _one = ONE.lock().await;
        // Refreshes come every two minutes; a longer gap means this computer slept,
        // and devices that missed it meanwhile say nothing about its firewall.
        if now() - LAST_REFRESH.swap(now(), Ordering::Relaxed) > 600 {
            SINCE.store(now(), Ordering::Relaxed);
        }
        let (record, error) = if sharing() {
            publish().await
        } else {
            stop();
            Default::default()
        };
        *ERROR.lock().unwrap() = error;
        let key = format!("{RECORD}{}", own(ID));
        if db::setting(&key).unwrap_or_default() != record
            && let Err(e) = db::set_setting(&key, &record)
        {
            tracing::warn!("lan: couldn't save this device's address ({e:#})");
        }
    }
    crate::push("lan", &state());
}

/// This device's record, or none and why.
async fn publish() -> (String, String) {
    let port = match start().await {
        Ok(port) => port,
        Err(e) => {
            tracing::warn!("lan: couldn't share the library ({e:#})");
            return (String::new(), format!("Couldn't start sharing: {e}"));
        }
    };
    let Some(ip) = lan_ip() else { return (String::new(), "Not connected to a network".into()) };
    if !on_lan(ip) {
        return (String::new(), "Not on a local network. A VPN can cause this.".into());
    }
    let cert = SERVER.lock().unwrap().as_ref().map(|s| s.cert.clone()).unwrap_or_default();
    let host = Host { id: own(ID), name: device_name(), addr: SocketAddr::new(ip, port), key: own(KEY), cert };
    (serde_json::to_string(&host).unwrap_or_default(), String::new())
}

/// For Settings: `off`, `starting`, `waiting` (the address isn't on the account
/// yet, so phones can't find this device), `on` or `error`.
pub fn state() -> Value {
    let running = SERVER.lock().unwrap().as_ref().is_some_and(|s| !s.task.is_finished());
    let record = format!("{RECORD}{}", db::setting(ID).unwrap_or_default());
    let address = db::setting(&record).and_then(|r| serde_json::from_str::<Host>(&r).ok()).map(|h| h.addr.ip().to_string()).unwrap_or_default();
    let missed = db::setting(&format!("{MISS}{}", db::setting(ID).unwrap_or_default())).and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
    let blocked = running && missed > SINCE.load(Ordering::Relaxed).max(LAST_PEER.load(Ordering::Relaxed));
    let mut error = ERROR.lock().unwrap().clone();
    if error.is_empty() && blocked {
        error = "A device couldn't connect. Check the firewall.".into();
    }
    let state = match () {
        _ if !sharing() => "off",
        _ if !error.is_empty() => "error",
        _ if !running || address.is_empty() => "starting",
        _ if db::sync_queued("setting", &record) => "waiting",
        _ => "on",
    };
    json!({ "state": state, "address": address, "error": error })
}

async fn start() -> Result<u16> {
    if let Some(server) = &*SERVER.lock().unwrap()
        && !server.task.is_finished()
    {
        return Ok(server.port);
    }
    let listener = match tokio::net::TcpListener::bind(("0.0.0.0", PORT)).await {
        Ok(l) => l,
        Err(_) => tokio::net::TcpListener::bind(("0.0.0.0", 0)).await?,
    };
    let port = listener.local_addr()?.port();
    let identity = rcgen::generate_simple_self_signed(vec!["aikatsu.lan".into()])?;
    let cert = identity.cert.pem();
    let config = axum_server::tls_rustls::RustlsConfig::from_pem(cert.as_bytes().to_vec(), identity.signing_key.serialize_pem().into_bytes()).await?;
    let handle = axum_server::Handle::new();
    let server = axum_server::from_tcp_rustls(listener.into_std()?, config)?.handle(handle.clone());
    db::set_setting(KEY, &secret())?;
    SINCE.store(now(), Ordering::Relaxed);
    let task = tokio::spawn(async move {
        if let Err(e) = server.serve(axum::Router::new().fallback(serve).into_make_service_with_connect_info::<SocketAddr>()).await {
            tracing::error!("lan: library sharing stopped: {e}");
        }
    });
    *SERVER.lock().unwrap() = Some(Server { port, cert, handle, task });
    tracing::info!("lan: sharing the library on port {port}");
    Ok(port)
}

fn stop() {
    if let Some(server) = SERVER.lock().unwrap().take() {
        server.handle.shutdown();
    }
    let _ = db::set_setting(KEY, "");
}

/// At sign-out: a new key next time, and no other devices' addresses kept.
pub fn forget() {
    stop();
    crate::proxy::clear();
    let _ = db::delete_settings_with_prefix(RECORD);
    let _ = db::delete_settings_with_prefix(MISS);
    let _ = db::delete_settings_with_prefix(SEEN);
}

async fn serve(req: Request) -> Response {
    let q: HashMap<String, String> = url::form_urlencoded::parse(req.uri().query().unwrap_or("").as_bytes()).into_owned().collect();
    let key = db::setting(KEY).unwrap_or_default();
    let given = req.headers().get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")).unwrap_or_default();
    let peer = req.extensions().get::<axum::extract::ConnectInfo<SocketAddr>>().map(|c| c.0.ip());
    // Digests, so how long the comparison takes says nothing about the key.
    if !sharing() || key.is_empty() || !peer.is_some_and(on_lan) || Sha256::digest(given) != Sha256::digest(&key) {
        return status(StatusCode::FORBIDDEN);
    }
    if peer.is_some_and(|ip| !ip.is_loopback()) {
        LAST_PEER.store(now(), Ordering::Relaxed);
    }
    let head = req.method() == Method::HEAD;
    if req.method() != Method::GET && !head {
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
    let mut response = res.unwrap_or_else(|e| {
        let mut r = Response::new(Body::from(e.to_string()));
        *r.status_mut() = StatusCode::NOT_FOUND;
        r
    });
    if head { *response.body_mut() = Body::empty(); }
    response
}

async fn json<T: Serialize + Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<Response> {
    let v = tokio::task::spawn_blocking(f).await??;
    let mut r = Response::new(Body::from(serde_json::to_vec(&v)?));
    r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("application/json"));
    Ok(r)
}

async fn file(path: String, range: Option<&str>) -> Result<Response> {
    let opened = tokio::task::spawn_blocking(move || local::open_video(&path)).await??;
    let mut f = tokio::fs::File::from_std(opened);
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
        .filter_map(|(k, v)| {
            let mut h = serde_json::from_str::<Host>(&v).ok()?;
            h.id = k.strip_prefix(RECORD)?.to_owned();
            Some(h)
        })
        .filter(|h| on_lan(h.addr.ip()) && !h.cert.is_empty())
        .collect()
}

fn url(h: &Host, route: &str, path: &str) -> String {
    let mut u = url::Url::parse(&format!("https://aikatsu.lan:{}/{route}", h.addr.port())).expect("a port makes a valid URL");
    if !path.is_empty() {
        u.query_pairs_mut().append_pair("path", path);
    }
    u.into()
}

/// Both UIs' `describe` match "<name> is offline" and "<name> can't be reached";
/// keep filesystem paths out of network errors. A refused connection means
/// Aikatsu isn't sharing there; silence means a firewall, sleep or another network.
fn offline(h: &Host, e: reqwest::Error) -> anyhow::Error {
    let what = if e.is_timeout() { "can't be reached" } else { "is offline" };
    anyhow::Error::new(e.without_url()).context(format!("{} {what}", h.name))
}

fn timed_out(e: &anyhow::Error) -> bool {
    e.chain().any(|c| c.downcast_ref::<reqwest::Error>().is_some_and(reqwest::Error::is_timeout))
}

/// Same /24 as this device, so a home network rather than mobile data.
fn same_network(ip: IpAddr) -> bool {
    matches!((lan_ip(), ip), (Some(IpAddr::V4(a)), IpAddr::V4(b)) if a.octets()[..3] == b.octets()[..3])
}

fn client(h: &Host) -> Result<reqwest::Client> {
    ensure!(on_lan(h.addr.ip()), "Invalid sharing address");
    Ok(reqwest::Client::builder()
        .tls_certs_only([reqwest::Certificate::from_pem(h.cert.as_bytes())?])
        .resolve("aikatsu.lan", h.addr)
        .https_only(true)
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(ASK_TIMEOUT)
        .build()?)
}

fn location(id: &str, path: &str) -> String {
    let mut u = url::Url::parse("aikatsu-lan://device/").unwrap();
    u.query_pairs_mut().append_pair("id", id).append_pair("path", path);
    u.into()
}

pub(crate) fn local_path(path: &str) -> Option<String> {
    let u = url::Url::parse(path).ok().filter(|u| u.scheme() == "aikatsu-lan")?;
    let q: HashMap<_, _> = u.query_pairs().into_owned().collect();
    (q.get("id")? == &db::setting(ID)?).then(|| q.get("path").cloned()).flatten()
}

fn selected(path: &str) -> Result<(Vec<Host>, String)> {
    if !path.starts_with("aikatsu-lan:") { return Ok((hosts(), path.to_owned())); }
    let u = url::Url::parse(path)?;
    let q: HashMap<_, _> = u.query_pairs().into_owned().collect();
    let id = q.get("id").ok_or_else(|| anyhow!("Missing sharing device"))?;
    let path = q.get("path").ok_or_else(|| anyhow!("Missing shared path"))?.clone();
    let host = hosts().into_iter().find(|h| h.id == *id).ok_or_else(|| anyhow!("This sharing device is offline"))?;
    Ok((vec![host], path))
}

async fn ask(h: &Host, route: &str, path: &str) -> Result<Value> {
    let resp = client(h)?.get(url(h, route, path)).bearer_auth(&h.key).timeout(ASK_TIMEOUT).send().await.map_err(|e| offline(h, e))?;
    let code = resp.status();
    let text = resp.text().await.map_err(|e| offline(h, e))?;
    ensure!(code.is_success(), "{}: {}", h.name, if text.is_empty() { code.to_string() } else { text });
    Ok(serde_json::from_str(&text)?)
}

/// Series shared by the account's devices on this network, each tagged with
/// its device, and the names of the devices that didn't answer. A device that
/// timed out on this network hears about it through sync: its firewall is the
/// usual cause, and it can't see that itself.
pub async fn library() -> (Vec<Value>, Vec<String>) {
    let (out, missing, _) = gather().await;
    (out, missing)
}

/// [library], plus the ids of the devices that answered.
async fn gather() -> (Vec<Value>, Vec<String>, Vec<String>) {
    let hosts = hosts();
    let found = futures_util::future::join_all(hosts.iter().map(|h| ask(h, "library", ""))).await;
    let (mut out, mut missing, mut answered, mut missed) = (Vec::new(), Vec::new(), Vec::new(), false);
    for (h, res) in hosts.iter().zip(found) {
        let miss = format!("{MISS}{}", h.id);
        match res {
            Ok(mut lib) => {
                let shows = lib["series"].as_array().map_or(0, Vec::len);
                let _ = db::set_setting(&format!("{SEEN}{}", h.id), &json!({ "name": h.name, "at": now(), "shows": shows }).to_string());
                answered.push(h.id.clone());
                out.extend(lib["series"].as_array_mut().map(std::mem::take).unwrap_or_default().into_iter().map(|mut s| {
                    s["host"] = h.name.clone().into();
                    s["path"] = location(&h.id, s["path"].as_str().unwrap_or_default()).into();
                    s
                }));
                if db::setting(&miss).is_some_and(|v| !v.is_empty()) {
                    let _ = db::set_setting(&miss, "");
                }
            }
            Err(e) => {
                tracing::info!("lan: {} isn't sharing right now ({e:#})", h.name);
                missing.push(h.name.clone());
                if timed_out(&e) && same_network(h.addr.ip()) {
                    missed |= db::set_setting(&miss, &now().to_string()).is_ok();
                }
            }
        }
    }
    if missed {
        tokio::spawn(crate::sync::sync());
    }
    (out, missing, answered)
}

/// Devices whose shared folders have loaded here, last seen first; `online` if listed there.
pub fn devices(online: &[String]) -> Value {
    let mut list: Vec<Value> = db::settings_with_prefix(SEEN)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|(k, v)| {
            let mut d: Value = serde_json::from_str(&v).ok()?;
            let id = k.strip_prefix(SEEN)?;
            d["online"] = online.iter().any(|o| o == id).into();
            d["id"] = id.into();
            Some(d)
        })
        .collect();
    list.sort_by_key(|d| std::cmp::Reverse(d["at"].as_i64()));
    json!(list)
}

/// Asks every device on the account, so each saved one is online or not right now.
pub async fn check_devices() -> Value {
    devices(&gather().await.2)
}

pub fn forget_device(id: &str) -> Result<()> {
    ensure!(!id.is_empty(), "Missing device");
    db::delete_settings_with_prefix(&format!("{SEEN}{id}"))
}

pub async fn episodes(folder: &str) -> Result<Vec<Episode>> {
    let (hosts, folder) = selected(folder)?;
    let mut last = anyhow!("This folder isn't in this device's library");
    for h in hosts {
        match ask(&h, "episodes", &folder).await {
            Ok(v) => {
                let mut episodes: Vec<Episode> = serde_json::from_value(v)?;
                for e in &mut episodes { e.url = location(&h.id, &e.url); }
                return Ok(episodes);
            }
            Err(e) => last = e,
        }
    }
    Err(last)
}

pub async fn stream(file: &str) -> Result<Stream> {
    let (hosts, file) = selected(file)?;
    let mut last = anyhow!("This file isn't in this device's library");
    for h in hosts {
        let url = url(&h, "file", &file);
        let client = client(&h)?;
        match client.get(&url).bearer_auth(&h.key).header("Range", "bytes=0-0").timeout(ASK_TIMEOUT).send().await {
            Ok(r) if r.status().is_success() => {
                let url = crate::proxy::lan(url, h.key, client).await?;
                return Ok(Stream { url, referer: String::new() });
            }
            Ok(r) => {
                let code = r.status();
                let text = r.text().await.unwrap_or_default();
                last = anyhow!("{}: {}", h.name, if text.is_empty() { code.to_string() } else { text });
            }
            Err(e) => last = offline(&h, e),
        }
    }
    Err(last)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http;

    #[test]
    fn lan_client_does_not_follow_redirects() {
        crate::RT.block_on(async {
            let identity = rcgen::generate_simple_self_signed(vec!["aikatsu.lan".into()]).unwrap();
            let cert = identity.cert.pem();
            let config = axum_server::tls_rustls::RustlsConfig::from_pem(cert.as_bytes().to_vec(), identity.signing_key.serialize_pem().into_bytes()).await.unwrap();
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let handle = axum_server::Handle::new();
            let server = axum_server::from_tcp_rustls(listener.into_std().unwrap(), config).unwrap().handle(handle.clone());
            let app = axum::Router::new().fallback(|| async {
                (StatusCode::FOUND, [(header::LOCATION, "http://192.0.2.1/outside-lan")])
            });
            let task = tokio::spawn(server.serve(app.into_make_service()));
            let h = Host { id: "test".into(), name: "Redirect".into(), addr, key: "test".into(), cert };
            let response = client(&h).unwrap().get(url(&h, "library", "")).send().await.unwrap();
            assert_eq!(response.status(), 302);
            handle.shutdown();
            task.await.unwrap().unwrap();
        });
    }

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
            let port = SERVER.lock().unwrap().as_ref().map(|s| s.port).expect("sharing started");
            ERROR.lock().unwrap().clear(); // whatever this machine's network is
            let own_miss = format!("{MISS}{}", db::setting(ID).unwrap());
            db::set_setting(&own_miss, &(now() + 1).to_string()).unwrap();
            assert!(state()["error"].as_str().unwrap().contains("firewall"), "a device on this network timed out");
            LAST_PEER.store(now() + 2, Ordering::Relaxed);
            assert_eq!(state()["error"], "", "one got through since");
            db::set_setting(&own_miss, "").unwrap();
            let desk = Host { id: "test-desk".into(), name: "Desk".into(), addr: SocketAddr::from(([127, 0, 0, 1], port)), key: db::setting(KEY).unwrap(), cert: SERVER.lock().unwrap().as_ref().unwrap().cert.clone() };
            let far = Host { id: "test-far".into(), name: "Far".into(), addr: SocketAddr::from(([8, 8, 8, 8], port)), key: desk.key.clone(), cert: desk.cert.clone() };
            db::set_setting(&format!("{RECORD}test-desk"), &serde_json::to_string(&desk).unwrap()).unwrap();
            db::set_setting(&format!("{RECORD}test-far"), &serde_json::to_string(&far).unwrap()).unwrap();
            assert_eq!(hosts(), [desk], "own record and public addresses are skipped");

            let (shared, _) = library().await;
            assert!(shared.iter().any(|s| s["path"] == location("test-desk", &show) && s["host"] == "Desk"), "{shared:?}");
            let saved = check_devices().await;
            assert!(saved.as_array().unwrap().iter().any(|d| d["id"] == "test-desk" && d["name"] == "Desk" && d["online"] == true && d["shows"].as_u64() >= Some(1)), "{saved}");
            assert_eq!(episodes(&show).await.unwrap().len(), 1);
            let s = stream(&video).await.unwrap();
            let r = http::PLAIN.get(&s.url).header("Range", "bytes=2-5").send().await.unwrap();
            assert_eq!(r.status(), 206);
            assert_eq!(r.headers()["content-range"], "bytes 2-5/10");
            assert_eq!(&r.bytes().await.unwrap()[..], b"2345");
            let h = hosts().remove(0);
            let direct = url(&h, "file", &video);
            assert!(!direct.contains("key="));
            assert_eq!(client(&h).unwrap().get(&direct).send().await.unwrap().status(), 403);
            assert_eq!(client(&h).unwrap().get(&direct).bearer_auth("nope").send().await.unwrap().status(), 403);
            let eps = crate::sources::episodes(local::SOURCE, &location(&h.id, &show)).await.unwrap();
            assert_eq!(eps[0].url, location(&h.id, &video));
            let own_folder = location(&db::setting(ID).unwrap(), &show);
            assert_eq!(crate::sources::episodes(local::SOURCE, &own_folder).await.unwrap()[0].url, video, "synced history plays locally on its original device");
            let own_video = location(&db::setting(ID).unwrap(), &video);
            assert_eq!(crate::sources::stream(local::SOURCE, &own_video, "").await.unwrap().url, video);
            assert!(crate::sources::stream(local::SOURCE, &location("missing-device", &video), "").await.is_err());
            let wrong_pin = Host { cert: rcgen::generate_simple_self_signed(vec!["aikatsu.lan".into()]).unwrap().cert.pem(), ..h.clone() };
            assert!(client(&wrong_pin).unwrap().get(&direct).bearer_auth(&h.key).send().await.is_err(), "a different certificate must fail");
            let mut wrong_device = h.clone();
            wrong_device.key = "wrong".into();
            db::set_setting(&format!("{RECORD}test-other"), &serde_json::to_string(&wrong_device).unwrap()).unwrap();
            assert!(crate::sources::episodes(local::SOURCE, &location("test-other", &show)).await.is_err(), "never fall back to a local path or another host");
            db::delete_settings_with_prefix(&format!("{RECORD}test-other")).unwrap();
            let head = http::PLAIN.head(&s.url).send().await.unwrap();
            assert_eq!(head.status(), 200);
            assert_eq!(head.headers()["content-length"], "10");
            assert!(head.bytes().await.unwrap().is_empty());
            assert!(stream(&std::env::temp_dir().join("elsewhere.mkv").display().to_string()).await.is_err(), "outside the shared folders");

            local::remove_root(&root.display().to_string()).unwrap();
            let err = crate::sources::episodes(local::SOURCE, &show).await.unwrap_err().to_string();
            assert!(err.starts_with("Desk:"), "a folder not on this device is asked of the shared one: {err}");
            local::add_root(&root.display().to_string()).unwrap();

            let large = root.join("Show/large.mkv");
            std::fs::File::create(&large).unwrap().set_len(64 << 20).unwrap();
            let relayed = stream(&large.display().to_string()).await.unwrap();
            let active = http::PLAIN.get(&relayed.url).send().await.unwrap();
            crate::proxy::clear();
            assert!(tokio::time::timeout(Duration::from_secs(5), active.bytes()).await.unwrap().is_err(), "closing playback cancels the relay");
            let response = client(&h).unwrap().get(url(&h, "file", &large.display().to_string())).bearer_auth(&h.key).send().await.unwrap();
            assert_eq!(response.status(), 200);
            db::set_setting(SETTING, "false").unwrap();
            refresh().await;
            assert!(tokio::time::timeout(Duration::from_secs(5), response.bytes()).await.unwrap().is_err(), "active transfers must be cut off");
            let saved = check_devices().await;
            assert!(saved.as_array().unwrap().iter().any(|d| d["id"] == "test-desk" && d["online"] == false), "a device that stops sharing stays, offline: {saved}");
            forget_device("test-desk").unwrap();
            assert!(!devices(&[]).to_string().contains("test-desk"));
            db::set_setting(SETTING, "true").unwrap();
            refresh().await;
            assert_ne!(db::setting(KEY).unwrap(), h.key, "re-enabling rotates credentials");
            let (port, cert) = {
                let server = SERVER.lock().unwrap();
                let server = server.as_ref().unwrap();
                (server.port, server.cert.clone())
            };
            let fresh = Host { key: db::setting(KEY).unwrap(), addr: SocketAddr::from(([127, 0, 0, 1], port)), cert, ..h.clone() };
            assert_eq!(client(&fresh).unwrap().get(url(&fresh, "library", "")).bearer_auth(&h.key).send().await.unwrap().status(), 403);
            forget();
            assert!(SERVER.lock().unwrap().is_none(), "sign-out stops sharing immediately");
            db::set_setting(&format!("{RECORD}test-desk"), &serde_json::to_string(&fresh).unwrap()).unwrap();
            db::set_setting(SETTING, "false").unwrap();
            refresh().await;
            assert!(SERVER.lock().unwrap().is_none(), "sharing stops");
            let err = format!("{:#}", episodes(&show).await.unwrap_err());
            assert!(err.starts_with("Desk is offline") && !err.contains("key="), "{err}");
            db::delete_settings_with_prefix(&format!("{RECORD}test-")).unwrap();
            local::remove_root(&root.display().to_string()).unwrap();
            for (k, v) in &before { db::set_setting(k, v).unwrap(); }
        });
        std::fs::remove_dir_all(&root).unwrap();
    }
}
