//! The whole Dart-facing surface, mirroring desktop/src/bridge.rs: `call`
//! runs an async core method, `get` a quick local one, and `init` returns the
//! event stream (search results per source, download progress, …).

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use std::path::PathBuf;
use std::sync::{Mutex, Once, OnceLock};

pub struct Event {
    pub kind: String,
    pub json: String,
}

static EVENTS: Mutex<Option<StreamSink<Event>>> = Mutex::new(None);
static INIT: Once = Once::new();
static LOG: OnceLock<Result<aikatsu_core::WorkerGuard, String>> = OnceLock::new();

/// `data_dir`: app-private storage (history, logs, Anime4K shaders);
/// `videos_dir`: the default download folder. A Flutter hot restart calls
/// this again with a fresh stream; the core itself starts once.
pub fn init(data_dir: String, videos_dir: String, events: StreamSink<Event>) {
    *EVENTS.lock().unwrap() = Some(events);
    INIT.call_once(|| {
        let data = PathBuf::from(data_dir);
        let dirs = aikatsu_core::Dirs { config: data.clone(), data, videos: PathBuf::from(videos_dir) };
        let guard = aikatsu_core::init(dirs, false, |kind, value| {
            if let Some(sink) = EVENTS.lock().unwrap().as_ref() {
                let _ = sink.add(Event { kind: kind.to_owned(), json: value.to_string() });
            }
        }).map_err(|e| format!("{e:#}"));
        let _ = LOG.set(guard);
    });
    let (kind, json) = match LOG.get().expect("initialization finished") {
        Ok(_) => ("ready", "null".to_owned()),
        Err(e) => ("startupError", serde_json::to_string(e).unwrap()),
    };
    if let Some(sink) = EVENTS.lock().unwrap().as_ref() {
        let _ = sink.add(Event { kind: kind.into(), json });
    }
}

fn parse(args: &str) -> serde_json::Value {
    serde_json::from_str(args).unwrap_or(serde_json::Value::Null)
}

/// One line with the cause chain, as the desktop app shows it.
fn message(method: &str, e: anyhow::Error) -> String {
    tracing::warn!("{method} failed: {e:#}");
    format!("{e:#}")
}

/// Runs on the core runtime: the stream proxy and downloads spawn onto it.
/// Errors reach Dart as a thrown String.
pub async fn call(method: String, args: String) -> Result<String, String> {
    let m = method.clone();
    let task = aikatsu_core::RT.spawn(async move { aikatsu_core::api::call(&m, parse(&args)).await });
    match task.await {
        Ok(Ok(v)) => Ok(v.to_string()),
        Ok(Err(e)) => Err(message(&method, e)),
        Err(e) => Err(message(&method, e.into())),
    }
}

#[frb(sync)]
pub fn get(method: String, args: String) -> Result<String, String> {
    aikatsu_core::api::get(&method, parse(&args)).map(|v| v.to_string()).map_err(|e| message(&method, e))
}
