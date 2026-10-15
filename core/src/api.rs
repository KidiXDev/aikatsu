//! Method table behind each app's `call` (async) and `get` (sync).
//! Arguments and results are JSON, so both UIs see plain objects.

use crate::push;
use crate::sources::{self, SourceId};
use crate::{anime4k, db, download, meta, proxy};
use anyhow::{Result, anyhow, bail};
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

fn source(args: &Value) -> Result<SourceId> {
    SourceId::from_key(s(args, "source")).ok_or_else(|| anyhow!("unknown source {:?}", args["source"]))
}

/// Defaults for every setting the UI exposes; stored values override them.
pub const SETTING_DEFAULTS: &[(&str, &str)] = &[
    ("autoplay", "true"),
    ("autoSkip", "false"),
    ("theme", "system"),
    ("quality", "best"),
    ("disabledSources", ""),
    ("downloadDir", ""),
    ("tmdbKey", ""),
    ("discord", "true"),
    ("debug", "false"),
    ("anime4k", "off"),
    ("volume", "100"),
];

pub fn setting(key: &str) -> String {
    db::setting(key).unwrap_or_else(|| SETTING_DEFAULTS.iter().find(|(k, _)| *k == key).map(|(_, v)| v.to_string()).unwrap_or_default())
}

pub fn enabled_sources() -> Vec<SourceId> {
    let disabled = setting("disabledSources").to_lowercase();
    SourceId::ALL.into_iter().filter(|s| !disabled.split(',').any(|d| d.trim() == s.key())).collect()
}

pub async fn call(method: &str, args: Value) -> Result<Value> {
    match method {
        "search" => {
            let query = s(&args, "query").to_owned();
            sources::search_all(&query, &enabled_sources(), |src, res| {
                push(
                    "searchResult",
                    &match res {
                        Ok(items) => json!({ "source": src.key(), "name": src.name(), "items": items }),
                        Err(e) => json!({ "source": src.key(), "name": src.name(), "error": format!("{e:#}") }),
                    },
                )
            })
            .await;
            Ok(json!({ "done": true }))
        }
        "enrich" => {
            let id = i(&args, "anilistId");
            let key = if id > 0 { format!("meta:anilist:{id}") } else { format!("meta:{}", meta::clean_title(s(&args, "name")).to_lowercase()) };
            let m = db::cached(&key, DAY * 3, refresh(&args), async {
                let mut m = if id > 0 { meta::by_anilist_id(id).await? } else { meta::enrich(s(&args, "name"), s(&args, "url")).await? };
                let tmdb = setting("tmdbKey");
                if m.season_map.is_empty() && m.episodes > 13 && m.mal_id > 0 && !tmdb.is_empty() {
                    m.season_map = meta::tmdb_season_map(m.mal_id, &tmdb).await;
                }
                Ok(m)
            })
            .await?;
            Ok(serde_json::to_value(m)?)
        }
        "episodes" => {
            if refresh(&args) {
                crate::http::clear_pages();
            }
            Ok(serde_json::to_value(sources::episodes(source(&args)?, s(&args, "url")).await?)?)
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
        "qualities" => Ok(serde_json::to_value(sources::qualities(source(&args)?, s(&args, "url")).await?)?),
        "resolve" => resolve(source(&args)?, s(&args, "url"), s(&args, "quality")).await,
        "shaders" => {
            let paths = anime4k::shaders(s(&args, "mode")).await?;
            Ok(json!({ "list": anime4k::path_list(&paths) }))
        }
        "installShaders" => {
            anime4k::install(args["gan"].as_bool().unwrap_or(false)).await?;
            Ok(json!({ "dir": anime4k::shader_dir() }))
        }
        "skipTimes" => {
            let (mal, ep) = (i(&args, "malId"), i(&args, "episode") as u32);
            let skip = db::cached(&format!("skip:{mal}:{ep}"), DAY * 7, false, meta::skip_times(mal, ep)).await?;
            Ok(serde_json::to_value(skip)?)
        }
        _ => bail!("unknown method {method}"),
    }
}

/// Source stream → something mpv can open. Blogger and Wibufile go through
/// the local proxy (Chrome TLS / HTTP/3); everything else plays directly.
async fn resolve(src: SourceId, episode_url: &str, quality: &str) -> Result<Value> {
    let stream = sources::stream(src, episode_url, quality).await?;
    let mut url = stream.url.clone();
    if crate::blogger::is_blogger(&url) {
        url = proxy::blogger(&url).await?;
    } else if sources::is_wibufile(&url) {
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
        "saveProgress" => {
            db::upsert(&serde_json::from_value(args)?)?;
            Ok(Value::Null)
        }
        "setCompleted" => {
            db::set_completed(&serde_json::from_value(args["progress"].clone())?, args["completed"].as_bool().unwrap_or(true))?;
            Ok(Value::Null)
        }
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
        "settings" => Ok(Value::Object(SETTING_DEFAULTS.iter().map(|(k, _)| (k.to_string(), Value::String(setting(k)))).collect())),
        "setSetting" => {
            db::set_setting(s(&args, "key"), s(&args, "value"))?;
            Ok(Value::Null)
        }
        "sources" => Ok(Value::Array(SourceId::ALL.iter().map(|s| json!({ "key": s.key(), "name": s.name() })).collect())),
        "stopStreams" => {
            proxy::clear();
            Ok(Value::Null)
        }
        "download" => {
            let ids = download::enqueue(serde_json::from_value(args)?, download::base_dir(&setting("downloadDir")))?;
            Ok(json!(ids))
        }
        "downloads" => Ok(serde_json::to_value(download::jobs())?),
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
        })),
        "presence" => {
            #[cfg(feature = "desktop")]
            crate::discord::update(serde_json::from_value(args)?);
            Ok(Value::Null)
        }
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
        "logTail" => Ok(Value::String(crate::log_tail(400))),
        "version" => Ok(json!(env!("CARGO_PKG_VERSION"))),
        _ => bail!("unknown method {method}"),
    }
}
