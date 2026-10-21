# Plugin testing and debugging

Test parsers with saved HTML or JSON. This lets you reproduce parsing errors without depending on the site. Keep network requests in the four entry points and pass fixtures directly to parser helpers.

## Build the CLI

Complete [the CLI prerequisites](./first-plugin.md#before-you-start) first. You don't need to build either app interface to run these checks.

From the Aikatsu checkout:

```sh
cargo build -p aikatsu-core --bin aikatsu-plugin
```

The examples below use `aikatsu-plugin` as the command name. Substitute the full binary path, such as `./target/debug/aikatsu-plugin` from the Aikatsu root, or put it on PATH.

## Run offline tests

```sh
aikatsu-plugin test /path/to/my-plugins
aikatsu-plugin test /path/to/my-plugins/sources/example.rhai
```

Passing a repo directory tests every script listed in its `index.json`. For `sources/example.rhai`, the CLI looks for `tests/example.rhai` beside the `sources` directory.

The CLI merges each test file with its source script and runs functions whose names start with `test_`. Functions run in sorted order, without arguments, and have a 30-second limit each.

Three helpers are available only in tests:

```rust
assert(condition);
assert(condition, "What went wrong");
assert_eq(got, expected);
```

Use small fixtures that show the relevant page structure. Cover normal results, missing optional data, empty searches, and unusual cases from the site. Each required test file must exist and define at least one `test_` function.

The CLI doesn't block network access during tests. They're offline only if your test functions avoid `page`, `fetch`, and other network helpers.

## Call a function

```sh
aikatsu-plugin call sources/example.rhai search "one piece"
aikatsu-plugin call sources/example.rhai heights "https://example.org/watch/1"
aikatsu-plugin call sources/example.rhai stream "https://example.org/watch/1" "720p"
```

The command prints its result as JSON and has a 60-second limit. You can call parser helpers too, but all command-line arguments are passed as strings, including those intended as numbers or maps.

## Try the real site

```sh
aikatsu-plugin live sources/example.rhai frieren
aikatsu-plugin live /path/to/my-plugins "one piece"
```

A live check searches, takes the first result, loads its episodes, asks for qualities, and resolves the last episode in the sorted list with `"best"` quality. With no query, it uses `"one piece"`.

Live checks resolve one episode without playing it. They do not cover every mirror, resolution, or anime. If listing qualities fails, the CLI still tries to resolve the stream with an empty quality list. Read the output for errors even when the check passes.

Adapt the starter to a real site before running live checks. Its `example.org` URLs are placeholders for offline parser tests.

## Refresh checksums

```sh
aikatsu-plugin index /path/to/my-plugins
```

This compiles every indexed source and updates its `sha256`. Run it after the final script edit. It doesn't run your tests, update the entry's version, or publish anything.

## Try it in the app

Publish a test repo on its default branch and add it in **Settings > Plugins**. Check that the source appears without a manual page refresh, then try search, episode selection, quality changes, and playback on the platforms you support.

For local development, enable **Developer Mode** in Settings to install or update a repo through a `file://` link ending in `index.json`. On desktop, the Add plugins dialog also offers **Choose folder**. Use local repos for development and publish an HTTPS repo for phone users. The CLI does not require Developer Mode and is usually simpler for local testing.

## Errors and logs

Put the source name in thrown errors. Use `print` for short diagnostics and `debug` for more detail. In the app, enable debug logging and restart before reproducing a problem.

On desktop, **Ctrl+L** opens the log. Android's Settings has a Logs screen and export action. Don't publish logs with sensitive headers, cookies, or tokens.
