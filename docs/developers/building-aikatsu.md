# Build the app

If you're only writing a source plugin, build [the plugin CLI](./testing.md) instead. You don't need either UI toolchain for that.

For app work, Aikatsu has a shared Rust core, a Qt desktop interface, and a Flutter Android interface. The release workflow currently pins Qt **6.11.2** and Flutter **3.47.1**. Those are useful reference points when matching the project's build environment.

## What's where

| Path | What lives there |
| --- | --- |
| `core/src/api.rs` | JSON methods shared by both interfaces |
| `core/src/plugins.rs` | Plugin engine, host helpers, repo checks, and installation |
| `core/src/sources.rs` | Source return types and search/playback wrappers |
| `core/src/plugin_cli.rs` | Plugin authoring CLI |
| `core/src/meta.rs` | Anime metadata, episode information, and skip times |
| `core/src/download.rs` | Episode downloads and recorded files |
| `core/src/proxy.rs` | Local relays for supported video hosts |
| `desktop/src/bridge.rs` | Qt's Backend object and event bridge |
| `desktop/qml/` | Desktop screens and components |
| `desktop/cpp/mpvitem.*` | Desktop libmpv video item |
| `mobile/rust/src/api/mod.rs` | Dart-facing Rust API and events |
| `mobile/lib/api.dart` | Flutter's JSON API wrapper |
| `mobile/lib/pages/` | Android screens and player |

The core API has asynchronous `call` methods, quick synchronous `get` methods, and pushed events. A cross-platform behavior change usually starts in the core, then updates the relevant callers in both interfaces.

## Linux desktop

Use a current stable Rust toolchain, Qt 6.11 development packages, libmpv, CMake, and a C/C++ compiler. You need Qt Base, Declarative, and SVG support. Install ffmpeg too if you want HLS downloads remuxed to MP4.

From the repo root:

```sh
cargo build --release
./target/release/aikatsu
```

If the wrong Qt is being picked up, point `QMAKE` at the Qt 6 installation you want:

```sh
QMAKE=/usr/bin/qmake6 cargo build --release
```

The exact qmake path depends on how Qt was installed.

## Windows desktop

Use the MSVC Rust toolchain, Visual Studio Build Tools, CMake, NASM, Qt 6.11 for MSVC, and a libmpv development package with an MSVC import library.

In a developer command prompt, point the build at Qt and libmpv:

```bat
set QMAKE=C:\Qt\6.11.2\msvc2022_64\bin\qmake.exe
set MPV_DIR=C:\path\to\mpv-dev
cargo build --release
```

Packaging also needs `libmpv-2.dll` and Qt's deployed libraries. Use `windeployqt` with `desktop\qml` as the QML source directory. The [repo README](https://github.com/KidiXDev/aikatsu#build-it-yourself) covers creating an import library if your libmpv archive doesn't include one; the [release workflow](https://github.com/KidiXDev/aikatsu/blob/main/.github/workflows/release.yml) shows the current automated packaging steps.

## Android

Install Flutter, Rust through rustup, the Android SDK, and CMake. The build can install its configured NDK when needed.

For an ARM64 device:

```sh
rustup target add aarch64-linux-android
cd mobile
flutter pub get
flutter run
```

For release APKs, install the Rust targets for the ABIs you're building:

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd mobile
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-info
```

Keep `--split-per-abi` for release builds so each APK contains matching native libraries. To build only ARM64 while keeping the split, add `--target-platform android-arm64`.

Local release signing reads `mobile/android/key.properties`. Without it, a local build falls back to the debug key. That won't update an installed APK signed with the project's release key.

## Regenerate the mobile bridge

After changing the exposed Rust API in `mobile/rust/src/api/mod.rs`, regenerate the Dart bindings from `mobile/`:

```sh
RUSTFLAGS='--cfg reqwest_unstable' flutter_rust_bridge_codegen generate
```

The explicit flag keeps the HTTP/3 configuration used by the core while the generator runs Cargo expansion. Don't edit generated bindings by hand.

## Run checks

From the repo root:

```sh
cargo test -p aikatsu-core --lib
cargo check -p aikatsu -p aikatsu_mobile
```

From `mobile/`:

```sh
flutter test
flutter analyze
```

Ignored tests that contact real sources are separate:

```sh
cargo test -p aikatsu-core live_ -- --ignored --nocapture
```

## Releases and versions

The root `Cargo.toml` supplies the desktop, core, and mobile Rust package version. Keep `mobile/pubspec.yaml` and the workspace entries in `Cargo.lock` in step.

Pushing a `v` version tag starts the existing release workflow. Android release builds use the tag for their visible version and the workflow run number for the build number. Signing secrets are required for published Android releases. Check the workflow before changing release behavior, especially signing and APK ABI handling.
