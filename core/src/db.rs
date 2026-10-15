//! Watch history, settings, downloaded episodes and the lookup cache, stored in SQLite.

use crate::meta::Meta;
use anyhow::Result;
use rusqlite::{Connection, OptionalExtension, params};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
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

/// `anilist:<id>` when known (shares progress across sources), else `<source>:<url>`.
pub fn series_key(anilist_id: i64, source: &str, series_url: &str) -> String {
    if anilist_id > 0 { format!("anilist:{anilist_id}") } else { format!("{}:{series_url}", source.to_lowercase()) }
}

pub fn episode_key(series_key: &str, ep: i64) -> String {
    format!("{series_key}:ep{ep}")
}

static DB: LazyLock<Mutex<Connection>> = LazyLock::new(|| {
    let dir = &crate::dirs().data;
    let _ = std::fs::create_dir_all(dir);
    let conn = Connection::open(dir.join("progress.db")).unwrap_or_else(|e| {
        tracing::error!("history database unavailable ({e}); using an in-memory one");
        Connection::open_in_memory().expect("sqlite")
    });
    init(&conn).expect("history schema");
    Mutex::new(conn)
});

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
        DELETE FROM cache WHERE expires < strftime('%s', 'now') - 30 * 86400;",
    )
}

/// Remote lookups (AniList, Jikan, AniSkip) kept across restarts. A fresh entry
/// is returned as is; otherwise `fetch` runs and is stored for `ttl` (`refresh`
/// skips the read). When `fetch` fails, an expired entry (kept up to 30 days)
/// beats an error on a flaky connection.
pub async fn cached<T: Serialize + DeserializeOwned>(key: &str, ttl: Duration, refresh: bool, fetch: impl Future<Output = Result<T>>) -> Result<T> {
    cached_on(&DB, key, ttl, refresh, fetch).await
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
    DB.lock().unwrap().execute("DELETE FROM cache", [])?;
    Ok(())
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn upsert(p: &Progress) -> Result<()> {
    upsert_on(&DB.lock().unwrap(), p)
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
            completed=excluded.completed, last_updated=excluded.last_updated",
        params![
            p.episode_key, p.anilist_id, p.mal_id, p.series_key, p.series_url, p.series_title, p.source, p.episode_url,
            p.total_episodes, p.episode_number, p.playback_time.max(0), p.duration.max(0), p.title, p.cover, p.completed, updated
        ],
    )?;
    Ok(())
}

/// Marks an episode (not) completed, creating the row if it was never played.
pub fn set_completed(p: &Progress, completed: bool) -> Result<()> {
    let c = DB.lock().unwrap();
    let existing = get_on(&c, &p.episode_key)?;
    let mut row = existing.unwrap_or_else(|| p.clone());
    row.completed = completed;
    row.last_updated = 0;
    upsert_on(&c, &row)
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
    all_on(&DB.lock().unwrap())
}

fn all_on(c: &Connection) -> Result<Vec<Progress>> {
    let mut st = c.prepare(&format!("SELECT {COLUMNS} FROM media_progress ORDER BY last_updated DESC"))?;
    Ok(st.query_map([], row)?.collect::<rusqlite::Result<_>>()?)
}

/// Every saved episode of one series, matched by key or by its source URL
/// (covers rows saved before the AniList id was known).
pub fn series_episodes(series_key: &str, series_url: &str) -> Result<Vec<Progress>> {
    let c = DB.lock().unwrap();
    let mut st = c.prepare(&format!(
        "SELECT {COLUMNS} FROM media_progress WHERE series_key = ?1 OR series_url = ?2 ORDER BY episode_number"
    ))?;
    Ok(st.query_map([series_key, series_url], row)?.collect::<rusqlite::Result<_>>()?)
}

pub fn delete_series(series_key: &str) -> Result<()> {
    DB.lock().unwrap().execute("DELETE FROM media_progress WHERE series_key = ?1", [series_key])?;
    Ok(())
}

pub fn clear_history() -> Result<()> {
    DB.lock().unwrap().execute("DELETE FROM media_progress", [])?;
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
    add_download_on(&DB.lock().unwrap(), d)
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
    for d in missing {
        c.execute("DELETE FROM downloads WHERE path = ?1", [&d.path])?;
    }
    Ok(present)
}

pub fn library() -> Result<Vec<LibrarySeries>> {
    Ok(group_library(downloads_on(&DB.lock().unwrap(), "", &[])?))
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
    let rows = downloads_on(&DB.lock().unwrap(), "WHERE source = ?1 AND series_url = ?2", &[source, series_url])?;
    Ok(rows.into_iter().map(|d| (d.episode_url, d.path)).collect())
}

/// Forgets a recorded download; false when `path` was never one (so callers
/// never delete files the app didn't download).
pub fn remove_download(path: &str) -> Result<bool> {
    Ok(DB.lock().unwrap().execute("DELETE FROM downloads WHERE path = ?1", [path])? > 0)
}

pub fn setting(key: &str) -> Option<String> {
    DB.lock().unwrap().query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0)).optional().ok().flatten()
}

pub fn set_setting(key: &str, value: &str) -> Result<()> {
    DB.lock().unwrap().execute(
        "INSERT INTO settings(key, value) VALUES(?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [key, value],
    )?;
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
        std::fs::remove_file(&rows[1].path).unwrap(); // deleted outside the app
        let lib = group_library(downloads_on(&c, "", &[]).unwrap());
        let summary: Vec<(&str, Vec<i64>, i64)> =
            lib.iter().map(|s| (s.series_name.as_str(), s.episodes.iter().map(|e| e.episode_number).collect(), s.size)).collect();
        assert_eq!(summary, [("a", vec![1, 2], 20), ("c", vec![1], 10)], "newest series first, episodes in order");
        let left: i64 = c.query_row("SELECT COUNT(*) FROM downloads", [], |r| r.get(0)).unwrap();
        assert_eq!(left, 3, "the missing file's row is gone");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
