# Publish a plugin repo

Aikatsu needs a repo index and the scripts it points to. You can host them in a public GitHub repo or serve an index and scripts over HTTPS. There's no separate plugin store submission step.

## The index

Here's the starter's complete index, including its real script checksum:

<<< @/public/examples/hello-source/index.json

| Field | What it means |
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

`version` defaults to `0` and `api` defaults to `1` when omitted, but it's clearer to write both. The current host supports **API 1**.

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

That means the default branch. A GitHub `/tree/branch-name` URL is normalized back to the repo; it doesn't select a custom branch. Release tags alone don't publish an update to that default-branch index.

For another HTTPS host, share a direct index URL ending in `.json`, with script paths that resolve from it. This isn't an authenticated-repo login flow, so don't assume a user's browser session or GitHub login will be available to the app.

## Ship an update

1. Fix the script and its fixture tests.
2. Run `aikatsu-plugin test` and any relevant live checks.
3. Bump the entry's integer `version` so people can track the change.
4. Run `aikatsu-plugin index` to calculate the final checksum.
5. Commit the script and updated index together, then push to the default branch.
6. In Aikatsu, check for updates and download them to verify the release path.

The host compares metadata and actual file hashes. A script can be recognized as changed even if you forgot to bump its version, but keeping the version meaningful makes maintenance easier.

Never change the script after hashing it without regenerating the index. Line-ending changes count too, because the hash covers bytes rather than how the code looks.

## What users see

A startup or manual check fetches your index and reports the number of available changes. It doesn't install your script.

The Plugins page's download action fetches changed scripts, checks their hashes, compiles them, and reloads the source registry. Files whose hashes already match don't need another script download. Source removals in the new index are applied during installation too.

A bad checksum or compilation failure doesn't replace the previous working script. A repo can still show partial errors when some sources updated and another failed. Offline users keep the scripts they already have.

## When you need a new host function

Don't raise `api` just because your own source changed. It describes the host functions the plugin needs.

If a feature needs a host API that isn't available yet, it requires an Aikatsu change first. Scripts asking for an API newer than the installed app supports are skipped and shown as needing a newer Aikatsu.

## A small CI checklist

Your repo's CI can build the Aikatsu plugin CLI and run `test` against your repo. It's also useful to run `index` and check that it leaves no diff, which catches forgotten checksum updates.

Keep live tests separate from fixture tests. A site's downtime shouldn't hide a real parser regression, and a passing fixture test shouldn't pretend the site is reachable.
