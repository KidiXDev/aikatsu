// Release builds start without a console window; debug builds keep it for logs.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod bridge;

use cxx_qt_lib::{QByteArray, QGuiApplication, QQmlApplicationEngine, QUrl};
use anyhow::Context;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};

fn lock_instance(data: &std::path::Path) -> std::io::Result<Option<std::fs::File>> {
    std::fs::create_dir_all(data)?;
    let file = std::fs::OpenOptions::new().create(true).write(true).truncate(false).open(data.join("instance.lock"))?;
    match file.try_lock() {
        Ok(()) => Ok(Some(file)),
        Err(std::fs::TryLockError::WouldBlock) => Ok(None),
        Err(std::fs::TryLockError::Error(e)) => Err(e),
    }
}

/// The running copy may be hidden in the tray, so a second launch asks it to
/// show its window instead, passing on the watch-together link it was opened with.
fn listen_for_launches(data: &std::path::Path) {
    let Ok(listener) = TcpListener::bind("127.0.0.1:0") else { return };
    let Ok(addr) = listener.local_addr() else { return };
    if std::fs::write(data.join("instance.port"), addr.port().to_string()).is_err() {
        return;
    }
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut link = String::new();
            let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(1)));
            let _ = stream.take(4096).read_to_string(&mut link);
            bridge::push("show", &serde_json::Value::Null);
            if link.starts_with("aikatsu:") {
                bridge::push("link", &serde_json::Value::String(link));
            }
        }
    });
}

fn show_running(data: &std::path::Path) {
    if let Some(port) = std::fs::read_to_string(data.join("instance.port")).ok().and_then(|p| p.trim().parse::<u16>().ok())
        && let Ok(mut stream) = TcpStream::connect_timeout(&SocketAddr::from(([127, 0, 0, 1], port)), std::time::Duration::from_secs(1))
        && let Some(link) = std::env::args().skip(1).find(|a| a.starts_with("aikatsu:"))
    {
        let _ = stream.write_all(link.as_bytes());
    }
}

/// An AppImage isn't installed, so it registers aikatsu: links itself, pointing at wherever it now lives.
#[cfg(target_os = "linux")]
fn register_appimage_links() {
    let (Some(appimage), Some(dir)) = (std::env::var_os("APPIMAGE"), dirs::data_dir().map(|d| d.join("applications"))) else { return };
    let file = dir.join("aikatsu-link.desktop");
    let entry = format!(
        "[Desktop Entry]\nType=Application\nName=Aikatsu\nExec=\"{}\" %u\nIcon=aikatsu\nNoDisplay=true\nMimeType=x-scheme-handler/aikatsu;\n",
        appimage.to_string_lossy()
    );
    if std::fs::read_to_string(&file).is_ok_and(|old| old == entry) {
        return;
    }
    if std::fs::create_dir_all(&dir).is_ok() && std::fs::write(&file, entry).is_ok() {
        let _ = std::process::Command::new("xdg-mime").args(["default", "aikatsu-link.desktop", "x-scheme-handler/aikatsu"]).status();
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
    let Some(_instance) = lock_instance(&dirs.data).context("couldn't lock the Aikatsu instance")? else {
        show_running(&dirs.data);
        return Ok(());
    };
    listen_for_launches(&dirs.data);
    #[cfg(target_os = "linux")]
    register_appimage_links();
    let startup = aikatsu_core::init(dirs, std::env::args().any(|a| a == "--debug"), bridge::push);
    // SAFETY: single-threaded at this point
    unsafe {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
        // Image CDNs trip harmless Qt HTTP/2 stream warnings on every cover load.
        if std::env::var_os("QT_LOGGING_RULES").is_none() {
            std::env::set_var("QT_LOGGING_RULES", "qt.network.http2*=false");
        }
        // mpv's console chatter (hwdec probing, audio underruns) only with debug logging.
        if startup.is_ok() && aikatsu_core::debug_enabled() {
            std::env::set_var("AIKATSU_MPV_LOG", "1");
        }
    }
    let mut app = QGuiApplication::new();
    bridge::ffi::aikatsu_init();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        if let Err(error) = &startup {
            let message = serde_json::to_string(&format!("Couldn't open app storage.\n\n{error:#}"))?;
            let qml = format!(r#"import QtQuick
import QtQuick.Controls
ApplicationWindow {{
    visible: true; width: 520; height: 260; title: "Aikatsu"
    Label {{ anchors.fill: parent; anchors.margins: 24; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: {message} }}
}}"#);
            engine.load_data(&QByteArray::from(qml.as_str()), &QUrl::default());
        } else {
            bridge::ffi::aikatsu_engine_init(engine.as_mut());
            engine.load(&QUrl::from("qrc:/qt/qml/Aikatsu/qml/Main.qml"));
        }
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
    startup.map(|_| ())
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
