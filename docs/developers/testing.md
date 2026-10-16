# Test the parser before you test the site

A parser test should be quick, repeatable, and useful when a website goes down. Keep network requests in the four entry points and move HTML or JSON parsing into helpers you can call with fixtures.

## Build the CLI

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

A repo directory means every script listed in its `index.json`. For `sources/example.rhai`, the CLI looks for `tests/example.rhai` beside the `sources` directory.

It merges the test file with the source script, discovers functions whose names start with `test_`, sorts them, and runs them without arguments. Each test gets a 30-second budget.

Three helpers are available only in tests:

```rust
assert(condition);
assert(condition, "What went wrong");
assert_eq(got, expected);
```

Keep fixture HTML small enough to explain the page structure. Good tests cover an ordinary result, missing optional data, an empty search, and the site's odd cases. A missing required test file is an error. Also make sure you've actually defined `test_` functions; a file with no such functions has nothing to run.

The CLI doesn't block network access during tests. They're offline only if your test functions avoid `page`, `fetch`, and other network helpers.

## Call one function

```sh
aikatsu-plugin call sources/example.rhai search "one piece"
aikatsu-plugin call sources/example.rhai heights "https://example.org/watch/1"
aikatsu-plugin call sources/example.rhai stream "https://example.org/watch/1" "720p"
```

The result is printed as JSON. Arguments from the command line are passed as strings, and a call gets a 60-second budget.

This is also handy for calling one of your own parser helpers while debugging. If that helper expects a number or a map, remember that the CLI isn't converting its string arguments into those types for you.

## Try the real site

```sh
aikatsu-plugin live sources/example.rhai frieren
aikatsu-plugin live /path/to/my-plugins "one piece"
```

A live check searches, takes the first result, loads its episodes, asks for qualities, and resolves the last episode in the sorted list with `"best"` quality. With no query, it uses `"one piece"`.

This checks a small playback path. It doesn't play the whole video or test every mirror, resolution, or anime. The CLI also lets a quality-list failure fall back to an empty list before trying stream resolution, so inspect the output instead of treating a successful live run as complete coverage.

Live checks need a real, adapted plugin. The downloadable teaching starter still points to `example.org`, so use its offline parser tests until you've changed it for an actual site.

## Refresh checksums

```sh
aikatsu-plugin index /path/to/my-plugins
```

This compiles every indexed source and updates its `sha256`. Run it after the final script edit. It doesn't run your tests, update the entry's version, or publish anything.

## Try it in the app

Publish a test repo on its default branch and add it in **Settings > Plugins**. Check that the source appears without a manual page refresh, then try search, episode selection, quality changes, and playback on the platforms you support.

For local development, the core also accepts a `file://` link ending in `index.json`. That's a development path, not a practical distribution method for phone users. The CLI is usually the easier way to iterate locally.

## Read the error, then the log

Put the source name in thrown errors. Use `print` for short diagnostics and `debug` for more detail. In the app, enable debug logging and restart before reproducing a problem.

On desktop, **Ctrl+L** opens the log. Android's Settings has a Logs screen and export action. Don't publish logs with sensitive headers, cookies, or tokens.
