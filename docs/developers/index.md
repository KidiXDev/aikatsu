# Develop plugins and app features

## What is Rhai?

[Rhai](https://rhai.rs/book/index.html) is a scripting language designed to run inside Rust applications. Its syntax resembles JavaScript and Rust, with functions, variables, arrays, and maps. Aikatsu source plugins are plain text files with a `.rhai` extension.

Aikatsu runs these scripts and supplies functions for fetching pages, parsing HTML and JSON, and resolving video URLs. You don't need to install a separate Rhai interpreter. The engine is included in the app and the plugin CLI.

## Why Aikatsu uses it

Anime sites change their page layouts and video links. Keeping each site's search and playback logic in a script lets its author fix and publish that source without rebuilding Aikatsu. Users install the updated plugin separately from app updates.

The shared Rust core runs the same scripts on desktop and Android. The CLI uses that engine too, so you can test a plugin before loading it into either app. Each source implements four required functions: `search`, `episodes`, `heights`, and `stream`.

## What you need installed

| What you want to work on | What to prepare |
| --- | --- |
| Source plugins | A text editor, an Aikatsu checkout, and Rust with the native tools needed to build the plugin CLI. Follow [the plugin setup](./first-plugin.md#before-you-start). |
| Shared Rust core | The same Rust build environment. Qt and Flutter are needed when you build their respective interfaces. |
| Desktop app | Rust, Qt, libmpv development files, and your platform's C/C++ build tools. See [the app build guide](./building-aikatsu.md). |
| Android app | Rust, Flutter, a JDK, and the Android SDK/NDK toolchain. See [the Android setup](./building-aikatsu.md#android). |
| Documentation | Node.js 22.12 or newer and npm. See [the docs setup](./docs-site.md). |

For plugin work, familiarity with HTML, CSS selectors, HTTP requests, and JSON will help you read a site's responses. The [Rhai book](https://rhai.rs/book/index.html) covers the language itself. Aikatsu's extra functions are in the [host API reference](./host-api.md).

## If you're adding a site

Start with [your first plugin](./first-plugin.md). It walks through a small repo you can copy, run offline, and adapt to a real site.

Use these references as you work:

- [Plugin function contract](./plugin-contract.md) for inputs and return values.
- [Host API](./host-api.md) for network, parsing, URL, and cache helpers.
- [Testing](./testing.md) for fixtures, live checks, and debugging.
- [Publishing](./publishing.md) for `index.json`, checksums, and repo updates.

## If you're changing the app

The [app build guide](./building-aikatsu.md) covers the shared core, both interfaces, and their build commands.

Most shared behavior lives in `core/`. Desktop and mobile talk to it through JSON methods and receive events. Fix site layout changes in the plugin. Add host functions and player features in the app.

## Useful source links

- [Plugin engine and repo handling](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugins.rs)
- [Source types and playback contract](https://github.com/KidiXDev/aikatsu/blob/main/core/src/sources.rs)
- [Plugin CLI](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugin_cli.rs)
- [Kyoko's source plugins](https://github.com/KidiXDev/kyoko)

These docs describe the current host API, **API 1**. A plugin's `api` field is separate from Aikatsu's app version and your plugin's own version number.
