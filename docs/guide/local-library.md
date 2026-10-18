# Your library

Open **Library** to find your watch history and local videos:

- **Continue watching** shows the same history as Home. Switch between **Continue** and **Recent**. Long-press a card on Android or right-click on desktop to resume an episode or remove it from history.
- **Your folders**: anime from your own video files.
- **Downloaded** (Android): episodes you downloaded in Aikatsu. See [Downloads and offline viewing](./downloads.md).

## Add your own videos

Choose **Add folder** and select where you keep your videos.

- A folder with videos in it becomes one anime.
- Subfolders with videos become separate anime, up to two levels deep. You can add `Anime` or a specific folder such as `Anime/Frieren/Season 02`.

Aikatsu looks up each folder's anime on AniList by the folder's name. Tags like `[Group]`, `1080p` or `01-12` are ignored. A folder that Aikatsu downloaded links by itself, because its name carries the AniList id. Its later season folders are matched by name.

Choose **Manage** next to **Your folders** to add or remove folders and see each folder's anime count. Disconnected drives stay listed.

You can also remove a folder from a card's menu. Right-click on desktop or long-press on Android, then choose **Remove from library**. This removes all anime in that folder from the library and keeps your files.

## Choose the right anime

When a folder doesn't match, or matches the wrong show, its card says **Choose anime**. Open the card's menu, or the anime page, and pick **Choose anime…**. Search AniList by any title (English, romaji or Japanese) and pick the right one.

Once linked, the anime page shows the poster, description and episode titles. Your progress is shared with the same anime from a streaming source.

## How episodes are numbered

Aikatsu reads the episode number from each file name. These all work:

- `[Group] Show S2 - 01 [1080p].mkv`
- `Show - 12 END.mkv`
- `Show.S02E05.1080p.WEB-DL.mkv`
- `Show Episode 3.mp4`
- `第12話.mkv`

When two files have the same number, such as `- 07` and `- 07v2`, the last one by name plays. Files without a number, such as an OVA, come after the numbered episodes and keep their file name as the title.

Supported files: `.mkv`, `.mp4`, `.avi`, `.webm`, `.m4v`, `.mov`, `.ts`, `.m2ts`, `.wmv` and `.flv`. Subtitles inside the file work. On desktop, a subtitle file next to the video with the same name loads too.

A second season numbered 13 to 24 keeps those numbers.

## Disconnected drives

Shows on a disconnected drive stay in the library, greyed out. Reconnect the drive to watch them again. Their anime matches are kept.

## On Android

Adding a folder asks for permission to read your videos. Pick a folder on the phone's storage or SD card. Folders from other apps or cloud storage can't be added.

On Android 14 and later, choosing **Select videos** instead of allowing all videos limits Aikatsu to the videos you picked.

## Watch your desktop folders on your phone

Watch videos from your desktop on your phone over your home network without copying files.

1. Sign in to the same [account](./sync.md) on both devices.
2. On the desktop, turn on **Settings > Library > Share your folders**.
3. Keep both devices on the same network. The desktop's shows appear in the phone's **Your folders**, marked **On** and the computer's name.

The desktop must be running. On Windows, allow Aikatsu through the firewall on private networks when asked. Choose the anime for each folder on desktop. Your phone uses the same match.

Video and library requests are encrypted over your network. Your devices use the sharing certificate and key delivered through account sync to verify the desktop. Use HTTPS for a self-hosted sync server too, because it carries those credentials.

Update both devices for encrypted sharing. Older versions cannot connect. Turning sharing off or signing out closes active transfers, and turning it back on creates a new certificate and key. Give the other device a moment to sync the new connection details.

Aikatsu keeps shared videos linked to their computer, even if another computer uses the same folder paths. Symbolic links that leave a library folder cannot be shared.

## On other devices

Watch progress syncs like any other history. A show you watched from a folder still shows up in **Continue watching** on your other devices. It opens there if the same folder is in that device's library, or if the desktop that has it is sharing on the same network. Otherwise, search for the anime to keep watching from a source. The folder's location is part of the synced history.
