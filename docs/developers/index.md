# Development

Aikatsu uses a shared Rust core with Qt and Flutter interfaces. Anime sites are supported through Rhai plugins. Each plugin implements four required functions and can be tested with the CLI using the same engine as both apps.

## Source plugins

Start with [your first plugin](./first-plugin.md) to copy a starter repo, run its offline tests, and adapt it to a site. The reference pages cover:

- [Plugin function contract](./plugin-contract.md) for inputs and return values.
- [Host API](./host-api.md) for network, parsing, URL, and cache helpers.
- [Testing](./testing.md) for fixtures, live checks, and debugging.
- [Publishing](./publishing.md) for `index.json`, checksums, and repo updates.

Building the plugin CLI requires Rust and its native build tools. Qt and Flutter are not required.

## App development

The [app build guide](./building-aikatsu.md) covers the shared core, both interfaces, and their build commands.

Most shared behavior lives in `core/`. Both interfaces call JSON methods and receive events from the core. Site layout fixes belong in plugins. New host functions and player features require app changes.

## Source code

- [Plugin engine and repo handling](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugins.rs)
- [Source types and playback contract](https://github.com/KidiXDev/aikatsu/blob/main/core/src/sources.rs)
- [Plugin CLI](https://github.com/KidiXDev/aikatsu/blob/main/core/src/plugin_cli.rs)
- [Kyoko's source plugins](https://github.com/KidiXDev/kyoko)

The current host API is API 1. A plugin's `api` field refers to this API version, independently of the app version and the plugin's own version.
