# Develop plugins and app features

To add an anime site, write a Rhai plugin with four required functions. Test it with the CLI, which uses the same engine as desktop and Android.

## If you're adding a site

Start with [your first plugin](./first-plugin.md). It walks through a small repo you can copy, run offline, and adapt to a real site.

Use these references as you work:

- [Plugin function contract](./plugin-contract.md) for inputs and return values.
- [Host API](./host-api.md) for network, parsing, URL, and cache helpers.
- [Testing](./testing.md) for fixtures, live checks, and debugging.
- [Publishing](./publishing.md) for `index.json`, checksums, and repo updates.

You don't need Qt or Flutter just to write a plugin. You do need a working Rust build environment to build the CLI from Aikatsu's source.

## If you're changing the app

The [app build guide](./building-aikatsu.md) covers the shared core, both interfaces, and their build commands.

Most shared behavior lives in `core/`. Desktop and mobile talk to it through JSON methods and receive events. Fix site layout changes in the plugin. Add host functions and player features in the app.

## Useful source links

- [Plugin engine and repo handling](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugins.rs)
- [Source types and playback contract](https://github.com/KidiXDev/aikatsu/blob/main/core/src/sources.rs)
- [Plugin CLI](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugin_cli.rs)
- [Kyoko's source plugins](https://github.com/KidiXDev/kyoko)

These docs describe the current host API, **API 1**. A plugin's `api` field is separate from Aikatsu's app version and your plugin's own version number.
