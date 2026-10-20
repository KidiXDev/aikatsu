//! AniList and MyAnimeList accounts. Finished episodes and watchlist changes
//! go to every connected one. Only their current entry is read back, so
//! progress never goes down.

use crate::{db, http, push};
use anyhow::{Context, Result, anyhow, bail, ensure};
use axum::extract::Request;
use axum::response::Html;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

// Public client ids. Both are registered with redirects to PORT.
const ANILIST_CLIENT: &str = "54389";
const MAL_CLIENT: &str = "0db57cf9e301ba5d142b627fd1b2f1e8";
const PORT: u16 = 47541;
const MAL_API: &str = "https://api.myanimelist.net/v2";
const MAL_OAUTH: &str = "https://myanimelist.net/v1/oauth2";
const EXPIRED: &str = "Session expired. Connect again.";

const SERVICES: [&str; 2] = ["anilist", "mal"];

/// Watchlist status, AniList's, MyAnimeList's.
const STATUSES: [(&str, &str, &str); 5] = [
    ("watching", "CURRENT", "watching"),
    ("planning", "PLANNING", "plan_to_watch"),
    ("completed", "COMPLETED", "completed"),
    ("paused", "PAUSED", "on_hold"),
    ("dropped", "DROPPED", "dropped"),
];

static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
static ERRORS: LazyLock<Mutex<HashMap<&'static str, String>>> = LazyLock::new(Default::default);

struct Login {
    service: &'static str,
    state: String,
    verifier: String,
}
static LOGIN: Mutex<Option<Login>> = Mutex::new(None);
static LISTENING: AtomicBool = AtomicBool::new(false);
static FINISHED: tokio::sync::Notify = tokio::sync::Notify::const_new();

#[derive(Debug)]
struct Refused(String);

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Refused {}

pub fn is_status(s: &str) -> bool {
    STATUSES.iter().any(|t| t.0 == s)
}

/// AniList's REPEATING reads as watching; no entry reads as "".
fn local_status(remote: &str) -> &'static str {
    STATUSES.iter().find(|t| t.1 == remote || t.2 == remote).map_or(if remote.is_empty() { "" } else { "watching" }, |t| t.0)
}

fn named(service: &str) -> Result<&'static str> {
    SERVICES.into_iter().find(|s| *s == service).ok_or_else(|| anyhow!("unknown tracker {service}"))
}

fn label(service: &str) -> &'static str {
    if service == "anilist" { "AniList" } else { "MyAnimeList" }
}

// Outside SETTING_DEFAULTS and SYNCED_SETTINGS: the UIs never see the tokens,
// and each device connects on its own.
fn stored(service: &str, what: &str) -> String {
    db::setting(&format!("{service}{what}")).unwrap_or_default()
}

fn store(service: &str, what: &str, value: &str) -> Result<()> {
    db::set_setting(&format!("{service}{what}"), value)
}

fn forget(service: &str) {
    for what in ["Token", "User", "Refresh", "Expires"] {
        let _ = store(service, what, "");
    }
}

fn connected(service: &str) -> bool {
    !stored(service, "Token").is_empty()
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn status() -> Value {
    let errors = ERRORS.lock().unwrap();
    let services = SERVICES.iter().map(|s| (s.to_string(), json!({ "user": stored(s, "User"), "error": errors.get(s).cloned().unwrap_or_default() })));
    Value::Object(services.collect())
}

pub fn logout(service: &str) -> Result<Value> {
    let service = named(service)?;
    forget(service);
    ERRORS.lock().unwrap().remove(service);
    Ok(status())
}

fn redirect(service: &str) -> String {
    format!("http://127.0.0.1:{PORT}/{service}")
}

/// The page to open in the browser. It sends the user back to a listener here.
pub async fn login(service: &str) -> Result<Value> {
    let service = named(service)?;
    let (state, verifier) = (crate::lan::secret(), crate::lan::secret());
    let url = if service == "anilist" {
        ensure!(!ANILIST_CLIENT.is_empty(), "This build has no AniList client.");
        url::Url::parse_with_params("https://anilist.co/api/v2/oauth/authorize", [("client_id", ANILIST_CLIENT), ("response_type", "token")])?
    } else {
        ensure!(!MAL_CLIENT.is_empty(), "This build has no MyAnimeList client.");
        url::Url::parse_with_params(
            &format!("{MAL_OAUTH}/authorize"),
            [
                ("response_type", "code"),
                ("client_id", MAL_CLIENT),
                ("code_challenge", &verifier), // MAL only supports `plain`
                ("code_challenge_method", "plain"),
                ("state", &state),
                ("redirect_uri", &redirect("mal")),
            ],
        )?
    };
    *LOGIN.lock().unwrap() = Some(Login { service, state, verifier });
    listen().await?;
    Ok(json!({ "url": url.as_str() }))
}

/// Up for five minutes, or until a login finishes.
async fn listen() -> Result<()> {
    if LISTENING.swap(true, Ordering::SeqCst) {
        return Ok(());
    }
    let listener = match tokio::net::TcpListener::bind(("127.0.0.1", PORT)).await {
        Ok(l) => l,
        Err(e) => {
            LISTENING.store(false, Ordering::SeqCst);
            return Err(e).context(format!("Port {PORT} is in use"));
        }
    };
    let app = axum::Router::new().route("/anilist", axum::routing::get(anilist_back)).route("/mal", axum::routing::get(mal_back));
    tokio::spawn(async move {
        let stop = async {
            tokio::select! {
                _ = tokio::time::sleep(Duration::from_secs(300)) => {}
                _ = FINISHED.notified() => {}
            }
        };
        if let Err(e) = axum::serve(listener, app).with_graceful_shutdown(stop).await {
            tracing::warn!("tracker login listener stopped: {e}");
        }
        LOGIN.lock().unwrap().take();
        LISTENING.store(false, Ordering::SeqCst);
    });
    Ok(())
}

fn query(req: &Request) -> HashMap<String, String> {
    url::form_urlencoded::parse(req.uri().query().unwrap_or_default().as_bytes()).into_owned().collect()
}

async fn anilist_back(req: Request) -> Html<String> {
    let q = query(&req);
    // The token comes in the fragment, which only the page can read.
    if !q.contains_key("access_token") && !q.contains_key("error") {
        return Html("<!doctype html><script>location.replace('/anilist?' + (location.hash.slice(1) || 'error=No%20token'))</script>".into());
    }
    finish("anilist", anilist_login(&q).await)
}

async fn mal_back(req: Request) -> Html<String> {
    finish("mal", mal_login(&query(&req)).await)
}

fn finish(service: &'static str, result: Result<()>) -> Html<String> {
    let message = match result {
        Ok(()) => {
            ERRORS.lock().unwrap().remove(service);
            FINISHED.notify_one();
            "Connected. You can close this tab.".to_owned()
        }
        Err(e) => {
            tracing::warn!("{} login failed: {e:#}", label(service));
            ERRORS.lock().unwrap().insert(service, e.to_string());
            format!("Couldn't connect: {e}")
        }
    };
    push("tracker", &status());
    Html(format!("<!doctype html><meta charset=utf-8><title>Aikatsu</title><p>{}</p>", html_escape::encode_text(&message)))
}

/// `state: None` skips the check: AniList's implicit grant has none.
fn take_login(service: &str, state: Option<&str>) -> Result<Login> {
    let mut pending = LOGIN.lock().unwrap();
    let ok = pending.as_ref().is_some_and(|l| l.service == service && state.is_none_or(|s| s == l.state));
    ensure!(ok, "Start connecting from Aikatsu again.");
    Ok(pending.take().expect("checked above"))
}

fn denied(q: &HashMap<String, String>) -> Result<()> {
    match q.get("error") {
        Some(e) => bail!("{}", q.get("error_description").unwrap_or(e)),
        None => Ok(()),
    }
}

async fn anilist_login(q: &HashMap<String, String>) -> Result<()> {
    take_login("anilist", None)?;
    denied(q)?;
    let token = q.get("access_token").context("AniList sent no token")?;
    let d = graphql(token, "query { Viewer { name } }", json!({})).await?;
    let user = d["Viewer"]["name"].as_str().context("Unexpected response from AniList")?;
    store("anilist", "Token", token)?;
    store("anilist", "User", user)
}

async fn mal_login(q: &HashMap<String, String>) -> Result<()> {
    let login = take_login("mal", Some(q.get("state").map_or("", String::as_str)))?;
    denied(q)?;
    let code = q.get("code").context("MyAnimeList sent no code")?;
    let t = mal_tokens(&[("grant_type", "authorization_code"), ("code", code), ("code_verifier", &login.verifier), ("redirect_uri", &redirect("mal"))]).await?;
    let auth = format!("Bearer {}", t["access_token"].as_str().unwrap_or_default());
    let me = send("mal", http::PLAIN.get(format!("{MAL_API}/users/@me")).header("Authorization", auth)).await?;
    let user = me["name"].as_str().context("Unexpected response from MyAnimeList")?;
    save_mal_tokens(&t)?;
    store("mal", "User", user)
}

/// A 401 ends the session; AniList answers an expired token with 400 "Invalid token".
async fn send(service: &str, rb: wreq::RequestBuilder) -> Result<Value> {
    let resp = rb
        .header("User-Agent", http::API_UA)
        .header("Accept", "application/json")
        .timeout(Duration::from_secs(20))
        .send()
        .await
        .with_context(|| format!("Couldn't reach {}", label(service)))?;
    let status = resp.status();
    let body: Value = resp.json().await.unwrap_or_default();
    let message = body["errors"][0]["message"].as_str().or(body["message"].as_str()).or(body["error"].as_str()).unwrap_or_default();
    if status.as_u16() == 401 || message == "Invalid token" {
        forget(service);
        bail!(EXPIRED);
    }
    if !status.is_success() {
        let detail = if message.is_empty() { String::new() } else { format!(": {message}") };
        return Err(Refused(format!("{} returned {status}{detail}", label(service))).into());
    }
    Ok(body)
}

async fn graphql(token: &str, query: &str, variables: Value) -> Result<Value> {
    let rb = http::PLAIN
        .post(crate::meta::ANILIST)
        .header("Authorization", format!("Bearer {token}"))
        .json(&json!({ "query": query, "variables": variables }));
    let v = send("anilist", rb).await?;
    if let Some(e) = v["errors"][0]["message"].as_str() {
        bail!("AniList: {e}");
    }
    Ok(v["data"].clone())
}

async fn mal_tokens(form: &[(&str, &str)]) -> Result<Value> {
    let form = [&[("client_id", MAL_CLIENT)], form].concat();
    let t = send("mal", http::PLAIN.post(format!("{MAL_OAUTH}/token")).form(&form)).await?;
    ensure!(t["access_token"].is_string(), "Unexpected response from MyAnimeList");
    Ok(t)
}

fn save_mal_tokens(t: &Value) -> Result<()> {
    store("mal", "Token", t["access_token"].as_str().unwrap_or_default())?;
    store("mal", "Refresh", t["refresh_token"].as_str().unwrap_or_default())?;
    store("mal", "Expires", &(now() + t["expires_in"].as_i64().unwrap_or(3600)).to_string())
}

/// Refreshed with a day to spare. A refused refresh (the refresh token lasts
/// about a month) ends the session.
async fn mal_access() -> Result<String> {
    if stored("mal", "Expires").parse::<i64>().unwrap_or(0) < now() + 86400 {
        match mal_tokens(&[("grant_type", "refresh_token"), ("refresh_token", &stored("mal", "Refresh"))]).await {
            Ok(t) => save_mal_tokens(&t)?,
            Err(e) if e.downcast_ref::<Refused>().is_some() => {
                forget("mal");
                bail!(EXPIRED);
            }
            Err(e) => return Err(e),
        }
    }
    Ok(stored("mal", "Token"))
}

/// The local watchlist moves at once; the trackers follow in the background.
pub fn watched(p: &db::Progress, total: i64) -> Result<()> {
    let e = db::auto_watch(p, total)?;
    crate::RT.spawn(update(e, None));
    Ok(())
}

pub fn set_status(e: db::WatchEntry) {
    let status = e.status.clone();
    crate::RT.spawn(update(e, Some(status)));
}

/// Progress never goes down and stops at the last episode. Without a chosen
/// status, the status follows progress.
fn target<'a>(remote_progress: i64, remote_status: &str, highest: i64, total: i64, chosen: Option<&'a str>) -> (i64, &'a str) {
    let mut progress = remote_progress.max(highest);
    if total > 0 {
        progress = progress.min(total);
    }
    let status = chosen.unwrap_or_else(|| db::next_status(remote_status, progress, total));
    if status == "completed" && total > 0 {
        progress = total;
    }
    (progress, status)
}

async fn update(e: db::WatchEntry, chosen: Option<String>) {
    let services: Vec<_> = SERVICES.into_iter().filter(|s| connected(s) && if *s == "anilist" { e.anilist_id > 0 } else { e.mal_id > 0 }).collect();
    if services.is_empty() {
        return;
    }
    let _one = ONE.lock().await;
    let highest = db::highest_watched(&e.series_key, &e.series_url).unwrap_or(0);
    for service in services {
        let result = if service == "anilist" {
            anilist_update(e.anilist_id, highest, e.total_episodes, chosen.as_deref()).await
        } else {
            mal_update(e.mal_id, highest, e.total_episodes, chosen.as_deref()).await
        };
        match result {
            Ok(()) => _ = ERRORS.lock().unwrap().remove(service),
            Err(err) => {
                tracing::warn!("{} update for {} failed: {err:#}", label(service), e.title);
                ERRORS.lock().unwrap().insert(service, err.to_string());
            }
        }
    }
    push("tracker", &status());
}

async fn anilist_update(id: i64, highest: i64, total: i64, chosen: Option<&str>) -> Result<()> {
    let token = stored("anilist", "Token");
    let d = graphql(&token, "query ($id: Int) { Media(id: $id, type: ANIME) { mediaListEntry { progress status } } }", json!({ "id": id })).await?;
    let entry = &d["Media"]["mediaListEntry"];
    let remote = (entry["progress"].as_i64().unwrap_or(0), local_status(entry["status"].as_str().unwrap_or_default()));
    let (progress, status) = target(remote.0, remote.1, highest, total, chosen);
    if !entry.is_null() && (progress, status) == remote {
        return Ok(());
    }
    let remote_status = STATUSES.iter().find(|t| t.0 == status).map_or("CURRENT", |t| t.1);
    graphql(
        &token,
        "mutation ($id: Int, $progress: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $id, progress: $progress, status: $status) { id } }",
        json!({ "id": id, "progress": progress, "status": remote_status }),
    )
    .await?;
    Ok(())
}

async fn mal_update(id: i64, highest: i64, total: i64, chosen: Option<&str>) -> Result<()> {
    let auth = format!("Bearer {}", mal_access().await?);
    let v = send("mal", http::PLAIN.get(format!("{MAL_API}/anime/{id}?fields=my_list_status")).header("Authorization", &auth)).await?;
    let entry = &v["my_list_status"];
    let remote = (entry["num_episodes_watched"].as_i64().unwrap_or(0), local_status(entry["status"].as_str().unwrap_or_default()));
    let (progress, status) = target(remote.0, remote.1, highest, total, chosen);
    if !entry.is_null() && (progress, status) == remote {
        return Ok(());
    }
    let (remote_status, watched) = (STATUSES.iter().find(|t| t.0 == status).map_or("watching", |t| t.2), progress.to_string());
    let rb = http::PLAIN
        .patch(format!("{MAL_API}/anime/{id}/my_list_status"))
        .header("Authorization", &auth)
        .form(&[("status", remote_status), ("num_watched_episodes", watched.as_str())]);
    send("mal", rb).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_never_goes_down() {
        assert_eq!(target(5, "watching", 3, 12, None), (5, "watching"), "watched more elsewhere");
        assert_eq!(target(0, "", 1, 12, None), (1, "watching"), "not on the list yet");
        assert_eq!(target(11, "paused", 12, 12, None), (12, "completed"));
        assert_eq!(target(12, "completed", 2, 12, None), (12, "completed"), "a rewatch");
        assert_eq!(target(3, "watching", 3, 0, Some("dropped")), (3, "dropped"));
        assert_eq!(target(3, "watching", 3, 12, Some("completed")), (12, "completed"));
        assert_eq!((local_status("REPEATING"), local_status("plan_to_watch"), local_status("")), ("watching", "planning", ""));
    }

    #[test]
    fn a_login_needs_its_own_state() {
        *LOGIN.lock().unwrap() = Some(Login { service: "mal", state: "s".into(), verifier: "v".into() });
        assert!(take_login("mal", Some("wrong")).is_err());
        assert!(take_login("anilist", None).is_err(), "another service's login");
        assert!(take_login("mal", Some("s")).is_ok());
        assert!(take_login("mal", Some("s")).is_err(), "used once");
    }
}
