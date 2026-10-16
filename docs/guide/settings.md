# Make the app feel right

Settings are stored on each device. Desktop and Android share most options. Sign in to [sync](./sync.md), and your history and most settings follow you between them.

## Sync

**Sync** at the top of Settings signs you in to keep watch history and settings the same on your phone and computer. See [sync between devices](./sync.md) for what follows you and what stays per device.

## Appearance and playback

| Setting | What it changes | Default |
| --- | --- | --- |
| Theme | Follow the system, or stay light or dark | System |
| Autoplay next episode | Continue after the end-of-episode countdown | On |
| Skip intro & outro | Skip known opening and ending segments automatically | Off |
| Preferred quality | Your starting playback quality preference | Auto |
| Sharpen video (Anime4K) | Apply a video-processing preset | Off |

Player quality changes are remembered too. Available resolutions and tracks still depend on the source.

## Sources and updates

**Plugins** opens your repo and source list. Turn sources on or off there to decide which sites Search uses.

**Check for plugin updates on startup** is on by default. It checks for changes and shows an update-count dialog when something is available. It doesn't download plugin updates. Turn it off if you'd rather use the Plugins page's manual check button.

See [managing plugins](../plugins/managing-plugins.md) for adding repos, trust prompts, and manual downloads.

## History

Home has Continue and Recent views. Aikatsu remembers episode progress on this device and lets you remove a series from history through its available menu actions.

Signed in to [sync](./sync.md), removing a series removes it on your other devices too. Metadata from AniList or MyAnimeList doesn't mean Aikatsu is connected to your personal account on those services.

## Downloads

Desktop shows the download folder in Settings and lets you choose another. Android uses its app-specific folder.

The optional **TMDB API key** helps organize season folders for long shows. Leave it empty if you don't need that.

## Discord activity on desktop

**Discord status** shares what you're watching through Discord's desktop activity integration. It's enabled by default in the desktop settings. Turn it off if you'd rather keep that to yourself.

This option isn't part of the Android settings.

## Logs and cache

**Debug logging** records extra detail and applies after a restart. Use it when you're trying to reproduce a problem.

**Logs** lets you read and export a diagnostic report. Desktop also opens the log with **Ctrl+L**. A report includes the app version, platform, and log text. Check it before sharing, since URLs and other playback details can appear in it.

**Clear cache** removes cached lookup data and fetched pages. It doesn't delete watch history or downloaded videos. It's useful when metadata or a source page seems stuck on an older response.
