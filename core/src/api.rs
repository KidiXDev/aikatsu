//! Method table behind each app's `call` (async) and `get` (sync).
//! Arguments and results are JSON, so both UIs see plain objects.

use crate::plugins::{self, Plugin};
use crate::push;
use crate::sources;
use crate::{anime4k, db, download, local, meta, proxy, sync, tracker, update};
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

fn s<'a>(args: &'a Value, key: &str) -> &'a str {
    args[key].as_str().unwrap_or_default()
}

fn i(args: &Value, key: &str) -> i64 {
    args[key].as_i64().unwrap_or(0)
}

/// The page's refresh button: bypass caches.
fn refresh(args: &Value) -> bool {
    args["refresh"].as_bool().unwrap_or(false)
}

const DAY: std::time::Duration = std::time::Duration::from_secs(86400);


/// Defaults for every setting the UI exposes; stored values override them.
pub const SETTING_DEFAULTS: &[(&str, &str)] = &[
    ("autoplay", "true"),
    ("autoSkip", "false"),
    ("theme", "system"),
    ("quality", "best"),
    ("disabledSources", ""),
    ("autoCheckPluginUpdates", "true"),
    ("autoCheckAppUpdates", "true"),
    ("downloadDir", ""),
    ("tmdbKey", ""),
    ("discord", "true"),
    ("developerMode", "false"),
    ("debug", "false"),
    ("anime4k", "off"),
    ("volume", "100"),
    ("airingAlerts", "true"),
    ("closeAction", "quit"),
    (crate::lan::SETTING, "false"),
];

pub fn setting(key: &str) -> String {
    db::setting(key).unwrap_or_else(|| SETTING_DEFAULTS.iter().find(|(k, _)| *k == key).map(|(_, v)| v.to_string()).unwrap_or_default())
}

pub fn enabled_sources() -> Vec<std::sync::Arc<Plugin>> {
    let disabled = setting("disabledSources");
    plugins::installed().into_iter().filter(|p| !disabled.split(',').any(|d| d.trim() == p.id)).collect()
}

pub async fn call(method: &str, args: Value) -> Result<Value> {
    match method {
        "exportLog" => {
            let path = s(&args, "path");
            anyhow::ensure!(!path.is_empty(), "choose a file for the exported log");
            tokio::fs::write(path, crate::log_report()?).await.with_context(|| format!("couldn't export log to {path}"))?;
            Ok(Value::Null)
        }
        "search" => {
            let query = s(&args, "query").to_owned();
            sources::search_all(&query, &enabled_sources(), |p, res| {
                push(
                    "searchResult",
                    &match res {
                        Ok(items) => json!({ "requestId": args["requestId"], "source": p.id, "name": p.label, "items": items }),
                        Err(e) => json!({ "requestId": args["requestId"], "source": p.id, "name": p.label, "error": format!("{e:#}") }),
                    },
                )
            })
            .await;
            Ok(json!({ "done": true }))
        }
        // Third-party repos: shown with a trust warning before `addRepo`.
        "previewRepo" => plugins::preview(s(&args, "url")).await,
        "checkPluginUpdates" => Ok(plugins::check_updates().await),
        "checkAppUpdate" => update::check().await,
        // Progress arrives as `appUpdate` pushes.
        "installAppUpdate" => update::install().await,
        "addRepo" => {
            plugins::add(s(&args, "url")).await?;
            Ok(plugins::repos())
        }
        "removeRepo" => {
            plugins::remove(s(&args, "url")).await?;
            Ok(plugins::repos())
        }
        "syncPlugins" => {
            let updated = plugins::sync_all().await;
            Ok(json!({ "repos": plugins::repos(), "updated": updated }))
        }
        "enrich" => {
            let url = s(&args, "url");
            let id = db::setting(&format!("{LINK}{url}")).and_then(|v| v.parse().ok()).unwrap_or(i(&args, "anilistId"));
            Ok(serde_json::to_value(enrich(id, s(&args, "name"), url, refresh(&args)).await?)?)
        }
        "episodes" => {
            if refresh(&args) {
                crate::http::clear_pages();
            }
            Ok(serde_json::to_value(sources::episodes(s(&args, "source"), s(&args, "url")).await?)?)
        }
        "episodeInfo" => {
            let (mal, al) = (i(&args, "malId"), i(&args, "anilistId"));
            // Up to 30 Jikan pages, so it's worth keeping; a day lets airing shows catch up.
            let list = db::cached(&format!("epinfo:{mal}:{al}"), DAY, refresh(&args), async {
                let list = meta::episode_info(mal, al).await;
                anyhow::ensure!(!list.is_empty(), "no episode info");
                Ok(list)
            })
            .await
            .unwrap_or_default();
            Ok(serde_json::to_value(list)?)
        }
        "qualities" => Ok(serde_json::to_value(sources::qualities(s(&args, "source"), s(&args, "url")).await?)?),
        "resolve" => resolve(s(&args, "source"), s(&args, "url"), s(&args, "quality")).await,
        "shaders" => {
            let paths = anime4k::shaders(s(&args, "mode")).await?;
            Ok(json!({ "list": anime4k::path_list(&paths) }))
        }
        "installShaders" => {
            anime4k::install(args["gan"].as_bool().unwrap_or(false)).await?;
            Ok(json!({ "dir": anime4k::shader_dir() }))
        }
        "discover" => {
            // Short-lived: the schedule moves. Stale copies still show when AniList is down.
            let d = db::cached("discover", std::time::Duration::from_secs(30 * 60), refresh(&args), meta::discover()).await?;
            Ok(serde_json::to_value(d)?)
        }
        // syncNow never fails; errors are in its status.
        "syncSetServer" => sync::set_server(s(&args, "server")),
        "syncSignIn" => sync::sign_in(s(&args, "username"), s(&args, "password"), args["create"].as_bool().unwrap_or(false)).await,
        "syncSignOut" => Ok(sync::sign_out().await),
        "trackerLogin" => tracker::login(s(&args, "service")).await,
        // Watching and planned shows' next two weeks, for Android's notifications.
        "upcomingEpisodes" => {
            let shows: Vec<db::WatchEntry> =
                db::watchlist()?.into_iter().filter(|w| w.anilist_id > 0 && matches!(w.status.as_str(), "watching" | "planning")).collect();
            let mut ids: Vec<i64> = shows.iter().map(|w| w.anilist_id).collect();
            ids.sort();
            ids.dedup();
            if ids.is_empty() {
                return Ok(json!([]));
            }
            let key = format!("airing:{}", ids.iter().map(i64::to_string).collect::<Vec<_>>().join(","));
            let airing = db::cached(&key, std::time::Duration::from_secs(6 * 3600), false, meta::upcoming(&ids)).await?;
            let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs() as i64;
            let episodes = airing.iter().filter(|a| a.airing_at > now).filter_map(|a| {
                let w = shows.iter().find(|w| w.anilist_id == a.anilist_id)?;
                Some(json!({ "key": w.series_key, "title": w.title, "episode": a.episode, "airing_at": a.airing_at }))
            });
            Ok(json!(episodes.collect::<Vec<_>>()))
        }
        "syncNow" => Ok(sync::sync().await),
        "syncChangePassword" => {
            sync::change_password(s(&args, "current"), s(&args, "password")).await?;
            Ok(Value::Null)
        }
        "syncDeleteAccount" => sync::delete_account(s(&args, "password")).await,
        "skipTimes" => {
            let (mal, ep) = (i(&args, "malId"), i(&args, "episode") as u32);
            let skip = db::cached(&format!("skip:{mal}:{ep}"), DAY * 7, false, meta::skip_times(mal, ep)).await?;
            Ok(serde_json::to_value(skip)?)
        }
        "localLibrary" => {
            let mut lib = serde_json::to_value(tokio::task::spawn_blocking(local::library).await?)?;
            if args["lan"].as_bool() != Some(false) {
                let (shared, unreachable) = crate::lan::library().await;
                if let Some(series) = lib["series"].as_array_mut() {
                    series.extend(shared);
                }
                lib["unreachable"] = json!(unreachable);
            }
            Ok(lib)
        }
        "matchLocal" => Ok(json!(local::match_all().await?)),
        "linkAnime" => Ok(serde_json::to_value(link(s(&args, "source"), s(&args, "url"), i(&args, "anilistId")).await?)?),
        "searchAnime" => Ok(serde_json::to_value(meta::search(s(&args, "query")).await?)?),
        _ => bail!("unknown method {method}"),
    }
}

/// Settings key prefix + a streaming series' URL → the AniList id the user chose for it.
pub const LINK: &str = "anilistLink:";

/// Local folders keep their own link, with details for the offline library.
async fn link(source: &str, url: &str, id: i64) -> Result<meta::Meta> {
    let m = if source == local::SOURCE {
        local::link(url, id).await?
    } else {
        let m = enrich(id, "", "", false).await?;
        anyhow::ensure!(m.anilist_id > 0, "No AniList entry {id}");
        db::set_setting(&format!("{LINK}{url}"), &id.to_string())?;
        m
    };
    db::relink(source, url, &m)?;
    Ok(m)
}

pub(crate) async fn enrich(id: i64, name: &str, url: &str, refresh: bool) -> Result<meta::Meta> {
    let key = if id > 0 { format!("meta:v2:anilist:{id}") } else { format!("meta:v2:{}", meta::clean_title(name).to_lowercase()) };
    db::cached(&key, DAY * 3, refresh, async {
        let mut m = if id > 0 { meta::by_anilist_id(id).await? } else { meta::enrich(name, url).await? };
        let tmdb = setting("tmdbKey");
        if m.season_map.is_empty() && m.episodes > 13 && m.mal_id > 0 && !tmdb.is_empty() {
            m.season_map = meta::tmdb_season_map(m.mal_id, &tmdb).await;
        }
        Ok(m)
    })
    .await
}

/// Source stream → something mpv can open. Blogger and Wibufile go through
/// the local proxy (Chrome TLS / HTTP/3); everything else plays directly.
async fn resolve(src: &str, episode_url: &str, quality: &str) -> Result<Value> {
    let stream = sources::stream(src, episode_url, quality).await?;
    let mut url = stream.url.clone();
    if crate::blogger::is_blogger(&url) {
        url = proxy::blogger(&url).await?;
    } else if proxy::is_wibufile(&url) {
        match proxy::wibufile(&url, &stream.referer).await {
            Ok(p) => url = p,
            Err(e) => tracing::warn!("wibufile HTTP/3 proxy unavailable ({e}); playing directly"),
        }
    }
    let hls = stream.url.to_lowercase().contains(".m3u8");
    Ok(json!({ "url": url, "original": stream.url, "referer": stream.referer, "hls": hls }))
}

pub fn get(method: &str, args: Value) -> Result<Value> {
    match method {
        "history" => Ok(serde_json::to_value(db::group_series(&db::all()?))?),
        "seriesProgress" => Ok(serde_json::to_value(db::series_episodes(s(&args, "key"), s(&args, "url"))?)?),
        // `meta_episodes`: AniList's episode count, 0 when unknown.
        "saveProgress" => {
            let total = i(&args, "meta_episodes");
            let p = serde_json::from_value(args)?;
            if db::upsert(&p)? {
                tracker::watched(&p, total)?;
            }
            Ok(Value::Null)
        }
        // `progress`: a list of rows, all from one series.
        "setCompleted" => {
            let list: Vec<db::Progress> = serde_json::from_value(args["progress"].clone())?;
            if db::set_completed(&list, args["completed"].as_bool().unwrap_or(true))?
                && let Some(last) = list.last()
            {
                tracker::watched(last, i(&args["progress"][0], "meta_episodes"))?;
            }
            Ok(Value::Null)
        }
        "watchlist" => Ok(serde_json::to_value(db::watchlist()?)?),
        "watchEntry" => Ok(serde_json::to_value(db::watch_entry(&serde_json::from_value(args)?)?)?),
        // An empty status takes the show off the list, here only: trackers keep it.
        "setWatchStatus" => {
            let e: db::WatchEntry = serde_json::from_value(args["entry"].clone())?;
            match s(&args, "status") {
                "" => db::remove_watch(&e)?,
                status => {
                    anyhow::ensure!(tracker::is_status(status), "unknown status {status}");
                    tracker::set_status(db::set_watch(&db::WatchEntry { status: status.into(), ..e })?);
                }
            }
            Ok(Value::Null)
        }
        "trackers" => Ok(tracker::status()),
        "trackerLogout" => tracker::logout(s(&args, "service")),
        "deleteSeries" => {
            db::delete_series(s(&args, "key"))?;
            Ok(Value::Null)
        }
        "clearHistory" => {
            db::clear_history()?;
            Ok(Value::Null)
        }
        "keys" => {
            let series = db::series_key(i(&args, "anilistId"), s(&args, "source"), s(&args, "url"));
            Ok(json!({ "series": series, "episode": db::episode_key(&series, i(&args, "episode")) }))
        }
        "syncStatus" => Ok(sync::status()),
        "lanStatus" => Ok(crate::lan::state()),
        "settings" => Ok(Value::Object(SETTING_DEFAULTS.iter().map(|(k, _)| (k.to_string(), Value::String(setting(k)))).collect())),
        "setSetting" => {
            db::set_setting(s(&args, "key"), s(&args, "value"))?;
            if s(&args, "key") == crate::lan::SETTING {
                crate::RT.spawn(async {
                    crate::lan::refresh().await;
                    sync::sync().await;
                });
            }
            Ok(Value::Null)
        }
        "sources" => Ok(plugins::list()),
        "repos" => Ok(plugins::repos()),
        "officialRepo" => Ok(json!(plugins::OFFICIAL_REPO)),
        "stopStreams" => {
            proxy::clear();
            Ok(Value::Null)
        }
        "download" => {
            let ids = download::enqueue(serde_json::from_value(args)?, download::base_dir(&setting("downloadDir")))?;
            Ok(json!(ids))
        }
        "downloads" => Ok(serde_json::to_value(download::jobs())?),
        // Finished downloads still on disk, grouped by series.
        "library" => Ok(serde_json::to_value(db::library()?)?),
        // Episode URL → file for one series, so those episodes play offline.
        "localEpisodes" => Ok(serde_json::to_value(db::local_episodes(s(&args, "source"), s(&args, "url"))?)?),
        "addLocalFolder" => {
            local::add_root(s(&args, "path"))?;
            Ok(Value::Null)
        }
        "removeLocalFolder" => {
            local::remove_root(s(&args, "path"))?;
            Ok(Value::Null)
        }
        "deleteDownloads" => {
            download::delete(&serde_json::from_value::<Vec<String>>(args["paths"].clone())?)?;
            Ok(Value::Null)
        }
        "cancelDownload" => {
            download::cancel(i(&args, "id") as u64);
            Ok(Value::Null)
        }
        "clearDownloads" => {
            download::clear_finished();
            Ok(Value::Null)
        }
        "downloadDir" => Ok(json!(download::base_dir(&setting("downloadDir")))),
        "tools" => Ok(json!({
            "ffmpeg": download::which("ffmpeg").is_some(),
            "ytdlp": download::which("yt-dlp").is_some(),
            "ytdlpFetched": download::ytdlp_local().is_file(),
        })),
        "presence" => {
            #[cfg(feature = "desktop")]
            crate::discord::update(serde_json::from_value(args)?);
            Ok(Value::Null)
        }
        "cacheSize" => Ok(json!(db::cache_size()?)),
        "clearCache" => {
            db::clear_cache()?;
            crate::http::clear_pages();
            Ok(Value::Null)
        }
        "anime4kModes" => Ok(serde_json::to_value(anime4k::MODES)?),
        "anime4kInstalled" => Ok(json!(anime4k::installed())),
        // The label `resolve` should ask for: `want` if offered, else the nearest higher, else lower.
        "pickQuality" => {
            let mut list: Vec<String> = serde_json::from_value(args["list"].clone())?;
            sources::sort_by_height(&mut list, sources::height_of(s(&args, "want")), |q| sources::height_of(q));
            Ok(json!(list.first()))
        }
        // File URLs/paths built in Rust so Windows drive letters come out right.
        "fileUrl" => {
            let path = std::path::PathBuf::from(s(&args, "path"));
            let target = if args["parent"].as_bool().unwrap_or(false) { path.parent().map(|p| p.to_path_buf()).unwrap_or(path) } else { path };
            Ok(json!(url::Url::from_file_path(&target).map(String::from).unwrap_or_default()))
        }
        "localPath" => Ok(json!(url::Url::parse(s(&args, "url")).ok().and_then(|u| u.to_file_path().ok()).map(|p| p.display().to_string()).unwrap_or_default())),
        "logTail" => Ok(Value::String(crate::log_tail(400)?)),
        "logReport" => Ok(Value::String(crate::log_report()?)),
        "version" => Ok(json!(env!("CARGO_PKG_VERSION"))),
        _ => bail!("unknown method {method}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn export_log_report_and_write_errors() {
        let dir = std::env::temp_dir().join(format!("aikatsu-export-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("aikatsu-log.txt");
        let report = get("logReport", Value::Null).unwrap();
        call("exportLog", json!({"path": path})).await.unwrap();
        let contents = std::fs::read_to_string(&path).unwrap();
        assert_eq!(contents, report.as_str().unwrap());
        assert!(contents.starts_with(&format!("Aikatsu {}\nPlatform: ", env!("CARGO_PKG_VERSION"))));
        assert!(call("exportLog", json!({"path": ""})).await.is_err());
        assert!(call("exportLog", json!({"path": dir})).await.unwrap_err().to_string().contains("couldn't export log"));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
