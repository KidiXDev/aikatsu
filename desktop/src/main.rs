mod bridge;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

/// The same folders the app used before the core split, so history, shaders
/// and downloads carry over.
fn dirs() -> aikatsu_core::Dirs {
    let fallback = std::env::temp_dir;
    aikatsu_core::Dirs {
        data: dirs::data_dir().unwrap_or_else(fallback).join("aikatsu"),
        config: dirs::config_dir().unwrap_or_else(fallback).join("aikatsu"),
        videos: dirs::video_dir()
            .map(|d| d.join("Aikatsu"))
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".local/aikatsu/downloads/anime")),
    }
}

fn main() {
    let _log = aikatsu_core::init(dirs(), std::env::args().any(|a| a == "--debug"), bridge::push);
    // SAFETY: single-threaded at this point
    unsafe {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
        // Image CDNs trip harmless Qt HTTP/2 stream warnings on every cover load.
        if std::env::var_os("QT_LOGGING_RULES").is_none() {
            std::env::set_var("QT_LOGGING_RULES", "qt.network.http2*=false");
        }
        // mpv's console chatter (hwdec probing, audio underruns) only with debug logging.
        if aikatsu_core::debug_enabled() {
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
