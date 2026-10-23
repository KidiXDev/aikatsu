//! Watch together: one playback state per party, kept by the sync server and
//! streamed to its members as server-sent events. Each member plays the
//! episode from their own source; only the state travels.

use crate::{api, http, local, push, sync};
use anyhow::{Context, Result, anyhow, ensure};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The server sends a heartbeat every 15 s.
const SILENCE: Duration = Duration::from_secs(40);

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct Playback {
    #[serde(default)]
    anime: Value,
    episode: f64,
    position: f64,
    paused: bool,
    speed: f64,
    #[serde(default)]
    by: String,
    #[serde(default)]
    rev: i64,
}

struct Party {
    id: String,
    server: String,
    qr: Value,
    state: Playback,
    /// When `state.position` was current, by this device's clock.
    anchor: Instant,
    members: Value,
    connected: bool,
    task: Option<tokio::task::JoinHandle<()>>,
}

static PARTY: Mutex<Option<Party>> = Mutex::new(None);

/// Retrying won't help: the party ended, is full, or we're no longer let in.
#[derive(Debug)]
struct Closed(String);

impl std::fmt::Display for Closed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Closed {}

/// The UIs show these as they are, so just the outer message; the log keeps the rest.
pub fn plain(e: anyhow::Error) -> anyhow::Error {
    tracing::warn!("watch together: {e:#}");
    anyhow!("{e}")
}

fn link(server: &str, id: &str) -> String {
    format!("{server}/party/{id}")
}

fn valid_id(id: &str) -> bool {
    id.len() == 22 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// The shared `https://<server>/party/<id>`, or the `aikatsu://party?server=…&id=…` its page opens.
fn parse_link(input: &str) -> Option<(String, String)> {
    let url = url::Url::parse(input.trim()).ok()?;
    let (server, id) = match url.scheme() {
        "aikatsu" if url.host_str() == Some("party") => {
            let q = |k: &str| url.query_pairs().find(|(name, _)| name == k).map(|(_, v)| v.into_owned());
            (q("server")?, q("id")?)
        }
        "http" | "https" => {
            let (base, id) = url.path().trim_end_matches('/').rsplit_once("/party/")?;
            (format!("{}{base}", url.origin().ascii_serialization()), id.to_owned())
        }
        _ => return None,
    };
    valid_id(&id).then_some(())?;
    Some((sync::normalize(&server).ok()?, id))
}

/// `{anime?, episode, position, paused, speed}` from a UI, cut to what the server accepts.
fn playback(args: &Value) -> Value {
    let mut body = json!({
        "episode": args["episode"].as_f64().unwrap_or(0.0).max(0.0),
        "position": args["position"].as_f64().unwrap_or(0.0).max(0.0),
        "paused": args["paused"].as_bool().unwrap_or(false),
        "speed": args["speed"].as_f64().unwrap_or(1.0).clamp(0.25, 4.0),
    });
    let a = &args["anime"];
    if a.is_object() {
        let s = |k: &str| a[k].as_str().unwrap_or_default();
        body["anime"] = json!({
            "name": s("name").chars().take(300).collect::<String>(),
            "url": s("url"),
            "image": s("image"),
            "source": s("source"),
            "anilistId": a["anilistId"].as_i64().unwrap_or(0).max(0),
        });
    }
    body
}

fn position(state: &Playback, elapsed: Duration) -> f64 {
    if state.paused { state.position } else { state.position + elapsed.as_secs_f64() * state.speed }
}

fn qr(text: &str) -> Value {
    let Ok(code) = qrcode::QrCode::new(text) else { return Value::Null };
    let modules: String = code.to_colors().iter().map(|c| if *c == qrcode::Color::Dark { '1' } else { '0' }).collect();
    json!({ "size": code.width(), "modules": modules })
}

pub fn status() -> Value {
    let guard = PARTY.lock().unwrap();
    let Some(p) = guard.as_ref() else { return json!({ "active": false }) };
    let mut state = serde_json::to_value(&p.state).unwrap_or_default();
    state["position"] = position(&p.state, p.anchor.elapsed()).into();
    json!({
        "active": true,
        "link": link(&p.server, &p.id),
        "qr": p.qr,
        "me": sync::username(),
        "members": p.members,
        "connected": p.connected,
        "state": state,
    })
}

pub async fn create(args: &Value) -> Result<Value> {
    let (server, token) = sync::session().context("Sign in to sync first.")?;
    let body = playback(args);
    let source = body["anime"]["source"].as_str().unwrap_or_default();
    ensure!(!source.is_empty() && source != local::SOURCE, "Local files can't be shared.");
    let r = sync::post(&server, "/party", &token, &body).await.map_err(|e| {
        if e.downcast_ref::<sync::Refused>().is_some_and(|r| r.status == 404) { anyhow!("This sync server doesn't support watch together.") } else { e }
    })?;
    let id = r["id"].as_str().filter(|id| valid_id(id)).context("Unexpected response from the server")?;
    let state = Playback { by: sync::username(), rev: 1, ..serde_json::from_value(body)? };
    begin(server, token, id.to_owned(), state).await?;
    Ok(status())
}

pub async fn join(input: &str) -> Result<Value> {
    let (server, id) = parse_link(input).context("That isn't a party link.")?;
    let host = url::Url::parse(&server).ok().and_then(|u| u.host_str().map(str::to_owned)).unwrap_or_else(|| server.clone());
    let (mine, token) = sync::session().with_context(|| format!("Sign in to {host} to join."))?;
    ensure!(mine == server, "This party is on {host}.");
    begin(server, token, id.clone(), Playback::default()).await?;
    // The stream opens with the party's state.
    let mut source = String::new();
    for _ in 0..50 {
        source = PARTY.lock().unwrap().as_ref().filter(|p| p.id == id && p.state.rev > 0).map(|p| p.state.anime["source"].as_str().unwrap_or_default().to_owned()).unwrap_or_default();
        if !source.is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    if source.is_empty() || !api::enabled_sources().iter().any(|p| p.id == source) {
        leave();
        ensure!(!source.is_empty(), "Couldn't reach the party.");
        anyhow::bail!("Install the {} source to join.", source.rsplit('/').next().unwrap_or(&source));
    }
    Ok(status())
}

/// Applied here first, so following the party doesn't undo it before the server answers.
pub async fn update(args: &Value) -> Result<()> {
    let body = playback(args);
    let (server, id) = {
        let mut guard = PARTY.lock().unwrap();
        let p = guard.as_mut().context("Not in a party.")?;
        let s = &mut p.state;
        s.episode = body["episode"].as_f64().unwrap_or(s.episode);
        s.position = body["position"].as_f64().unwrap_or(s.position);
        s.paused = body["paused"].as_bool().unwrap_or(s.paused);
        s.speed = body["speed"].as_f64().unwrap_or(s.speed);
        if body["anime"].is_object() {
            s.anime = body["anime"].clone();
        }
        s.by = sync::username();
        p.anchor = Instant::now();
        (p.server.clone(), p.id.clone())
    };
    let (_, token) = sync::session().context("Sign in to sync first.")?;
    let r = sync::post(&server, &format!("/party/{id}/state"), &token, &body).await?;
    if let Some(rev) = r["rev"].as_i64()
        && let Some(p) = PARTY.lock().unwrap().as_mut().filter(|p| p.id == id)
    {
        p.state.rev = p.state.rev.max(rev);
    }
    Ok(())
}

pub fn leave() {
    if let Some(task) = PARTY.lock().unwrap().take().and_then(|p| p.task) {
        task.abort();
    }
}

async fn begin(server: String, token: String, id: String, state: Playback) -> Result<()> {
    leave();
    let resp = open(&server, &token, &id).await?;
    let qr = qr(&link(&server, &id));
    *PARTY.lock().unwrap() =
        Some(Party { id: id.clone(), server: server.clone(), qr, state, anchor: Instant::now(), members: json!([]), connected: true, task: None });
    let task = tokio::spawn(listen(server, token, id.clone(), resp));
    match PARTY.lock().unwrap().as_mut().filter(|p| p.id == id) {
        Some(p) => p.task = Some(task),
        None => task.abort(),
    }
    Ok(())
}

async fn open(server: &str, token: &str, id: &str) -> Result<wreq::Response> {
    let resp = http::PLAIN
        .get(format!("{server}/party/{id}/events?device={}", std::env::consts::OS))
        .header("User-Agent", http::API_UA)
        .header("Accept", "text/event-stream")
        .header("Authorization", format!("Bearer {token}"))
        .send()
        .await
        .context("Couldn't reach the sync server")?;
    let status = resp.status();
    if status.is_success() {
        return Ok(resp);
    }
    let message =
        resp.json::<Value>().await.ok().and_then(|v| v["error"].as_str().map(str::to_owned)).unwrap_or_else(|| format!("Server error ({status})"));
    if status.is_client_error() && status.as_u16() != 429 {
        return Err(Closed(message).into());
    }
    Err(anyhow!(message))
}

/// Reconnects until the party closes; phones lose their connection on every network change.
async fn listen(server: String, token: String, id: String, first: wreq::Response) {
    let mut resp = Some(first);
    let mut wait = 1;
    loop {
        let result = match resp.take() {
            Some(r) => read(&id, r).await,
            None => match open(&server, &token, &id).await {
                Ok(r) => {
                    wait = 1;
                    set(&id, |p| p.connected = true);
                    read(&id, r).await
                }
                Err(e) => Err(e),
            },
        };
        match result {
            Err(e) if e.downcast_ref::<Closed>().is_some() => return end(&id, &e.to_string()),
            Err(e) => tracing::warn!("party connection lost: {e:#}"),
            Ok(()) => tracing::warn!("party connection closed"),
        }
        set(&id, |p| p.connected = false);
        tokio::time::sleep(Duration::from_secs(wait)).await;
        wait = (wait * 2).min(15);
    }
}

async fn read(id: &str, resp: wreq::Response) -> Result<()> {
    let mut body = resp.bytes_stream();
    let mut events = Events::default();
    while let Some(chunk) = tokio::time::timeout(SILENCE, body.next()).await.context("The party stopped answering")? {
        for (event, data) in events.feed(&chunk?) {
            let Ok(data) = serde_json::from_str::<Value>(&data) else { continue };
            match event.as_str() {
                "state" => receive(id, &data),
                "members" => set(id, |p| p.members = data),
                _ => {}
            }
        }
    }
    Ok(())
}

fn receive(id: &str, data: &Value) {
    let Ok(state) = serde_json::from_value::<Playback>(data.clone()) else { return };
    // Server times, so the two clocks needn't agree.
    let age = Duration::from_millis((data["now"].as_i64().unwrap_or(0) - data["at"].as_i64().unwrap_or(0)).max(0) as u64);
    set(id, |p| {
        if state.rev > p.state.rev {
            p.anchor = Instant::now().checked_sub(age).unwrap_or_else(Instant::now);
            p.state = state;
        }
    });
}

fn set(id: &str, change: impl FnOnce(&mut Party)) {
    {
        let mut guard = PARTY.lock().unwrap();
        let Some(p) = guard.as_mut().filter(|p| p.id == id) else { return };
        change(p);
    }
    push("party", &status());
}

fn end(id: &str, message: &str) {
    let mut guard = PARTY.lock().unwrap();
    if guard.as_ref().is_some_and(|p| p.id == id) {
        *guard = None;
        drop(guard);
        push("party", &json!({ "active": false, "ended": message }));
    }
}

/// Server-sent events from a byte stream that may split anywhere.
#[derive(Default)]
struct Events(Vec<u8>);

impl Events {
    fn feed(&mut self, chunk: &[u8]) -> Vec<(String, String)> {
        self.0.extend_from_slice(chunk);
        let mut out = Vec::new();
        while let Some(end) = self.0.windows(2).position(|w| w == b"\n\n") {
            let block: Vec<u8> = self.0.drain(..end + 2).collect();
            let (mut event, mut data) = (String::from("message"), Vec::new());
            for line in String::from_utf8_lossy(&block).lines() {
                if let Some(v) = line.strip_prefix("event:") {
                    event = v.trim().to_owned();
                } else if let Some(v) = line.strip_prefix("data:") {
                    data.push(v.strip_prefix(' ').unwrap_or(v).to_owned());
                }
            }
            if !data.is_empty() {
                out.push((event, data.join("\n")));
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn links() {
        let id = "AbCdEfGhIjKlMnOpQrSt_-";
        let want = Some(("https://sync.example.com/aikatsu".to_owned(), id.to_owned()));
        assert_eq!(parse_link(&format!("https://sync.example.com/aikatsu/party/{id}/")), want);
        assert_eq!(parse_link(&format!(" aikatsu://party?server=https%3A%2F%2Fsync.example.com%2Faikatsu&id={id} ")), want);
        assert_eq!(parse_link(&format!("http://192.168.1.5:3000/party/{id}")).unwrap().0, "http://192.168.1.5:3000");
        assert_eq!(parse_link("https://sync.example.com/party/short"), None);
        assert_eq!(parse_link(&format!("aikatsu://other?server=https://x.com&id={id}")), None);
        assert_eq!(parse_link(&format!("ftp://x.com/party/{id}")), None);
        assert_eq!(parse_link("hello"), None);
    }

    #[test]
    fn events_split_anywhere() {
        let mut e = Events::default();
        assert!(e.feed(b"event: state\ndata: {\"a\"").is_empty());
        let got = e.feed(b":1}\n\n: ping\n\nevent: members\ndata: [1,\ndata: 2]\n\n");
        assert_eq!(got, [("state".to_owned(), "{\"a\":1}".to_owned()), ("members".to_owned(), "[1,\n2]".to_owned())]);
    }

    #[test]
    fn position_runs_on_while_playing() {
        let s = Playback { position: 100.0, speed: 1.5, ..Default::default() };
        assert_eq!(position(&s, Duration::from_secs(10)), 115.0);
        assert_eq!(position(&Playback { paused: true, ..s }, Duration::from_secs(10)), 100.0);
    }

    #[test]
    fn playback_fits_the_server() {
        let b = playback(&json!({
            "anime": { "name": "x".repeat(400), "url": "u", "source": "s", "anilistId": null, "extra": 1 },
            "episode": 2, "position": -5, "speed": 9
        }));
        assert_eq!(b["anime"]["name"].as_str().unwrap().len(), 300);
        assert_eq!((&b["anime"]["anilistId"], &b["anime"]["image"]), (&json!(0), &json!("")));
        assert!(b["anime"]["extra"].is_null());
        assert_eq!((b["position"].as_f64(), b["speed"].as_f64(), b["paused"].as_bool()), (Some(0.0), Some(4.0), Some(false)));
        assert!(playback(&json!({ "episode": 1 }))["anime"].is_null());
    }
}
