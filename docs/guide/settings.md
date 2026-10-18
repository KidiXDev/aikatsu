# Adjust your settings

Settings are stored on each device. Desktop and Android share most options. Sign in to [sync](./sync.md), and your history and most settings follow you between them.

Desktop Settings has five sections: **General**, **Watch**, **Library**, **Sources**, and **Account**. Each shows a summary, such as your preferred quality or last sync time.

## Sync

**Sync** signs you in to keep watch history and settings the same on your phone and computer. It's under **Account** on desktop and at the top of Settings on Android. See [sync between devices](./sync.md) for what follows you and what stays per device.

## Appearance and playback

| Setting | What it changes | Default |
| --- | --- | --- |
| Theme | Follow the system, or stay light or dark | System |
| Autoplay next episode | Continue after the end-of-episode countdown | On |
| Skip intro & outro | Skip known opening and ending segments automatically | Off |
| Preferred quality | Your starting playback quality preference | Auto |
| Sharpen video (Anime4K) | Apply a video-processing preset | Off |

Player quality changes are remembered too. Available resolutions and tracks still depend on the source.

On desktop, find Theme in **General** and the playback settings in **Watch**. Watch also lists sharpening presets and keyboard shortcuts.

## Sources and updates

**Plugins** opens your repo and source list. Turn sources on or off there to decide which sites Search uses. On desktop, the **Sources** section lists your sources. Click one to turn it on or off, or choose **Manage** for the full list.

**Check for plugin updates on startup** is on by default. It shows how many updates are available and waits for you to download them. Turn it off to check manually. On desktop, choose **Check now** in **Sources**.

See [managing plugins](../plugins/managing-plugins.md) for adding repos, trust prompts, and manual downloads.

## App updates

**Check for Aikatsu updates on startup** is on by default. When a newer release is out, Aikatsu shows its version and asks before downloading anything. **What's new** opens the release notes. To check by hand, use **Check for updates** in **General** on desktop, or **Check now** under **Updates** on Android.

**Update** downloads the new version, checks that it arrived intact, and installs it:

- **Windows, installed with `setup.exe`:** Aikatsu closes, installs the update, and opens again.
- **Linux AppImage:** the AppImage file is replaced with the new one, then Aikatsu restarts. The folder holding it must be writable.
- **Android:** the first time, Android asks you to let Aikatsu install apps. Turn that on, go back, and tap **Update** again. Android then asks you to confirm the install.

The Windows ZIP and builds from source can't replace themselves, so the dialog offers **Download** instead, which opens the release page. Updating keeps your history, settings, and downloads.

## History

Home has Continue and Recent views. Aikatsu saves episode progress on this device. Use a series card's menu to remove it from history.

Signed in to [sync](./sync.md), removing a series removes it on your other devices too. Metadata from AniList or MyAnimeList doesn't mean Aikatsu is connected to your personal account on those services.

## Downloads

Desktop's **Library** section shows the download folder and how much you've downloaded there, and lets you choose another folder. It also shows whether ffmpeg and yt-dlp are available. Android uses its app-specific folder.

The optional **TMDB API key** helps organize season folders for long shows. Leave it empty if you don't need that.

## Discord activity on desktop

**Discord status** shares what you're watching through Discord's desktop activity integration. It's enabled by default in the desktop settings. Turn it off to keep your activity private.

This option isn't part of the Android settings.

## Logs and cache

**Developer Mode** is off by default. Turn it on in **General** on desktop or **Other** on Android to unlock the log viewer and local plugin installs. This setting stays on the current device. Turning it off closes the desktop log viewer and disables **Ctrl+L**. Installed sources keep working.

**Debug logging** records extra detail and applies after a restart. Use it when you're trying to reproduce a problem.

With Developer Mode enabled, **Logs** lets you read and export a diagnostic report. On desktop, choose **View** next to **Log** in **General**, or press **Ctrl+L**. A report includes the app version, platform, and log text. Check it before sharing, since URLs and other playback details can appear in it.

**Clear cache** removes cached lookup data and fetched pages. It doesn't delete watch history or downloaded videos. Try it when show details or source pages seem out of date. On desktop it's **Cached lookups** in **General**, which shows how much is cached.
