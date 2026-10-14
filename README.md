# Aikatsu 🌸

A desktop anime player for Indonesian-sub sources: Rust + Qt 6 Quick, with a Material 3 look (adapted from [caelestia](https://github.com/caelestia-dots/shell)) and an embedded mpv player. It is the desktop counterpart of the GonimeId CLI and offers the same features.

- **Search** across Otakudesu, Samehadaku, Nimegami, YLnime, Moenime and Astronime in parallel.
  - Results stream in per source.
  - A source that keeps failing is paused for 10 minutes.
- **Watch Hub**: Continue / Recent with resume points, AniList art, and per-series removal or clear-all.
- **Embedded player** (libmpv):
  - YouTube-style quality menu (saved; falls back to the next higher resolution) and resume
  - progress saved every 5 s; an episode counts as complete at 90 %
  - 5 s autoplay countdown
  - AniSkip intro/outro skip (button or automatic)
  - audio/subtitle tracks, speed
  - Anime4K real-time shaders (10 modes)
  - Discord Rich Presence
- **Downloads**: one episode, a range or a whole series, 4 at a time.
  - Plain files download in 4 resumable parts.
  - HLS downloads natively, remuxed with ffmpeg.
  - Blogger/Wibufile downloads go through their special clients.
  - yt-dlp is the fallback and is fetched automatically.
  - Files are laid out for Plex/Jellyfin: `Title (Year) {anilist-ID}/Season 01/Title (Year) - S01E01.mp4`.
- Logs overlay with **Ctrl+L**.

## Build (Linux)

Requirements:
- Rust ≥ 1.88
- Qt ≥ 6.7: `qt6-base qt6-declarative qt6-svg`
- libmpv: `mpv`, with headers available through pkg-config
- cmake and a C compiler (wreq builds BoringSSL)

Optional:
- `ffmpeg`
- `yt-dlp`

```sh
cargo build --release
./target/release/aikatsu            # --debug for verbose logs
install -Dm644 packaging/aikatsu.desktop ~/.local/share/applications/aikatsu.desktop
install -Dm644 assets/icon.svg ~/.local/share/icons/hicolor/scalable/apps/aikatsu.svg
```

If more than one Qt is installed, point at Qt 6 with `QMAKE=/usr/bin/qmake6`.

## Build (Windows, MSVC)

1. Install:
   - Rust (MSVC toolchain)
   - Visual Studio Build Tools
   - CMake
   - NASM (BoringSSL)
   - Qt 6 for MSVC, e.g. `aqt install-qt windows desktop 6.8.3 win64_msvc2022_64`
2. Get libmpv: unpack a `mpv-dev-x86_64-*.7z` from <https://github.com/shinchiro/mpv-winbuild-cmake/releases>. MSVC needs an import library named `mpv.lib` next to `libmpv-2.dll`. If the archive doesn't ship one, generate it from the DLL's exports (`gendef` comes with mingw-w64):
   ```bat
   gendef libmpv-2.dll
   lib /def:libmpv-2.def /name:libmpv-2.dll /out:mpv.lib /machine:x64
   ```
3. Build:
   ```bat
   set QMAKE=C:\Qt\6.8.3\msvc2022_64\bin\qmake.exe
   set MPV_DIR=C:\path\to\mpv-dev
   cargo build --release
   ```
4. Package:
   ```bat
   mkdir dist && copy target\release\aikatsu.exe dist\ && copy %MPV_DIR%\libmpv-2.dll dist\
   C:\Qt\6.8.3\msvc2022_64\bin\windeployqt.exe --qmldir qml dist\aikatsu.exe
   ```
   Zip `dist\`. For HLS remuxing, put `ffmpeg.exe` (gyan.dev "full" build) on PATH or next to the exe.

## Data locations

| | Linux | Windows |
|---|---|---|
| History & settings | `~/.local/share/aikatsu/progress.db` | `%APPDATA%\aikatsu\progress.db` |
| Logs | `~/.local/share/aikatsu/logs/aikatsu.log` | `%APPDATA%\aikatsu\logs\` |
| Anime4K shaders | `~/.config/aikatsu/anime4k-shaders` | `%APPDATA%\aikatsu\anime4k-shaders` |
| Downloads (default) | `~/Videos/Aikatsu` | `%USERPROFILE%\Videos\Aikatsu` |

## Development

```sh
cargo test                                   # parsers, season map, HLS, naming, history
cargo test live_ -- --ignored --nocapture    # hits the real sites (LIVE_Q=<query>)
```

Dev flags for driving the UI headlessly:
- `aikatsu --search <query> [--open [--play]] --screenshot out.png [--delay ms] [--tab N]`
- Set `XDG_DATA_HOME` to a scratch directory to keep test runs out of your real history.

Layout:
- `src/sources/`: the six scrapers (ported from GonimeId).
- `src/proxy.rs`: local Chrome-TLS / HTTP/3 stream relay for mpv.
- `src/bridge.rs`: the `Backend` QObject (`call`/`get`/`pushed`).
- `cpp/mpvitem.*`: the libmpv video item.
- `qml/`: the UI.

## License

GPL-3.0 (the QML components are adapted from caelestia, which is GPL-3.0).

Bundled fonts:
- Google Sans Flex: SIL OFL 1.1
- Material Symbols Rounded: Apache-2.0

See `assets/fonts/`.
