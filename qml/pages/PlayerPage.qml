pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

// Embedded mpv player. Mirrors the CLI flow: resolve at the saved quality → play,
// resume prompt, progress every 5 s, complete at 90 %, 5 s autoplay countdown,
// AniSkip OP/ED, Anime4K shaders, Discord presence.
FocusScope {
    id: root

    required property var ctx // {anime, meta, episodes, index, info, seriesKey}

    property int index: ctx.index
    readonly property var ep: ctx.episodes[index]
    readonly property var meta: ctx.meta ?? {}
    readonly property string seriesTitle: meta.title_english || meta.title_romaji || ctx.anime.name
    readonly property string episodeTitle: ctx.info?.[ep?.num]?.title || ep?.title || ""
    readonly property bool hasNext: index + 1 < ctx.episodes.length
    readonly property bool hasPrev: index > 0

    property string phase: "resolving" // resolving | playing | error | ended
    property string errorText
    property var stream: null
    property var qualities: [] // offered for this episode, highest first
    property string quality // label actually requested from the source
    property string preferredQuality: Api.setting("quality")
    property real startAt: -1 // seek here on load without the resume prompt (quality switch)
    property var skip: ({})
    property real resumeAt: 0
    property bool resumePrompt
    property bool completedMarked
    property bool skippedOp
    property bool skippedEd
    property int countdownLeft: 0
    property int request: 0
    property string anime4k: Api.setting("anime4k")
    property var anime4kModes: Api.get("anime4kModes")
    readonly property bool autoplay: Api.setting("autoplay") === "true"
    readonly property bool autoSkip: Api.setting("autoSkip") === "true"
    property bool controlsVisible: true
    readonly property bool showControls: controlsVisible || mpv.paused || phase !== "playing" || speedMenu.opened || trackMenu.opened || a4kMenu.opened || qualityMenu.opened

    readonly property bool inOp: !!skip.op && mpv.position >= skip.op[0] && mpv.position < skip.op[1] - 1
    readonly property bool inEd: !!skip.ed && mpv.position >= skip.ed[0] && mpv.position < skip.ed[1] - 1

    function keysFor(num: int): var {
        return Api.get("keys", {
            anilistId: meta.anilist_id ?? 0,
            source: ctx.anime.source,
            url: ctx.anime.url,
            episode: num
        });
    }

    function save(completed: bool): void {
        if (!ep || mpv.duration <= 0)
            return;
        const done = completed || completedMarked || mpv.position / mpv.duration >= 0.9;
        completedMarked = done;
        Api.get("saveProgress", {
            episode_key: keysFor(ep.num).episode,
            anilist_id: meta.anilist_id ?? 0,
            mal_id: meta.mal_id ?? 0,
            series_key: ctx.seriesKey,
            series_url: ctx.anime.url,
            series_title: seriesTitle,
            source: ctx.anime.source,
            episode_url: ep.url,
            total_episodes: meta.episodes || ctx.episodes.length,
            episode_number: ep.num,
            playback_time: Math.floor(completed ? mpv.duration : mpv.position), // time-pos is gone at end-file
            duration: Math.floor(mpv.duration),
            title: episodeTitle,
            cover: meta.cover || ctx.anime.image || "",
            completed: done,
            last_updated: 0
        });
    }

    function start(i: int): void {
        if (i < 0 || i >= ctx.episodes.length) {
            errorText = `No episode at position ${i}`;
            phase = "error";
            return;
        }
        if (phase === "playing")
            save(false);
        Api.forget(request);
        mpv.command(["stop"]);
        index = i;
        phase = "resolving";
        stream = null;
        skip = {};
        completedMarked = false;
        skippedOp = skippedEd = false;
        resumePrompt = false;
        countdownLeft = 0;
        const saved = Api.get("seriesProgress", {
            key: ctx.seriesKey,
            url: ctx.anime.url
        }).find(p => p.episode_number === ep.num);
        resumeAt = saved && !saved.completed && saved.playback_time > 30 ? saved.playback_time : 0;
        startAt = -1;
        qualities = [];
        quality = "";
        if (meta.mal_id)
            Api.call("skipTimes", {
                malId: meta.mal_id,
                episode: ep.num
            }, s => root.skip = s);
        request = Api.call("qualities", {
            source: ctx.anime.source,
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
        if (phase === "playing") {
            save(false);
            startAt = mpv.position;
            resumePrompt = false;
        }
        resolve(target);
    }

    function resolve(q: string): void {
        Api.forget(request);
        quality = q;
        phase = "resolving";
        request = Api.call("resolve", {
            source: ctx.anime.source,
            url: ep.url,
            quality: q
        }, s => root.load(s), e => {
            root.errorText = e;
            root.phase = "error";
        });
    }

    function load(s: var): void {
        stream = s;
        if (startAt >= 0)
            startAt = Math.max(startAt, mpv.position); // the old stream kept playing while resolving
        mpv.setProp("http-header-fields", s.referer ? "Referer: " + s.referer : "");
        mpv.setProp("demuxer-lavf-o", s.hls ? "allowed_extensions=ALL" : "");
        mpv.setProp("force-media-title", `${seriesTitle} - Episode ${ep.num}`);
        applyShaders();
        mpv.command(["loadfile", s.url]);
        phase = "playing";
        poke();
    }

    function applyShaders(): void {
        if (!anime4k || anime4k === "off") {
            mpv.command(["change-list", "glsl-shaders", "clr", ""]);
            return;
        }
        Api.call("shaders", {
            mode: anime4k
        }, r => mpv.command(["change-list", "glsl-shaders", "set", r.list]), e => ApplicationWindow.window.toast("Anime4K: " + e));
    }

    function setAnime4k(mode: string): void {
        anime4k = mode;
        Api.setSetting("anime4k", mode);
        applyShaders();
        ApplicationWindow.window.toast(mode === "off" ? "Anime4K off" : "Anime4K: " + (anime4kModes.find(m => m.key === mode)?.name ?? mode));
    }

    function seek(sec: real): void {
        mpv.command(["seek", String(sec), "absolute"]);
    }

    function skipSegment(): void {
        if (inOp)
            seek(skip.op[1]);
        else if (inEd)
            seek(skip.ed[1]);
    }

    function exit(): void {
        if (phase === "playing")
            save(false);
        Api.forget(request);
        mpv.command(["stop"]);
        Api.get("stopStreams");
        Api.get("presence", {
            clear: true
        });
        ApplicationWindow.window.closePlayer();
    }

    function poke(): void {
        controlsVisible = true;
        if (!Qt.application.arguments.includes("--screenshot")) // keep controls for dev captures
            hideTimer.restart();
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onPressed: e => {
        poke();
        switch (e.key) {
        case Qt.Key_Space:
        case Qt.Key_K:
            mpv.paused = !mpv.paused;
            break;
        case Qt.Key_Left:
        case Qt.Key_J:
            mpv.command(["seek", e.modifiers & Qt.ShiftModifier ? "-85" : "-5"]);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            mpv.command(["seek", e.modifiers & Qt.ShiftModifier ? "85" : "5"]);
            break;
        case Qt.Key_Up:
            mpv.volume = Math.min(130, mpv.volume + 5);
            break;
        case Qt.Key_Down:
            mpv.volume = Math.max(0, mpv.volume - 5);
            break;
        case Qt.Key_M:
            mpv.command(["cycle", "mute"]);
            break;
        case Qt.Key_F:
            ApplicationWindow.window.toggleFullScreen();
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
        case Qt.Key_Escape:
            if (ApplicationWindow.window.visibility === Window.FullScreen)
                ApplicationWindow.window.showNormal();
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

    MpvItem {
        id: mpv

        anchors.fill: parent
        Component.onCompleted: {
            setProp("cache", "yes");
            setProp("demuxer-max-bytes", "300MiB");
            setProp("demuxer-readahead-secs", "20");
            setProp("audio-display", "no");
            setProp("keep-open", "no");
            volume = Number(Api.setting("volume")) || 100;
        }
        onReadyChanged: if (ready)
            root.start(root.index)
        onFileLoaded: {
            if (root.startAt >= 0) {
                root.seek(root.startAt);
                root.startAt = -1;
            } else if (root.resumeAt > 0) {
                root.seek(root.resumeAt);
                root.resumePrompt = true;
                resumeHide.restart();
            }
        }
        onEndFile: (reason, error) => {
            if (root.phase !== "playing")
                return;
            if (reason === "eof") {
                root.save(true);
                ApplicationWindow.window.historyRevision++;
                if (root.autoplay && root.hasNext)
                    root.countdownLeft = 5;
                else
                    root.phase = "ended";
            } else if (reason === "error") {
                root.errorText = error || "Playback failed";
                root.phase = "error";
            }
        }
        onVolumeChanged: volSave.restart()
        onPositionChanged: {
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
            cover: root.meta.cover || root.ctx.anime.image || "",
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
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.showControls ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: root.poke()
        onClicked: {
            mpv.paused = !mpv.paused;
            flash.trigger(mpv.paused ? "pause" : "play_arrow");
        }
        onDoubleClicked: ApplicationWindow.window.toggleFullScreen()
    }

    // ---- centre feedback
    Loading {
        anchors.centerIn: parent
        size: 64
        visible: root.phase === "resolving" || (root.phase === "playing" && (mpv.buffering || mpv.idle))
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: 52
        visible: root.phase === "resolving"
        text: `Finding a stream for episode ${root.ep?.num ?? ""}…`
        color: "#ffffff"
        font: Theme.font.title.medium
    }

    StyledRect {
        id: flash

        function trigger(icon: string): void {
            flashIcon.text = icon;
            flashAnim.restart();
        }

        anchors.centerIn: parent
        width: 88
        height: 88
        radius: 44
        color: Qt.alpha("#000000", 0.5)
        opacity: 0

        MaterialIcon {
            id: flashIcon

            anchors.centerIn: parent
            fill: 1
            size: 32
            color: "#ffffff"
        }

        ParallelAnimation {
            id: flashAnim

            NumberAnimation {
                target: flash
                property: "opacity"
                from: 1
                to: 0
                duration: 600
            }
            NumberAnimation {
                target: flash
                property: "scale"
                from: 0.8
                to: 1.3
                duration: 600
                easing.type: Easing.OutCubic
            }
        }
    }

    // ---- top bar
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 120
        opacity: root.showControls ? 1 : 0
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
                text: root.ctx.anime.source + (root.quality && root.quality !== "best" ? `  ·  ${root.quality}` : "")
                icon: "public"
                selected: true
                tint: Qt.alpha("#000000", 0.45)
                onTint: "#ffffff"
            }
        }
    }

    // ---- bottom controls
    Item {
        id: bottom

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 150
        opacity: root.showControls ? 1 : 0
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
                    color: Qt.alpha("#000000", 0.8)
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
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                StyledText {
                    text: Theme.formatTime(seek.pressed ? seek.value * mpv.duration : mpv.position)
                    color: "#ffffff"
                    font: Theme.font.label.large
                }
                StyledSlider {
                    id: seek

                    Layout.fillWidth: true
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
                }
                StyledText {
                    text: Theme.formatTime(mpv.duration)
                    color: Qt.alpha("#ffffff", 0.75)
                    font: Theme.font.label.large
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "skip_previous"
                    disabled: !root.hasPrev
                    label.color: "#ffffff"
                    onClicked: root.start(root.index - 1)
                }
                IconButton {
                    icon: mpv.paused ? "play_arrow" : "pause"
                    iconSize: 20
                    onClicked: mpv.paused = !mpv.paused
                }
                IconButton {
                    type: IconButton.Text
                    icon: "skip_next"
                    disabled: !root.hasNext
                    label.color: "#ffffff"
                    onClicked: root.start(root.index + 1)
                }
                IconButton {
                    type: IconButton.Text
                    icon: mpv.volume === 0 ? "volume_off" : mpv.volume < 50 ? "volume_down" : "volume_up"
                    label.color: "#ffffff"
                    onClicked: mpv.volume = mpv.volume > 0 ? 0 : 100
                }
                StyledSlider {
                    Layout.preferredWidth: 110
                    trackHeight: 6
                    from: 0
                    to: 130
                    value: mpv.volume
                    onMoved: mpv.volume = value
                }
                Item {
                    Layout.fillWidth: true
                }
                IconTextButton {
                    visible: root.inOp || root.inEd
                    icon: "fast_forward"
                    text: root.inOp ? "Skip intro" : "Skip outro"
                    onClicked: root.skipSegment()
                }
                IconTextButton {
                    type: TextButton.Text
                    icon: "settings"
                    text: root.quality && root.quality !== "best" ? root.quality : "Auto"
                    label.color: "#ffffff"
                    iconLabel.color: "#ffffff"
                    onClicked: qualityMenu.open()

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
                    text: mpv.speed === 1 ? "1×" : mpv.speed + "×"
                    label.color: "#ffffff"
                    iconLabel.color: "#ffffff"
                    onClicked: speedMenu.open()

                    StyledMenu {
                        id: speedMenu

                        y: -height - 8
                        header: "Speed"
                        model: [0.5, 0.75, 1, 1.25, 1.5, 2].map(v => ({
                                    text: v + "×",
                                    value: v,
                                    checked: mpv.speed === v
                                }))
                        onTriggered: item => mpv.speed = item.value
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: "subtitles"
                    label.color: "#ffffff"
                    onClicked: trackMenu.open()

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
                                        text: (t.type === "audio" ? "🔊 " : "💬 ") + (t.title || t.lang || `Track ${t.id}`) + (t.lang && t.title ? ` (${t.lang})` : ""),
                                        checked: t.selected,
                                        type: t.type,
                                        id: t.id
                                    }));
                            items.push({
                                text: "Subtitles off",
                                type: "sub",
                                id: "no"
                            });
                            return items;
                        }
                        onTriggered: item => mpv.setProp(item.type === "audio" ? "aid" : "sid", String(item.id))
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: "auto_awesome"
                    label.color: root.anime4k && root.anime4k !== "off" ? Theme.palette.primary : "#ffffff"
                    onClicked: a4kMenu.open()

                    StyledMenu {
                        id: a4kMenu

                        y: -height - 8
                        header: "Anime4K upscaling"
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
                    icon: ApplicationWindow.window.visibility === Window.FullScreen ? "fullscreen_exit" : "fullscreen"
                    label.color: "#ffffff"
                    onClicked: ApplicationWindow.window.toggleFullScreen()
                }
            }
        }
    }

    // ---- resume prompt
    StyledRect {
        anchors.left: parent.left
        anchors.bottom: bottom.top
        anchors.margins: Theme.padding.extraLarge
        visible: opacity > 0
        opacity: root.resumePrompt ? 1 : 0
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

    // ---- autoplay countdown
    StyledRect {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.padding.extraLarge
        visible: root.countdownLeft > 0
        implicitWidth: 320
        implicitHeight: countCol.implicitHeight + Theme.padding.large * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainerHigh

        ColumnLayout {
            id: countCol

            anchors.fill: parent
            anchors.margins: Theme.padding.large
            spacing: Theme.spacing.medium

            StyledText {
                text: "UP NEXT"
                font: Theme.font.label.large
                color: Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.hasNext ? `Episode ${root.ctx.episodes[root.index + 1].num} in ${root.countdownLeft}…` : ""
                font: Theme.font.title.medium
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

    // ---- error / ended card
    StyledRect {
        anchors.centerIn: parent
        visible: root.phase === "error" || root.phase === "ended"
        implicitWidth: 420
        implicitHeight: card.implicitHeight + Theme.padding.extraLarge * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainerHigh

        ColumnLayout {
            id: card

            anchors.fill: parent
            anchors.margins: Theme.padding.extraLarge
            spacing: Theme.spacing.large

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.phase === "error" ? "(×﹏×)" : "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧"
                font: Theme.font.headline.large
                color: root.phase === "error" ? Theme.palette.error : Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.phase === "error" ? "Couldn't play this episode" : root.hasNext ? "Episode finished" : "You've reached the last episode!"
                font: Theme.font.title.large
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.phase === "error"
                horizontalAlignment: Text.AlignHCenter
                text: root.errorText
                color: Theme.palette.onSurfaceVariant
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacing.small

                TextButton {
                    type: TextButton.Text
                    text: "Back"
                    onClicked: root.exit()
                }
                TextButton {
                    visible: root.phase === "error"
                    type: TextButton.Tonal
                    text: "Retry"
                    onClicked: root.start(root.index)
                }
                TextButton {
                    visible: root.phase === "ended" && root.hasNext
                    text: "Next episode"
                    onClicked: root.start(root.index + 1)
                }
                TextButton {
                    visible: root.phase === "ended"
                    type: TextButton.Tonal
                    text: "Replay"
                    onClicked: {
                        root.resumeAt = 0;
                        root.start(root.index);
                    }
                }
            }
        }
    }

    // ---- episode picker
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
                model: root.ctx.episodes
                currentIndex: root.index
                ScrollBar.vertical: StyledScrollBar {}
                Component.onCompleted: positionViewAtIndex(root.index, ListView.Center)

                delegate: EpisodeTile {
                    required property var modelData
                    required property int index

                    width: epList.width - 8
                    num: modelData.num
                    title: root.ctx.info?.[modelData.num]?.title || modelData.title
                    current: index === root.index
                    onClicked: {
                        episodesDrawer.close();
                        root.start(index);
                    }
                }
            }
        }
    }
}
