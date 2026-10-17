use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};
use std::path::{Path, PathBuf};

fn qml_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            qml_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "qml") {
            out.push(path);
        }
    }
}

/// compile_commands.json for clangd on cpp/, with the same Qt (qmake) and
/// libmpv include paths as the real build. Editor-only; the build ignores it.
fn write_compile_commands(mpv_include: &Path) {
    let qmakes = std::env::var("QMAKE").ok().into_iter().chain(["qmake6".to_owned(), "qmake".to_owned()]);
    let Some(headers) = qmakes
        .filter_map(|q| std::process::Command::new(q).args(["-query", "QT_INSTALL_HEADERS"]).output().ok())
        .find(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
    else {
        return;
    };
    let mut args = vec!["clang++".to_owned(), "-std=c++17".to_owned()];
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        args.push("-fPIC".to_owned()); // Qt's headers refuse to compile without it on ELF
    }
    args.push(format!("-I{}", headers.display()));
    for module in ["QtCore", "QtGui", "QtQml", "QtQuick", "QtOpenGL", "QtDBus"] {
        args.push(format!("-I{}", headers.join(module).display()));
    }
    // An explicit -I/usr/include reorders system dirs and breaks libstdc++'s #include_next.
    if mpv_include != Path::new("/usr/include") {
        args.push(format!("-I{}", mpv_include.display()));
    }
    let dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let esc = |s: &str| format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""));
    let file = "cpp/mpvitem.cpp";
    let argv: Vec<String> = args.iter().map(String::as_str).chain(["-c", file]).map(esc).collect();
    let json = format!("[\n  {{\"directory\": {}, \"file\": {}, \"arguments\": [{}]}}\n]\n", esc(&dir), esc(file), argv.join(", "));
    let path = Path::new(&dir).join("compile_commands.json");
    if std::fs::read_to_string(&path).ok().as_deref() != Some(json.as_str()) {
        let _ = std::fs::write(path, json);
    }
}

/// The app icon on aikatsu.exe (Explorer, shortcuts). rc.exe comes with the
/// Windows SDK and is on PATH in a VS developer prompt.
fn embed_windows_icon() {
    println!("cargo::rerun-if-changed=assets/icon.ico");
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let icon = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("assets").join("icon.ico");
    let rc = out.join("aikatsu.rc");
    std::fs::write(&rc, format!("1 ICON \"{}\"\n", icon.display().to_string().replace('\\', "\\\\"))).unwrap();
    let res = out.join("aikatsu.res");
    let ok = std::process::Command::new("rc").arg("/nologo").arg("/fo").arg(&res).arg(&rc).status().is_ok_and(|s| s.success());
    if ok {
        println!("cargo::rustc-link-arg-bins={}", res.display());
    } else {
        println!("cargo::warning=rc.exe failed or is not on PATH (build from a VS developer prompt); aikatsu.exe gets no icon");
    }
}

fn main() {
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        embed_windows_icon();
    }

    let mut files = Vec::new();
    qml_files(Path::new("qml"), &mut files);
    files.sort();
    println!("cargo::rerun-if-changed=qml");
    let qml = files.into_iter().map(|p| {
        let singleton = std::fs::read_to_string(&p).unwrap().contains("pragma Singleton");
        QmlFile::from(p).singleton(singleton)
    });

    // cfg!(windows) would describe the build host; the target is what matters.
    let mpv_include = if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        // MPV_DIR: unpacked shinchiro mpv-dev archive (include/, mpv.lib made via `lib /def:mpv.def`)
        let dir = PathBuf::from(std::env::var("MPV_DIR").expect("set MPV_DIR to the mpv-dev folder"));
        println!("cargo::rustc-link-search=native={}", dir.display());
        println!("cargo::rustc-link-lib=mpv");
        println!("cargo::rustc-link-lib=dwmapi"); // window animations around fullscreen (cpp/mpvitem.cpp)
        println!("cargo::rerun-if-env-changed=MPV_DIR");
        dir.join("include")
    } else {
        let lib = pkg_config::probe_library("mpv").expect("libmpv development files not found");
        lib.include_paths.first().cloned().unwrap_or_else(|| "/usr/include".into())
    };

    write_compile_commands(&mpv_include);

    let mut builder = CxxQtBuilder::new_qml_module(QmlModule::new("Aikatsu").qml_files(qml).depend("QtQuick"))
        .files(["src/bridge.rs"])
        .cpp_files(["cpp/mpvitem.h", "cpp/mpvitem.cpp", "cpp/windowstate.h"])
        .qt_module("Quick")
        .qt_module("OpenGL")
        .qt_module("Network")
        .qrc("assets/assets.qrc");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        builder = builder.qt_module("DBus"); // screensaver inhibit
    }
    // SAFETY: only adds an include path
    unsafe { builder.cc_builder(|cc| { cc.include(&mpv_include); }) }.build();
}
