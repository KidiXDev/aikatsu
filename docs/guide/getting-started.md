# Get started

Aikatsu needs at least one source plugin to stream anime. Install the app, download a source, then search for a show. You can watch without an account.

## Install Aikatsu

Download the latest release from [GitHub Releases](https://github.com/KidiXDev/aikatsu/releases/latest).

### Windows

Download `windows-x64-setup.exe` and run it. Read and accept the license agreement, then choose an installation folder. No admin rights are needed for the default folder. The installer adds Start menu and desktop shortcuts.

Aikatsu offers [updates](./settings.md#app-updates) in the app. To uninstall, open **Settings > Apps** in Windows. Updating or uninstalling keeps your history and settings.

To run Aikatsu without installing it, download the Windows ZIP instead, unpack it, and run `aikatsu.exe` from the extracted folder. Keep the other files beside it. The app needs those libraries to start.

### macOS

Aikatsu runs on Macs with Apple silicon and macOS 14 or later. Download `macos-arm64.dmg`, open it, and drag Aikatsu to Applications.

Aikatsu isn't notarized by Apple, so macOS blocks it the first time. Open it once, then go to **System Settings > Privacy & Security** and choose **Open Anyway**. When macOS asks whether Aikatsu may find devices on your local network, allow it if you [share folders](./local-library.md#watch-your-desktop-folders-on-your-phone) with your phone.

To update, download the new `.dmg` and replace the app in Applications. Your history and settings stay.

### Linux

Download the AppImage, give it permission to run, and open it:

```sh
chmod +x Aikatsu-*.AppImage
./Aikatsu-*.AppImage
```

The AppImage updates itself. On Debian, Ubuntu and their derivatives, you can install the `.deb` instead; it adds Aikatsu to your app menu:

```sh
sudo apt install ./Aikatsu-*-linux-amd64.deb
```

The `.tar.gz` runs without installing: unpack it and run `aikatsu/AppRun`. Both need a current distribution, such as Ubuntu 24.04 or Debian 13, and update by installing the newer file.

You can also build the app yourself. The [build guide](../developers/building-aikatsu.md) covers the dependencies.

### Android

Download the `android-arm64-v8a.apk` for most current phones. Older 32-bit devices need the `armeabi-v7a.apk` instead. Open the APK and allow installation from your browser or file manager if Android asks.

On first launch, a short welcome offers **Create account** or **Sign in** for [sync](./sync.md). Choose **Skip** to use Aikatsu without an account; you can sign in later in Settings.

## Install sources

1. Open **Settings > Plugins**. On desktop, open **Sources** and choose **Manage**.
2. Kyoko, the official source repo, is listed by default.
3. If its sources haven't been downloaded yet, use **Check for updates**, then tap or click the **download icon**.
4. Wait for installation to finish. The source list updates as soon as it's ready.

If Kyoko has been removed, choose **Add Kyoko** to add it again. You can also [add another plugin repo](../plugins/managing-plugins.md).

Startup checks report available plugin updates. To install them, choose **View updates**, then use the download icon in Plugins. You can disable startup checks in Settings.

## Play an episode

Open **Search**, enter at least two characters, and submit. Results appear as each source responds. Select a show, choose an episode, and press play. If a source fails, try another source. Each uses a separate site.

## Playback and sync settings

- **Preferred quality** sets your starting preference. Auto lets the app pick.
- **Autoplay next episode** controls the end-of-episode countdown.
- **Skip intro & outro** enables automatic skipping when timing data is available.
- **Theme** follows your system or stays light or dark.
- **Sync** keeps your history the same on your phone and computer. See [sync between devices](./sync.md).

See [Settings](./settings.md) for all options.
