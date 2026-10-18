# Download episodes for offline viewing

Save one episode, a range, or a whole series to watch offline.

## Start a download

Open a show's episode list and use its download action. Choose the episodes and a quality, then confirm. The Downloads screen shows each job's state and progress.

Aikatsu runs up to four episode downloads at once. Others wait in the queue. A job can move through resolving, downloading, and remuxing before it's done.

On Android, download notifications show progress and completed episodes. Tapping a download notification opens Downloads in the app.

You can cancel queued or running downloads. If one fails, check the error and restart it from the episode list. Unfinished downloads may need to be started again after you close the app.

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

Clearing finished jobs from Downloads removes them from the list. Your video files stay on the device.

## MP4, HLS, and ffmpeg

Some sources serve plain video files. Others use HLS, where a video is split into small segments. On desktop, installing `ffmpeg` helps Aikatsu combine HLS downloads into a regular MP4. Without it, an HLS download may remain a `.ts` file.

On Windows, put `ffmpeg.exe` beside `aikatsu.exe` or somewhere on PATH. On Linux, install it with your package manager. The desktop downloader also has a yt-dlp fallback for sources that need it.

The optional TMDB API key helps organize long shows into season folders. You can watch and download without it.
