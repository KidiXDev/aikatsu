//! Everything the desktop and mobile apps share. A UI only needs `init`, then
//! `api::call` (async) / `api::get` (sync) with JSON in and out, plus the
//! events handed to the `init` sink (search results per source, download
//! progress, …).

pub mod api;
mod anime4k;
mod blogger;
mod db;
#[cfg(feature = "desktop")]
mod discord;
mod download;
mod http;
mod meta;
mod proxy;
mod sources;

use serde_json::Value;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, OnceLock};
pub use tracing_appender::non_blocking::WorkerGuard;

/// The work is mostly network I/O, so a few workers do; one per core just adds
/// thread stacks and allocator arenas.
pub static RT: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    let workers = std::thread::available_parallelism().map_or(2, |n| n.get().min(4));
    tokio::runtime::Builder::new_multi_thread().worker_threads(workers).enable_all().build().expect("tokio runtime")
});

/// Where the app keeps its files; each platform picks its own.
pub struct Dirs {
    /// History database, logs, fetched tools.
    pub data: PathBuf,
    /// Anime4K shaders.
    pub config: PathBuf,
    /// Default download folder.
    pub videos: PathBuf,
}

static DIRS: OnceLock<Dirs> = OnceLock::new();

/// A temp folder until `init` runs, so tests work without it.
pub(crate) fn dirs() -> &'static Dirs {
    DIRS.get_or_init(|| {
        let tmp = std::env::temp_dir().join("aikatsu");
        Dirs { data: tmp.clone(), config: tmp.clone(), videos: tmp.join("downloads") }
    })
}

type Sink = Box<dyn Fn(&str, &Value) + Send + Sync>;
static SINK: OnceLock<Sink> = OnceLock::new();

/// Sends an event to the UI; callable from any thread.
pub(crate) fn push(kind: &str, value: &Value) {
    if let Some(sink) = SINK.get() {
        sink(kind, value);
    }
}

static DEBUG_FLAG: AtomicBool = AtomicBool::new(false);

/// Call once at startup, before anything else here. `debug` forces debug
/// logging on top of the stored setting (the desktop `--debug` flag).
/// Keep the returned guard alive: dropping it flushes the log file.
pub fn init(dirs: Dirs, debug: bool, push: impl Fn(&str, &Value) + Send + Sync + 'static) -> WorkerGuard {
    assert!(DIRS.set(dirs).is_ok(), "aikatsu_core::init must run first, and once");
    let _ = SINK.set(Box::new(push));
    DEBUG_FLAG.store(debug, Ordering::Relaxed);
    init_logging()
}

pub fn debug_enabled() -> bool {
    DEBUG_FLAG.load(Ordering::Relaxed) || api::setting("debug") == "true"
}

fn log_path() -> PathBuf {
    dirs().data.join("logs").join("aikatsu.log")
}

/// A fresh log file each run, also printed to the console.
fn init_logging() -> WorkerGuard {
    use tracing_subscriber::{EnvFilter, fmt, prelude::*};
    let path = log_path();
    let dir = path.parent().unwrap();
    let _ = std::fs::create_dir_all(dir);
    let _ = std::fs::remove_file(&path);
    let (file, guard) = tracing_appender::non_blocking(tracing_appender::rolling::never(dir, "aikatsu.log"));
    let filter = EnvFilter::new(if debug_enabled() { "aikatsu=debug,aikatsu_core=debug,warn" } else { "aikatsu=info,aikatsu_core=info,warn" });
    tracing_subscriber::registry()
        .with(filter)
        .with(fmt::layer().with_ansi(false).with_writer(file))
        .with(fmt::layer().with_writer(std::io::stderr))
        .init();
    guard
}

pub fn log_tail(lines: usize) -> String {
    let text = std::fs::read_to_string(log_path()).unwrap_or_default();
    let all: Vec<&str> = text.lines().collect();
    all[all.len().saturating_sub(lines)..].join("\n")
}
