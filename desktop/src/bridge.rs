//! The one QObject QML talks to. `call` runs an async API method on the tokio
//! runtime and answers with `reply(id, ok, json)`; `get` runs a quick local
//! (DB/settings) method synchronously; `pushed(kind, json)` streams events
//! (search results per source, download progress, …).

use std::pin::Pin;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicI32, Ordering};

use cxx_qt::{CxxQtThread, Threading};
use cxx_qt_lib::QString;

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qqmlapplicationengine.h");
        type QQmlApplicationEngine = cxx_qt_lib::QQmlApplicationEngine;
        include!("aikatsu/cpp/mpvitem.h");
        fn aikatsu_init();
        fn aikatsu_engine_init(engine: Pin<&mut QQmlApplicationEngine>);
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        type Backend = super::BackendRust;

        #[qinvokable]
        fn call(self: Pin<&mut Backend>, method: &QString, args: &QString) -> i32;
        #[qinvokable]
        fn get(self: Pin<&mut Backend>, method: &QString, args: &QString) -> QString;

        #[qsignal]
        fn reply(self: Pin<&mut Backend>, id: i32, ok: bool, json: QString);
        #[qsignal]
        fn pushed(self: Pin<&mut Backend>, kind: QString, json: QString);
    }

    impl cxx_qt::Threading for Backend {}
    impl cxx_qt::Initialize for Backend {}
}

#[derive(Default)]
pub struct BackendRust;

static THREAD: OnceLock<CxxQtThread<ffi::Backend>> = OnceLock::new();
static NEXT_ID: AtomicI32 = AtomicI32::new(1);

impl cxx_qt::Initialize for ffi::Backend {
    fn initialize(self: Pin<&mut Self>) {
        let _ = THREAD.set(self.qt_thread());
    }
}

/// Emits `pushed(kind, json)` on the Qt thread; callable from any thread.
pub fn push(kind: &str, value: &serde_json::Value) {
    if let Some(t) = THREAD.get() {
        let (kind, json) = (kind.to_owned(), value.to_string());
        let _ = t.queue(move |o| o.pushed(QString::from(&kind), QString::from(&json)));
    }
}

fn reply(id: i32, result: anyhow::Result<serde_json::Value>) {
    let (ok, json) = match result {
        Ok(v) => (true, v.to_string()),
        Err(e) => {
            tracing::warn!("call {id} failed: {e:#}");
            (false, serde_json::Value::String(format!("{e:#}")).to_string())
        }
    };
    if let Some(t) = THREAD.get() {
        let _ = t.queue(move |o| o.reply(id, ok, QString::from(&json)));
    }
}

fn parse_args(args: &QString) -> serde_json::Value {
    let s = args.to_string();
    if s.is_empty() { serde_json::Value::Null } else { serde_json::from_str(&s).unwrap_or(serde_json::Value::Null) }
}

impl ffi::Backend {
    fn call(self: Pin<&mut Self>, method: &QString, args: &QString) -> i32 {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let (method, args) = (method.to_string(), parse_args(args));
        aikatsu_core::RT.spawn(async move { reply(id, aikatsu_core::api::call(&method, args).await) });
        id
    }

    fn get(self: Pin<&mut Self>, method: &QString, args: &QString) -> QString {
        let value = aikatsu_core::api::get(&method.to_string(), parse_args(args)).unwrap_or_else(|e| {
            tracing::warn!("get {method} failed: {e:#}");
            serde_json::json!({ "error": format!("{e:#}") })
        });
        QString::from(&value.to_string())
    }
}
