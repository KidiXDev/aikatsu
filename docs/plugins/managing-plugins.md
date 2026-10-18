# Manage your sources

Open **Settings > Plugins** on Android. On desktop, choose **Manage** next to Plugins in Settings.

## Add a repo

Choose **Add** and paste a GitHub repo link, such as:

```text
https://github.com/your-name/your-plugin-repo
```

Aikatsu checks the repo's index before adding it. For third-party repos, you'll see a trust prompt with the repo and its sources. Accept only if you trust the author. Kyoko skips this prompt because it is the official repo.

The app installs the scripts and refreshes the list when it's done. You don't need to run another check or reopen the page. If only some scripts fail, the repo stays listed with an error so you can see what happened.

GitHub links use the repo's default branch. Pasting a `/tree/some-branch` link doesn't pin that branch. Developers can also use a direct HTTPS link ending in `index.json`.

### Test a local repo

Turn on **Developer Mode** in Settings. It is off by default. Then choose **Add** and paste a file URL such as `file:///F:/APPS/kyoko/index.json`. On desktop, **Choose folder** lets you select the repo folder containing `index.json`. Local repos use the same trust confirmation and checksum checks as remote repos.

Repo IDs must be unique. If your local Kyoko copy uses the `kyoko` ID, remove the installed Kyoko repo entry before adding it, or give the test repo its own ID.

After editing a script, regenerate its index checksum with `aikatsu-plugin index <repo folder>`, then check for updates and download them in Aikatsu. Local installs and updates require Developer Mode. Installed sources keep working after you turn it off.

## Check, then download

The refresh icon is **Check for updates**. It fetches repo metadata and leaves installed scripts alone.

When updates are available, a **download icon** appears beside it, and each repo shows its update count. That button installs available changes across the repos you've added. It disappears once no changes remain.

The message under each repo shows whether an update is available, installed, or failed. Check it for errors if a check or download fails.

## Turn off startup checks

In Settings, switch off **Check for plugin updates on startup**. You can still open Plugins and use the manual check button whenever you want.

Turning that setting off doesn't disable installed sources. It only stops the automatic check when the app starts.

## Disable one source

Use the switch beside a loaded plugin. That leaves it installed but removes it from searches. You can turn it back on later.

A plugin that needs a newer API shows **Needs a newer Aikatsu**. A source awaiting its first download can show **Download to enable**. A script that couldn't be loaded doesn't get a normal enabled-source switch.

## Remove a repo

Choose **Remove** beside the repo and confirm. Its installed sources disappear from the available source list.

Removing a repo doesn't erase your watch history or downloaded video files. History entries that use that source may need the repo installed again for online playback.

## When you're offline

Already installed scripts stay available if checking a repo fails. Streaming still needs access to the source and video host. For offline watching, use downloaded episodes instead.
