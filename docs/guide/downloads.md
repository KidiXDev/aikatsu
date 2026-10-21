# Downloads and offline viewing

You can download a single episode, a range of episodes, or a whole series.

## Start a download

Open a show's episode list and use its download action. Choose the episodes and a quality, then confirm. The Downloads screen shows each job's state and progress.

Up to four episodes download at once. The rest wait in the queue. Each job may pass through resolving, downloading, and remuxing before it finishes.

On Android, download notifications show progress and completed episodes. Tapping a download notification opens Downloads in the app.

You can cancel queued or running downloads. If one fails, check the error and restart it from the episode list. Unfinished downloads may need to be started again after you close the app.

## Download folders

On desktop, view or change the download folder in **Settings > Library**. Finished files are named and organized for media servers such as Plex and Jellyfin. Some longer shows can use metadata-based season folders.

On Android, downloads use the app's external storage folder, `Android/data/io.github.kidixdev.aikatsu/files/Anime`. Android can remove app-specific files when you uninstall the app, so copy anything you want to keep before uninstalling.

## Watch offline

On Android, finished downloads appear in **Library**, grouped by anime. Open a series and pick an episode. You can also open finished downloads from the download history when the recorded file is still available.

Desktop saves files in your download folder. To watch them in Aikatsu, add that folder under **Library > Your folders**. Aikatsu's folder names carry the AniList id, so each show links to the right anime by itself. See [Your library](./local-library.md). You can also open the files with any local video player.

The desktop Downloads screen has **Open folder**, and a finished job's folder button opens the directory containing its file.

If your download folder is on a drive that's disconnected, Aikatsu keeps its record of those downloads and lists them again once the drive is back.

Search, discovery, and new episode listings still need an internet connection. While offline, open downloads from Android's Library or play the saved files directly.

## Delete files and clear finished jobs

Android's Library lets you delete one episode or all downloaded episodes for a series. That deletes the actual files after confirmation. If a file cannot be deleted, its library entry stays so you can retry.

Clearing finished jobs from Downloads removes them from the list. Your video files stay on the device.

## MP4, HLS, and ffmpeg

Some sources serve plain video files. Others use HLS, where a video is split into small segments. On desktop, installing `ffmpeg` helps Aikatsu combine HLS downloads into a regular MP4. Without it, an HLS download may remain a `.ts` file.

On Windows, put `ffmpeg.exe` beside `aikatsu.exe` or somewhere on PATH. On Linux, install it with your package manager. The desktop downloader also has a yt-dlp fallback for sources that need it.

HLS playlists that require initialization segments or byte ranges use the desktop yt-dlp fallback. Android reports these as unsupported rather than saving an incomplete video.

An optional TMDB API key helps organize long shows into season folders. It is not required for playback or downloads.
