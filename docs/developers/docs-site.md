# Work on these docs

The site lives entirely in `docs/`. It uses VitePress's default theme, local search, and a small set of sakura color overrides. No app build is needed.

## Run it locally

Use Node.js 22.12 or newer. From the repo root:

```sh
cd docs
npm ci
npm run dev
```

VitePress prints the local URL, usually `http://localhost:5173/aikatsu/`. Changes to Markdown show up while you write.

The dependency is pinned to VitePress `2.0.0-alpha.20`, the current `next` release used by its setup guide. It's a prerelease, so keep the lockfile and check the build when updating it.

## Build and preview

```sh
npm run build
npm run preview
```

The static site is written to `docs/.vitepress/dist/`. The build checks internal page links. You can host that directory with a static web host; it doesn't need the Rust core or a server-side app.

The site uses `/aikatsu/` as its base path for GitHub Pages. If you move it to a custom domain or another subdirectory, change the `base` constant in `.vitepress/config.ts` and rebuild. A site at the host's root needs `const base = '/'`.

## GitHub Pages deployment

The live site is [kidixdev.github.io/aikatsu](https://kidixdev.github.io/aikatsu/).

The **Deploy docs** workflow in `.github/workflows/docs.yml` runs when changes to `docs/` or that workflow reach `main`. It installs the locked dependencies with Node.js 24, builds the site, and deploys the generated files through GitHub's Pages artifact flow.

You can also run it manually from GitHub Actions, or from a checkout with an authenticated GitHub CLI:

```sh
gh workflow run docs.yml --ref main
```

Pages uses **GitHub Actions** as its publishing source. The workflow uses the `github-pages` environment and GitHub's built-in token, so no personal token needs to be saved as a repository secret.

## Where to edit

- `guide/` explains the app for people using it.
- `plugins/` covers source management and update behavior.
- `developers/` covers plugin authoring and app development.
- `.vitepress/config.ts` defines navigation and the sidebar.
- `.vitepress/theme/custom.css` holds the color overrides.
- `public/examples/hello-source/` contains the downloadable starter.

The tutorial imports the actual example files as code snippets. Keep them runnable, update their checksums after edits, and test them with:

```sh
# From the Aikatsu repo root, not docs/
cargo run -p aikatsu-core --bin aikatsu-plugin -- test docs/public/examples/hello-source
cargo run -p aikatsu-core --bin aikatsu-plugin -- index docs/public/examples/hello-source
```

## Keep the writing easy to follow

Write like you're helping someone use the app beside you. Use the control names they can see, explain platform differences, and say when a feature depends on a source or metadata service.

Keep examples honest. A made-up URL should be marked as an example, and a working code sample should have a small test. Avoid em dashes and don't claim account sync, automatic plugin installation, or other behavior the app doesn't have.
