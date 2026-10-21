# Build the app

Aikatsu has a shared Rust core, a Qt desktop app, and a Flutter Android app. The release environment uses Qt 6.11.2 and Flutter 3.47.1.

For source plugin development, build [the plugin CLI](./testing.md). It requires neither UI toolchain.

## Before you build

Install a current stable Rust toolchain through [rustup](https://www.rust-lang.org/tools/install), then clone the [repository](https://github.com/KidiXDev/aikatsu) with Git or extract its source archive. The core needs the same [native build tools as the plugin CLI](./first-plugin.md#before-you-start), including libclang for its HTTP client's TLS bindings. Add the tools for your platform from the sections below. Cargo downloads Rust dependencies automatically, and `flutter pub get` downloads the Android app's Dart packages.

Keep these files from the checkout:

- `Cargo.lock` pins the Rust dependencies. Some locked versions have since been yanked, so deleting it can prevent dependency resolution.
- `.cargo/config.toml` enables `reqwest_unstable`, which the core's HTTP/3 support requires. Run Cargo from the repo root so it reads this configuration.
- `mobile/pubspec.lock` pins the Dart dependencies for Android builds.

A normal local build needs no `.env` file, release secrets, or signing key. Android release signing and the optional default sync server are covered below. Rhai is a Cargo dependency and needs no separate installation.

## Source files

| Path | Purpose |
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

Both interfaces use asynchronous `call` methods, quick synchronous `get` methods, and events from the core. Shared behavior changes usually require updating the core and the relevant callers in both interfaces.

## Linux desktop

Use a current stable Rust toolchain, Qt 6.11 development packages, libmpv development headers and libraries, CMake, pkg-config, and a C/C++ compiler. You need Qt Base, Declarative, SVG, and Image Formats support (including WebP covers). A standalone mpv player package may not include the headers needed to build Aikatsu. Install ffmpeg too if you want HLS downloads remuxed to MP4.

From the repo root:

```sh
cargo build --release
./target/release/aikatsu
```

To select a Qt 6 installation, set `QMAKE`:

```sh
QMAKE=/usr/bin/qmake6 cargo build --release
```

Adjust the path for your Qt installation.

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

Install Flutter, Rust through rustup, a JDK (the release workflow uses Java 17), the Android SDK with its command-line tools and platform-tools, and CMake. Android Studio can manage the SDK and emulator for you. The build uses Flutter's configured NDK version and can install it when needed.

Before building, run `flutter doctor` and resolve its Android toolchain issues. Accept the SDK licenses with `flutter doctor --android-licenses`. To run the app, connect an Android device with USB debugging enabled or start an emulator. Install the Rust target matching that device or emulator, such as `aarch64-linux-android` for ARM64 or `x86_64-linux-android` for an x86_64 emulator.

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

The stats test plays a generated video in a small window using Qt's threaded OpenGL renderer. It verifies that playback continues as statistics are shown, toggled, and disabled. A GUI freeze causes a timeout. Run it in a desktop session, not with the offscreen or software Qt backend.

With Qt and libmpv runtime libraries on your library path (`PATH` on Windows), and `MPV_DIR` set for Windows builds:

```sh
cmake -S desktop/tests -B target/mpv-stats-test -DCMAKE_PREFIX_PATH="/path/to/Qt/kit"
cmake --build target/mpv-stats-test --config Release
ctest --test-dir target/mpv-stats-test -C Release --output-on-failure
```

## Releases and versions

The root `Cargo.toml` supplies the desktop, core, and mobile Rust package version. Keep `mobile/pubspec.yaml` and the workspace entries in `Cargo.lock` at the same version.

The default sync server is compiled in from the `AIKATSU_SYNC_SERVER` environment variable, which the release workflow sets from a repository secret. Builds without it have no default: users enter a server in Settings before signing in. Set it locally to test against your own server, for example `AIKATSU_SYNC_SERVER=http://localhost:3000 cargo run`.

Pushing a `v` version tag starts the existing release workflow. Android release builds use the tag for their visible version and the workflow run number for the build number. Signing secrets are required for published Android releases. Check the workflow before changing release behavior, especially signing and APK ABI handling.
