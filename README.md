# Aikatsu 🌸

Watch anime with Indonesian subtitles on Linux, Windows, and Android, without ads or a browser.

## What you can do

- Search several sources at once and see results as they arrive.
- Resume episodes from your saved position on Home.
- Sign in to sync history and settings between your phone and computer. Use Aikatsu's server or [run your own](https://kidixdev.github.io/aikatsu/guide/self-hosting) with Docker.
- Choose a video quality or let the player pick. Aikatsu remembers your choice.
- Skip openings and endings with a button or automatically when timing data is available.
- Play the next episode after a short countdown.
- Change playback speed and switch audio or subtitle tracks when available.
- Sharpen video with optional Anime4K presets on desktop and Android. Performance depends on your GPU or phone.
- Download an episode, a range, or a whole series with file names Plex and Jellyfin recognize.
- View cover art, descriptions, scores, genres, episode titles, and filler or recap markers when available.
- Show what you're watching on Discord from desktop, or turn it off in Settings.
- Choose a dark or light theme.

Sources come from [Kyoko](https://github.com/KidiXDev/kyoko) and other plugin repos you add in Settings. Startup checks show available updates. Download them from Plugins when you're ready, or turn off automatic checks in Settings.

## Documentation

Use the [documentation site](https://kidixdev.github.io/aikatsu/) for app guides, plugin management, and source plugin tutorials.

To edit the docs, open [`docs/`](./docs/index.md) and run `cd docs`, `npm ci`, then `npm run dev`. Changes on `main` deploy to GitHub Pages. See [editing the docs](./docs/developers/docs-site.md) for builds and hosting.

## Keyboard shortcuts (desktop)

| Key               | Action                                               |
| ----------------- | ---------------------------------------------------- |
| Space or K        | Play / pause                                         |
| ← / → (or J / L)  | Back / forward 5 seconds (hold Shift for 85 seconds) |
| ↑ / ↓             | Volume                                               |
| M                 | Mute                                                 |
| F or double-click | Fullscreen                                           |
| N / P             | Next / previous episode                              |
| S                 | Skip opening or ending                               |
| Esc               | Leave fullscreen, then close the player              |
| Ctrl+L            | Show the log (Developer Mode)                        |

On Android, tap the video for the controls, double-tap its left or right side to jump 10 seconds, and long-press an episode or a card for more options.

## Download

Download the latest version from [Releases](../../releases):

- **Windows:** download the `-setup.exe`, accept the license agreement, and choose an installation folder. The default folder needs no admin rights. Or download the `.zip`, unpack it anywhere, and run `aikatsu.exe`.
- **Linux:** download the `.AppImage`, make it executable (`chmod +x Aikatsu-*.AppImage`), and run it.
- **Android:** download the `-android-arm64-v8a.apk` on your phone and open it (allow installing from your browser when asked). Older 32-bit phones need the `-armeabi-v7a.apk` instead.

Install [ffmpeg](https://ffmpeg.org/download.html) to help save HLS downloads as MP4 files.

## Build it yourself

### Linux

You need Rust 1.88+, Qt 6.11+ (`qt6-base qt6-declarative qt6-svg qt6-imageformats`), `mpv`, cmake and a C compiler. Install `ffmpeg` to help save HLS downloads as MP4 files.

```sh
cargo build --release
./target/release/aikatsu
```

To add it to your app menu:

```sh
install -Dm755 target/release/aikatsu ~/.local/bin/aikatsu
install -Dm644 desktop/packaging/aikatsu.desktop ~/.local/share/applications/aikatsu.desktop
install -Dm644 desktop/assets/icon.svg ~/.local/share/icons/hicolor/scalable/apps/aikatsu.svg
```

If more than one Qt version is installed, point the build at Qt 6 with `QMAKE=/usr/bin/qmake6`.

### Windows (MSVC)

1. Install Rust (MSVC toolchain), Visual Studio Build Tools, CMake, NASM, and Qt 6.11+ for MSVC including Qt Image Formats (for example `aqt install-qt windows desktop 6.11.2 win64_msvc2022_64 --modules qtimageformats`).
2. Unpack an `mpv-dev-x86_64-*.7z` from <https://github.com/shinchiro/mpv-winbuild-cmake/releases>. If it has no `mpv.lib`, make one next to `libmpv-2.dll` (`gendef` comes with mingw-w64):
   ```bat
   gendef libmpv-2.dll
   lib /def:libmpv-2.def /name:libmpv-2.dll /out:mpv.lib /machine:x64
   ```
3. Build:
   ```bat
   set QMAKE=C:\Qt\6.11.2\msvc2022_64\bin\qmake.exe
   set MPV_DIR=C:\path\to\mpv-dev
   cargo build --release
   ```
4. Package:
   ```bat
   mkdir dist && copy target\release\aikatsu.exe dist\ && copy %MPV_DIR%\libmpv-2.dll dist\
   C:\Qt\6.11.2\msvc2022_64\bin\windeployqt.exe --qmldir desktop\qml dist\aikatsu.exe
   ```
   Zip `dist\`. Include `ffmpeg.exe` beside `aikatsu.exe` or on PATH for HLS-to-MP4 downloads.

### Android

You need Flutter 3.47+, Rust through rustup with the Android target (`rustup target add aarch64-linux-android`), the Android SDK, and cmake. The NDK is installed on first build if missing.

```sh
cd mobile
flutter run                                                                     # on a connected phone or an emulator
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-info   # one APK per ABI in build/app/outputs/flutter-apk/
```

Keep `--split-per-abi` for release builds so each APK includes native libraries for one CPU architecture. Without it, `--target-platform` can leave media_kit libraries for other architectures in the APK without a matching Rust core. The app could then install on those devices but fail to start.

To build only the ARM64 APK, also add `--target-platform android-arm64`.

For release signing, set `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` in `mobile/android/key.properties`. Without that file, local builds use the debug key.

After changing `mobile/rust/src/api/mod.rs`, regenerate the Dart bindings. Pass the flags below because `cargo expand` replaces those from `.cargo/config.toml`:

```sh
cd mobile && RUSTFLAGS='--cfg reqwest_unstable' flutter_rust_bridge_codegen generate
```

## For developers

To publish a release, bump `version` in the root `Cargo.toml`, which also sets the version shown in About. Push a tag such as `v0.2.0` to build and publish Windows, Linux, and Android releases through GitHub Actions. Tags containing a `-`, such as `v0.2.0-beta.1`, create prereleases.

Android releases need these repository secrets:

- `ANDROID_KEYSTORE_B64`: the base64-encoded `.jks` signing key
- `ANDROID_KEYSTORE_PASSWORD`: its password
- `ANDROID_KEY_ALIAS`: its key alias

Tag builds fail without them. Updates must use the same signing key as the installed APK.

Set the `AIKATSU_SYNC_SERVER` secret to include a default sync server in the apps. Without it, users must enter a server address.

Each run saves Dart debug symbols in the `symbols-android` artifact for 90 days. They are not published with the release. Use them with `flutter symbolize` to read obfuscated crash traces.

```sh
cargo test --workspace                                    # offline tests
cargo test -p aikatsu-core live_ -- --ignored --nocapture  # hits the real sources (LIVE_Q=<query>)
aikatsu --search <query> --open --play --screenshot out.png   # drive the UI and save a screenshot
```

Set `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` to absolute scratch paths to keep test runs separate from your history, settings, and cache.

- `core/`: everything the apps share. A UI calls `api::call` / `api::get` (JSON in and out) and receives events.
  - `core/src/plugins.rs`: the plugin engine and repo management.
  - `core/src/sources.rs`: source types and the search/playback contract.
  - `core/src/api.rs`: the method table both UIs call, where new shared features start.
  - `core/src/proxy.rs`: local relay for the hosts mpv can't play directly.
- `desktop/`: the Qt app.
  - `desktop/src/bridge.rs`: the `Backend` object QML talks to.
  - `desktop/cpp/mpvitem.*`: the video item (libmpv).
  - `desktop/qml/`: the interface.
- `mobile/`: the Flutter app for Android.
  - `mobile/rust/src/api/mod.rs`: the same `call` / `get` / events surface for Dart (flutter_rust_bridge).
  - `mobile/lib/api.dart`: the Dart twin of `desktop/qml/Api.qml`.
  - `mobile/lib/pages/`: one file per screen, ported from `desktop/qml/pages/`. The player uses media_kit (also libmpv).

## Disclaimer

Aikatsu has no official connection to or endorsement from any other company, organization, or media franchise.

The app retrieves media, video streams, and metadata from publicly available third-party sources. Its developers do not host, upload, maintain, or control that content. They accept no responsibility or liability for third-party content, copyright compliance, or how the software is used.

## License

[GPL-3.0](./LICENSE). Bundled fonts: Google Sans Flex (SIL OFL 1.1) and Material Symbols Rounded (Apache-2.0), see `desktop/assets/fonts/`.
