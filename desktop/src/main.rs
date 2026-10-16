// Release builds start without a console window; debug builds keep it for logs.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod bridge;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use anyhow::Context;

fn lock_instance(data: &std::path::Path) -> std::io::Result<Option<std::fs::File>> {
    std::fs::create_dir_all(data)?;
    let file = std::fs::OpenOptions::new().create(true).write(true).truncate(false).open(data.join("instance.lock"))?;
    match file.try_lock() {
        Ok(()) => Ok(Some(file)),
        Err(std::fs::TryLockError::WouldBlock) => Ok(None),
        Err(std::fs::TryLockError::Error(e)) => Err(e),
    }
}

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

fn main() -> anyhow::Result<()> {
    let dirs = dirs();
    let Some(_instance) = lock_instance(&dirs.data).context("couldn't lock the Aikatsu instance")? else { return Ok(()) };
    let _log = aikatsu_core::init(dirs, std::env::args().any(|a| a == "--debug"), bridge::push);
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
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instance_lock_is_exclusive_and_released() {
        let dir = std::env::temp_dir().join(format!("aikatsu-instance-test-{}", std::process::id()));
        let first = lock_instance(&dir).unwrap().unwrap();
        assert!(lock_instance(&dir).unwrap().is_none());
        drop(first);
        let next = lock_instance(&dir).unwrap().unwrap();
        drop(next);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
