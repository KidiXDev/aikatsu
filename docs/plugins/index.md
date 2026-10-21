# Sources and plugins

Source plugins let Aikatsu search anime sites and play their videos. Each plugin is a small Rhai script that runs on desktop and Android.

## Terms

- A **source** is a site you can search and watch from.
- A **plugin** is the script that supports that source.
- A **repo** groups scripts with an `index.json` that describes them and records their checksums.

Add a repo to install its plugins, then enable the sources you want to use.

## Kyoko

[Kyoko](https://github.com/KidiXDev/kyoko) is the official plugin repo. It's listed by default, and you can remove it or add it again from the Plugins page.

A repo can contain several sources. Enable only the ones you use.

## Check and install updates

With startup checks enabled, Aikatsu checks your repos and shows how many updates are available. Your installed plugins stay as they are until you download the updates.

If something is available, a dialog offers **Later** or **View updates**. The Plugins page shows a download icon. Use it to apply available updates across your added repos.

You can also check manually, even with startup checks switched off. Adding a new repo downloads its scripts right away.

## What a plugin can access

Plugins can make network requests, parse HTML and JSON, process strings, and keep a small temporary cache. They can't read your watch history, settings, or arbitrary files through the host API.

They can still send searches and playback requests to websites and choose the video URLs the app opens. Add third-party repos only if you trust their authors. Checksums confirm that downloads match the repo index. They do not prove a script is safe.

## Write a plugin

Source plugins can be updated without rebuilding the app. Start with [your first plugin](../developers/first-plugin.md), test it with the CLI, and publish a repo people can add in Settings.
