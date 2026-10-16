# Where your sources come from

A plugin teaches Aikatsu how to search an anime site, list its episodes, find available resolutions, and turn an episode page into a playable video URL.

Plugins are small Rhai scripts. They run in Aikatsu's shared Rust core, so the same script can support desktop and Android.

## Plugin, source, repo: what's the difference?

- A **source** is a site you can search and watch from.
- A **plugin** is the script that supports that source.
- A **repo** groups scripts with an `index.json` that describes them and records their checksums.

In everyday use, a source and its plugin are almost the same thing. You add a repo, then switch its individual sources on or off.

## Kyoko

[Kyoko](https://github.com/KidiXDev/kyoko) is the official plugin repo. It's listed by default, and you can remove it or add it again from the Plugins page.

A repo can contain several sources. You're free to leave only the ones you use enabled.

## Updates need your say-so

Aikatsu checks repos at startup when the setting is enabled. It reads their indexes and counts available plugin changes. It doesn't install those changes or change the running scripts during a check.

If something is available, a dialog offers **Later** or **View updates**. The Plugins page shows a download icon. Use it to apply available updates across your added repos.

You can also check manually, even with startup checks switched off. Adding a new repo is an explicit install action and downloads its scripts straight away.

## What a plugin can access

Plugins can make network requests, parse HTML and JSON, process strings, and keep a small temporary cache. They can't read your watch history, settings, or arbitrary files through the host API.

They can still send searches and playback requests to websites and choose the video URLs the app opens. Add third-party repos only if you trust their authors. A checksum checks that a download matches its index; it isn't a promise that the author or script is trustworthy.

## Want to make one?

You don't need to rebuild the whole app for each source change. Start with [your first plugin](../developers/first-plugin.md), test it with the CLI, and publish a repo people can add in Settings.
