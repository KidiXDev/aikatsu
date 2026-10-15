# Aikatsu 🌸

Fast and smooth native app for watching anime with indonesian subs without ads or a browser, on desktop (Linux, Windows) and Android.

## What it can do

- **Search multiple sources at once.** Results appear as each source answers.
- **Continue watching.** The home screen shows what you were watching and the episode you're up to. Click once to carry on from the exact minute.
- **A proper video player.**
  - Picks a quality for you (or remembers the one you chose), like YouTube.
  - Skips openings and endings, automatically or with a button.
  - Plays the next episode after a short countdown.
  - Switches audio and subtitle tracks and playback speed.
- **Sharper video.** Optional Anime4K sharpening makes lower-quality video look crisp, on desktop and Android. Needs a decent graphics card (or a recent phone).
- **Download episodes.** One episode, a range, or a whole series, saved with names that Plex and Jellyfin recognize.
- **Anime details.** Cover art, synopsis, score, genres and episode titles, with filler and recap episodes marked.
- **Discord status.** Shows what you're watching on your Discord profile (desktop, can be turned off).
- **Dark and light themes.**

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
| Ctrl+L            | Show the log (for troubleshooting)                   |

On Android, tap the video for the controls, double-tap its left or right side to jump 10 seconds, and long-press an episode or a card for more options.

## Download

Get the latest version from the [Releases](../../releases) page:

- **Windows:** download the `.zip`, unpack it anywhere, and run `aikatsu.exe`.
- **Linux:** download the `.AppImage`, make it executable (`chmod +x Aikatsu-*.AppImage`), and run it.
- **Android:** download the `-android-arm64.apk` on your phone and open it (allow installing from your browser when asked).

Optional: install [ffmpeg](https://ffmpeg.org/download.html) so every download ends up as a normal .mp4.

## Build it yourself

### Linux

You need Rust 1.88+, Qt 6.11+ (`qt6-base qt6-declarative qt6-svg`), `mpv`, cmake and a C compiler. `ffmpeg` is recommended so every download ends up as a normal .mp4.

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

1. Install Rust (MSVC toolchain), Visual Studio Build Tools, CMake, NASM, and Qt 6.11+ for MSVC (for example `aqt install-qt windows desktop 6.11.2 win64_msvc2022_64`).
2. Unpack a `mpv-dev-x86_64-*.7z` from <https://github.com/shinchiro/mpv-winbuild-cmake/releases>. If it has no `mpv.lib`, make one next to `libmpv-2.dll` (`gendef` comes with mingw-w64):
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
   Zip `dist\`. Put `ffmpeg.exe` next to `aikatsu.exe` (or on PATH) so downloads end up as .mp4.

### Android

You need Flutter 3.47+, Rust through rustup with the Android target (`rustup target add aarch64-linux-android`), the Android SDK, and cmake. The NDK is installed on first build if missing.

```sh
cd mobile
flutter run                                                        # on a connected phone
flutter build apk --release --target-platform android-arm64       # build/app/outputs/flutter-apk/app-release.apk
```

Release builds are signed with `mobile/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) when it exists, else with the debug key.

After changing `mobile/rust/src/api/mod.rs`, regenerate the Dart bindings. Its `cargo expand` replaces the rustflags from `.cargo/config.toml`, so pass them again:

```sh
cd mobile && RUSTFLAGS='--cfg reqwest_unstable' flutter_rust_bridge_codegen generate
```

## Where your data lives

|                    | Linux                                | Windows                               |
| ------------------ | ------------------------------------ | ------------------------------------- |
| History & settings | `~/.local/share/aikatsu/progress.db` | `%APPDATA%\aikatsu\progress.db`       |
| Downloads          | `~/Videos/Aikatsu`                   | `%USERPROFILE%\Videos\Aikatsu`        |
| Cover image cache  | `~/.cache/Aikatsu/images`            | `%LOCALAPPDATA%\Aikatsu\cache\images` |
| Logs               | `~/.local/share/aikatsu/logs/`       | `%APPDATA%\aikatsu\logs\`             |
| Anime4K files      | `~/.config/aikatsu/anime4k-shaders`  | `%APPDATA%\aikatsu\anime4k-shaders`   |

The download folder can be changed in Settings.

On Android everything lives in the app's own storage and is removed with the app. Downloads go to `Android/data/io.github.kidixdev.aikatsu/files/Anime` and play from the Downloads tab.

## For developers

Pushing a tag like `v0.2.0` builds Windows, Linux and Android on GitHub Actions and publishes a release (tags with a `-`, like `v0.2.0-beta.1`, become pre-releases). Bump `version` in the root `Cargo.toml` first; the app's About line shows it. The APK is signed with the `ANDROID_KEYSTORE_B64` (base64 of the .jks), `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS` repository secrets; a tag build fails without them, since an APK signed with another key can't update an installed one.

```sh
cargo test --workspace                                    # offline tests
cargo test -p aikatsu-core live_ -- --ignored --nocapture  # hits the real sources (LIVE_Q=<query>)
aikatsu --search <query> --open --play --screenshot out.png   # drive the UI and save a screenshot
```

Set `XDG_DATA_HOME` to a scratch folder to keep test runs out of your real history.

- `core/`: everything the apps share. A UI calls `api::call` / `api::get` (JSON in and out) and receives events.
  - `core/src/sources/`: one file per source.
  - `core/src/api.rs`: the method table both UIs call; a new feature starts here.
  - `core/src/proxy.rs`: local relay for the hosts mpv can't play directly.
- `desktop/`: the Qt app.
  - `desktop/src/bridge.rs`: the `Backend` object QML talks to.
  - `desktop/cpp/mpvitem.*`: the video item (libmpv).
  - `desktop/qml/`: the interface.
- `mobile/`: the Flutter app for Android.
  - `mobile/rust/src/api/mod.rs`: the same `call` / `get` / events surface for Dart (flutter_rust_bridge).
  - `mobile/lib/api.dart`: the Dart twin of `desktop/qml/Api.qml`.
  - `mobile/lib/pages/`: one file per screen, ported from `desktop/qml/pages/`; the player uses media_kit (also libmpv).

## License

[GPL-3.0](./LICENSE). Bundled fonts: Google Sans Flex (SIL OFL 1.1) and Material Symbols Rounded (Apache-2.0), see `desktop/assets/fonts/`.
