# Get started

Install Aikatsu and a source plugin to start watching. No account is needed.

## Install Aikatsu

Download the latest release from [GitHub Releases](https://github.com/KidiXDev/aikatsu/releases/latest).

### Windows

Download `windows-x64-setup.exe` and run it. Read and accept the license agreement, then choose an installation folder. No admin rights are needed for the default folder. The installer adds Start menu and desktop shortcuts.

Aikatsu offers [updates](./settings.md#app-updates) in the app. To uninstall, open **Settings > Apps** in Windows. Updating or uninstalling keeps your history and settings.

To run Aikatsu without installing it, download the Windows ZIP instead, unpack it, and run `aikatsu.exe` from the extracted folder. Keep the other files beside it. The app needs those libraries to start.

### Linux

Download the AppImage, give it permission to run, and open it:

```sh
chmod +x Aikatsu-*.AppImage
./Aikatsu-*.AppImage
```

You can also build the app yourself. The [build guide](../developers/building-aikatsu.md) covers the dependencies.

### Android

Download the `android-arm64-v8a.apk` for most current phones. Older 32-bit devices need the `armeabi-v7a.apk` instead. Open the APK and allow installation from your browser or file manager if Android asks.

## Install your first sources

1. Open **Settings > Plugins**. On desktop, open **Sources** and choose **Manage**.
2. Kyoko, the official source repo, is listed by default.
3. If its sources haven't been downloaded yet, use **Check for updates**, then tap or click the **download icon**.
4. Wait for installation to finish. The source list updates as soon as it's ready.

If Kyoko has been removed, choose **Add Kyoko** to add it again. You can also [add another plugin repo](../plugins/managing-plugins.md).

::: tip Checks don't install anything
At startup, Aikatsu can tell you how many plugin updates are available. Choose **View updates** to open Plugins, then use the download icon when you're ready. You can turn startup checks off in Settings.
:::

## Play an episode

Open **Search**, enter at least two characters, and submit your search. Results arrive source by source. Pick a show, choose an episode, and press play.

If a source fails, try another. Each source uses a separate site.

## Choose your settings

- **Preferred quality** sets your starting preference. Auto lets the app pick.
- **Autoplay next episode** controls the end-of-episode countdown.
- **Skip intro & outro** enables automatic skipping when timing data is available.
- **Theme** follows your system or stays light or dark.
- **Sync** keeps your history the same on your phone and computer. See [sync between devices](./sync.md).

You can change these anytime in [Settings](./settings.md).
