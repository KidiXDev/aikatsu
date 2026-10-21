# Publish a plugin repo

Publish an `index.json` and its source scripts in a public GitHub repo or on an HTTPS host. Users add the repo directly in Aikatsu. No plugin store submission is required.

## The index

The starter includes this index with its script's checksum:

<<< @/public/examples/hello-source/index.json

| Field | Description |
| --- | --- |
| `id` | Stable ID for the repo |
| `name` | Human-readable repo name |
| `plugins` | The source entries this repo supplies |
| `key` | Stable source key within this repo |
| Plugin `name` | Source name shown in the app |
| `version` | Integer version for your source, not a semver string |
| `api` | Minimum Aikatsu host API required by the script |
| `file` | Script path resolved relative to the index URL |
| `sha256` | SHA-256 of the exact script bytes |

Repo IDs and source keys must be 1 to 32 characters of lowercase letters, digits, hyphens, or underscores. Keys must be unique within an index, and added repos can't share a repo ID. Names can't be blank. Each checksum needs exactly 64 hexadecimal characters.

If omitted, `version` defaults to `0` and `api` to `1`. Include both fields explicitly. The current host supports API 1.

Keep the repo ID and source keys stable. Aikatsu builds an identity such as `hello-source/example` from them, and history, downloads, and source settings refer to that identity. Renaming the display name is different from changing the ID.

## GitHub layout

Put `index.json` at the root of the repo and list paths such as `sources/example.rhai`.

When a user adds:

```text
https://github.com/your-name/your-plugin-repo
```

Aikatsu requests:

```text
https://raw.githubusercontent.com/your-name/your-plugin-repo/HEAD/index.json
```

Both plain repo links and GitHub `/tree/branch-name` links use the default branch. Release tags alone don't publish an update to that default-branch index.

For another HTTPS host, share a direct index URL ending in `.json`, with script paths that resolve from it. Use URLs the app can access without a browser session or GitHub login.

## Publish an update

1. Fix the script and its fixture tests.
2. Run `aikatsu-plugin test` and any relevant live checks.
3. Bump the entry's integer `version` so people can track the change.
4. Run `aikatsu-plugin index` to calculate the final checksum.
5. Commit the script and updated index together, then push to the default branch.
6. In Aikatsu, check for updates and download them to verify the release path.

Aikatsu compares metadata and file hashes, so it can detect changed scripts without a version bump. Increase the version anyway so users and maintainers can identify the update.

Never change the script after hashing it without regenerating the index. Even line-ending changes alter the hash.

## Update behavior

A startup or manual check fetches your index and reports the number of available changes. It doesn't install your script.

When users download updates from Plugins, Aikatsu fetches changed scripts, checks their hashes, compiles them, and loads the updated sources. Files whose hashes already match don't need another script download. Source removals in the new index are applied during installation too.

A bad checksum or compilation failure doesn't replace the previous working script. A repo can still show partial errors when some sources updated and another failed. Offline users keep the scripts they already have.

## Host API compatibility

Increase `api` only when the plugin requires a newer host API. Script updates alone do not need an API version change.

If a feature needs a host API that isn't available yet, it requires an Aikatsu change first. Scripts asking for an API newer than the installed app supports are skipped and shown as needing a newer Aikatsu.

## Check updates in CI

In CI, build the Aikatsu plugin CLI and run `test` against your repo. Run `index` and check for a diff to catch stale checksums.

Run live tests separately from fixture tests so you can tell a site outage from a parser bug. Passing fixture tests do not confirm that the site is reachable.
