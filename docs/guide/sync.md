# Sync between your phone and computer

Sign in on each device to keep your history in step. Stop an episode on your computer, and your phone picks it up at the same minute.

## Sign in

1. Open **Settings**. On desktop, choose **Account**. On Android, **Sync** is at the top.
2. Choose **Create account** the first time, or **Sign in** on your other devices.
3. Enter a username and a password of at least 8 characters. When you create an account, enter the password a second time to confirm it. The eye button in a password field shows what you typed.

Signing in never throws away a device's history. It's merged into the account, and each episode keeps its newest progress. For settings, the account's choices win, and the device's own fill in any the account doesn't have yet.

You only need a username and a password, no email. There's no automatic password reset, so keep the password somewhere safe. If you lose it and you use [your own server](./self-hosting.md), you can reset it there.

## What syncs

| Syncs | Stays on each device |
| --- | --- |
| Watch history and episode progress | Theme |
| Autoplay next episode | Anime4K |
| Skip intro & outro | Download folder and downloaded videos |
| Preferred quality | Volume |
| Which sources are on or off | Discord status (desktop) |
| Your plugin repos | Debug logging |
| TMDB API key | |

Plugin repos are listed on every device, but their plugins never download by themselves. Open **Plugins** on each device and download them when you choose, just as you would for updates.

## When it syncs

- **Opening:** Aikatsu syncs when it opens.
- **While open:** it syncs every couple of minutes.
- **Closing the player:** it syncs right away, so another device can pick up where you stopped.
- **Back to the app:** on Android, it also syncs when you return to the app.

**Sync now** in Settings syncs immediately.

Without a connection, Aikatsu keeps working and syncs the next time it can.

If the same thing changes on two devices, **the newest change wins**. That goes for each episode's progress, each setting, and a series you removed from history. "Newest" goes by each device's clock, so keep automatic time on.

## Sign out or delete your account

Use the **⋮** menu next to **Sync now**.

- **Sign out** stops syncing on that device. Its history and settings stay where they are.
- **Change password** asks for your current password and the new one twice. It signs out your other devices. Sign in there again with the new password.
- **Delete account** removes your account and everything synced to it from the server. Each device keeps its own history.

## Use your own server

Aikatsu uses its own sync server unless you choose another. To keep your history on your own machine, [run the sync server yourself](./self-hosting.md). Then, before signing in, choose **Change** next to the server in **Settings > Sync** (**Settings > Account** on desktop) and enter its address. Clear the address to use the default server again.

An account belongs to the server it was created on. To switch servers, sign out first. Your history stays on the device and merges into the account you sign in to next.

If the address starts with `http://` instead of `https://`, your password travels unencrypted. That's fine at home, but use HTTPS for a server you reach over the internet.

## If sync stops

- **"Couldn't reach the sync server":** check your connection, or whether your own server is running. Your changes wait on the device until it's reachable again.
- **"Session expired":** your password was changed on another device, or the device went unused for about six months. Sign in again. Nothing on the device is lost.
- **"Storage limit reached":** the server caps how much each account can store. Ask whoever runs the server.
