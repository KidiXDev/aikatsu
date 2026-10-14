mod anime4k;
mod api;
mod blogger;
mod bridge;
mod db;
mod discord;
mod download;
mod http;
mod meta;
mod proxy;
mod sources;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use std::path::PathBuf;
use std::sync::LazyLock;

pub static RT: LazyLock<tokio::runtime::Runtime> =
    LazyLock::new(|| tokio::runtime::Builder::new_multi_thread().enable_all().build().expect("tokio runtime"));

fn log_path() -> PathBuf {
    dirs::data_dir().unwrap_or_else(std::env::temp_dir).join("aikatsu").join("logs").join("aikatsu.log")
}

/// One log file per run (like the CLI), mirrored to stderr.
fn debug_enabled() -> bool {
    std::env::args().any(|a| a == "--debug") || api::setting("debug") == "true"
}

fn init_logging() -> tracing_appender::non_blocking::WorkerGuard {
    use tracing_subscriber::{EnvFilter, fmt, prelude::*};
    let path = log_path();
    let _ = std::fs::create_dir_all(path.parent().unwrap());
    let _ = std::fs::remove_file(&path);
    let (file, guard) = tracing_appender::non_blocking(tracing_appender::rolling::never(path.parent().unwrap(), "aikatsu.log"));
    let filter = EnvFilter::new(if debug_enabled() { "aikatsu=debug,warn" } else { "aikatsu=info,warn" });
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

fn main() {
    let _log = init_logging();
    // SAFETY: single-threaded at this point
    unsafe {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
        // Image CDNs trip harmless Qt HTTP/2 stream warnings on every cover load.
        if std::env::var_os("QT_LOGGING_RULES").is_none() {
            std::env::set_var("QT_LOGGING_RULES", "qt.network.http2*=false");
        }
        // mpv's console chatter (hwdec probing, audio underruns) only with debug logging.
        if debug_enabled() {
            std::env::set_var("AIKATSU_MPV_LOG", "1");
        }
    }
    let mut app = QGuiApplication::new();
    bridge::ffi::aikatsu_init();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        bridge::ffi::aikatsu_engine_init(engine.as_mut());
        engine.load(&QUrl::from("qrc:/qt/qml/Aikatsu/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
