# Troubleshooting

Find the problem below and try the suggested steps.

## Search has no sources or no results

Open **Settings > Plugins** (**Settings > Sources** on desktop). Make sure at least one source is installed and switched on. If Kyoko's scripts haven't been downloaded yet, check for updates and use the download icon.

Try a shorter query or a different title spelling. If a source filter shows an error, the site may be failing even when it has the anime.

## A source stopped working

1. Open Plugins and choose **Check for updates**.
2. If an update is available, use the download icon.
3. Try the search or episode again.
4. If it still fails, try another source and check the log.

Use the download icon to install an update after checking. You can keep the repo installed.

Sites can be down, change their layout, block automated requests, or remove a video. Plugin authors can fix some of those problems, but a fresh plugin can't make an unavailable video come back.

## A repo won't check or update

Check your connection and try again. Aikatsu keeps previously installed scripts when a repo can't be reached.

A **checksum mismatch** can happen when an index and its script haven't both reached the server yet, or when the repo published an incorrect hash. Try again a little later. If it continues, report it to the repo's author. A failed checksum doesn't replace a working script with the bad download.

**Needs a newer Aikatsu** means the plugin requests a newer host API. Update the app first. Repeatedly downloading the same plugin won't add the missing API.

## Playback won't start

Try another quality or source. If an episode worked earlier, its stream URL may have expired. Reopen it so the plugin can resolve a fresh one.

A 403, challenge, or blocked-request message usually points to the source or video host refusing the request. Metadata loading successfully doesn't mean that host is reachable.

## Video stutters or the phone gets hot

Turn Anime4K off, then try a lower video quality. If only a heavy shader preset causes trouble, choose Light or keep it off.

## Episode titles, covers, or skip times are missing

Those come from separate metadata services. Not every anime has complete episode information or AniSkip timings. Try refreshing the details page when that action is available. A plain episode list can still play normally.

If a desktop cover fails with **Unsupported image format** for a `.webp` URL, the Qt installation may be missing WebP support. Source builds need Qt Image Formats. Packaged Windows builds need `qwebp.dll` in their `imageformats` folder. Install the matching Qt module and restart the app.

## A download is missing from Android's Library

Wait until its job is marked done. A partial download isn't an offline episode yet.

If you moved or deleted the file outside Aikatsu, the saved library record may no longer point to a playable file. Also remember that uninstalling the Android app can remove its app-specific download folder.

## Share a useful bug report

For jagged or overly sharp text on Windows, include your display scaling percentage and a screenshot at its original size. Windows builds use Qt's scalable text renderer for labels and text fields.

Include your app version, platform, source name, anime title, and the steps that led to the problem. If it's repeatable, enable Developer Mode and debug logging in Settings, restart, reproduce it, then export the log.

Read the report before posting it. Remove anything you don't want to share. Report app bugs in [Aikatsu issues](https://github.com/KidiXDev/aikatsu/issues). Report source bugs to the plugin repo.
