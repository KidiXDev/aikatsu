pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

// Opens immediately; the series details can arrive after playback has started.
// An episode counts as watched at 90 %.
FocusScope {
    id: root

    readonly property Main app: ApplicationWindow.window as Main

    required property var page // AnimePage: anime, meta, metaLoaded, episodes, info, progress, seriesKey
    property int index

    readonly property var anime: page.anime
    readonly property var episodes: page.episodes
    readonly property var meta: page.meta ?? {}
    readonly property bool metaLoaded: page.metaLoaded
    readonly property var ep: episodes[index]
    readonly property string seriesTitle: meta.title_english || meta.title_romaji || anime.name
    readonly property string episodeTitle: page.info?.[ep?.num]?.title || ep?.title || ""
    readonly property string sourceName: Api.sourceName(anime.source)
    readonly property bool hasNext: index + 1 < episodes.length
    readonly property bool hasPrev: index > 0

    property string phase: "resolving" // resolving | playing | error | ended
    property string status: "Starting the player…" // what the loading screen waits on
    property bool slow // status unchanged for a while
    property bool started // first frame of this episode is on screen
    property bool loaded // the file from the latest loadfile is open (ignores the old file's events)
    property string errorText
    property var stream: null
    property var qualities: [] // offered for this episode, highest first
    property var tried: [] // qualities already attempted for this episode
    property int reconnects
    property string quality // label actually requested from the source
    property string preferredQuality: Api.setting("quality")
    property real startAt: -1 // seek here on load without the resume prompt
    property real lastPos // last real position; mpv drops time-pos on errors
    property var skip: ({})
    property real resumeAt: 0
    property bool resumePrompt
    property bool completedMarked
    property bool skippedOp
    property bool skippedEd
    property int countdownLeft: 0
    property int request: 0
    property real unmuteVolume: 100
    property string anime4k: Api.setting("anime4k")
    property bool downloadingShaders
    property var anime4kModes: Api.get("anime4kModes")
    property real subScale: Number(Api.setting("subtitleScale")) || 1
    property real subDelay // per episode: each file is timed on its own
    property bool timing // the subtitle timing bar is open
    readonly property bool autoplay: Api.setting("autoplay") === "true"
    readonly property bool autoSkip: Api.setting("autoSkip") === "true"
    property bool controlsVisible: true
    readonly property bool menuOpen: speedMenu.opened || trackMenu.opened || subSizeMenu.opened || a4kMenu.opened || qualityMenu.opened || episodesDrawer.opened
    readonly property bool showControls: controlsVisible || mpv.paused || phase !== "playing" || !started || menuOpen
    readonly property bool loadingScreen: !started && (phase === "resolving" || phase === "playing")
    readonly property var party: app.party
    property int partyRev
    property var outgoing: null // party changes waiting for publishTimer
    property real quietUntil // ms: our own change is on its way, so don't follow the party back
    property real lastJump

    readonly property bool inOp: !!skip.op && mpv.position >= skip.op[0] && mpv.position < skip.op[1] - 1
    readonly property bool inEd: !!skip.ed && mpv.position >= skip.ed[0] && mpv.position < skip.ed[1] - 1

    function keysFor(num: int): var {
        return Api.get("keys", {
            anilistId: meta.anilist_id ?? 0,
            source: anime.source,
            url: anime.url,
            episode: num
        });
    }

    function save(completed: bool): void {
        // Until metadata lands the series key can still change; the next tick saves.
        if (!ep || mpv.duration <= 0 || !metaLoaded)
            return;
        const done = completed || completedMarked || mpv.position / mpv.duration >= 0.9;
        if (done && !completedMarked && hasNext) // warm the page cache so the next episode starts fast
            Api.call("qualities", {
                source: anime.source,
                url: episodes[index + 1].url
            });
        completedMarked = done;
        Api.get("saveProgress", {
            episode_key: keysFor(ep.num).episode,
            anilist_id: meta.anilist_id ?? 0,
            mal_id: meta.mal_id ?? 0,
            series_key: page.seriesKey,
            series_url: anime.url,
            series_title: seriesTitle,
            source: anime.source,
            episode_url: ep.url,
            total_episodes: meta.episodes || episodes.length,
            meta_episodes: meta.episodes || 0,
            episode_number: ep.num,
            playback_time: Math.floor(completed ? mpv.duration : mpv.position), // time-pos is gone at end-file
            duration: Math.floor(mpv.duration),
            title: episodeTitle,
            cover: meta.cover || anime.image || "",
            completed: done,
            last_updated: 0
        });
    }

    function fetchSkip(): void {
        const num = ep?.num;
        if (meta.mal_id && num)
            Api.call("skipTimes", {
                malId: meta.mal_id,
                episode: num
            }, s => {
                if (root.ep?.num === num)
                    root.skip = s;
            });
    }

    onMetaLoadedChanged: if (metaLoaded)
        fetchSkip()

    function start(i: int): void {
        if (i < 0 || i >= episodes.length) {
            errorText = `No episode at position ${i}`;
            phase = "error";
            return;
        }
        if (phase === "playing")
            save(false);
        Api.forget(request);
        mpv.command(["stop"]);
        subDelay = 0;
        mpv.setProp("sub-delay", "0");
        index = i;
        phase = "resolving";
        status = `Looking up episode ${ep.num} on ${sourceName}…`;
        started = false;
        stream = null;
        skip = {};
        completedMarked = false;
        skippedOp = skippedEd = false;
        resumePrompt = false;
        countdownLeft = 0;
        startAt = -1;
        lastPos = 0;
        qualities = [];
        tried = [];
        quality = "";
        reconnects = 0;
        const saved = Api.get("seriesProgress", {
            key: page.seriesKey,
            url: anime.url
        }).find(p => p.episode_number === ep.num);
        resumeAt = saved && !saved.completed && saved.playback_time > 30 ? saved.playback_time : 0;
        const shared = Api.get("party");
        if (shared.active) {
            resumeAt = 0;
            if (shared.state.episode === ep.num)
                startAt = shared.state.position;
            else
                publish({
                    episode: ep.num,
                    position: 0,
                    paused: false
                });
        }
        fetchSkip();
        request = Api.call("qualities", {
            source: anime.source,
            url: ep.url
        }, list => {
            root.qualities = list;
            root.resolve(root.pickQuality(root.preferredQuality));
        }, () => root.resolve(root.preferredQuality));
    }

    function pickQuality(q: string): string {
        return qualities.length ? Api.get("pickQuality", {
            list: qualities,
            want: q
        }) : q;
    }

    // YouTube-style: the choice is saved for later episodes; switching mid-episode
    // reloads the stream at the same position.
    function setQuality(q: string): void {
        preferredQuality = q;
        Api.setSetting("quality", q);
        const target = pickQuality(q);
        if (phase === "ended" || (target === quality && phase !== "error"))
            return;
        if (phase === "playing" && started) {
            save(false);
            startAt = lastPos;
            resumePrompt = false;
        }
        resolve(target);
    }

    function resolve(q: string): void {
        Api.forget(request);
        quality = q;
        tried = tried.concat([q]);
        phase = "resolving";
        status = started ? `Switching to ${q}…` : "Finding a working server…";
        request = Api.call("resolve", {
            source: anime.source,
            url: ep.url,
            quality: q
        }, s => root.load(s), e => root.fail(e));
    }

    function load(s: var): void {
        stream = s;
        if (startAt >= 0)
            startAt = Math.max(startAt, lastPos); // the old stream kept playing while resolving
        mpv.setProp("http-header-fields", s.referer ? "Referer: " + s.referer : "");
        mpv.setProp("demuxer-lavf-o", s.hls ? "allowed_extensions=ALL" : "");
        mpv.setProp("force-media-title", `${seriesTitle} - Episode ${ep.num}`);
        applyShaders();
        loaded = false;
        mpv.command(["loadfile", s.url]);
        phase = "playing";
        status = "Loading video…";
        poke();
    }

    // Before the first frame, try each other quality once; mid-episode,
    // reconnect at the same spot up to twice. Then the error card.
    function fail(err: string): void {
        const next = started ? (reconnects < 2 ? quality : "") : (qualities.find(q => !tried.includes(q)) ?? "");
        if (!next) {
            errorText = err || "Playback failed";
            phase = "error";
            return;
        }
        console.warn("playback failed, retrying:", err);
        const failed = quality;
        if (started) {
            reconnects++;
            startAt = lastPos;
        }
        resolve(next);
        status = started ? "Connection dropped, reconnecting…" : `${failed || "That stream"} didn't work, trying ${next}…`;
    }

    // From the error card: same or another quality, keeping the position.
    function retry(q: string): void {
        if (!started && qualities.length === 0) {
            start(index); // the quality lookup itself failed
            return;
        }
        tried = [];
        reconnects = 0;
        if (started)
            startAt = lastPos;
        resolve(q || quality);
        status = "Retrying…";
    }

    function modeName(mode: string): string {
        return mode === "off" ? "Sharpening off" : (anime4kModes.find(m => m.key === mode)?.name ?? mode);
    }

    // The first use downloads the shaders. A reply for a mode switched away from meanwhile is
    // dropped; a failure turns sharpening off for this session and keeps the saved choice.
    function applyShaders(): void {
        const mode = anime4k;
        if (!mode || mode === "off") {
            mpv.command(["change-list", "glsl-shaders", "clr", ""]);
            return;
        }
        Api.call("shaders", {
            mode: mode
        }, r => {
            if (mode !== anime4k)
                return;
            mpv.command(["change-list", "glsl-shaders", "set", r.list]);
            if (downloadingShaders)
                osd.show("auto_awesome", modeName(mode));
            downloadingShaders = false;
        }, e => {
            if (mode !== anime4k)
                return;
            downloadingShaders = false;
            anime4k = "off";
            mpv.command(["change-list", "glsl-shaders", "clr", ""]);
            root.app.toast("Couldn't turn on sharpening: " + Api.describe(e));
        });
    }

    function setAnime4k(mode: string): void {
        anime4k = mode;
        Api.setSetting("anime4k", mode);
        applyShaders();
        osd.show("auto_awesome", modeName(mode));
    }

    function seek(sec: real): void {
        jump(sec);
        publish({
            position: sec
        });
    }

    // Without telling the party: loading at a spot, or following it.
    function jump(sec: real): void {
        mpv.command(["seek", String(sec), "absolute"]);
    }

    function seekBy(sec: real): void {
        mpv.command(["seek", String(sec)]);
        osd.show(sec < 0 ? "fast_rewind" : "fast_forward", `${sec < 0 ? "−" : "+"}${Math.abs(sec)}s`);
        publish({
            position: Math.max(0, mpv.position + sec)
        });
    }

    function pause(): void {
        mpv.paused = true;
        publish({
            paused: true
        });
    }

    function togglePause(): void {
        clickDelay.stop();
        const p = !mpv.paused;
        mpv.paused = p;
        osd.show(p ? "pause" : "play_arrow", "");
        publish({
            paused: p
        });
    }

    function setVolume(v: real): void {
        const vol = Math.max(0, Math.min(130, v));
        mpv.volume = vol;
        osd.show(vol === 0 ? "volume_off" : vol < 50 ? "volume_down" : "volume_up", `${Math.round(vol)}%`);
    }

    function toggleMute(): void {
        if (mpv.volume > 0) {
            unmuteVolume = mpv.volume;
            setVolume(0);
        } else
            setVolume(unmuteVolume || 100);
    }

    function setSpeed(v: real): void {
        mpv.speed = v;
        osd.show("speed", v + "×");
        publish({
            speed: v
        });
    }

    // Our own play, pause, seek, speed or episode change, for the rest of the party.
    function publish(changes: var): void {
        if (!party.active)
            return;
        quietUntil = Date.now() + 1500;
        outgoing = Object.assign(outgoing ?? {}, changes);
        publishTimer.restart();
    }

    // Into step with the party: its episode, then play or pause, speed and position.
    function follow(): void {
        const p = Api.get("party");
        if (!p.active || Date.now() < quietUntil || !ep)
            return;
        const s = p.state;
        if (s.episode !== ep.num) {
            const i = episodes.findIndex(e => e.num === s.episode);
            if (i >= 0)
                start(i);
            return;
        }
        if (!started)
            return;
        if (mpv.paused !== s.paused)
            mpv.paused = s.paused;
        if (mpv.speed !== s.speed)
            mpv.speed = s.speed;
        if (!mpv.buffering && Math.abs(mpv.position - s.position) > 2 && Date.now() - lastJump > 3000) {
            lastJump = Date.now();
            jump(s.position);
        }
    }

    function startParty(): void {
        partyDialog.busy = true;
        partyDialog.error = "";
        Api.call("partyCreate", {
            anime: Object.assign({}, anime, {
                anilistId: meta.anilist_id || anime.anilistId || 0
            }),
            episode: ep.num,
            position: mpv.position,
            paused: mpv.paused,
            speed: mpv.speed
        }, p => {
            partyDialog.busy = false;
            root.partyRev = p.state.rev;
            root.app.party = p;
        }, e => {
            partyDialog.busy = false;
            partyDialog.error = e;
        });
    }

    function leaveParty(): void {
        Api.get("partyLeave");
        root.app.party = Api.get("party");
    }

    function scaleName(v: real): string {
        return v === 1 ? "Normal" : `${Math.round(v * 100)}%`;
    }

    function setSubScale(v: real): void {
        subScale = v;
        mpv.setProp("sub-scale", String(v));
        Api.setSetting("subtitleScale", v);
        osd.show("format_size", scaleName(v));
    }

    // Positive is later, as mpv counts it.
    function delayName(): string {
        return `${subDelay < 0 ? "−" : "+"}${Math.abs(subDelay).toFixed(1)} s`;
    }

    function nudgeSubs(sec: real): void {
        subDelay = Math.round((subDelay + sec) * 10) / 10;
        mpv.setProp("sub-delay", String(subDelay));
        osd.show("subtitles", `Subtitles ${delayName()}`);
    }

    function skipSegment(): void {
        if (inOp)
            root.seek(skip.op[1]);
        else if (inEd)
            root.seek(skip.ed[1]);
    }

    function exit(): void {
        if (phase === "playing")
            save(false);
        if (party.active)
            leaveParty();
        Api.forget(request);
        mpv.command(["stop"]);
        Api.get("stopStreams");
        Api.get("presence", {
            clear: true
        });
        root.app.closePlayer();
    }

    function poke(): void {
        controlsVisible = true;
        if (!Qt.application.arguments.includes("--screenshot")) // keep controls for dev captures
            hideTimer.restart();
    }

    focus: true
    Component.onCompleted: forceActiveFocus()
    onShowControlsChanged: if (!showControls)
        timing = false
    onStatusChanged: {
        slow = false;
        slowTimer.restart();
    }
    onPhaseChanged: if (root.app.pip && (phase === "error" || phase === "ended"))
        root.app.togglePip()

    Keys.onPressed: e => {
        if (e.key !== Qt.Key_I)
            poke();
        // Held keys repeat seeks, volume and subtitle timing steps only; a held N would skip through episodes.
        if (e.isAutoRepeat && ![Qt.Key_Left, Qt.Key_Right, Qt.Key_J, Qt.Key_L, Qt.Key_Up, Qt.Key_Down, Qt.Key_Z, Qt.Key_X].includes(e.key))
            return;
        switch (e.key) {
        case Qt.Key_Space:
        case Qt.Key_K:
            togglePause();
            break;
        case Qt.Key_Left:
        case Qt.Key_J:
            seekBy(e.modifiers & Qt.ShiftModifier ? -85 : -5);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            seekBy(e.modifiers & Qt.ShiftModifier ? 85 : 5);
            break;
        case Qt.Key_Up:
            setVolume(mpv.volume + 5);
            break;
        case Qt.Key_Down:
            setVolume(mpv.volume - 5);
            break;
        case Qt.Key_M:
            toggleMute();
            break;
        case Qt.Key_F:
            root.app.toggleFullScreen();
            break;
        case Qt.Key_N:
            if (hasNext)
                start(index + 1);
            break;
        case Qt.Key_P:
            if (hasPrev)
                start(index - 1);
            break;
        case Qt.Key_S:
            skipSegment();
            break;
        case Qt.Key_Z:
            nudgeSubs(-0.1);
            break;
        case Qt.Key_X:
            nudgeSubs(0.1);
            break;
        case Qt.Key_I:
            if (!root.app.developerMode || (e.modifiers & ~Qt.ShiftModifier))
                return;
            controlsVisible = false;
            mpv.command(["script-binding", e.modifiers & Qt.ShiftModifier ? "stats/display-stats-toggle" : "stats/display-stats"]);
            break;
        case Qt.Key_Escape:
            if (root.app.pip)
                root.app.togglePip();
            else if (root.app.visibility === Window.FullScreen)
                root.app.toggleFullScreen();
            else
                exit();
            break;
        default:
            return;
        }
        e.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Connections {
        target: root.app

        function onDeveloperModeChanged(): void {
            mpv.setProp("load-stats-overlay", root.app.developerMode ? "yes" : "no");
            if (!root.app.developerMode)
                mpv.command(["show-text", "", "0"]);
        }
    }

    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind !== "anime4k")
                return;
            root.downloadingShaders = true;
            osd.show("auto_awesome", `Downloading Anime4K… ${Math.round(data.progress * 100)}%`);
        }
    }

    MpvItem {
        id: mpv

        anchors.fill: parent
        // Through playback, buffering, the next episode's lookup and the autoplay countdown; not when paused or on the end/error card.
        keepAwake: (root.phase === "playing" || root.phase === "resolving") && !mpv.paused
        Component.onCompleted: {
            setProp("load-stats-overlay", root.app.developerMode ? "yes" : "no");
            setProp("cache", "yes");
            // The demuxer cache lives in RAM: a few minutes ahead and ~1 minute back is plenty.
            setProp("demuxer-max-bytes", "128MiB");
            setProp("demuxer-max-back-bytes", "32MiB");
            setProp("demuxer-readahead-secs", "20");
            setProp("audio-display", "no");
            setProp("keep-open", "no");
            setProp("sub-scale", String(root.subScale));
            volume = Number(Api.setting("volume")) || 100;
        }
        onReadyChanged: if (ready)
            root.start(root.index)
        onFileLoaded: {
            root.loaded = true;
            root.status = "Buffering…";
            if (root.startAt >= 0) {
                root.jump(root.startAt);
                root.startAt = -1;
            } else if (root.resumeAt > 0) {
                root.jump(root.resumeAt);
                root.resumePrompt = true;
                resumeHide.restart();
            }
        }
        onPlaybackRestart: if (root.loaded)
            root.started = true
        onEndFile: (reason, error) => {
            if (root.phase !== "playing")
                return;
            if (reason === "eof") {
                root.save(true);
                root.app.historyRevision++;
                if (root.autoplay && root.hasNext)
                    root.countdownLeft = 5;
                else
                    root.phase = "ended";
            } else if (reason === "error")
                root.fail(error);
        }
        onVolumeChanged: volSave.restart()
        onPositionChanged: {
            if (mpv.position > 0 && root.started)
                root.lastPos = mpv.position;
            if (!root.autoSkip)
                return;
            if (root.inOp && !root.skippedOp) {
                root.skippedOp = true;
                root.seek(root.skip.op[1]);
            } else if (root.inEd && !root.skippedEd && root.hasNext) {
                root.skippedEd = true;
                root.seek(root.skip.ed[1]);
            }
        }
    }

    Timer {
        id: publishTimer

        interval: 250 // a dragged seek bar moves many times a second
        onTriggered: {
            Api.call("partyUpdate", Object.assign({
                episode: root.ep.num,
                position: mpv.position,
                paused: mpv.paused,
                speed: mpv.speed
            }, root.outgoing), null, e => console.warn("party update failed:", e));
            root.outgoing = null;
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.party.active
        onTriggered: root.follow()
    }

    Connections {
        target: root.app

        function onPartyChanged(): void {
            const s = root.party.state;
            if (s && s.rev > root.partyRev) {
                if (root.partyRev > 0 && s.by !== root.party.me)
                    osd.show(s.paused ? "pause" : "play_arrow", s.by);
                root.partyRev = s.rev;
            }
            root.follow();
        }
    }

    Timer {
        id: volSave

        interval: 800
        onTriggered: Api.setSetting("volume", Math.round(mpv.volume))
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.phase === "playing" && !mpv.paused && mpv.duration > 0
        onTriggered: root.save(false)
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.phase === "playing" && Api.setting("discord") === "true"
        triggeredOnStart: true
        onTriggered: Api.get("presence", {
            title: root.meta.title_romaji || root.seriesTitle,
            episode: root.ep.num,
            position: mpv.position,
            duration: mpv.duration,
            paused: mpv.paused,
            speed: mpv.speed,
            cover: root.meta.cover || root.anime.image || "",
            anilistId: root.meta.anilist_id ?? 0,
            malId: root.meta.mal_id ?? 0
        })
    }

    Timer {
        id: hideTimer

        interval: 2500
        onTriggered: root.controlsVisible = false
    }

    Timer {
        id: slowTimer

        interval: 12000
        onTriggered: root.slow = true
    }

    Timer {
        id: resumeHide

        interval: 8000
        onTriggered: root.resumePrompt = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.countdownLeft > 0
        onTriggered: {
            root.countdownLeft--;
            if (root.countdownLeft === 0)
                root.start(root.index + 1);
        }
    }

    MouseArea {
        property point lastPoke

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.showControls ? Qt.ArrowCursor : Qt.BlankCursor
        // Jitter (a bumped desk, a twitchy mouse) shouldn't bring the controls up; a real move should.
        onPositionChanged: mouse => {
            if (Math.hypot(mouse.x - lastPoke.x, mouse.y - lastPoke.y) < 12)
                return;
            lastPoke = Qt.point(mouse.x, mouse.y);
            root.poke();
        }
        onClicked: if (root.started && root.phase === "playing") {
            osd.show(mpv.paused ? "play_arrow" : "pause", "");
            clickDelay.restart();
        }
        onDoubleClicked: {
            if (clickDelay.running) {
                clickDelay.stop();
                osdAnim.stop();
                osd.opacity = 0;
            } else if (root.started && root.phase === "playing")
                root.togglePause();
            root.app.toggleFullScreen();
        }

        DragHandler {
            target: null
            enabled: root.app.pip
            onActiveChanged: if (active)
                root.app.startSystemMove()
        }

        Timer {
            id: clickDelay

            interval: 200
            onTriggered: if (root.started && root.phase === "playing")
                mpv.paused = !mpv.paused
        }
    }

    // Series art behind the loading screen and the error card
    Item {
        anchors.fill: parent
        opacity: !root.started || root.phase === "error" || root.phase === "ended" ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }

        ClippedImage {
            id: art

            anchors.fill: parent
            radius: 0
            visible: false
            source: root.meta.banner || root.meta.cover || root.anime.image || ""
        }
        MultiEffect {
            anchors.fill: parent
            source: art
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
            opacity: art.status === Image.Ready ? 0.55 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.SlowEffects
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha("#000000", 0.35)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha("#000000", 0.85)
                }
            }
        }

        // loading screen: what we're waiting on, until the first frame
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.padding.extraLarge * 2, 560)
            opacity: root.loadingScreen ? 1 : 0
            visible: opacity > 0
            spacing: Theme.spacing.small

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            ClippedImage {
                Layout.alignment: Qt.AlignHCenter
                visible: !root.app.pip
                Layout.preferredWidth: 132
                Layout.preferredHeight: 190
                Layout.bottomMargin: Theme.spacing.large
                radius: Theme.rounding.large
                source: root.meta.cover || root.anime.image || ""

                Elevation {
                    z: -1
                    anchors.fill: parent
                    radius: parent.radius
                    level: 4
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: `EPISODE ${root.ep?.num ?? ""}`
                font: Theme.font.label.large
                color: Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.seriesTitle
                font: Theme.font.headline.small
                color: "#ffffff"
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.episodeTitle !== "" && !root.episodeTitle.startsWith("Episode")
                horizontalAlignment: Text.AlignHCenter
                text: root.episodeTitle
                color: Qt.alpha("#ffffff", 0.7)
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.large
                spacing: Theme.spacing.medium

                Loading {
                    size: 24
                }
                StyledText {
                    text: root.status
                    color: Qt.alpha("#ffffff", 0.85)
                    font: Theme.font.body.large
                }
            }
            StyledText {
                Layout.fillWidth: true
                opacity: root.slow ? 1 : 0
                horizontalAlignment: Text.AlignHCenter
                text: `${root.sourceName} is slow right now. Keep waiting or try another source.`
                color: Qt.alpha("#ffffff", 0.55)
                font: Theme.font.body.medium
                wrapMode: Text.Wrap

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }

    // Spinner while buffering, switching quality or reconnecting
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.started && (root.phase === "resolving" || (root.phase === "playing" && mpv.buffering))
        spacing: Theme.spacing.medium

        Loading {
            Layout.alignment: Qt.AlignHCenter
            size: 56
        }
        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            visible: root.phase === "resolving"
            implicitWidth: switchText.implicitWidth + Theme.padding.large * 2
            implicitHeight: switchText.implicitHeight + Theme.padding.small * 2
            radius: Theme.rounding.full
            color: Qt.alpha("#000000", 0.6)

            StyledText {
                id: switchText

                anchors.centerIn: parent
                text: root.status
                color: "#ffffff"
            }
        }
    }

    StyledRect {
        id: osd

        function show(icon: string, text: string): void {
            osdIcon.text = icon;
            osdText.text = text;
            osdAnim.restart();
        }

        anchors.centerIn: parent
        implicitWidth: Math.max(implicitHeight, osdRow.implicitWidth + Theme.padding.large * 2)
        implicitHeight: 72
        radius: Theme.rounding.full
        color: Qt.alpha("#000000", 0.55)
        opacity: 0

        RowLayout {
            id: osdRow

            anchors.centerIn: parent
            spacing: Theme.spacing.small

            MaterialIcon {
                id: osdIcon

                fill: 1
                size: 26
                color: "#ffffff"
            }
            StyledText {
                id: osdText

                visible: text !== ""
                font: Theme.font.title.large
                color: "#ffffff"
            }
        }

        SequentialAnimation {
            id: osdAnim

            ParallelAnimation {
                NumberAnimation {
                    target: osd
                    property: "opacity"
                    to: 1
                    duration: 90
                }
                NumberAnimation {
                    target: osd
                    property: "scale"
                    from: osd.opacity > 0 ? 1 : 0.85 // pops in once, not on every update
                    to: 1
                    duration: 160
                    easing.type: Easing.OutBack
                }
            }
            PauseAnimation {
                duration: 450
            }
            NumberAnimation {
                target: osd
                property: "opacity"
                to: 0
                duration: 300
            }
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 120
        opacity: root.showControls && !root.app.pip ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.started
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha("#000000", 0.75)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padding.large
            spacing: Theme.spacing.medium

            IconButton {
                type: IconButton.Tonal
                icon: "arrow_back"
                onClicked: root.exit()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                opacity: root.started ? 1 : 0 // the loading screen already shows these

                StyledText {
                    Layout.fillWidth: true
                    text: root.seriesTitle
                    font: Theme.font.title.large
                    color: "#ffffff"
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: `Episode ${root.ep?.num ?? ""}` + (root.episodeTitle && !root.episodeTitle.startsWith("Episode") ? `  ·  ${root.episodeTitle}` : "")
                    color: Qt.alpha("#ffffff", 0.75)
                    elide: Text.ElideRight
                }
            }
            Chip {
                visible: root.anime.source !== "local"
                text: root.party.active ? String(root.party.members.length) : "Watch together"
                icon: root.party.active && !root.party.connected ? "sync_problem" : "group"
                selected: true
                clickable: true
                tint: Qt.alpha("#000000", 0.45)
                onTint: "#ffffff"
                onClicked: partyDialog.open()
            }
            Chip {
                text: root.sourceName + (root.quality && root.quality !== "best" ? `  ·  ${root.quality}` : "")
                icon: "public"
                selected: true
                tint: Qt.alpha("#000000", 0.45)
                onTint: "#ffffff"
            }
        }
    }

    Item {
        id: bottom

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 140
        opacity: root.showControls && !root.app.pip && root.started && (root.phase === "playing" || root.phase === "resolving") ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha("#000000", 0.85)
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: root.poke()
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.padding.large
            spacing: 0

            StyledSlider {
                id: seek

                Layout.fillWidth: true
                trackHeight: 8
                enabled: mpv.duration > 0
                from: 0
                to: 1
                value: mpv.duration > 0 ? mpv.position / mpv.duration : 0
                buffered: mpv.duration > 0 ? mpv.cacheTime / mpv.duration : 0
                markers: {
                    const out = [];
                    const d = mpv.duration;
                    if (d > 0)
                        for (const k of ["op", "ed"])
                            if (root.skip[k])
                                out.push({
                                    from: root.skip[k][0] / d,
                                    to: root.skip[k][1] / d
                                });
                    return out;
                }
                onMoved: root.seek(value * mpv.duration)

                // time under the cursor
                StyledRect {
                    readonly property real t: Math.max(0, Math.min(1, seek.hoverX / seek.width)) * mpv.duration
                    readonly property string segment: root.skip.op && t >= root.skip.op[0] && t < root.skip.op[1] ? "Opening" : root.skip.ed && t >= root.skip.ed[0] && t < root.skip.ed[1] ? "Ending" : ""

                    visible: (seek.hovering || seek.pressed) && mpv.duration > 0
                    x: Math.max(0, Math.min(seek.width - width, (seek.pressed ? seek.visualPosition * seek.width : seek.hoverX) - width / 2))
                    y: -height
                    implicitWidth: hoverText.implicitWidth + Theme.padding.medium * 2
                    implicitHeight: hoverText.implicitHeight + Theme.padding.small
                    radius: Theme.rounding.small
                    color: Qt.alpha("#000000", 0.8)

                    StyledText {
                        id: hoverText

                        anchors.centerIn: parent
                        text: Theme.formatTime(seek.pressed ? seek.value * mpv.duration : parent.t) + (parent.segment && !seek.pressed ? `  ·  ${parent.segment}` : "")
                        font: Theme.font.label.large
                        color: "#ffffff"
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "skip_previous"
                    disabled: !root.hasPrev
                    label.color: disabled ? Qt.alpha("#ffffff", 0.35) : "#ffffff"
                    onClicked: root.start(root.index - 1)
                }
                IconButton {
                    icon: mpv.paused ? "play_arrow" : "pause"
                    iconSize: 20
                    onClicked: root.togglePause()
                }
                IconButton {
                    type: IconButton.Text
                    icon: "skip_next"
                    disabled: !root.hasNext
                    label.color: disabled ? Qt.alpha("#ffffff", 0.35) : "#ffffff"
                    onClicked: root.start(root.index + 1)
                }
                IconButton {
                    Layout.leftMargin: Theme.spacing.small
                    type: IconButton.Text
                    icon: mpv.volume === 0 ? "volume_off" : mpv.volume < 50 ? "volume_down" : "volume_up"
                    label.color: "#ffffff"
                    onClicked: root.toggleMute()
                }
                StyledSlider {
                    Layout.preferredWidth: 96
                    trackHeight: 6
                    from: 0
                    to: 130
                    value: mpv.volume
                    onMoved: mpv.volume = value
                }
                StyledText {
                    Layout.leftMargin: Theme.spacing.medium
                    text: Theme.formatTime(seek.pressed ? seek.value * mpv.duration : mpv.position) + "  /  " + Theme.formatTime(mpv.duration)
                    color: Qt.alpha("#ffffff", 0.9)
                    font: Theme.font.label.large
                }
                Item {
                    Layout.fillWidth: true
                }
                IconTextButton {
                    type: TextButton.Text
                    icon: "settings"
                    text: root.quality && root.quality !== "best" ? root.quality : "Auto"
                    label.color: "#ffffff"
                    iconLabel.color: "#ffffff"
                    onClicked: qualityMenu.toggle()

                    StyledMenu {
                        id: qualityMenu

                        y: -height - 8
                        header: "Quality"
                        model: [
                            {
                                text: root.preferredQuality === "best" && root.quality && root.quality !== "best" ? `Auto (${root.quality})` : "Auto",
                                value: "best",
                                checked: root.preferredQuality === "best"
                            }
                        ].concat(root.qualities.map(q => ({
                                        text: q,
                                        value: q,
                                        checked: root.preferredQuality !== "best" && root.quality === q
                                    })))
                        onTriggered: item => root.setQuality(item.value)
                    }
                }
                IconTextButton {
                    type: TextButton.Text
                    icon: "speed"
                    text: mpv.speed + "×"
                    label.color: "#ffffff"
                    iconLabel.color: "#ffffff"
                    onClicked: speedMenu.toggle()

                    StyledMenu {
                        id: speedMenu

                        y: -height - 8
                        header: "Speed"
                        model: [0.5, 0.75, 1, 1.25, 1.5, 2].map(v => ({
                                    text: v === 1 ? "Normal" : v + "×",
                                    value: v,
                                    checked: mpv.speed === v
                                }))
                        onTriggered: item => root.setSpeed(item.value)
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: "subtitles"
                    label.color: "#ffffff"
                    onClicked: trackMenu.toggle()

                    StyledMenu {
                        id: trackMenu

                        y: -height - 8
                        header: "Audio & subtitles"
                        model: {
                            let tracks = [];
                            try {
                                tracks = JSON.parse(mpv.trackList || "[]");
                            } catch (e) {}
                            const items = tracks.filter(t => t.type === "audio" || t.type === "sub").map(t => ({
                                        text: (t.title || t.lang || `Track ${t.id}`) + (t.lang && t.title ? ` (${t.lang})` : ""),
                                        icon: t.type === "audio" ? "music_note" : "subtitles",
                                        checked: t.selected,
                                        type: t.type,
                                        id: t.id
                                    }));
                            const subs = tracks.some(t => t.type === "sub" && t.selected);
                            items.push({
                                text: "Subtitles off",
                                icon: "subtitles_off",
                                checked: !subs,
                                type: "sub",
                                id: "no"
                            });
                            if (subs)
                                items.push({
                                    text: `Subtitle size · ${root.scaleName(root.subScale)}`,
                                    icon: "format_size",
                                    action: "size"
                                }, {
                                    text: `Subtitle timing · ${root.delayName()}`,
                                    icon: "timer",
                                    action: "timing"
                                });
                            return items;
                        }
                        onTriggered: item => {
                            if (item.action === "size")
                                subSizeMenu.open();
                            else if (item.action === "timing")
                                root.timing = true;
                            else
                                mpv.setProp(item.type === "audio" ? "aid" : "sid", String(item.id));
                        }
                    }

                    StyledMenu {
                        id: subSizeMenu

                        y: -height - 8
                        header: "Subtitle size"
                        model: [0.75, 1, 1.25, 1.5, 2].map(v => ({
                                    text: root.scaleName(v),
                                    value: v,
                                    checked: root.subScale === v
                                }))
                        onTriggered: item => root.setSubScale(item.value)
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: "auto_awesome"
                    label.color: root.anime4k && root.anime4k !== "off" ? Theme.palette.primary : "#ffffff"
                    onClicked: a4kMenu.toggle()

                    StyledMenu {
                        id: a4kMenu

                        y: -height - 8
                        header: "Sharpen video"
                        model: [
                            {
                                text: "Off",
                                value: "off",
                                checked: !root.anime4k || root.anime4k === "off"
                            }
                        ].concat(root.anime4kModes.map(m => ({
                                        text: m.name,
                                        value: m.key,
                                        checked: root.anime4k === m.key
                                    })))
                        onTriggered: item => root.setAnime4k(item.value)
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: "playlist_play"
                    label.color: "#ffffff"
                    onClicked: episodesDrawer.open()
                }
                IconButton {
                    type: IconButton.Text
                    icon: "picture_in_picture_alt"
                    label.color: "#ffffff"
                    onClicked: root.app.togglePip()
                }
                IconButton {
                    type: IconButton.Text
                    icon: root.app.visibility === Window.FullScreen ? "fullscreen_exit" : "fullscreen"
                    label.color: "#ffffff"
                    onClicked: root.app.toggleFullScreen()
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.app.pip && root.showControls ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha("#000000", 0.35)
        }
        MouseArea {
            width: 16
            height: 16
            visible: Qt.platform.os !== "osx" // Qt has no system resize there
            cursorShape: Qt.SizeFDiagCursor
            onPressed: root.app.startSystemResize(Qt.TopEdge | Qt.LeftEdge)
        }
        RowLayout {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spacing.small
            spacing: 0

            IconButton {
                type: IconButton.Text
                icon: "open_in_full"
                label.color: "#ffffff"
                onClicked: root.app.togglePip()
            }
            IconButton {
                type: IconButton.Text
                icon: "close"
                label.color: "#ffffff"
                onClicked: root.exit()
            }
        }
        IconButton {
            anchors.centerIn: parent
            visible: root.started && root.phase === "playing"
            icon: mpv.paused ? "play_arrow" : "pause"
            iconSize: 20
            onClicked: root.togglePause()
        }
        LinearProgress {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: mpv.duration > 0
            value: mpv.position / mpv.duration
            trackColor: Qt.alpha("#ffffff", 0.25)
        }
    }

    // Stays visible while the controls are hidden
    IconTextButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.padding.extraLarge
        anchors.bottomMargin: bottom.opacity > 0 ? bottom.height + Theme.spacing.small : Theme.padding.extraLarge
        visible: root.started && root.phase === "playing" && (root.inOp || root.inEd)
        icon: "fast_forward"
        text: root.inOp ? "Skip intro" : "Skip outro"
        verticalPadding: Theme.padding.medium
        horizontalPadding: Theme.padding.large
        onClicked: root.skipSegment()

        Behavior on anchors.bottomMargin {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    StyledRect {
        anchors.left: parent.left
        anchors.bottom: bottom.top
        anchors.margins: Theme.padding.extraLarge
        visible: opacity > 0
        opacity: root.resumePrompt && root.started ? 1 : 0
        implicitWidth: resumeRow.implicitWidth + Theme.padding.large * 2
        implicitHeight: resumeRow.implicitHeight + Theme.padding.medium * 2
        radius: Theme.rounding.large
        color: Theme.palette.surfaceContainerHigh

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        RowLayout {
            id: resumeRow

            anchors.centerIn: parent
            spacing: Theme.spacing.medium

            MaterialIcon {
                text: "history"
                color: Theme.palette.primary
            }
            StyledText {
                text: `Resumed at ${Theme.formatTime(root.resumeAt)}`
            }
            TextButton {
                type: TextButton.Text
                text: "Start over"
                onClicked: {
                    root.seek(0);
                    root.resumePrompt = false;
                }
            }
        }
    }

    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: bottom.top
        anchors.bottomMargin: Theme.padding.extraLarge
        visible: root.timing && bottom.opacity > 0
        implicitWidth: timingRow.implicitWidth + Theme.padding.small * 2
        implicitHeight: timingRow.implicitHeight + Theme.padding.small * 2
        radius: Theme.rounding.full
        color: Theme.palette.surfaceContainerHigh

        RowLayout {
            id: timingRow

            anchors.centerIn: parent
            spacing: Theme.spacing.small

            IconButton {
                type: IconButton.Text
                icon: "remove"
                onClicked: {
                    root.nudgeSubs(-0.1);
                    root.poke();
                }
            }
            StyledText {
                text: `Subtitles ${root.delayName()}`
                font: Theme.font.label.large
            }
            IconButton {
                type: IconButton.Text
                icon: "add"
                onClicked: {
                    root.nudgeSubs(0.1);
                    root.poke();
                }
            }
        }
    }

    StyledRect {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.padding.extraLarge
        visible: root.countdownLeft > 0
        implicitWidth: 340
        implicitHeight: countCol.implicitHeight + Theme.padding.large * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainerHigh

        ColumnLayout {
            id: countCol

            anchors.fill: parent
            anchors.margins: Theme.padding.large
            spacing: Theme.spacing.medium

            StyledText {
                text: `UP NEXT IN ${root.countdownLeft}`
                font: Theme.font.label.large
                color: Theme.palette.primary
            }
            StyledText {
                readonly property var next: root.hasNext ? root.episodes[root.index + 1] : null

                Layout.fillWidth: true
                text: next ? `Episode ${next.num}` + (root.page.info?.[next.num]?.title ? `  ·  ${root.page.info[next.num].title}` : "") : ""
                font: Theme.font.title.medium
                elide: Text.ElideRight
            }
            LinearProgress {
                Layout.fillWidth: true
                value: (5 - root.countdownLeft) / 5
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight

                TextButton {
                    type: TextButton.Text
                    text: "Cancel"
                    onClicked: {
                        root.countdownLeft = 0;
                        root.phase = "ended";
                    }
                }
                TextButton {
                    text: "Play now"
                    onClicked: root.start(root.index + 1)
                }
            }
        }
    }

    StyledRect {
        anchors.centerIn: parent
        visible: root.phase === "error" || root.phase === "ended"
        width: Math.min(parent.width - Theme.padding.extraLarge * 2, 460)
        implicitHeight: card.implicitHeight + Theme.padding.extraLarge * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainerHigh

        ColumnLayout {
            id: card

            readonly property bool failed: root.phase === "error"
            readonly property var others: failed ? root.qualities.filter(q => q !== root.quality).slice(0, 4) : []

            anchors.fill: parent
            anchors.margins: Theme.padding.extraLarge
            spacing: Theme.spacing.medium

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: card.failed ? "(×﹏×)" : "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧"
                font: Theme.font.headline.large
                color: card.failed ? Theme.palette.error : Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: card.failed ? `Couldn't play episode ${root.ep?.num ?? ""}` : root.hasNext ? `Episode ${root.ep?.num} finished` : "You've reached the last episode!"
                font: Theme.font.title.large
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: card.failed ? Api.describe(root.errorText) + (root.tried.length > 1 ? ` Tried ${root.tried.join(", ")} on ${root.sourceName}.` : "") : root.hasNext ? "Ready for the next one?" : "Thanks for watching."
                color: Theme.palette.onSurfaceVariant
                wrapMode: Text.Wrap
            }
            TextEdit {
                Layout.fillWidth: true
                Layout.maximumHeight: 64
                visible: card.failed && text !== ""
                clip: true
                text: root.errorText
                readOnly: true
                selectByMouse: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font: Theme.font.body.small
                color: Qt.alpha(Theme.palette.onSurfaceVariant, 0.7)
                selectionColor: Theme.palette.secondaryContainer
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: card.others.length > 0
                spacing: Theme.spacing.small

                Repeater {
                    model: card.others

                    TextButton {
                        required property string modelData

                        type: TextButton.Tonal
                        text: `Try ${modelData}`
                        onClicked: root.retry(modelData)
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                TextButton {
                    type: TextButton.Text
                    text: "Back"
                    onClicked: root.exit()
                }
                IconTextButton {
                    visible: card.failed
                    type: TextButton.Tonal
                    icon: "refresh"
                    text: "Retry"
                    onClicked: root.retry("")
                }
                IconTextButton {
                    visible: root.phase === "ended"
                    type: TextButton.Tonal
                    icon: "replay"
                    text: "Replay"
                    onClicked: {
                        root.resumeAt = 0;
                        root.start(root.index);
                    }
                }
                IconTextButton {
                    visible: root.hasNext
                    icon: "skip_next"
                    text: "Next episode"
                    onClicked: root.start(root.index + 1)
                }
            }
        }
    }

    Drawer {
        id: episodesDrawer

        edge: Qt.RightEdge
        width: 360
        height: root.height

        background: StyledRect {
            color: Theme.palette.surfaceContainerLow
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padding.large
            spacing: Theme.spacing.medium

            StyledText {
                text: "Episodes"
                font: Theme.font.headline.small
            }

            ListView {
                id: epList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.spacing.small
                model: root.episodes
                currentIndex: root.index
                ScrollBar.vertical: StyledScrollBar {}
                Component.onCompleted: positionViewAtIndex(root.index, ListView.Center)

                delegate: EpisodeTile {
                    required property var modelData
                    required property int index

                    width: epList.width - 8
                    num: modelData.num
                    title: root.page.info?.[modelData.num]?.title || modelData.title
                    record: root.page.progress?.[modelData.num] ?? null
                    current: index === root.index
                    onClicked: {
                        episodesDrawer.close();
                        root.start(index);
                    }
                }
            }
        }
    }

    StyledDialog {
        id: partyDialog

        property bool signedIn
        property bool busy
        property bool copied
        property string error

        icon: "group"
        title: "Watch together"
        text: !signedIn ? "Sign in to sync first." : root.party.active ? "" : "Anyone signed in to your sync server can join with the link."
        width: Math.min(560, parent ? parent.width - 48 : 560)
        onAboutToShow: {
            signedIn = Api.get("syncStatus").signedIn;
            error = "";
            copied = false;
        }
        onClosed: root.forceActiveFocus()

        RowLayout {
            Layout.fillWidth: true
            visible: root.party.active
            spacing: Theme.spacing.extraLarge

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 168
                implicitHeight: 168
                radius: Theme.rounding.medium
                color: "#ffffff"

                Canvas {
                    readonly property var qr: root.party.qr ?? null

                    anchors.fill: parent
                    onQrChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        if (!qr)
                            return;
                        const n = qr.size + 4; // two modules of quiet zone each side, inside the white card's padding
                        const cell = Math.floor(width / n);
                        const offset = (width - cell * qr.size) / 2;
                        ctx.fillStyle = "#000000";
                        for (let y = 0; y < qr.size; y++)
                            for (let x = 0; x < qr.size; x++)
                                if (qr.modules[y * qr.size + x] === "1")
                                    ctx.fillRect(offset + x * cell, offset + y * cell, cell, cell);
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.spacing.medium

                StyledTextField {
                    id: linkField

                    Layout.fillWidth: true
                    readOnly: true
                    text: root.party.link ?? ""
                }
                IconTextButton {
                    type: TextButton.Tonal
                    icon: partyDialog.copied ? "check" : "content_copy"
                    text: partyDialog.copied ? "Copied" : "Copy link"
                    onClicked: {
                        linkField.selectAll();
                        linkField.copy();
                        linkField.deselect();
                        partyDialog.copied = true;
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    spacing: Theme.spacing.small

                    Repeater {
                        model: root.party.members ?? []

                        Chip {
                            required property var modelData

                            icon: modelData.device === "android" ? "smartphone" : "computer"
                            text: modelData.username === root.party.me ? "You" : modelData.username
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: partyDialog.error !== ""
            text: partyDialog.error
            color: Theme.palette.error
            wrapMode: Text.Wrap
        }

        actions: [
            TextButton {
                visible: root.party.active
                type: TextButton.Text
                text: "Leave"
                onClicked: {
                    root.leaveParty();
                    partyDialog.close();
                }
            },
            TextButton {
                type: TextButton.Text
                text: "Close"
                onClicked: partyDialog.close()
            },
            TextButton {
                visible: !partyDialog.signedIn
                type: TextButton.Tonal
                text: "Account"
                onClicked: {
                    partyDialog.close();
                    root.exit();
                    root.app.openAccount();
                }
            },
            TextButton {
                visible: partyDialog.signedIn && !root.party.active
                type: TextButton.Tonal
                text: partyDialog.busy ? "Starting…" : "Start"
                disabled: partyDialog.busy || !root.started
                onClicked: root.startParty()
            }
        ]
    }
}
