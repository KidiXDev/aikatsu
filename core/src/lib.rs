//! Everything the desktop and mobile apps share. A UI only needs `init`, then
//! `api::call` (async) / `api::get` (sync) with JSON in and out, plus the
//! events handed to the `init` sink (search results per source, download
//! progress, plugin changes, …).

pub mod api;
mod anime4k;
mod blogger;
mod db;
#[cfg(feature = "desktop")]
mod discord;
mod download;
mod http;
mod local;
mod meta;
pub mod plugin_cli;
mod plugins;
mod proxy;
mod sources;
mod sync;
mod update;

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
    let guard = init_logging();
    RT.spawn(sync::run());
    guard
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

pub fn log_tail(lines: usize) -> anyhow::Result<String> {
    read_log_tail(&log_path(), lines)
}

pub fn log_report() -> anyhow::Result<String> {
    Ok(format!("Aikatsu {}\nPlatform: {} ({})\n\n{}\n", env!("CARGO_PKG_VERSION"), std::env::consts::OS, std::env::consts::ARCH, log_tail(usize::MAX)?))
}

fn read_log_tail(path: &std::path::Path, lines: usize) -> anyhow::Result<String> {
    use anyhow::Context;
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(String::new()),
        Err(e) => return Err(e).with_context(|| format!("couldn't read log {}", path.display())),
    };
    let all: Vec<&str> = text.lines().collect();
    Ok(all[all.len().saturating_sub(lines)..].join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_tail_handles_empty_missing_and_unreadable_files() {
        let dir = std::env::temp_dir().join(format!("aikatsu-log-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("test.log");
        assert_eq!(read_log_tail(&path, 400).unwrap(), "");
        std::fs::write(&path, "").unwrap();
        assert_eq!(read_log_tail(&path, 400).unwrap(), "");
        std::fs::write(&path, "first\nsecond\nlast\n").unwrap();
        assert_eq!(read_log_tail(&path, 2).unwrap(), "second\nlast");
        assert_eq!(read_log_tail(&path, 0).unwrap(), "");
        let full = (0..450).map(|i| format!("entry {i}")).collect::<Vec<_>>().join("\n");
        std::fs::write(&path, &full).unwrap();
        assert_eq!(read_log_tail(&path, usize::MAX).unwrap(), full);
        assert!(read_log_tail(&dir, 400).unwrap_err().to_string().contains("couldn't read log"));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
