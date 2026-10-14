//! Watch history, settings and the lookup cache, stored in SQLite.

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
    let dir = dirs::data_dir().unwrap_or_else(std::env::temp_dir).join("aikatsu");
    let _ = std::fs::create_dir_all(&dir);
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
}
