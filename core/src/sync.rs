//! Cloud sync with an aikatsu-sync server. Each episode and setting is one
//! record, and the newest change wins.

use crate::{db, http, plugins, push};
use anyhow::{Context, Result, ensure};
use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::Mutex;
use std::time::Duration;

// Set at build time; release builds get it from the AIKATSU_SYNC_SERVER secret.
const DEFAULT_SERVER: Option<&str> = option_env!("AIKATSU_SYNC_SERVER");

pub const SYNCED_SETTINGS: [&str; 7] =
    ["autoplay", "autoSkip", "quality", "disabledSources", "autoCheckPluginUpdates", "tmdbKey", plugins::REPOS_SETTING];

/// Also each device's shared-library address, so phones on the account find it,
/// and when they couldn't.
pub fn synced(key: &str) -> bool {
    SYNCED_SETTINGS.contains(&key) || key.starts_with(crate::lan::RECORD) || key.starts_with(crate::lan::MISS)
}

// Outside SETTING_DEFAULTS, so the UIs never see the token.
const SERVER: &str = "syncServer";
const TOKEN: &str = "syncToken";
const USER: &str = "syncUser";
const CURSOR: &str = "syncCursor";
const LAST: &str = "syncLast";

const BATCH: usize = 500;
static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
static ERROR: Mutex<String> = Mutex::new(String::new());

#[derive(Debug)]
struct Refused {
    status: u16,
    message: String,
}

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for Refused {}

#[derive(Deserialize)]
struct Pulled {
    cursor: i64,
    more: bool,
    changes: Vec<db::Change>,
}

fn stored(key: &str) -> String {
    db::setting(key).unwrap_or_default()
}

fn server() -> String {
    Some(stored(SERVER)).filter(|s| !s.is_empty()).or_else(|| DEFAULT_SERVER.and_then(|s| normalize(s).ok())).unwrap_or_default()
}

pub(crate) fn signed_in() -> bool {
    !stored(TOKEN).is_empty()
}

pub fn status() -> Value {
    json!({
        "signedIn": signed_in(),
        "username": stored(USER),
        "server": stored(SERVER),
        "lastSync": stored(LAST).parse::<i64>().unwrap_or(0),
        "syncing": ONE.try_lock().is_err(),
        "error": ERROR.lock().unwrap().clone(),
    })
}

fn normalize(input: &str) -> Result<String> {
    let s = input.trim().trim_end_matches('/');
    let s = if s.contains("://") { s.to_owned() } else { format!("https://{s}") };
    let url = url::Url::parse(&s).ok().filter(|u| matches!(u.scheme(), "http" | "https") && u.host().is_some());
    Ok(url.context("Invalid server address")?.as_str().trim_end_matches('/').to_owned())
}

async fn post(server: &str, path: &str, token: &str, body: &Value) -> Result<Value> {
    let mut rb = http::PLAIN
        .post(format!("{server}{path}"))
        .header("User-Agent", http::API_UA)
        .header("Accept", "application/json")
        .json(body)
        .timeout(Duration::from_secs(20));
    if !token.is_empty() {
        rb = rb.header("Authorization", format!("Bearer {token}"));
    }
    let resp = rb.send().await.context("Couldn't reach the sync server")?;
    let status = resp.status();
    let text = resp.text().await.context("Couldn't reach the sync server")?;
    if status.is_success() {
        return Ok(if text.is_empty() { Value::Null } else { serde_json::from_str(&text).context("Unexpected response from the server")? });
    }
    let message = serde_json::from_str::<Value>(&text).ok().and_then(|v| v["error"].as_str().map(str::to_owned));
    Err(Refused { status: status.as_u16(), message: message.unwrap_or_else(|| format!("Server error ({status})")) }.into())
}

/// Empty means the default. Signed in, it's refused: an account belongs to its server.
pub fn set_server(input: &str) -> Result<Value> {
    ensure!(!signed_in(), "Sign out before changing the server.");
    let server = if input.trim().is_empty() { String::new() } else { normalize(input)? };
    db::set_setting(SERVER, &server)?;
    Ok(status())
}

pub async fn sign_in(username: &str, password: &str, create: bool) -> Result<Value> {
    let server = server();
    ensure!(!server.is_empty(), "Choose a server first.");
    let path = if create { "/auth/register" } else { "/auth/login" };
    let r = post(&server, path, "", &json!({ "username": username, "password": password, "device": std::env::consts::OS })).await?;
    let token = r["token"].as_str().context("Unexpected response from the server")?;
    {
        let _one = ONE.lock().await;
        db::set_setting(TOKEN, token)?;
        db::set_setting(USER, r["username"].as_str().unwrap_or(username))?;
        db::set_setting(CURSOR, "0")?;
        db::set_setting(LAST, "")?;
        db::sync_seed()?;
    }
    crate::lan::refresh().await;
    Ok(sync().await)
}

fn forget() {
    for key in [TOKEN, USER, CURSOR, LAST] {
        let _ = db::set_setting(key, "");
    }
    crate::lan::forget();
}

pub async fn sign_out() -> Value {
    {
        let _one = ONE.lock().await;
        let token = stored(TOKEN);
        if !token.is_empty() {
            let _ = post(&server(), "/auth/logout", &token, &Value::Null).await;
        }
        forget();
        ERROR.lock().unwrap().clear();
    }
    let s = status();
    push("sync", &s);
    s
}

pub async fn change_password(current: &str, password: &str) -> Result<()> {
    post(&server(), "/account/password", &stored(TOKEN), &json!({ "current": current, "password": password })).await?;
    Ok(())
}

pub async fn delete_account(password: &str) -> Result<Value> {
    {
        let _one = ONE.lock().await;
        post(&server(), "/account/delete", &stored(TOKEN), &json!({ "password": password })).await?;
        forget();
    }
    let s = status();
    push("sync", &s);
    Ok(s)
}

/// Never fails: the error shows in `status()`.
pub async fn sync() -> Value {
    if !signed_in() {
        return status();
    }
    let (history, settings) = {
        let _one = ONE.lock().await;
        match exchange().await {
            Ok(changed) => {
                ERROR.lock().unwrap().clear();
                changed
            }
            Err(e) => {
                tracing::warn!("sync failed: {e:#}");
                let ended = e.downcast_ref::<Refused>().is_some_and(|r| r.status == 401);
                if ended {
                    forget();
                }
                *ERROR.lock().unwrap() = if ended { "Session expired. Sign in again.".into() } else { e.to_string() };
                (false, false)
            }
        }
    };
    let mut s = status();
    s["history"] = history.into();
    s["settings"] = settings.into();
    push("sync", &s);
    s
}

/// Returns whether history and settings changed here.
async fn exchange() -> Result<(bool, bool)> {
    let (server, token) = (server(), stored(TOKEN));
    let mut cursor: i64 = stored(CURSOR).parse().unwrap_or(0);
    let repos_before = plugins::repo_urls();
    let (mut history, mut settings) = (false, Vec::new());
    for _ in 0..50 {
        let (changes, last) = db::sync_pending(BATCH)?;
        let sent = changes.len();
        let r: Pulled = serde_json::from_value(post(&server, "/sync", &token, &json!({ "cursor": cursor, "changes": changes })).await?)
            .context("Unexpected response from the server")?;
        db::sync_ack(last)?;
        let applied = db::sync_apply(&r.changes)?;
        history |= applied.history;
        settings.extend(applied.settings);
        cursor = r.cursor;
        db::set_setting(CURSOR, &cursor.to_string())?;
        if !r.more && sent < BATCH {
            break;
        }
    }
    db::set_setting(LAST, &std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs().to_string())?;
    if settings.iter().any(|k| k == plugins::REPOS_SETTING) {
        plugins::repos_synced(&repos_before).await;
    }
    Ok((history, !settings.is_empty()))
}

/// Progress saves every few seconds while playing, so it's pushed in batches.
pub async fn run() {
    loop {
        crate::lan::refresh().await;
        sync().await;
        tokio::time::sleep(Duration::from_secs(120)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_server_addresses() {
        assert_eq!(normalize(" sync.example.com/ ").unwrap(), "https://sync.example.com");
        assert_eq!(normalize("http://192.168.1.5:3000").unwrap(), "http://192.168.1.5:3000");
        assert_eq!(normalize("https://example.com/aikatsu/").unwrap(), "https://example.com/aikatsu");
        assert!(normalize("").is_err());
        assert!(normalize("ftp://example.com").is_err());
    }
}
