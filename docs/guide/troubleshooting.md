# When something doesn't cooperate

Start with the part that failed. A metadata problem, a source problem, and a video-decoding problem can look similar from the player.

## Search has no sources or no results

Open **Settings > Plugins** (**Settings > Sources** on desktop). Make sure at least one source is installed and switched on. If Kyoko's scripts haven't been downloaded yet, check for updates and use the download icon.

Try a shorter query or a different title spelling. A failed source filter is a clue that the site had a problem, rather than proof that the anime doesn't exist.

## A source stopped working

1. Open Plugins and choose **Check for updates**.
2. If an update is available, use the download icon.
3. Try the search or episode again.
4. If it still fails, try another source and check the log.

Checking alone doesn't apply the update. You don't need to remove and re-add a repo to install a normal update.

Sites can be down, change their layout, block automated requests, or remove a video. Plugin authors can fix some of those problems, but a fresh plugin can't make an unavailable video come back.

## The app says the repo couldn't be checked or updated

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

## A download is missing from Android's Library

Wait until its job is marked done. A partial download isn't an offline episode yet.

If you moved or deleted the file outside Aikatsu, the saved library record may no longer point to a playable file. Also remember that uninstalling the Android app can remove its app-specific download folder.

## Share a useful bug report

For jagged or overly sharp text on Windows, include your display scaling percentage and a screenshot at its original size. Windows builds use Qt's scalable text renderer for labels and text fields.

Include your app version, platform, source name, anime title, and the steps that led to the problem. If it's repeatable, enable debug logging, restart, reproduce it, then export the log.

Read the report before posting it. Remove anything you don't want to share. You can report app bugs in [Aikatsu issues](https://github.com/KidiXDev/aikatsu/issues); source-specific bugs may belong in the plugin repo instead.
