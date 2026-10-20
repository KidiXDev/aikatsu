pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    required property var anime // {name, url, image, source, anilistId?}
    property int autoplayEpisode: 0 // episode number to start right away; -1 = latest

    property var meta: null
    property bool metaLoaded: false // the player holds progress saves until this (keeps keys stable)
    property var episodes: []
    property var info: ({}) // episode number -> {title, filler, recap}
    property var progress: ({}) // episode number -> progress row
    property var watchEntry: null
    property bool loading: true
    property string error
    property bool descending: false
    property string jump: ""
    readonly property bool local: anime.source === "local"

    readonly property string seriesKey: Api.get("keys", {
        anilistId: meta?.anilist_id ?? 0,
        source: anime.source,
        url: anime.url,
        episode: 0
    }).series
    readonly property var shownEpisodes: {
        let eps = episodes;
        if (jump)
            eps = eps.filter(e => String(e.num).startsWith(jump));
        return descending ? eps.slice().reverse() : eps;
    }
    readonly property int continueIndex: {
        let latest = -1, at = 0;
        for (let i = 0; i < episodes.length; i++) {
            const p = progress[episodes[i].num];
            if (p && !p.completed && p.playback_time > 0 && p.last_updated > at) {
                latest = i;
                at = p.last_updated;
            }
        }
        if (latest >= 0)
            return latest;
        const firstUnwatched = episodes.findIndex(e => !progress[e.num]?.completed);
        return firstUnwatched >= 0 ? firstUnwatched : 0;
    }

    function listEntry(): var {
        return {
            anilist_id: meta?.anilist_id ?? 0,
            mal_id: meta?.mal_id ?? 0,
            title: meta?.title_english || meta?.title_romaji || anime.name,
            cover: meta?.cover || anime.image || "",
            source: anime.source,
            series_url: anime.url,
            total_episodes: meta?.episodes || 0
        };
    }

    function setWatchStatus(status: string): void {
        Api.get("setWatchStatus", {
            entry: listEntry(),
            status: status
        });
        ApplicationWindow.window.historyRevision++;
    }

    function refreshProgress(): void {
        watchEntry = metaLoaded ? Api.get("watchEntry", listEntry()) : null;
        const map = {};
        for (const p of Api.get("seriesProgress", {
            key: seriesKey,
            url: anime.url
        }))
            map[p.episode_number] = p;
        progress = map;
    }

    // Repeater/menu modelData are copies of the array elements, so match by URL, not identity.
    function indexOfEpisode(ep: var): int {
        return episodes.findIndex(e => e.url === ep?.url);
    }

    // Opens right away; the player picks up metadata when it lands.
    function play(index: int): void {
        if (index >= 0 && index < episodes.length)
            ApplicationWindow.window.play(root, index);
    }

    function progressRow(ep: var): var {
        return {
            episode_key: Api.get("keys", {
                anilistId: meta?.anilist_id ?? 0,
                source: anime.source,
                url: anime.url,
                episode: ep.num
            }).episode,
            anilist_id: meta?.anilist_id ?? 0,
            mal_id: meta?.mal_id ?? 0,
            series_key: seriesKey,
            series_url: anime.url,
            series_title: meta?.title_english || meta?.title_romaji || anime.name,
            source: anime.source,
            episode_url: ep.url,
            total_episodes: meta?.episodes || episodes.length,
            meta_episodes: meta?.episodes || 0,
            episode_number: ep.num,
            playback_time: progress[ep.num]?.playback_time ?? 0,
            duration: progress[ep.num]?.duration ?? 0,
            title: info[ep.num]?.title || ep.title,
            cover: meta?.cover || anime.image,
            completed: false,
            last_updated: 0
        };
    }

    // refresh: the refresh/retry buttons skip the page and metadata caches.
    function load(refresh: bool): void {
        loading = true;
        error = "";
        Api.call("episodes", {
            source: anime.source,
            url: anime.url,
            refresh: refresh
        }, eps => {
            root.episodes = eps;
            root.loading = false;
            root.refreshProgress();
            if (root.autoplayEpisode !== 0) {
                // -1 = latest episode (dev aid `--play`)
                const i = root.autoplayEpisode < 0 ? eps.length - 1 : eps.findIndex(e => e.num === root.autoplayEpisode);
                root.autoplayEpisode = 0;
                root.play(i >= 0 ? i : root.continueIndex);
            }
        }, e => {
            root.loading = false;
            root.error = e;
        });
        Api.call("enrich", {
            name: anime.name,
            url: anime.url,
            anilistId: anime.anilistId ?? 0,
            refresh: refresh
        }, m => {
            root.meta = m;
            root.metaLoaded = true;
            root.refreshProgress();
            if (m.mal_id || m.anilist_id)
                Api.call("episodeInfo", {
                    malId: m.mal_id,
                    anilistId: m.anilist_id,
                    refresh: refresh
                }, list => {
                    const map = {};
                    for (const e of list)
                        map[e.num] = e;
                    root.info = map;
                });
        }, () => {
            root.meta = {};
            root.metaLoaded = true;
            root.refreshProgress();
        });
    }

    Component.onCompleted: load(false)

    Connections {
        target: root.ApplicationWindow.window

        function onHistoryRevisionChanged(): void {
            root.refreshProgress();
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.padding.extraLarge
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col

            width: flick.width
            spacing: Theme.spacing.large

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 300

                ClippedImage {
                    id: banner

                    anchors.fill: parent
                    radius: 0
                    visible: false
                    source: root.meta?.banner || root.meta?.cover || root.anime.image
                }
                MultiEffect {
                    anchors.fill: parent
                    source: banner
                    autoPaddingEnabled: false // the padded blur halo shows as a line under the hero
                    blurEnabled: true
                    blur: root.meta?.banner ? 0.1 : 1
                    blurMax: 56
                    opacity: banner.status === Image.Ready ? 1 : 0

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
                            color: Qt.alpha(Theme.palette.surface, 0.2)
                        }
                        GradientStop {
                            position: 1
                            color: Theme.palette.surface
                        }
                    }
                }

                SakuraFall {
                    rate: 2
                }

                IconButton {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: Theme.padding.large
                    type: IconButton.Tonal
                    icon: "arrow_back"
                    onClicked: root.StackView.view.pop()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.topMargin: -200
                spacing: Theme.spacing.extraLarge

                ClippedImage {
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 275
                    Layout.alignment: Qt.AlignTop
                    radius: Theme.rounding.extraLarge
                    source: root.meta?.cover || root.anime.image

                    Elevation {
                        z: -1
                        anchors.fill: parent
                        radius: parent.radius
                        level: 4
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Theme.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: root.meta?.title_english || root.meta?.title_romaji || root.anime.name
                        font: Theme.font.display.medium
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: [root.meta?.title_romaji, root.meta?.title_native].filter(t => t && t !== (root.meta?.title_english || "")).join("  ·  ")
                        color: Theme.palette.onSurfaceVariant
                        font: Theme.font.title.medium
                        elide: Text.ElideRight
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.small
                        spacing: Theme.spacing.small

                        Chip {
                            text: Api.sourceName(root.anime.source)
                            icon: root.local ? "folder" : "public"
                            selected: true
                        }
                        Chip {
                            visible: (root.meta?.score ?? 0) > 0
                            text: `★ ${((root.meta?.score ?? 0) / 10).toFixed(1)}`
                            selected: true
                            tint: Theme.palette.tertiaryContainer
                            onTint: Theme.palette.onTertiaryContainer
                        }
                        Chip {
                            visible: (root.meta?.year ?? 0) > 0
                            text: String(root.meta?.year ?? "")
                            icon: "calendar_month"
                        }
                        Chip {
                            visible: root.episodes.length > 0
                            text: `${root.episodes.length} episodes` + ((root.meta?.episodes ?? 0) > root.episodes.length ? ` of ${root.meta.episodes}` : "")
                            icon: "video_library"
                        }
                        Chip {
                            visible: !!root.meta?.status
                            text: (root.meta?.status ?? "").replace(/_/g, " ").toLowerCase()
                            icon: "radio_button_checked"
                        }
                        Repeater {
                            model: root.meta?.genres ?? []

                            Chip {
                                required property string modelData

                                text: modelData
                            }
                        }
                    }

                    RowLayout {
                        Layout.topMargin: Theme.spacing.medium
                        spacing: Theme.spacing.small

                        IconTextButton {
                            disabled: root.episodes.length === 0
                            icon: root.loading ? "hourglass_top" : "play_arrow"
                            text: root.episodes.length ? (Object.keys(root.progress).length ? `Continue  ·  Ep ${root.episodes[root.continueIndex].num}` : `Play  ·  Ep ${root.episodes[0].num}`) : root.loading ? "Loading episodes…" : "Play"
                            verticalPadding: Theme.padding.medium
                            horizontalPadding: Theme.padding.large
                            onClicked: root.play(root.continueIndex)
                        }
                        IconTextButton {
                            visible: !root.local
                            type: TextButton.Tonal
                            disabled: root.episodes.length === 0
                            icon: "download"
                            text: "Download…"
                            verticalPadding: Theme.padding.medium
                            horizontalPadding: Theme.padding.large
                            onClicked: downloadDialog.openFor(null)
                        }
                        IconTextButton {
                            visible: root.local
                            type: TextButton.Tonal
                            icon: "link"
                            text: "Choose anime…"
                            verticalPadding: Theme.padding.medium
                            horizontalPadding: Theme.padding.large
                            onClicked: matchDialog.openFor(root.anime.url, root.anime.name)
                        }
                        IconTextButton {
                            readonly property var current: Api.watchStatuses.find(s => s.value === root.watchEntry?.status)

                            type: TextButton.Tonal
                            disabled: !root.metaLoaded
                            icon: current?.icon ?? "bookmark_add"
                            text: current?.text ?? "Add to list"
                            verticalPadding: Theme.padding.medium
                            horizontalPadding: Theme.padding.large
                            onClicked: watchMenu.toggle()

                            StyledMenu {
                                id: watchMenu

                                y: parent.height + 4
                                model: Api.watchStatuses.map(s => Object.assign({
                                        checked: s.value === root.watchEntry?.status
                                    }, s)).concat(root.watchEntry ? [
                                        {
                                            text: "Remove from list",
                                            icon: "bookmark_remove",
                                            value: ""
                                        }
                                    ] : [])
                                onTriggered: item => root.setWatchStatus(item.value)
                            }
                        }
                        IconButton {
                            type: IconButton.Text
                            icon: "refresh"
                            onClicked: root.load(true)
                        }
                    }
                }
            }

            StyledText {
                id: synopsis

                property bool expanded

                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.maximumWidth: 980
                visible: text !== ""
                text: root.meta?.description ?? ""
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.body.large
                wrapMode: Text.Wrap
                maximumLineCount: expanded ? 100 : 3
                elide: Text.ElideRight
                lineHeight: 1.15

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: synopsis.expanded = !synopsis.expanded
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.topMargin: Theme.spacing.medium
                spacing: Theme.spacing.medium

                StyledText {
                    text: "Episodes"
                    font: Theme.font.headline.small
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledRect {
                    implicitWidth: 150
                    implicitHeight: 36
                    radius: Theme.rounding.full
                    color: Theme.palette.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padding.medium
                        anchors.rightMargin: Theme.padding.medium

                        MaterialIcon {
                            text: "tag"
                            size: 13
                            color: Theme.palette.onSurfaceVariant
                        }
                        TextFieldBase {
                            id: jumpField

                            Layout.fillWidth: true
                            validator: IntValidator {
                                bottom: 0
                            }
                            onTextChanged: root.jump = text

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !jumpField.text
                                text: "Jump to…"
                                color: Theme.palette.onSurfaceVariant
                            }
                        }
                    }
                }
                IconButton {
                    type: IconButton.Text
                    icon: root.descending ? "arrow_upward" : "arrow_downward"
                    onClicked: root.descending = !root.descending
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                columns: Math.max(1, Math.floor((width + columnSpacing) / (260 + columnSpacing)))
                columnSpacing: Theme.spacing.medium
                rowSpacing: Theme.spacing.medium

                // skeleton while the episode list loads
                Repeater {
                    model: root.loading && root.episodes.length === 0 ? 12 : 0

                    StyledRect {
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: Theme.rounding.large
                        color: Theme.palette.surfaceContainer

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation {
                                duration: (index % 6) * 90
                            }
                            NumberAnimation {
                                to: 0.45
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 1
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }

                Repeater {
                    model: root.shownEpisodes

                    EpisodeTile {
                        required property var modelData

                        Layout.fillWidth: true
                        num: modelData.num
                        title: root.info[modelData.num]?.title || modelData.title
                        filler: root.info[modelData.num]?.filler ?? false
                        recap: root.info[modelData.num]?.recap ?? false
                        record: root.progress[modelData.num] ?? null
                        current: root.episodes[root.continueIndex]?.num === modelData.num && Object.keys(root.progress).length > 0
                        onClicked: root.play(root.indexOfEpisode(modelData))
                        onRightClicked: (x, y) => {
                            epMenu.ep = modelData;
                            const p = mapToItem(root, x, y);
                            epMenu.x = p.x;
                            epMenu.y = p.y;
                            epMenu.open();
                        }
                    }
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge
                visible: !root.loading && root.episodes.length === 0
                face: "(×﹏×)"
                title: root.error ? `Couldn't load episodes from ${Api.sourceName(root.anime.source)}` : "No episodes yet"
                message: root.error ? Api.describe(root.error) : ""
                details: root.error
                tint: Theme.palette.error

                IconTextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    type: TextButton.Tonal
                    icon: "refresh"
                    text: "Try again"
                    onClicked: root.load(true)
                }
            }
        }
    }

    StyledMenu {
        id: epMenu

        property var ep

        model: [
            {
                text: "Play",
                icon: "play_arrow",
                value: "play"
            },
            {
                text: root.progress[ep?.num]?.completed ? "Mark as unwatched" : "Mark as watched",
                icon: "task_alt",
                value: "toggle"
            }
        ].concat(root.local ? [] : [
                {
                    text: "Download episode",
                    icon: "download",
                    value: "download"
                }
            ])
        onTriggered: item => {
            if (item.value === "play")
                root.play(root.indexOfEpisode(ep));
            else if (item.value === "toggle") {
                const done = !(root.progress[ep.num]?.completed ?? false);
                Api.get("setCompleted", {
                    progress: root.progressRow(ep),
                    completed: done
                });
                root.refreshProgress();
            } else if (item.value === "download")
                downloadDialog.openFor(ep);
        }
    }

    DownloadDialog {
        id: downloadDialog

        anime: root.anime
        meta: root.meta
        episodes: root.episodes
    }

    MatchDialog {
        id: matchDialog

        onLinked: m => {
            root.anime = Object.assign({}, root.anime, {
                anilistId: m.anilist_id
            });
            root.load(true);
        }
    }
}
