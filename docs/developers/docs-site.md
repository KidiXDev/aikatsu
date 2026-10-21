# Edit the docs

The documentation site lives in `docs/` and uses VitePress with the default theme, local search, and sakura colors. It builds independently of the app.

## Run it locally

Use Node.js 22.12 or newer. From the repo root:

```sh
cd docs
npm ci
npm run dev
```

VitePress prints the local URL, usually `http://localhost:5173/aikatsu/`. Markdown changes appear automatically in the browser.

VitePress is pinned to the prerelease `2.0.0-alpha.20`. Keep the lockfile and verify the site build after dependency updates.

## Build and preview

```sh
npm run build
npm run preview
```

The build checks internal page links and writes the static site to `docs/.vitepress/dist/`. Deploy that directory to a static host. No Rust core or application server is required.

The site uses `/aikatsu/` as its base path for GitHub Pages. If you move it to a custom domain or another subdirectory, change the `base` constant in `.vitepress/config.ts` and rebuild. A site at the host's root needs `const base = '/'`.

## GitHub Pages deployment

The live site is [kidixdev.github.io/aikatsu](https://kidixdev.github.io/aikatsu/).

The **Deploy docs** workflow in `.github/workflows/docs.yml` runs when changes to `docs/` or that workflow reach `main`. It installs the locked dependencies with Node.js 24, builds the site, and deploys the generated files through GitHub's Pages artifact flow.

You can also run it manually from GitHub Actions, or from a checkout with an authenticated GitHub CLI:

```sh
gh workflow run docs.yml --ref main
```

Pages uses **GitHub Actions** as its publishing source. The workflow uses the `github-pages` environment and GitHub's built-in token, so no personal token needs to be saved as a repository secret.

## Site files

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

## Writing guidelines

Use direct instructions and the control names shown in the app. Keep headings descriptive and paragraphs focused on one task. Explain differences between desktop and Android, and mention dependencies on sources or metadata services where they affect the feature.

Test code samples and mark placeholder URLs as examples. Use periods or commas instead of em dashes and semicolons in prose. State when sign-in or a manual plugin download is required.
