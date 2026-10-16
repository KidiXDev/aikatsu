# Build a source, or work on Aikatsu

A new source usually needs a plugin, not changes to the app. Plugins are Rhai scripts with four required functions, and the CLI runs them through the same engine that desktop and Android use.

## If you're adding a site

Start with [your first plugin](./first-plugin.md). It walks through a small repo you can copy, run offline, and adapt to a real site.

Keep these pages nearby:

- [Plugin function contract](./plugin-contract.md) for inputs and return values.
- [Host API](./host-api.md) for network, parsing, URL, and cache helpers.
- [Testing](./testing.md) for fixtures, live checks, and debugging.
- [Publishing](./publishing.md) for `index.json`, checksums, and repo updates.

You don't need Qt or Flutter just to write a plugin. You do need a working Rust build environment to build the CLI from Aikatsu's source.

## If you're changing the app

The [app build guide](./building-aikatsu.md) covers the shared core, both interfaces, and their build commands.

Most shared behavior lives in `core/`. Desktop and mobile talk to it through JSON methods and receive events. A plugin change is usually the right fix for a site's new HTML layout; a new host function or player feature belongs in the app.

## Useful source links

- [Plugin engine and repo handling](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugins.rs)
- [Source types and playback contract](https://github.com/KidiXDev/aikatsu/blob/main/core/src/sources.rs)
- [Plugin CLI](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugin_cli.rs)
- [Kyoko's source plugins](https://github.com/KidiXDev/kyoko)

These docs describe the current host API, **API 1**. A plugin's `api` field is separate from Aikatsu's app version and your plugin's own version number.
