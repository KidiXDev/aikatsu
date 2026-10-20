//! Watch history, settings, downloaded episodes and the lookup cache, stored in SQLite.

use crate::meta::Meta;
use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, params};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)] // rows from other app versions may lack fields
pub struct Progress {
    pub episode_key: String,
    pub anilist_id: i64,
    pub mal_id: i64,
    pub series_key: String,
    pub series_url: String,
    pub series_title: String,
    pub source: String,
    pub episode_url: String,
    pub total_episodes: i64,
    pub episode_number: i64,
    pub playback_time: i64,
    pub duration: i64,
    pub title: String,
    pub cover: String,
    pub completed: bool,
    pub last_updated: i64,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Series {
    pub key: String,
    pub url: String,
    pub title: String,
    pub source: String,
    pub anilist_id: i64,
    pub mal_id: i64,
    pub cover: String,
    pub total_episodes: i64,
    pub continue_episode: i64,
    pub last_updated: i64,
    pub finished: bool,
    pub episodes: Vec<Progress>,
}

/// A show on the watchlist. `status`: watching, planning, completed, paused or dropped.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct WatchEntry {
    pub series_key: String,
    pub status: String,
    pub anilist_id: i64,
    pub mal_id: i64,
    pub title: String,
    pub cover: String,
    pub source: String,
    pub series_url: String,
    pub total_episodes: i64,
    pub updated: i64,
}

/// `anilist:<id>` when known (shares progress across sources), else `<source>:<url>`.
pub fn series_key(anilist_id: i64, source: &str, series_url: &str) -> String {
    if anilist_id > 0 { format!("anilist:{anilist_id}") } else { format!("{}:{series_url}", source.to_lowercase()) }
}

pub fn episode_key(series_key: &str, ep: i64) -> String {
    format!("{series_key}:ep{ep}")
}

static DB: OnceLock<Mutex<Connection>> = OnceLock::new();

fn open_database(dir: &std::path::Path) -> Result<Connection> {
    std::fs::create_dir_all(dir).context("Couldn't create the app storage folder")?;
    let path = dir.join("progress.db");
    let conn = Connection::open(&path).with_context(|| format!("Couldn't open {}", path.display()))?;
    init(&conn).context("Couldn't initialize the history database")?;
    Ok(conn)
}

pub(crate) fn initialize() -> Result<()> {
    if DB.get().is_none() {
        let conn = open_database(&crate::dirs().data)?;
        let _ = DB.set(Mutex::new(conn));
    }
    Ok(())
}

fn database() -> &'static Mutex<Connection> {
    DB.get_or_init(|| Mutex::new(open_database(&crate::dirs().data).expect("initialize storage before using it")))
}

fn init(c: &Connection) -> rusqlite::Result<()> {
    c.execute_batch(
        "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000;
        CREATE TABLE IF NOT EXISTS media_progress (
            episode_key    TEXT    PRIMARY KEY NOT NULL,
            anilist_id     INTEGER NOT NULL DEFAULT 0,
            mal_id         INTEGER NOT NULL DEFAULT 0,
            series_key     TEXT    NOT NULL DEFAULT '',
            series_url     TEXT    NOT NULL DEFAULT '',
            series_title   TEXT    NOT NULL DEFAULT '',
            source         TEXT    NOT NULL DEFAULT '',
            episode_url    TEXT    NOT NULL DEFAULT '',
            total_episodes INTEGER NOT NULL DEFAULT 0,
            episode_number INTEGER NOT NULL,
            playback_time  INTEGER NOT NULL CHECK(playback_time >= 0),
            duration       INTEGER NOT NULL CHECK(duration >= 0),
            title          TEXT    NOT NULL DEFAULT '',
            cover          TEXT    NOT NULL DEFAULT '',
            completed      INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0, 1)),
            last_updated   INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_recent ON media_progress(last_updated DESC);
        CREATE INDEX IF NOT EXISTS idx_series ON media_progress(series_key, episode_number);
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS downloads (
            path           TEXT    PRIMARY KEY NOT NULL,
            source         TEXT    NOT NULL,
            series_url     TEXT    NOT NULL DEFAULT '',
            series_name    TEXT    NOT NULL DEFAULT '',
            episode_number INTEGER NOT NULL,
            episode_url    TEXT    NOT NULL DEFAULT '',
            size           INTEGER NOT NULL DEFAULT 0,
            finished       INTEGER NOT NULL,
            meta           TEXT    NOT NULL DEFAULT '{}'
        );
        CREATE INDEX IF NOT EXISTS idx_downloads_series ON downloads(source, series_url);
        CREATE TABLE IF NOT EXISTS local_series (path TEXT PRIMARY KEY NOT NULL, meta TEXT NOT NULL DEFAULT '{}');
        CREATE TABLE IF NOT EXISTS watchlist (
            series_key     TEXT    PRIMARY KEY NOT NULL,
            status         TEXT    NOT NULL,
            anilist_id     INTEGER NOT NULL DEFAULT 0,
            mal_id         INTEGER NOT NULL DEFAULT 0,
            title          TEXT    NOT NULL DEFAULT '',
            cover          TEXT    NOT NULL DEFAULT '',
            source         TEXT    NOT NULL DEFAULT '',
            series_url     TEXT    NOT NULL DEFAULT '',
            total_episodes INTEGER NOT NULL DEFAULT 0,
            updated        INTEGER NOT NULL
        );
        -- Unsent changes. REPLACE gives a changed row a new id, above any already sent.
        CREATE TABLE IF NOT EXISTS sync_dirty (
            id   INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT    NOT NULL,
            key  TEXT    NOT NULL,
            at   INTEGER NOT NULL,
            UNIQUE(kind, key)
        );
        DELETE FROM cache WHERE expires < strftime('%s', 'now') - 30 * 86400;",
    )?;
    migrate(c)
}

/// The sources that were built in before plugins; Kyoko carries them on.
const BUILT_IN: [&str; 6] = ["otakudesu", "samehadaku", "nimegami", "ylnime", "moenime", "astronime"];

fn migrate(c: &Connection) -> rusqlite::Result<()> {
    migrate_v1(c)?;
    // v2: versions before the watchlist skipped its records but synced past
    // them, so pull everything again once. Records older than the local copy change nothing.
    if c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))? < 2 {
        c.execute_batch("UPDATE settings SET value = '0' WHERE key = 'syncCursor'; PRAGMA user_version = 2")?;
    }
    Ok(())
}

/// v1: source keys gained their repo ("otakudesu" → "kyoko/otakudesu"), in
/// history (and the keys built from it), downloads and the disabled list.
fn migrate_v1(c: &Connection) -> rusqlite::Result<()> {
    let version: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if version >= 1 {
        return Ok(());
    }
    let tx = c.unchecked_transaction()?;
    for key in BUILT_IN {
        tx.execute(
            "UPDATE media_progress SET series_key = 'kyoko/' || series_key, episode_key = 'kyoko/' || episode_key
             WHERE source = ?1 AND series_key LIKE ?1 || ':%'",
            [key],
        )?;
        tx.execute("UPDATE media_progress SET source = 'kyoko/' || source WHERE source = ?1", [key])?;
        tx.execute("UPDATE downloads SET source = 'kyoko/' || source WHERE source = ?1", [key])?;
    }
    let disabled: Option<String> = tx.query_row("SELECT value FROM settings WHERE key = 'disabledSources'", [], |r| r.get(0)).optional()?;
    if let Some(list) = disabled {
        let list: Vec<String> =
            list.split(',').map(str::trim).filter(|k| !k.is_empty()).map(|k| if BUILT_IN.contains(&k) { format!("kyoko/{k}") } else { k.to_owned() }).collect();
        tx.execute("UPDATE settings SET value = ?1 WHERE key = 'disabledSources'", [list.join(",")])?;
    }
    tx.execute_batch("PRAGMA user_version = 1")?;
    tx.commit()
}

/// Remote lookups (AniList, Jikan, AniSkip) kept across restarts. A fresh entry
/// is returned as is; otherwise `fetch` runs and is stored for `ttl` (`refresh`
/// skips the read). When `fetch` fails, an expired entry (kept up to 30 days)
/// beats an error on a flaky connection.
pub async fn cached<T: Serialize + DeserializeOwned>(key: &str, ttl: Duration, refresh: bool, fetch: impl Future<Output = Result<T>>) -> Result<T> {
    cached_on(database(), key, ttl, refresh, fetch).await
}

async fn cached_on<T: Serialize + DeserializeOwned>(
    db: &Mutex<Connection>,
    key: &str,
    ttl: Duration,
    refresh: bool,
    fetch: impl Future<Output = Result<T>>,
) -> Result<T> {
    let stored: Option<(String, i64)> =
        db.lock().unwrap().query_row("SELECT value, expires FROM cache WHERE key = ?1", [key], |r| Ok((r.get(0)?, r.get(1)?))).optional().ok().flatten();
    if let Some((v, expires)) = &stored
        && !refresh
        && *expires > now()
        && let Ok(t) = serde_json::from_str(v)
    {
        return Ok(t);
    }
    match fetch.await {
        Ok(t) => {
            if let Ok(v) = serde_json::to_string(&t) {
                let _ = db.lock().unwrap().execute(
                    "INSERT OR REPLACE INTO cache (key, value, expires) VALUES (?1, ?2, ?3)",
                    params![key, v, now() + ttl.as_secs() as i64],
                );
            }
            Ok(t)
        }
        Err(e) => match stored.and_then(|(v, _)| serde_json::from_str(&v).ok()) {
            Some(t) => {
                tracing::warn!("{key}: refresh failed, using cached copy ({e:#})");
                Ok(t)
            }
            None => Err(e),
        },
    }
}

pub fn clear_cache() -> Result<()> {
    database().lock().unwrap().execute("DELETE FROM cache", [])?;
    Ok(())
}

/// Bytes of cached lookups.
pub fn cache_size() -> Result<i64> {
    Ok(database().lock().unwrap().query_row("SELECT COALESCE(SUM(LENGTH(value)), 0) FROM cache", [], |r| r.get(0))?)
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// A row's time only moves forward, so a local change beats the copy it
/// replaces, even one from a clock running ahead. True when the episode has
/// just been completed: the player keeps saving it as completed after 90%.
pub fn upsert(p: &Progress) -> Result<bool> {
    let c = database().lock().unwrap();
    let was = get_on(&c, &p.episode_key)?.is_some_and(|r| r.completed);
    upsert_on(&c, p)?;
    queue_change(&c, "progress", &p.episode_key)?;
    Ok(p.completed && !was)
}

fn queue_change(c: &Connection, kind: &str, key: &str) -> Result<()> {
    c.execute("INSERT OR REPLACE INTO sync_dirty (kind, key, at) VALUES (?1, ?2, ?3)", params![kind, key, now()])?;
    Ok(())
}

fn upsert_on(c: &Connection, p: &Progress) -> Result<()> {
    let updated = if p.last_updated > 0 { p.last_updated } else { now() };
    c.execute(
        "INSERT INTO media_progress (episode_key, anilist_id, mal_id, series_key, series_url, series_title, source, episode_url,
            total_episodes, episode_number, playback_time, duration, title, cover, completed, last_updated)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)
         ON CONFLICT(episode_key) DO UPDATE SET
            anilist_id=excluded.anilist_id, mal_id=excluded.mal_id, series_key=excluded.series_key, series_url=excluded.series_url,
            series_title=excluded.series_title, source=excluded.source, episode_url=excluded.episode_url,
            total_episodes=MAX(total_episodes, excluded.total_episodes), episode_number=excluded.episode_number,
            playback_time=excluded.playback_time, duration=excluded.duration, title=excluded.title,
            cover=CASE WHEN excluded.cover != '' THEN excluded.cover ELSE cover END,
            completed=excluded.completed, last_updated=MAX(excluded.last_updated, last_updated + 1)",
        params![
            p.episode_key, p.anilist_id, p.mal_id, p.series_key, p.series_url, p.series_title, p.source, p.episode_url,
            p.total_episodes, p.episode_number, p.playback_time.max(0), p.duration.max(0), p.title, p.cover, p.completed, updated
        ],
    )?;
    Ok(())
}

/// Marks an episode (not) completed, creating the row if it was never played.
/// True when it has just been completed.
pub fn set_completed(p: &Progress, completed: bool) -> Result<bool> {
    let c = database().lock().unwrap();
    let existing = get_on(&c, &p.episode_key)?;
    let was = existing.as_ref().is_some_and(|r| r.completed);
    let mut row = existing.unwrap_or_else(|| p.clone());
    row.completed = completed;
    row.last_updated = 0;
    upsert_on(&c, &row)?;
    queue_change(&c, "progress", &row.episode_key)?;
    Ok(completed && !was)
}

fn row(r: &rusqlite::Row) -> rusqlite::Result<Progress> {
    Ok(Progress {
        episode_key: r.get(0)?,
        anilist_id: r.get(1)?,
        mal_id: r.get(2)?,
        series_key: r.get(3)?,
        series_url: r.get(4)?,
        series_title: r.get(5)?,
        source: r.get(6)?,
        episode_url: r.get(7)?,
        total_episodes: r.get(8)?,
        episode_number: r.get(9)?,
        playback_time: r.get(10)?,
        duration: r.get(11)?,
        title: r.get(12)?,
        cover: r.get(13)?,
        completed: r.get(14)?,
        last_updated: r.get(15)?,
    })
}

const COLUMNS: &str = "episode_key, anilist_id, mal_id, series_key, series_url, series_title, source, episode_url,
    total_episodes, episode_number, playback_time, duration, title, cover, completed, last_updated";

fn get_on(c: &Connection, episode_key: &str) -> Result<Option<Progress>> {
    Ok(c.query_row(&format!("SELECT {COLUMNS} FROM media_progress WHERE episode_key = ?1"), [episode_key], row).optional()?)
}

pub fn all() -> Result<Vec<Progress>> {
    all_on(&database().lock().unwrap())
}

fn all_on(c: &Connection) -> Result<Vec<Progress>> {
    let mut st = c.prepare(&format!("SELECT {COLUMNS} FROM media_progress ORDER BY last_updated DESC"))?;
    Ok(st.query_map([], row)?.collect::<rusqlite::Result<_>>()?)
}

/// Every saved episode of one series, matched by key or by its source URL
/// (covers rows saved before the AniList id was known).
pub fn series_episodes(series_key: &str, series_url: &str) -> Result<Vec<Progress>> {
    let c = database().lock().unwrap();
    let mut st = c.prepare(&format!(
        "SELECT {COLUMNS} FROM media_progress WHERE series_key = ?1 OR series_url = ?2 ORDER BY episode_number"
    ))?;
    Ok(st.query_map([series_key, series_url], row)?.collect::<rusqlite::Result<_>>()?)
}

/// The highest completed episode: the progress a tracker gets.
pub fn highest_watched(series_key: &str, series_url: &str) -> Result<i64> {
    highest_watched_on(&database().lock().unwrap(), series_key, series_url)
}

fn highest_watched_on(c: &Connection, series_key: &str, series_url: &str) -> Result<i64> {
    Ok(c.query_row(
        "SELECT COALESCE(MAX(episode_number), 0) FROM media_progress WHERE completed = 1 AND (series_key = ?1 OR (?2 != '' AND series_url = ?2))",
        [series_key, series_url],
        |r| r.get(0),
    )?)
}

const WATCH_COLUMNS: &str = "series_key, status, anilist_id, mal_id, title, cover, source, series_url, total_episodes, updated";

fn watch_row(r: &rusqlite::Row) -> rusqlite::Result<WatchEntry> {
    Ok(WatchEntry {
        series_key: r.get(0)?,
        status: r.get(1)?,
        anilist_id: r.get(2)?,
        mal_id: r.get(3)?,
        title: r.get(4)?,
        cover: r.get(5)?,
        source: r.get(6)?,
        series_url: r.get(7)?,
        total_episodes: r.get(8)?,
        updated: r.get(9)?,
    })
}

fn watch_get_on(c: &Connection, series_key: &str) -> Result<Option<WatchEntry>> {
    Ok(c.query_row(&format!("SELECT {WATCH_COLUMNS} FROM watchlist WHERE series_key = ?1"), [series_key], watch_row).optional()?)
}

/// Matched like `series_episodes`: by key, else by the source URL of an entry
/// saved before the AniList id was known.
fn watch_find_on(c: &Connection, series_key: &str, series_url: &str) -> Result<Option<WatchEntry>> {
    Ok(c.query_row(
        &format!("SELECT {WATCH_COLUMNS} FROM watchlist WHERE series_key = ?1 OR (?2 != '' AND series_url = ?2) ORDER BY series_key = ?1 DESC LIMIT 1"),
        [series_key, series_url],
        watch_row,
    )
    .optional()?)
}

fn watch_key(e: &WatchEntry) -> String {
    series_key(e.anilist_id, &e.source, &e.series_url)
}

pub fn watchlist() -> Result<Vec<WatchEntry>> {
    let c = database().lock().unwrap();
    let mut st = c.prepare(&format!("SELECT {WATCH_COLUMNS} FROM watchlist ORDER BY updated DESC"))?;
    Ok(st.query_map([], watch_row)?.collect::<rusqlite::Result<_>>()?)
}

/// The entry for a show, found from its AniList id, source and URL.
pub fn watch_entry(e: &WatchEntry) -> Result<Option<WatchEntry>> {
    watch_find_on(&database().lock().unwrap(), &watch_key(e), &e.series_url)
}

/// Saved under the show's existing key, so it never gets a second entry.
pub fn set_watch(e: &WatchEntry) -> Result<WatchEntry> {
    let c = database().lock().unwrap();
    let key = watch_key(e);
    let e = WatchEntry { series_key: watch_find_on(&c, &key, &e.series_url)?.map_or(key, |w| w.series_key), updated: 0, ..e.clone() };
    set_watch_on(&c, &e)?;
    queue_change(&c, "watchlist", &e.series_key)?;
    Ok(e)
}

pub fn remove_watch(e: &WatchEntry) -> Result<()> {
    remove_watch_on(&database().lock().unwrap(), e)
}

fn remove_watch_on(c: &Connection, e: &WatchEntry) -> Result<()> {
    let Some(w) = watch_find_on(c, &watch_key(e), &e.series_url)? else { return Ok(()) };
    let tx = c.unchecked_transaction()?;
    tx.execute("INSERT OR REPLACE INTO sync_dirty (kind, key, at) VALUES ('watchlist', ?1, ?2)", params![w.series_key, now().max(w.updated + 1)])?;
    tx.execute("DELETE FROM watchlist WHERE series_key = ?1", [&w.series_key])?;
    tx.commit()?;
    Ok(())
}

fn set_watch_on(c: &Connection, e: &WatchEntry) -> Result<()> {
    let updated = if e.updated > 0 { e.updated } else { now() };
    c.execute(
        "INSERT INTO watchlist (series_key, status, anilist_id, mal_id, title, cover, source, series_url, total_episodes, updated)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
         ON CONFLICT(series_key) DO UPDATE SET
            status=excluded.status, anilist_id=excluded.anilist_id, mal_id=excluded.mal_id, title=excluded.title,
            cover=CASE WHEN excluded.cover != '' THEN excluded.cover ELSE cover END, source=excluded.source, series_url=excluded.series_url,
            total_episodes=MAX(total_episodes, excluded.total_episodes), updated=MAX(excluded.updated, updated + 1)",
        params![e.series_key, e.status, e.anilist_id, e.mal_id, e.title, e.cover, e.source, e.series_url, e.total_episodes, updated],
    )?;
    Ok(())
}

/// After finishing episodes up to `highest`: completed at the last one, a
/// rewatch stays completed, anything else is watching.
pub fn next_status(current: &str, highest: i64, total: i64) -> &'static str {
    if current == "completed" || (total > 0 && highest >= total) { "completed" } else { "watching" }
}

/// A finished episode puts its show on the watchlist, or moves it along.
/// `total` is AniList's count, unlike the row's (the released episodes when that's unknown).
pub fn auto_watch(p: &Progress, total: i64) -> Result<WatchEntry> {
    auto_watch_on(&database().lock().unwrap(), p, total)
}

fn auto_watch_on(c: &Connection, p: &Progress, total: i64) -> Result<WatchEntry> {
    let found = watch_find_on(c, &p.series_key, &p.series_url)?;
    let mut e = found.clone().unwrap_or_else(|| WatchEntry {
        series_key: p.series_key.clone(),
        title: p.series_title.clone(),
        cover: p.cover.clone(),
        source: p.source.clone(),
        series_url: p.series_url.clone(),
        ..Default::default()
    });
    if p.anilist_id > 0 {
        e.anilist_id = p.anilist_id;
    }
    if p.mal_id > 0 {
        e.mal_id = p.mal_id;
    }
    e.total_episodes = e.total_episodes.max(total);
    e.status = next_status(&e.status, highest_watched_on(c, &p.series_key, &p.series_url)?, e.total_episodes).into();
    if found.as_ref() != Some(&e) {
        set_watch_on(c, &WatchEntry { updated: 0, ..e.clone() })?;
        queue_change(c, "watchlist", &e.series_key)?;
    }
    Ok(e)
}

pub fn delete_series(series_key: &str) -> Result<()> {
    delete_progress_on(&database().lock().unwrap(), "WHERE series_key = ?1", &[series_key])
}

pub fn clear_history() -> Result<()> {
    delete_progress_on(&database().lock().unwrap(), "", &[])
}

/// Queues each deletion, timed after its row so it wins.
fn delete_progress_on(c: &Connection, filter: &str, args: &[&str]) -> Result<()> {
    let tx = c.unchecked_transaction()?;
    tx.execute(
        &format!("INSERT OR REPLACE INTO sync_dirty (kind, key, at) SELECT 'progress', episode_key, MAX({}, last_updated + 1) FROM media_progress {filter}", now()),
        rusqlite::params_from_iter(args),
    )?;
    tx.execute(&format!("DELETE FROM media_progress {filter}"), rusqlite::params_from_iter(args))?;
    tx.commit()?;
    Ok(())
}

/// A finished download on disk, recorded so the app can list and play it offline.
#[derive(Clone, Debug, Default, Serialize)]
pub struct Download {
    pub path: String,
    pub source: String,
    pub series_url: String,
    /// The source's name for the series (`meta` has the AniList titles when known).
    pub series_name: String,
    pub episode_number: i64,
    pub episode_url: String,
    pub size: i64,
    pub finished: i64,
    #[serde(skip)] // once per series in `Library`, not per episode
    pub meta: Meta,
}

/// One series in the offline library, newest download first.
#[derive(Clone, Debug, Default, Serialize)]
pub struct LibrarySeries {
    pub source: String,
    pub series_url: String,
    pub series_name: String,
    pub meta: Meta,
    pub size: i64,
    pub finished: i64,
    pub episodes: Vec<Download>,
}

pub fn add_download(d: &Download) -> Result<()> {
    add_download_on(&database().lock().unwrap(), d)
}

fn add_download_on(c: &Connection, d: &Download) -> Result<()> {
    c.execute(
        "INSERT OR REPLACE INTO downloads (path, source, series_url, series_name, episode_number, episode_url, size, finished, meta)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
        params![
            d.path, d.source, d.series_url, d.series_name, d.episode_number, d.episode_url, d.size,
            if d.finished > 0 { d.finished } else { now() },
            serde_json::to_string(&d.meta)?
        ],
    )?;
    Ok(())
}

/// Every recorded download whose file is still there; rows for files deleted
/// outside the app are dropped on the way.
fn downloads_on(c: &Connection, filter: &str, args: &[&str]) -> Result<Vec<Download>> {
    let mut st = c.prepare(&format!(
        "SELECT path, source, series_url, series_name, episode_number, episode_url, size, finished, meta
         FROM downloads {filter} ORDER BY finished DESC"
    ))?;
    let rows: Vec<Download> = st
        .query_map(rusqlite::params_from_iter(args), |r| {
            Ok(Download {
                path: r.get(0)?,
                source: r.get(1)?,
                series_url: r.get(2)?,
                series_name: r.get(3)?,
                episode_number: r.get(4)?,
                episode_url: r.get(5)?,
                size: r.get(6)?,
                finished: r.get(7)?,
                meta: serde_json::from_str(&r.get::<_, String>(8)?).unwrap_or_default(),
            })
        })?
        .collect::<rusqlite::Result<_>>()?;
    let (present, missing): (Vec<_>, Vec<_>) = rows.into_iter().partition(|d| std::path::Path::new(&d.path).is_file());
    for d in missing.iter().filter(|d| std::path::Path::new(&d.path).parent().is_some_and(std::path::Path::is_dir)) {
        c.execute("DELETE FROM downloads WHERE path = ?1", [&d.path])?;
    }
    Ok(present)
}

pub fn library() -> Result<Vec<LibrarySeries>> {
    Ok(group_library(downloads_on(&database().lock().unwrap(), "", &[])?))
}

/// Groups by source and series URL (by name for rows without a URL), keeping
/// the newest-first order of `rows` for the series.
fn group_library(rows: Vec<Download>) -> Vec<LibrarySeries> {
    let mut out: Vec<LibrarySeries> = Vec::new();
    for d in rows {
        let same = |s: &LibrarySeries| s.source == d.source && if d.series_url.is_empty() { s.series_name == d.series_name } else { s.series_url == d.series_url };
        let i = match out.iter().position(same) {
            Some(i) => i,
            None => {
                out.push(LibrarySeries {
                    source: d.source.clone(),
                    series_url: d.series_url.clone(),
                    series_name: d.series_name.clone(),
                    meta: d.meta.clone(),
                    finished: d.finished,
                    ..Default::default()
                });
                out.len() - 1
            }
        };
        out[i].size += d.size;
        out[i].episodes.push(d);
    }
    for s in &mut out {
        s.episodes.sort_by_key(|d| d.episode_number);
    }
    out
}

/// Episode URL → file, for one series of one source: those play offline.
pub fn local_episodes(source: &str, series_url: &str) -> Result<HashMap<String, String>> {
    let rows = downloads_on(&database().lock().unwrap(), "WHERE source = ?1 AND series_url = ?2", &[source, series_url])?;
    Ok(rows.into_iter().map(|d| (d.episode_url, d.path)).collect())
}

/// Only recorded downloads may be deleted from disk.
pub fn download_recorded(path: &str) -> Result<bool> {
    Ok(database().lock().unwrap().query_row("SELECT EXISTS(SELECT 1 FROM downloads WHERE path = ?1)", [path], |r| r.get(0))?)
}

/// Forgets a download after its file was deleted.
pub fn remove_download(path: &str) -> Result<bool> {
    Ok(database().lock().unwrap().execute("DELETE FROM downloads WHERE path = ?1", [path])? > 0)
}

pub fn local_links() -> Result<HashMap<String, Meta>> {
    let c = database().lock().unwrap();
    let mut st = c.prepare("SELECT path, meta FROM local_series")?;
    let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?.collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows.into_iter().map(|(path, meta)| (path, serde_json::from_str(&meta).unwrap_or_default())).collect())
}

pub fn set_local_link(path: &str, meta: &Meta) -> Result<()> {
    database().lock().unwrap().execute("INSERT OR REPLACE INTO local_series (path, meta) VALUES (?1, ?2)", params![path, serde_json::to_string(meta)?])?;
    Ok(())
}

pub fn setting(key: &str) -> Option<String> {
    database().lock().unwrap().query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0)).optional().ok().flatten()
}

pub fn set_setting(key: &str, value: &str) -> Result<()> {
    let c = database().lock().unwrap();
    set_setting_on(&c, key, value)?;
    if crate::sync::synced(key) {
        queue_change(&c, "setting", key)?;
    }
    Ok(())
}

pub fn settings_with_prefix(prefix: &str) -> Result<Vec<(String, String)>> {
    let c = database().lock().unwrap();
    let mut st = c.prepare("SELECT key, value FROM settings WHERE substr(key, 1, length(?1)) = ?1")?;
    let rows = st.query_map([prefix], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Local only: nothing is queued for sync.
pub fn delete_settings_with_prefix(prefix: &str) -> Result<()> {
    database().lock().unwrap().execute("DELETE FROM settings WHERE substr(key, 1, length(?1)) = ?1", [prefix])?;
    Ok(())
}

fn set_setting_on(c: &Connection, key: &str, value: &str) -> Result<()> {
    c.execute("INSERT INTO settings(key, value) VALUES(?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])?;
    Ok(())
}

fn setting_on(c: &Connection, key: &str) -> Result<Option<String>> {
    Ok(c.query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0)).optional()?)
}

/// A record on the sync server: a history row (`progress`), a `watchlist` entry or a setting.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Change {
    pub kind: String,
    pub key: String,
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
    #[serde(default)]
    pub data: Value,
}

/// Unsent changes, oldest first, and the id to pass to `sync_ack`.
pub fn sync_pending(limit: usize) -> Result<(Vec<Change>, i64)> {
    sync_pending_on(&database().lock().unwrap(), limit)
}

fn sync_pending_on(c: &Connection, limit: usize) -> Result<(Vec<Change>, i64)> {
    let queued: Vec<(i64, String, String, i64)> = c
        .prepare("SELECT id, kind, key, at FROM sync_dirty ORDER BY id LIMIT ?1")?
        .query_map([limit as i64], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
        .collect::<rusqlite::Result<_>>()?;
    let last = queued.last().map_or(0, |q| q.0);
    let mut out = Vec::with_capacity(queued.len());
    for (_, kind, key, at) in queued {
        // Gone locally → sent as a deletion.
        let (updated_at, data) = match kind.as_str() {
            "progress" => match get_on(c, &key)? {
                Some(p) => (p.last_updated, Some(serde_json::to_value(&p)?)),
                None => (at, None),
            },
            "watchlist" => match watch_get_on(c, &key)? {
                Some(w) => (w.updated, Some(serde_json::to_value(&w)?)),
                None => (at, None),
            },
            _ => (at, setting_on(c, &key)?.map(Value::String)),
        };
        out.push(Change { kind, key, updated_at, deleted: data.is_none(), data: data.unwrap_or_default() });
    }
    Ok((out, last))
}

/// Whether a change still waits to be sent.
pub fn sync_queued(kind: &str, key: &str) -> bool {
    let c = database().lock().unwrap();
    c.query_row("SELECT 1 FROM sync_dirty WHERE kind = ?1 AND key = ?2", [kind, key], |_| Ok(())).optional().ok().flatten().is_some()
}

pub fn sync_ack(last: i64) -> Result<()> {
    sync_ack_on(&database().lock().unwrap(), last)
}

fn sync_ack_on(c: &Connection, last: i64) -> Result<()> {
    c.execute("DELETE FROM sync_dirty WHERE id <= ?1", [last])?;
    Ok(())
}

#[derive(Debug, Default, PartialEq)]
pub struct Applied {
    /// History or the watchlist.
    pub history: bool,
    pub settings: Vec<String>,
}

/// Applies records newer than the local row or its unsent change. Only synced
/// settings are accepted, so a server can't change device settings.
pub fn sync_apply(changes: &[Change]) -> Result<Applied> {
    sync_apply_on(&database().lock().unwrap(), changes)
}

fn sync_apply_on(c: &Connection, changes: &[Change]) -> Result<Applied> {
    let tx = c.unchecked_transaction()?;
    let mut applied = Applied::default();
    for ch in changes {
        let queued: Option<i64> =
            tx.query_row("SELECT at FROM sync_dirty WHERE kind = ?1 AND key = ?2", [&ch.kind, &ch.key], |r| r.get(0)).optional()?;
        let local = match ch.kind.as_str() {
            "progress" => get_on(&tx, &ch.key)?.map(|p| p.last_updated).max(queued),
            "watchlist" => watch_get_on(&tx, &ch.key)?.map(|w| w.updated).max(queued),
            "setting" if crate::sync::synced(&ch.key) => queued,
            _ => continue,
        };
        if local.is_some_and(|at| at >= ch.updated_at) {
            continue;
        }
        match (ch.kind.as_str(), ch.deleted) {
            ("progress", true) => applied.history |= tx.execute("DELETE FROM media_progress WHERE episode_key = ?1", [&ch.key])? > 0,
            ("progress", false) => match serde_json::from_value::<Progress>(ch.data.clone()) {
                Ok(p) => {
                    upsert_on(&tx, &Progress { episode_key: ch.key.clone(), last_updated: ch.updated_at, ..p })?;
                    applied.history = true;
                }
                Err(e) => tracing::warn!("sync: skipped unreadable history row {} ({e})", ch.key),
            },
            ("watchlist", true) => applied.history |= tx.execute("DELETE FROM watchlist WHERE series_key = ?1", [&ch.key])? > 0,
            ("watchlist", false) => match serde_json::from_value::<WatchEntry>(ch.data.clone()) {
                Ok(w) => {
                    set_watch_on(&tx, &WatchEntry { series_key: ch.key.clone(), updated: ch.updated_at, ..w })?;
                    applied.history = true;
                }
                Err(e) => tracing::warn!("sync: skipped unreadable watchlist entry {} ({e})", ch.key),
            },
            _ => {
                let value = ch.data.as_str().filter(|_| !ch.deleted);
                if setting_on(&tx, &ch.key)?.as_deref() != value {
                    match value {
                        Some(v) => set_setting_on(&tx, &ch.key, v)?,
                        None => _ = tx.execute("DELETE FROM settings WHERE key = ?1", [&ch.key])?,
                    }
                    applied.settings.push(ch.key.clone());
                }
            }
        }
        tx.execute("DELETE FROM sync_dirty WHERE kind = ?1 AND key = ?2", [&ch.kind, &ch.key])?;
    }
    tx.commit()?;
    Ok(applied)
}

/// At sign-in, history keeps its own times so the newest copy wins; settings
/// go in at time 0 so the account's win.
pub fn sync_seed() -> Result<()> {
    sync_seed_on(&database().lock().unwrap())
}

fn sync_seed_on(c: &Connection) -> Result<()> {
    let tx = c.unchecked_transaction()?;
    tx.execute("UPDATE sync_dirty SET at = 0 WHERE kind = 'setting'", [])?;
    tx.execute("INSERT OR IGNORE INTO sync_dirty (kind, key, at) SELECT 'progress', episode_key, last_updated FROM media_progress", [])?;
    tx.execute("INSERT OR IGNORE INTO sync_dirty (kind, key, at) SELECT 'watchlist', series_key, updated FROM watchlist", [])?;
    for key in crate::sync::SYNCED_SETTINGS {
        tx.execute("INSERT OR IGNORE INTO sync_dirty (kind, key, at) SELECT 'setting', key, 0 FROM settings WHERE key = ?1", [key])?;
    }
    tx.commit()?;
    Ok(())
}

/// Groups rows (newest first) into series and picks the episode to continue:
/// the latest started-but-unfinished one, else the first uncompleted, else next.
pub fn group_series(entries: &[Progress]) -> Vec<Series> {
    let mut groups: Vec<Series> = Vec::new();
    let mut index: HashMap<&str, usize> = HashMap::new();
    for e in entries {
        if e.series_key.is_empty() || e.series_url.is_empty() || e.series_title.is_empty() {
            continue;
        }
        let i = *index.entry(&e.series_key).or_insert_with(|| {
            groups.push(Series {
                key: e.series_key.clone(),
                url: e.series_url.clone(),
                title: e.series_title.clone(),
                source: e.source.clone(),
                anilist_id: e.anilist_id,
                mal_id: e.mal_id,
                cover: e.cover.clone(),
                last_updated: e.last_updated,
                ..Default::default()
            });
            groups.len() - 1
        });
        let g = &mut groups[i];
        g.total_episodes = g.total_episodes.max(e.total_episodes);
        if g.cover.is_empty() {
            g.cover = e.cover.clone();
        }
        g.episodes.push(e.clone());
    }
    for g in &mut groups {
        let mut latest_incomplete: Option<(i64, i64)> = None; // (last_updated, episode)
        let mut completed = HashMap::new();
        let mut max_ep = 0;
        for e in &g.episodes {
            max_ep = max_ep.max(e.episode_number);
            completed.insert(e.episode_number, e.completed);
            if !e.completed && e.playback_time > 0 && latest_incomplete.is_none_or(|(at, _)| e.last_updated > at) {
                latest_incomplete = Some((e.last_updated, e.episode_number));
            }
        }
        g.episodes.sort_by_key(|e| e.episode_number);
        g.finished = g.total_episodes > 0 && completed.values().filter(|&&c| c).count() as i64 >= g.total_episodes;
        g.continue_episode = match latest_incomplete {
            Some((_, ep)) => ep,
            None => (1..=g.total_episodes)
                .find(|ep| !completed.get(ep).copied().unwrap_or(false))
                .unwrap_or(if g.total_episodes == 0 { max_ep + 1 } else { max_ep }),
        };
    }
    groups
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unavailable_storage_is_an_error() {
        let dir = std::env::temp_dir().join(format!("aikatsu-storage-test-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("progress.db")).unwrap();
        assert!(open_database(&dir).unwrap_err().to_string().contains("Couldn't open"));
        std::fs::remove_dir_all(&dir).unwrap();
        std::fs::write(&dir, b"not a directory").unwrap();
        assert!(open_database(&dir).unwrap_err().to_string().contains("Couldn't create"));
        std::fs::remove_file(dir).unwrap();
    }

    #[test]
    fn migrates_built_in_source_keys() {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        c.execute_batch(
            "PRAGMA user_version = 0;
            INSERT INTO media_progress (episode_key, series_key, series_url, source, episode_number, playback_time, duration, last_updated)
                VALUES ('otakudesu:https://o/a/:ep1', 'otakudesu:https://o/a/', 'https://o/a/', 'otakudesu', 1, 0, 0, 1),
                       ('anilist:7:ep2', 'anilist:7', 'https://s/b/', 'samehadaku', 2, 0, 0, 1);
            INSERT INTO downloads (path, source, episode_number, finished) VALUES ('/v/a.mp4', 'ylnime', 1, 1);
            INSERT INTO settings (key, value) VALUES ('disabledSources', 'moenime, astronime'), ('syncCursor', '57');",
        )
        .unwrap();
        migrate(&c).unwrap();
        assert_eq!(setting_on(&c, "syncCursor").unwrap().as_deref(), Some("0"), "pulls everything again");
        set_setting_on(&c, "syncCursor", "9").unwrap();
        migrate(&c).unwrap(); // runs once
        assert_eq!(setting_on(&c, "syncCursor").unwrap().as_deref(), Some("9"));
        let rows: Vec<(String, String, String)> = c
            .prepare("SELECT episode_key, series_key, source FROM media_progress ORDER BY episode_key")
            .unwrap()
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
            .unwrap()
            .collect::<rusqlite::Result<_>>()
            .unwrap();
        assert_eq!(
            rows,
            [
                ("anilist:7:ep2".into(), "anilist:7".into(), "kyoko/samehadaku".into()),
                ("kyoko/otakudesu:https://o/a/:ep1".into(), "kyoko/otakudesu:https://o/a/".into(), "kyoko/otakudesu".into()),
            ]
        );
        assert_eq!(c.query_row("SELECT source FROM downloads", [], |r| r.get::<_, String>(0)).unwrap(), "kyoko/ylnime");
        assert_eq!(
            c.query_row("SELECT value FROM settings WHERE key = 'disabledSources'", [], |r| r.get::<_, String>(0)).unwrap(),
            "kyoko/moenime,kyoko/astronime"
        );
    }

    #[tokio::test]
    async fn cache_fresh_refresh_and_stale() {
        let db = Mutex::new(Connection::open_in_memory().unwrap());
        init(&db.lock().unwrap()).unwrap();
        let ttl = Duration::from_secs(60);
        let offline = || async { Err::<i32, _>(anyhow::anyhow!("offline")) };
        assert_eq!(cached_on(&db, "k", ttl, false, async { Ok(1) }).await.unwrap(), 1);
        assert_eq!(cached_on(&db, "k", ttl, false, async { Ok(2) }).await.unwrap(), 1, "fresh entry is reused");
        assert_eq!(cached_on(&db, "k", ttl, true, async { Ok(3) }).await.unwrap(), 3, "refresh refetches");
        db.lock().unwrap().execute("UPDATE cache SET expires = 0", []).unwrap();
        assert_eq!(cached_on(&db, "k", ttl, false, offline()).await.unwrap(), 3, "expired copy beats an error");
        assert!(cached_on(&db, "missing", ttl, false, offline()).await.is_err());
    }

    fn ep(n: i64, pos: i64, done: bool, at: i64) -> Progress {
        let key = series_key(0, "Otakudesu", "https://o/anime/x/");
        Progress {
            episode_key: episode_key(&key, n),
            series_key: key,
            series_url: "https://o/anime/x/".into(),
            series_title: "X".into(),
            source: "otakudesu".into(),
            episode_number: n,
            playback_time: pos,
            duration: 1400,
            completed: done,
            last_updated: at,
            ..Default::default()
        }
    }

    #[test]
    fn continue_episode_rules() {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        for p in [ep(1, 1400, true, 10), ep(2, 300, false, 20), ep(3, 100, false, 15)] {
            upsert_on(&c, &p).unwrap();
        }
        let rows = all_on(&c).unwrap();
        assert_eq!(rows[0].episode_number, 2, "newest first");
        let g = group_series(&rows);
        assert_eq!((g.len(), g[0].continue_episode, g[0].finished), (1, 2, false));

        // nothing in progress, unknown total → next after the highest
        let g = group_series(&[ep(1, 1400, true, 10), ep(2, 1400, true, 20)]);
        assert_eq!(g[0].continue_episode, 3);
        // known total → first uncompleted; all done → finished
        let mut rows = vec![ep(1, 1400, true, 10), ep(3, 1400, true, 20)];
        rows.iter_mut().for_each(|r| r.total_episodes = 3);
        assert_eq!(group_series(&rows)[0].continue_episode, 2);
        rows.push(Progress { total_episodes: 3, ..ep(2, 1400, true, 30) });
        assert!(group_series(&rows)[0].finished);
    }

    #[test]
    fn sync_queues_acks_and_applies_newest() {
        use serde_json::json;
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        let (a, b) = (ep(1, 300, false, 100), ep(2, 600, false, 100));
        for p in [&a, &b] {
            upsert_on(&c, p).unwrap();
            queue_change(&c, "progress", &p.episode_key).unwrap();
        }
        set_setting_on(&c, "quality", "720p").unwrap();
        queue_change(&c, "setting", "quality").unwrap();
        let (pending, last) = sync_pending_on(&c, 10).unwrap();
        let summary: Vec<_> = pending.iter().map(|p| (p.kind.as_str(), p.key.as_str(), p.deleted)).collect();
        assert_eq!(summary, [("progress", a.episode_key.as_str(), false), ("progress", b.episode_key.as_str(), false), ("setting", "quality", false)]);
        assert_eq!((pending[0].updated_at, &pending[2].data), (100, &json!("720p")));
        assert_eq!(serde_json::from_value::<Progress>(pending[1].data.clone()).unwrap().playback_time, 600);

        // Changed while the request was out: survives the ack.
        upsert_on(&c, &Progress { playback_time: 400, last_updated: 150, ..a.clone() }).unwrap();
        queue_change(&c, "progress", &a.episode_key).unwrap();
        sync_ack_on(&c, last).unwrap();
        let (pending, _) = sync_pending_on(&c, 10).unwrap();
        assert_eq!(pending.iter().map(|p| (p.key.as_str(), p.updated_at)).collect::<Vec<_>>(), [(a.episode_key.as_str(), 150)]);

        let remote = |kind: &str, key: &str, updated_at: i64, data: Value| Change { kind: kind.into(), key: key.into(), updated_at, deleted: false, data };
        let applied = sync_apply_on(
            &c,
            &[
                remote("progress", &a.episode_key, 120, json!(Progress { playback_time: 50, ..a.clone() })), // older than the local 150
                remote("progress", &b.episode_key, 200, json!(Progress { playback_time: 900, ..b.clone() })),
                remote("setting", "quality", 1, json!("1080p")), // nothing queued: the account's value wins
                remote("setting", "downloadDir", 999, json!("/elsewhere")), // not synced
                remote("someday", "x", 999, json!(1)),
            ],
        )
        .unwrap();
        assert_eq!(applied, Applied { history: true, settings: vec!["quality".into()] });
        assert_eq!(get_on(&c, &a.episode_key).unwrap().unwrap().playback_time, 400);
        let got_b = get_on(&c, &b.episode_key).unwrap().unwrap();
        assert_eq!((got_b.playback_time, got_b.last_updated), (900, 200));
        assert_eq!(setting_on(&c, "quality").unwrap().as_deref(), Some("1080p"));
        assert_eq!(setting_on(&c, "downloadDir").unwrap(), None);
        assert_eq!(sync_apply_on(&c, &[remote("setting", "quality", 1, json!("1080p"))]).unwrap(), Applied::default(), "echo changes nothing");

        // A newer remote deletion removes the row and any queued change for it.
        let gone = Change { deleted: true, ..remote("progress", &a.episode_key, now() + 10, Value::Null) };
        assert!(sync_apply_on(&c, &[gone]).unwrap().history);
        assert!(get_on(&c, &a.episode_key).unwrap().is_none());
        assert!(sync_pending_on(&c, 10).unwrap().0.is_empty());

        // A local deletion is queued, and an older remote copy doesn't bring the row back.
        delete_progress_on(&c, "WHERE series_key = ?1", &[&b.series_key]).unwrap();
        let (pending, _) = sync_pending_on(&c, 10).unwrap();
        assert_eq!(pending.iter().map(|p| (p.key.as_str(), p.deleted)).collect::<Vec<_>>(), [(b.episode_key.as_str(), true)]);
        assert!(!sync_apply_on(&c, &[remote("progress", &b.episode_key, 300, json!(b))]).unwrap().history);
        assert!(get_on(&c, &b.episode_key).unwrap().is_none());

        // A row from a clock running ahead: saving or deleting it here still comes out newer.
        let ahead = now() + 100;
        sync_apply_on(&c, &[remote("progress", &a.episode_key, ahead, json!(a))]).unwrap();
        upsert_on(&c, &Progress { last_updated: 0, ..a.clone() }).unwrap();
        assert_eq!(get_on(&c, &a.episode_key).unwrap().unwrap().last_updated, ahead + 1);
        delete_progress_on(&c, "", &[]).unwrap();
        let (pending, _) = sync_pending_on(&c, 10).unwrap();
        assert_eq!(pending.iter().find(|p| p.key == a.episode_key).map(|p| (p.updated_at, p.deleted)), Some((ahead + 2, true)));
    }

    #[test]
    fn finished_episodes_move_the_watchlist() {
        assert_eq!(next_status("planning", 1, 0), "watching");
        assert_eq!(next_status("dropped", 3, 12), "watching");
        assert_eq!(next_status("watching", 12, 12), "completed");
        assert_eq!(next_status("completed", 1, 12), "completed", "a rewatch stays completed");

        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        let first = Progress { total_episodes: 2, ..ep(1, 1400, true, 10) };
        upsert_on(&c, &first).unwrap();
        assert_eq!(auto_watch_on(&c, &first, 0).unwrap().status, "watching", "added on the first episode");
        let last = Progress { total_episodes: 2, ..ep(2, 1400, true, 20) };
        upsert_on(&c, &last).unwrap();
        assert_eq!(auto_watch_on(&c, &last, 0).unwrap().status, "watching", "2 released isn't 2 in all");
        auto_watch_on(&c, &last, 2).unwrap();
        let e = watch_get_on(&c, &first.series_key).unwrap().unwrap();
        assert_eq!((e.status.as_str(), e.title.as_str(), e.total_episodes), ("completed", "X", 2));
    }

    #[test]
    fn watchlist_syncs_newest_and_deletions() {
        use serde_json::json;
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        let e = WatchEntry { series_key: "anilist:7".into(), status: "planning".into(), anilist_id: 7, updated: 100, ..Default::default() };
        set_watch_on(&c, &e).unwrap();
        queue_change(&c, "watchlist", &e.series_key).unwrap();
        let (pending, last) = sync_pending_on(&c, 10).unwrap();
        assert_eq!((pending[0].kind.as_str(), pending[0].updated_at, pending[0].deleted), ("watchlist", 100, false));
        assert_eq!(serde_json::from_value::<WatchEntry>(pending[0].data.clone()).unwrap(), e);
        sync_ack_on(&c, last).unwrap();

        let remote = |updated_at: i64, status: &str| Change {
            kind: "watchlist".into(),
            key: e.series_key.clone(),
            updated_at,
            deleted: false,
            data: json!(WatchEntry { status: status.into(), ..e.clone() }),
        };
        assert!(!sync_apply_on(&c, &[remote(90, "dropped")]).unwrap().history, "older than the local entry");
        assert!(sync_apply_on(&c, &[remote(200, "watching")]).unwrap().history);
        assert_eq!(watch_get_on(&c, &e.series_key).unwrap().unwrap().status, "watching");

        remove_watch_on(&c, &e).unwrap();
        let (pending, _) = sync_pending_on(&c, 10).unwrap();
        assert!(pending[0].deleted && pending[0].updated_at > 200);
        assert!(!sync_apply_on(&c, &[remote(150, "watching")]).unwrap().history, "an older copy doesn't bring it back");
        assert!(watch_get_on(&c, &e.series_key).unwrap().is_none());
    }

    #[test]
    fn sync_seed_offers_history_and_stored_settings() {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        upsert_on(&c, &ep(1, 300, false, 100)).unwrap();
        set_setting_on(&c, "quality", "720p").unwrap();
        queue_change(&c, "setting", "quality").unwrap(); // chosen while signed out
        set_setting_on(&c, "theme", "dark").unwrap(); // per device
        sync_seed_on(&c).unwrap();
        let (pending, _) = sync_pending_on(&c, 10).unwrap();
        let mut summary: Vec<_> = pending.iter().map(|p| (p.kind.as_str(), p.updated_at)).collect();
        summary.sort();
        assert_eq!(summary, [("progress", 100), ("setting", 0)], "settings at 0 never beat the account's");
    }

    #[test]
    fn library_groups_and_drops_missing_files() {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        let dir = std::env::temp_dir().join(format!("aikatsu-library-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let dl = |name: &str, url: &str, ep: i64, finished: i64| {
            let path = dir.join(format!("{name}-{ep}.mp4"));
            std::fs::write(&path, b"x").unwrap();
            Download {
                path: path.display().to_string(),
                source: "src".into(),
                series_url: url.into(),
                series_name: name.into(),
                episode_number: ep,
                episode_url: format!("{url}/ep{ep}"),
                size: 10,
                finished,
                ..Default::default()
            }
        };
        let rows = [dl("a", "https://s/a", 2, 30), dl("b", "https://s/b", 1, 20), dl("a", "https://s/a", 1, 10), dl("c", "", 1, 5)];
        for d in &rows {
            add_download_on(&c, d).unwrap();
        }
        let unplugged = Download { path: dir.join("unplugged-drive").join("d-1.mp4").display().to_string(), ..dl("d", "https://s/d", 1, 1) };
        add_download_on(&c, &unplugged).unwrap();
        std::fs::remove_file(&rows[1].path).unwrap(); // deleted outside the app
        let lib = group_library(downloads_on(&c, "", &[]).unwrap());
        let summary: Vec<(&str, Vec<i64>, i64)> =
            lib.iter().map(|s| (s.series_name.as_str(), s.episodes.iter().map(|e| e.episode_number).collect(), s.size)).collect();
        assert_eq!(summary, [("a", vec![1, 2], 20), ("c", vec![1], 10)], "newest series first, episodes in order");
        let left: Vec<String> = c.prepare("SELECT path FROM downloads").unwrap().query_map([], |r| r.get(0)).unwrap().collect::<rusqlite::Result<_>>().unwrap();
        assert_eq!(left.len(), 4, "the missing file's row is gone");
        assert!(left.contains(&unplugged.path), "a file whose folder is gone too (an unplugged drive) keeps its row");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
