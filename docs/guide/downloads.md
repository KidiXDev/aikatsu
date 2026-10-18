# Save a few episodes for later

You can download one episode, an episode range, or a whole series. The files stay on your device, so you can watch without relying on the source still being online.

## Start a download

Open a show's episode list and use its download action. Choose the episodes and a quality, then confirm. The Downloads screen shows each job's state and progress.

Aikatsu runs up to four episode downloads at once. Others wait in the queue. A job can move through resolving, downloading, and remuxing before it's done.

On Android, download notifications show progress and completed episodes. Tapping a download notification opens Downloads in the app.

You can cancel a queued or running job. If a download fails, check the error and start it again from the episode list. The active queue is kept in memory, so don't rely on unfinished jobs continuing automatically after closing the app.

## Where the files go

**Desktop:** **Settings > Library** shows the download folder and lets you change it. Finished files are named and organized for media servers such as Plex and Jellyfin. Some longer shows can use metadata-based season folders.

**Android:** downloads use the app's external storage folder, `Android/data/io.github.kidixdev.aikatsu/files/Anime`. Android can remove app-specific files when you uninstall the app, so copy anything you want to keep before uninstalling.

## Watch offline

On Android, finished downloads appear in **Library**, grouped by anime. Open a series and pick an episode. You can also open finished downloads from the download history when the recorded file is still available.

Desktop saves files in your download folder. To watch them in Aikatsu, add that folder under **Library > Your folders**. Aikatsu's folder names carry the AniList id, so each show links to the right anime by itself. See [Your library](./local-library.md). You can also open the files with any local video player.

The desktop Downloads screen has **Open folder**, and a finished job's folder button opens the directory containing its file.

If your download folder is on a drive that's disconnected, Aikatsu keeps its record of those downloads and lists them again once the drive is back.

Offline files don't make Search, discovery, or new episode listings work without a connection. Use Android's Library or the saved files directly when you're offline.

## Delete downloads or clear the list

Android's Library lets you delete one episode or all downloaded episodes for a series. That deletes the actual files after confirmation.

Clearing finished jobs from Downloads is different. It clears those queue entries; it isn't the same action as deleting the downloaded videos.

## MP4, HLS, and ffmpeg

Some sources serve plain video files. Others use HLS, where a video is split into small segments. On desktop, installing `ffmpeg` helps Aikatsu combine HLS downloads into a regular MP4. Without it, an HLS download may remain a `.ts` file.

On Windows, put `ffmpeg.exe` beside `aikatsu.exe` or somewhere on PATH. On Linux, install it with your package manager. The desktop downloader also has a yt-dlp fallback for sources that need it.

A TMDB API key is optional. It's used to help split long shows into season folders, not to unlock playback or downloads.
