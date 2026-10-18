# Build the app

If you're only writing a source plugin, build [the plugin CLI](./testing.md) instead. You don't need either UI toolchain for that.

Aikatsu uses a shared Rust core, Qt for desktop, and Flutter for Android. To match the release environment, use Qt **6.11.2** and Flutter **3.47.1**.

## Source files

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

Use a current stable Rust toolchain, Qt 6.11 development packages, libmpv, CMake, and a C/C++ compiler. You need Qt Base, Declarative, SVG, and Image Formats support (including WebP covers). Install ffmpeg too if you want HLS downloads remuxed to MP4.

From the repo root:

```sh
cargo build --release
./target/release/aikatsu
```

To select a Qt 6 installation, set `QMAKE`:

```sh
QMAKE=/usr/bin/qmake6 cargo build --release
```

The exact qmake path depends on how Qt was installed.

## Windows desktop

Use the MSVC Rust toolchain, Visual Studio Build Tools, CMake, NASM, Qt 6.11 for MSVC including Qt Image Formats, and a libmpv development package with an MSVC import library. With aqt, include `--modules qtimageformats` when installing Qt.

In a developer command prompt, point the build at Qt and libmpv:

```bat
set QMAKE=C:\Qt\6.11.2\msvc2022_64\bin\qmake.exe
set MPV_DIR=C:\path\to\mpv-dev
cargo build --release
```

Packaging also needs `libmpv-2.dll` and Qt's deployed libraries. Use `windeployqt` with `desktop\qml` as the QML source directory. If your libmpv archive has no import library, follow the [repo README](https://github.com/KidiXDev/aikatsu#build-it-yourself) to create one. See the [release workflow](https://github.com/KidiXDev/aikatsu/blob/main/.github/workflows/release.yml) for automated packaging steps.

Building the NSIS installer also needs Python on PATH. The installer build uses it to list the packaged files for safe removal during uninstall. The setup wizard shows the root `LICENSE` and lets users choose a folder. Silent updates reuse the saved installation folder.

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

The flag preserves the core's HTTP/3 configuration during code generation. Don't edit generated bindings by hand.

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

### Desktop renderer regression

The stats test opens a small window and plays a generated video through the real Qt threaded OpenGL renderer. It checks that playback continues while stats are shown, toggled, and disabled, and times out if the GUI freezes. Run it in a desktop session, not with the offscreen or software Qt backend.

With Qt and libmpv runtime libraries on your library path (`PATH` on Windows), and `MPV_DIR` set for Windows builds:

```sh
cmake -S desktop/tests -B target/mpv-stats-test -DCMAKE_PREFIX_PATH="/path/to/Qt/kit"
cmake --build target/mpv-stats-test --config Release
ctest --test-dir target/mpv-stats-test -C Release --output-on-failure
```

## Releases and versions

The root `Cargo.toml` supplies the desktop, core, and mobile Rust package version. Keep `mobile/pubspec.yaml` and the workspace entries in `Cargo.lock` in step.

The default sync server is compiled in from the `AIKATSU_SYNC_SERVER` environment variable, which the release workflow sets from a repository secret. Builds without it have no default: users enter a server in Settings before signing in. Set it locally to test against your own server, for example `AIKATSU_SYNC_SERVER=http://localhost:3000 cargo run`.

Pushing a `v` version tag starts the existing release workflow. Android release builds use the tag for their visible version and the workflow run number for the build number. Signing secrets are required for published Android releases. Check the workflow before changing release behavior, especially signing and APK ABI handling.
