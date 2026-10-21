# Sync between your phone and computer

Sign in to the same account on each device to share watch progress and supported settings.

## Sign in

1. Open **Settings**. On desktop, choose **Account**. On Android, **Sync** is at the top.
2. Choose **Create account** the first time, or **Sign in** on your other devices.
3. Enter a username and a password of at least 8 characters. When you create an account, enter the password a second time to confirm it. The eye button in a password field shows what you typed.

Signing in merges your device's history with your account. Each episode keeps its newest progress. Your account's settings take priority, with device settings filling in any gaps.

You don't need an email address. There's no automatic password reset, so keep the password somewhere safe. If you lose it and you use [your own server](./self-hosting.md), you can reset it there.

## What syncs

| Syncs | Stays on each device |
| --- | --- |
| Watch history and episode progress | Theme |
| [Watchlist](./trackers.md) | AniList and MyAnimeList connections |
| Autoplay next episode | Anime4K |
| Skip intro & outro | Download folder and downloaded videos |
| Preferred quality | Volume |
| Which sources are on or off | Discord status (desktop) |
| Your plugin repos | Debug logging |
| TMDB API key | New episode alerts (Android) |
| | When closed (desktop) |

The plugin repo list syncs, but scripts must be downloaded on each device. Open **Plugins** to install them.

## When it syncs

- When you open Aikatsu
- Every couple of minutes while it is open
- When you close the player
- When you return to the app on Android

**Sync now** in Settings syncs immediately.

Offline changes are saved on the device and synced when the server is reachable again.

If two devices change the same episode progress or setting, Aikatsu keeps the newest change. This also applies to removing a series from history. Changes are dated using each device's clock, so keep automatic time enabled.

## Sign out or delete your account

Use the **⋮** menu next to **Sync now**.

- **Sign out** stops syncing on that device. Its history and settings stay where they are.
- **Change password** asks for your current password and the new one twice. It signs out your other devices. Sign in there again with the new password.
- **Delete account** removes your account and everything synced to it from the server. Each device keeps its own history.

## Use your own server

Aikatsu uses its own sync server unless you choose another. To keep your history on your own machine, [run the sync server yourself](./self-hosting.md). Then, before signing in, choose **Change** next to the server in **Settings > Sync** (**Settings > Account** on desktop) and enter its address. Clear the address to use the default server again.

An account belongs to the server it was created on. To switch servers, sign out first. Your history stays on the device and merges into the account you sign in to next.

An `http://` address sends your password unencrypted. Use HTTPS to protect it, especially outside your home network.

## Sync errors

- **"Couldn't reach the sync server":** check your connection, or whether your own server is running. Your changes wait on the device until it's reachable again.
- **"Session expired":** your password was changed on another device, or the device went unused for about six months. Sign in again. Nothing on the device is lost.
- **"Storage limit reached":** the server caps how much each account can store. Ask whoever runs the server.
