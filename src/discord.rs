//! Discord Rich Presence ("Watching"), ported from GonimeId internal/discord.
//! The IPC client is blocking, so it lives on its own thread; QML pushes the
//! player state every few seconds and only meaningful changes reach Discord.

use discord_rich_presence::activity::{Activity, ActivityType, Assets, Button, Timestamps};
use discord_rich_presence::{DiscordIpc, DiscordIpcClient};
use serde::Deserialize;
use std::sync::LazyLock;
use std::sync::mpsc::{Sender, channel};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const CLIENT_ID: &str = "1302721937717334128";

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct State {
    pub title: String,
    pub episode: i64,
    pub position: f64,
    pub duration: f64,
    pub paused: bool,
    pub speed: f64,
    pub cover: String,
    pub anilist_id: i64,
    pub mal_id: i64,
    pub clear: bool,
}

static TX: LazyLock<Sender<State>> = LazyLock::new(|| {
    let (tx, rx) = channel::<State>();
    std::thread::Builder::new()
        .name("discord".into())
        .spawn(move || {
            let mut client: Option<DiscordIpcClient> = None;
            let mut last: Option<(State, Instant)> = None;
            for state in rx {
                if state.clear {
                    if let Some(c) = client.as_mut() {
                        let _ = c.clear_activity();
                    }
                    last = None;
                    continue;
                }
                if !should_update(last.as_ref(), &state) {
                    continue;
                }
                if client.is_none() {
                    let mut c = DiscordIpcClient::new(CLIENT_ID);
                    if c.connect().is_err() {
                        continue; // Discord not running; try again on the next update
                    }
                    client = Some(c);
                }
                if let Err(e) = client.as_mut().unwrap().set_activity(activity(&state)) {
                    tracing::debug!("discord presence update failed: {e}");
                    client = None;
                    continue;
                }
                last = Some((state, Instant::now()));
            }
        })
        .expect("discord thread");
    tx
});

pub fn update(state: State) {
    let _ = TX.send(state);
}

/// Push when pause/episode/title changed, the position drifted ≥ 2 s from
/// where it should be, or 2 minutes passed (keeps Discord's timer honest).
fn should_update(last: Option<&(State, Instant)>, s: &State) -> bool {
    let Some((prev, at)) = last else { return true };
    if prev.paused != s.paused || prev.episode != s.episode || prev.title != s.title || at.elapsed() >= Duration::from_secs(120) {
        return true;
    }
    let expected = if prev.paused { prev.position } else { prev.position + at.elapsed().as_secs_f64() * prev.speed.max(0.1) };
    (s.position - expected).abs() >= 2.0
}

fn activity(s: &State) -> Activity<'_> {
    let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0);
    let mut a = Activity::new()
        .activity_type(ActivityType::Watching)
        .details(s.title.as_str())
        .state(format!("Episode {}", s.episode))
        .assets({
            let mut assets = Assets::new().large_text(s.title.as_str());
            if !s.cover.is_empty() {
                assets = assets.large_image(s.cover.as_str());
            }
            if s.paused {
                assets = assets.small_image("pause-button").small_text("Paused");
            }
            assets
        });
    if !s.paused && s.duration > 0.0 {
        let start = now_ms - (s.position * 1000.0) as i64;
        let end = now_ms + ((s.duration - s.position).max(0.0) / s.speed.max(0.1) * 1000.0) as i64;
        a = a.timestamps(Timestamps::new().start(start).end(end));
    }
    let mut buttons = Vec::new();
    if s.anilist_id > 0 {
        buttons.push(Button::new("View on AniList", format!("https://anilist.co/anime/{}", s.anilist_id)));
    }
    if s.mal_id > 0 {
        buttons.push(Button::new("View on MAL", format!("https://myanimelist.net/anime/{}", s.mal_id)));
    }
    if !buttons.is_empty() {
        a = a.buttons(buttons);
    }
    a
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn update_rules() {
        let s = State { title: "X".into(), episode: 1, position: 100.0, speed: 1.0, ..Default::default() };
        assert!(should_update(None, &s));
        let last = (s.clone(), Instant::now());
        assert!(!should_update(Some(&last), &State { position: 100.5, ..s.clone() }));
        assert!(should_update(Some(&last), &State { position: 130.0, ..s.clone() }), "seek");
        assert!(should_update(Some(&last), &State { paused: true, ..s.clone() }));
        assert!(should_update(Some(&last), &State { episode: 2, ..s.clone() }));
    }
}
