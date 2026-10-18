<script setup>
import { withBase } from 'vitepress'
</script>

# Your first plugin

Copy the starter repo to build your first source plugin. It uses a made-up site at `example.org` and has offline parser tests. Replace its URL and selectors to support a real site.

## Get the CLI ready

From an Aikatsu checkout:

```sh
cargo build -p aikatsu-core --bin aikatsu-plugin
```

The binary is `target/debug/aikatsu-plugin`, or `target/debug/aikatsu-plugin.exe` on Windows. This builds the core CLI without the Qt or Flutter interfaces. You still need Rust and the native build tools its dependencies use.

Run the starter tests:

```sh
cargo run -p aikatsu-core --bin aikatsu-plugin -- test docs/public/examples/hello-source
```

All five tests should pass without making a network request.

## Copy the starter

The files are included at `docs/public/examples/hello-source/` in this checkout. Copy that folder into your own repo, or download each file:

- <a :href="withBase('/examples/hello-source/index.json')" download>index.json</a>
- <a :href="withBase('/examples/hello-source/sources/example.rhai')" download>sources/example.rhai</a>
- <a :href="withBase('/examples/hello-source/tests/example.rhai')" download>tests/example.rhai</a>

Keep this layout so the CLI can find the tests:

```text
hello-source/
├── index.json
├── sources/
│   └── example.rhai
└── tests/
    └── example.rhai
```

## Read the source script

The app calls `search`, `episodes`, `heights`, and `stream`. This starter keeps parsing in separate functions so tests can give them HTML directly.

<<< @/public/examples/hello-source/sources/example.rhai{rust}

The example expects search cards with `.anime-card`, episode links with `a.episode`, and direct video sources inside `<video>`. Real sites often use different markup, embeds, or JSON endpoints. Replace the selectors to match your site's pages.

## Adapt it to a real site

1. Change `BASE` to the site's actual URL.
2. Save small HTML examples from its search, series, and episode pages.
3. Update each parser to match those pages.
4. Return absolute URLs. A relative URL alone won't tell the player which host to use.
5. Resolve the real media URL in `stream`, not just the watch-page URL.
6. Keep the site's name in errors so people know which source failed.

`page` and `fetch` make HTTP requests. They don't run a site's JavaScript like a browser. If JavaScript builds the video URL, reproduce the requests or parsing needed to get it.

## Keep parser tests close

The starter includes these parser tests:

<<< @/public/examples/hello-source/tests/example.rhai{rust}

The tests call `parse_search`, `parse_episodes`, and `parse_sources` with saved HTML, so you can test parser changes offline.

The app sorts episodes by number after reading the result, so a parser doesn't have to return them in order. Still, each number should refer to the right episode.

## Refresh the index

After editing a script, run the CLI's `index` command against your repo folder. For the included example, from the Aikatsu root:

```sh
cargo run -p aikatsu-core --bin aikatsu-plugin -- index docs/public/examples/hello-source
```

For your own repo, replace that last path. The command compiles each listed script and recalculates its SHA-256. It doesn't bump your plugin version automatically.

Once your offline tests pass, try a [live check](./testing.md#try-the-real-site), then [publish the repo](./publishing.md).
