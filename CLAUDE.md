# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
cargo build                                   # desktop app (default workspace member); run ./target/debug/aikatsu
cargo test -p aikatsu-core --lib              # core tests (offline)
cargo test -p aikatsu-core db::tests::continue_episode_rules   # one test
cargo test -p aikatsu-core live_ -- --ignored --nocapture       # hits real sources (LIVE_Q=<query>)
cargo check -p aikatsu -p aikatsu_mobile
cargo clippy --workspace --all-targets
cargo build -p aikatsu-core --bin aikatsu-plugin   # plugin CLI: aikatsu-plugin test|call|live <repo or .rhai>

cd mobile && flutter analyze && flutter test       # one file: flutter test test/helpers_test.dart
cd mobile && flutter run                            # Android device/emulator
cd mobile && RUSTFLAGS='--cfg reqwest_unstable' flutter_rust_bridge_codegen generate   # after changing mobile/rust/src/api/mod.rs

cd docs && npm ci && npm run dev                    # VitePress docs; `npm run build` checks dead links
```

- `.cargo/config.toml` sets `--cfg reqwest_unstable` (reqwest's HTTP/3, used by `core/src/proxy.rs`). Anything that builds the core outside this workspace's config, such as FRB codegen or a scratch crate depending on `aikatsu-core`, must pass that `RUSTFLAGS` itself. It also needs this repo's `Cargo.lock`, since some locked versions have since been yanked.
- **Run the desktop app headless and isolated:** `XDG_DATA_HOME=<scratch> QT_QPA_PLATFORM=offscreen ./target/debug/aikatsu --screenshot out.png --tab 3 --delay 3000`.
  - `--tab` selects a page: 0 Home, 1 Search, 2 Downloads, 3 Settings.
  - Other dev flags: `--room <n>` (Settings room: 0 Watch, 1 Library, 2 Sources, 3 Account, 4 General), `--plugins`, `--search <q> --open --play`, `--debug`.
  - `XDG_DATA_HOME` keeps runs out of the real history database; also set `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`, or the run overwrites the real `window.ini`. All three must be absolute paths: relative ones are silently ignored and the run uses the real data.
  - QML `console.*` output goes to the systemd journal when stderr isn't a terminal; set `QT_FORCE_STDERR_LOGGING=1` to see it.
  - `--screenshot` grabs the page, not popups; dialogs don't appear in it.
- **QML is compiled in.** `desktop/build.rs` registers every file under `desktop/qml/` in the `Aikatsu` QML module. A file containing `pragma Singleton` becomes a singleton. QML loads from qrc, so a QML edit needs `cargo build`.

## Architecture

One Rust core (`core/`) with two thin UIs: Qt Quick on desktop (`desktop/`, via cxx-qt) and Flutter on Android (`mobile/`, via flutter_rust_bridge). A cross-platform feature usually starts in `core/src/api.rs`, then touches both UIs. Mobile screens in `mobile/lib/pages/` are ports of `desktop/qml/pages/`.

**Core surface.** The UIs only call these:
- `aikatsu_core::init(dirs, debug, push)` at startup.
- `api::call` (async) and `api::get` (sync, quick), JSON in and out.
- Events that the core sends through `push(kind, json)`.

On desktop, `desktop/src/bridge.rs` exposes these to the `Api.qml` singleton. A failed `get` comes back as a `{ "error": … }` object, not an exception, so use `call` when the UI must tell an error apart from a result. On mobile, `mobile/lib/api.dart` is the Dart twin of `Api.qml`. Its generated bindings in `mobile/lib/src/rust/` must never be edited by hand.

History refreshes go through a revision counter on each side: `historyRevision` in `desktop/qml/Main.qml`, and `Api.historyRevision` in `api.dart`.

**Storage.** One SQLite file, `progress.db`, is owned by `core/src/db.rs`:
- `media_progress`: watch history, keyed by `episode_key`; the series key is `anilist:<id>`, else `<source>:<url>`.
- `settings`: key/value pairs.
- `cache`: remote lookups, read through `db::cached`.
- `downloads`: recorded download files.
- `sync_dirty`: unsent sync changes.

The UIs only see the settings listed in `SETTING_DEFAULTS` in `api.rs`. Other keys stay internal, such as the plugin repo list and the sync account. Schema migrations use `PRAGMA user_version` in `db::migrate`.

**Sources are plugins.** Each site is a Rhai script that `core/src/plugins.rs` loads from plugin repos. The official repo is Kyoko (https://github.com/KidiXDev/kyoko). Fix a broken site in its plugin repo, not in the core. Plugin updates are checked automatically but downloaded only when the user chooses. `core/src/sources.rs` holds the search and playback contract; the plugin API is documented in `docs/developers/`.

**HTTP.** `core/src/http.rs` has two clients:
- `CHROME` (wreq with a Chrome emulation) for scraping sites that block non-browsers;
- `PLAIN` for APIs.

Hosts that mpv can't play directly go through local relays in `core/src/proxy.rs`.

**Cloud sync.** The client is `core/src/sync.rs` plus the `sync_*` functions in `db.rs`. The server is a separate repo, `aikatsu-sync` (Bun + Elysia, SQLite or Postgres).
- Each history row and each synced setting is one record, and the newest change wins.
- The server never reads record data, so changing what syncs needs no server change.
- Local changes queue in `sync_dirty`, deletions included. A background loop in `sync::run` pushes and pulls every 2 minutes; the UIs also call `syncNow` when the player closes and when the mobile app resumes.
- Only keys in `sync::SYNCED_SETTINGS` sync.
- The default server is compiled in from the `AIKATSU_SYNC_SERVER` env var (a repo secret in `release.yml`) and is never shown in the UI. Without it, users must enter a server.

## Conventions

- **Formatting:** no rustfmt config. Neither the Rust nor the Dart sources are formatter-clean, so running `cargo fmt` or `dart format` on a whole file reflows unrelated code. Match the surrounding style (lines up to about 140 columns; `mobile/analysis_options.yaml` sets `page_width: 140`) and keep diffs to the lines you change.
- **Comments and UI copy:** comments explain a non-obvious *why*, not what the code does. Keep UI text short. `DESIGN.md` has the visual tokens: colours, radii, motion.
- **Docs:** user-visible behaviour is described in `docs/guide/*.md`. Update the matching page when behaviour changes.
- **Versions:** the root `Cargo.toml` `version` drives every crate. Keep `mobile/pubspec.yaml` and the workspace entries in `Cargo.lock` in step. A `v*` tag runs `.github/workflows/release.yml`, which builds Windows, Linux and Android.
- **Android release builds:** keep `--split-per-abi`. Each APK must carry only its own ABI's native libraries; see the README.
