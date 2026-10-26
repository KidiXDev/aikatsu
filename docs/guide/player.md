# Video player

The player saves your position and has controls for quality, speed, audio, and subtitles. Available qualities and tracks depend on the video.

## Quality and playback

Set a preferred quality in Settings, or choose a different one from the player. Aikatsu remembers your quality choice. If the exact resolution isn't available, the source can fall back to another one.

Use the player controls to adjust speed and volume or switch between available audio and subtitle tracks. Indonesian subtitles are often part of the video itself, so there may be no separate subtitle track to switch off.

If a video fails to start, the player can try other qualities. If those fail too, retry the episode or choose another source. The source may be broken or the stream URL may have expired.

## Resume playback

Aikatsu saves watch progress on your device. Reopen a show from Home, or select an episode on its details page. When prompted, choose whether to resume from your saved position or start again.

Use [Aikatsu sync](./sync.md) to share it with your other devices. To update AniList or MyAnimeList as you watch, [connect them](./trackers.md).

## Skip openings and endings

Use **Skip intro & outro** in Settings for automatic skips, or use the player's skip control when a segment is available. Desktop also has the **S** shortcut.

Skip times come from AniSkip and aren't available for every anime or episode. An ending skip also depends on where you are in the episode and whether there's a next episode.

## Subtitle size and timing

With a subtitle track selected, the audio and subtitles menu has two more options:

- **Subtitle size**: make subtitles smaller or larger. Aikatsu remembers the size on this device.
- **Subtitle timing**: if subtitles appear too early or too late, use the minus and plus buttons to shift them by 0.1 seconds. Timing resets for each episode. On desktop, **Z** and **X** do the same.

Subtitles that are part of the video itself can't be resized or retimed.

## Picture in picture

On desktop, press **Ctrl+P** or the picture-in-picture button to shrink the player into a small window that stays on top of other apps. Drag the video to move it, and the top-left corner to resize it (not on macOS). Press **Ctrl+P** or **Esc**, or double-click, to return to the full window.

On Wayland, your compositor decides the window's size, position, and whether it stays on top. Use its float and pin rules if it doesn't.

## Next episode

Enable **Autoplay next episode** to continue after a short countdown at the end of each episode. Cancel the countdown to stop. You can also use the previous and next controls when those episodes are available.

## Desktop shortcuts

| Key | What it does |
| --- | --- |
| Space or K | Play or pause |
| Left / Right, or J / L | Jump back or forward 5 seconds |
| Shift + Left / Right, or Shift + J / L | Jump back or forward 85 seconds |
| Up / Down | Change volume |
| M | Mute or unmute |
| F, or double-click the video | Toggle fullscreen |
| Ctrl+P | Toggle picture in picture |
| N / P | Next or previous episode |
| S | Skip the current opening or ending segment |
| Z / X | Show subtitles 0.1 seconds earlier or later |
| Esc | Leave picture in picture or fullscreen first, then close the player |
| I | Show playback statistics briefly (Developer Mode) |
| Shift+I | Toggle playback statistics (Developer Mode) |
| Ctrl+L | Open the app log (Developer Mode) |

## Android controls

Tap the video to show or hide controls. Double-tap the left or right side to jump back or forward 10 seconds. Use the seek bar to move further through the episode.

Double-tapping the middle toggles play and pause. Playback pauses when you unplug your headphones.

## Picture-in-picture (Android)

Leave the app while an episode is playing, for example with the Home gesture, and the video keeps playing in a small window. Tap the window to expand it back to the full player. Close the window to pause playback. A paused episode doesn't shrink into a window, so pause first if you want to leave without it.

To turn this off, open Android's settings for Aikatsu and switch off **Picture-in-picture**.

With **Developer Mode** on, tap **info** next to the resolution to show playback stats. These include codec, dimensions, frame rates, hardware decoding, dropped frames, audio, and cache. Missing values appear as a dash. On desktop, press **i** to show mpv's stats briefly or **Shift+I** to keep them visible. Press **Shift+I** again to hide them.

Outside the player, long-press an episode or anime card to see its available actions.

## Sharpen video

Open the Anime4K controls in the player or Settings. Start with Standard or Light. Try a stronger preset if playback stays smooth. The [Anime4K guide](./anime4k.md) explains the choices.
