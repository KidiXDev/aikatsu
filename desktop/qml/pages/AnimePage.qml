pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    readonly property Main app: ApplicationWindow.window as Main

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
    property string epFilter: "all" // all | unwatched | watched
    property string section: "episodes" // episodes | cast | details
    property string roleFilter: "all" // all | MAIN | SUPPORTING
    readonly property bool local: anime.source === "local"
    readonly property int watchedCount: episodes.filter(e => progress[e.num]?.completed).length
    readonly property var characters: meta?.characters ?? []
    readonly property var shownCharacters: roleFilter === "all" ? characters : characters.filter(c => c.role === roleFilter)
    readonly property var staffList: meta?.staff ?? []
    readonly property var relationsList: meta?.relations ?? []
    readonly property var recommendationsList: meta?.recommendations ?? []
    readonly property var tagsList: meta?.tags ?? []

    readonly property string seriesKey: Api.get("keys", {
        anilistId: meta?.anilist_id ?? 0,
        source: anime.source,
        url: anime.url,
        episode: 0
    }).series
    readonly property var shownEpisodes: {
        let eps = episodes;
        if (epFilter === "unwatched")
            eps = eps.filter(e => !progress[e.num]?.completed);
        else if (epFilter === "watched")
            eps = eps.filter(e => !!progress[e.num]?.completed);
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

    function prettyEnum(raw: string): string {
        if (!raw)
            return "";
        const upper = raw.toUpperCase();
        if (upper === "TV" || upper === "OVA" || upper === "ONA")
            return upper;
        if (upper === "TV_SHORT")
            return "TV Short";
        return raw.replace(/_/g, " ").toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
    }

    function seasonLabel(): string {
        const s = prettyEnum(meta?.season ?? "");
        const y = (meta?.season_year ?? 0) || (meta?.year ?? 0);
        if (s && y > 0)
            return `${s} ${y}`;
        return y > 0 ? String(y) : s;
    }

    function airingText(): string {
        const next = meta?.next_airing;
        if (!next || !next.airing_at)
            return "";
        const diffSec = Math.floor(next.airing_at - Date.now() / 1000);
        if (diffSec <= 0)
            return `Episode ${next.episode} airing now`;
        const days = Math.floor(diffSec / 86400);
        const hours = Math.floor((diffSec % 86400) / 3600);
        const mins = Math.floor((diffSec % 3600) / 60);
        if (days > 0)
            return `Episode ${next.episode} airs in ${days}d ${hours}h`;
        if (hours > 0)
            return `Episode ${next.episode} airs in ${hours}h ${mins}m`;
        return `Episode ${next.episode} airs in ${Math.max(1, mins)}m`;
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
        root.app.historyRevision++;
    }

    function markAll(completed: bool): void {
        Api.get("setCompleted", {
            progress: episodes.map(e => progressRow(e)),
            completed: completed
        });
        root.app.historyRevision++;
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
            root.app.play(root, index);
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
        target: root.app

        function onHistoryRevisionChanged(): void {
            root.refreshProgress();
        }
    }

    component SectionHeader: RowLayout {
        id: secHdr

        property string icon: "info"
        property string title
        property string badge: ""

        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        StyledRect {
            implicitWidth: 34
            implicitHeight: 34
            radius: Theme.rounding.medium
            color: Theme.palette.secondaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: secHdr.icon
                fill: 1
                size: 16
                color: Theme.palette.onSecondaryContainer
            }
        }
        StyledText {
            text: secHdr.title
            font: Theme.font.headline.small
        }
        StyledRect {
            visible: secHdr.badge !== ""
            implicitWidth: Math.max(24, secBadgeText.implicitWidth + 12)
            implicitHeight: 24
            radius: Theme.rounding.full
            color: Theme.palette.surfaceContainerHigh

            StyledText {
                id: secBadgeText

                anchors.centerIn: parent
                text: secHdr.badge
                font: Theme.font.label.medium
                color: Theme.palette.onSurfaceVariant
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }

    component FactTile: StyledRect {
        id: factTile

        property string label
        property string value
        property string icon: ""

        Layout.fillWidth: true
        visible: value !== ""
        implicitHeight: factCol.implicitHeight + Theme.padding.medium * 2
        radius: Theme.rounding.medium
        color: Theme.palette.surfaceContainerHigh

        ColumnLayout {
            id: factCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.padding.medium
            spacing: 2

            RowLayout {
                spacing: 4

                MaterialIcon {
                    visible: factTile.icon !== ""
                    text: factTile.icon
                    size: 12
                    color: Theme.palette.onSurfaceVariant
                }
                StyledText {
                    text: factTile.label
                    font: Theme.font.label.medium
                    color: Theme.palette.onSurfaceVariant
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: factTile.value
                font: Theme.font.title.small
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col

            width: flick.width
            spacing: Theme.spacing.large

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 310

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
                            position: 0.6
                            color: Qt.alpha(Theme.palette.surface, 0.65)
                        }
                        GradientStop {
                            position: 1
                            color: Theme.palette.surface
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Qt.alpha(Theme.palette.surface, 0.78)
                        }
                        GradientStop {
                            position: 0.65
                            color: "transparent"
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
                    ToolTip.visible: hovered
                    ToolTip.text: "Back"
                    onClicked: root.StackView.view.pop()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.topMargin: -210
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
                            visible: (root.meta?.studios?.length ?? 0) > 0
                            text: root.meta?.studios?.[0] ?? ""
                            icon: "movie"
                            selected: true
                        }
                        Chip {
                            visible: !!root.meta?.format
                            text: root.prettyEnum(root.meta?.format ?? "")
                            icon: "tv"
                        }
                        Chip {
                            visible: root.seasonLabel() !== ""
                            text: root.seasonLabel()
                            icon: "calendar_month"
                        }
                        Chip {
                            visible: root.episodes.length > 0 || (root.meta?.episodes ?? 0) > 0
                            text: {
                                const avail = root.episodes.length;
                                const total = root.meta?.episodes ?? 0;
                                const dur = (root.meta?.duration ?? 0) > 0 ? ` · ${root.meta.duration}m` : "";
                                if (avail > 0)
                                    return `${avail} episodes` + (total > avail ? ` of ${total}` : "") + dur;
                                return `${total} episodes${dur}`;
                            }
                            icon: "video_library"
                        }
                        Chip {
                            visible: !!root.meta?.status
                            text: root.prettyEnum(root.meta?.status ?? "")
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

                    StyledRect {
                        visible: root.airingText() !== ""
                        Layout.topMargin: Theme.spacing.extraSmall
                        implicitWidth: airingRow.implicitWidth + Theme.padding.medium * 2
                        implicitHeight: 30
                        radius: Theme.rounding.full
                        color: Qt.alpha(Theme.palette.primaryContainer, Theme.dark ? 0.55 : 0.7)

                        RowLayout {
                            id: airingRow

                            anchors.centerIn: parent
                            spacing: Theme.spacing.extraSmall

                            MaterialIcon {
                                text: "schedule"
                                size: 14
                                color: Theme.palette.primary
                            }
                            StyledText {
                                text: root.airingText()
                                font: Theme.font.label.large
                                color: Theme.palette.onPrimaryContainer
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
                            onClicked: matchDialog.openFor(root.anime.source, root.anime.url, root.anime.name)
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
                            visible: !root.local
                            type: IconButton.Text
                            icon: "edit"
                            ToolTip.visible: hovered
                            ToolTip.text: "Choose anime…"
                            onClicked: matchDialog.openFor(root.anime.source, root.anime.url, root.anime.name)
                        }
                        IconButton {
                            visible: (root.meta?.anilist_id ?? 0) > 0
                            type: IconButton.Text
                            icon: "open_in_new"
                            ToolTip.visible: hovered
                            ToolTip.text: "Open on AniList"
                            onClicked: Qt.openUrlExternally(`https://anilist.co/anime/${root.meta.anilist_id}`)
                        }
                        IconButton {
                            type: IconButton.Text
                            icon: "refresh"
                            ToolTip.visible: hovered
                            ToolTip.text: "Refresh episodes and metadata"
                            onClicked: root.load(true)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.maximumWidth: 980
                visible: synopsis.text !== ""
                spacing: Theme.spacing.extraSmall

                StyledText {
                    id: synopsis

                    property bool expanded

                    Layout.fillWidth: true
                    text: root.meta?.description ?? ""
                    color: Theme.palette.onSurfaceVariant
                    font: Theme.font.body.large
                    wrapMode: Text.Wrap
                    maximumLineCount: expanded ? 100 : 3
                    elide: Text.ElideRight
                    lineHeight: 1.15

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: synopsis.truncated || synopsis.expanded ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (synopsis.truncated || synopsis.expanded)
                            synopsis.expanded = !synopsis.expanded
                    }
                }

                TextButton {
                    visible: synopsis.truncated || synopsis.expanded
                    type: TextButton.Text
                    horizontalPadding: 0
                    verticalPadding: 2
                    text: synopsis.expanded ? "Show less" : "Read more"
                    onClicked: synopsis.expanded = !synopsis.expanded
                }
            }

            // Top-level section navigation + contextual toolbar
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.medium

                SegmentedControl {
                    options: [
                        {
                            value: "episodes",
                            label: "Episodes",
                            icon: "video_library",
                            count: root.episodes.length
                        },
                        {
                            value: "cast",
                            label: "Cast & Staff",
                            icon: "groups",
                            count: root.characters.length + root.staffList.length
                        },
                        {
                            value: "details",
                            label: "Details & Relations",
                            icon: "info",
                            count: root.relationsList.length + root.recommendationsList.length
                        }
                    ]
                    value: root.section
                    onPicked: v => root.section = v
                }

                StyledRect {
                    visible: root.section === "episodes" && root.watchedCount > 0
                    implicitWidth: Math.max(24, epBadge.implicitWidth + 12)
                    implicitHeight: 26
                    radius: Theme.rounding.full
                    color: Theme.palette.surfaceContainerHigh

                    StyledText {
                        id: epBadge

                        anchors.centerIn: parent
                        text: `${root.watchedCount} / ${root.episodes.length} watched`
                        font: Theme.font.label.medium
                        color: Theme.palette.onSurfaceVariant
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Cast role filter
                SegmentedControl {
                    visible: root.section === "cast" && root.characters.some(c => c.role === "MAIN") && root.characters.some(c => c.role === "SUPPORTING")
                    options: [
                        {
                            value: "all",
                            label: "All",
                            count: root.characters.length
                        },
                        {
                            value: "MAIN",
                            label: "Main",
                            count: root.characters.filter(c => c.role === "MAIN").length
                        },
                        {
                            value: "SUPPORTING",
                            label: "Supporting",
                            count: root.characters.filter(c => c.role === "SUPPORTING").length
                        }
                    ]
                    value: root.roleFilter
                    onPicked: v => root.roleFilter = v
                }

                // Episode filters & jump
                SegmentedControl {
                    visible: root.section === "episodes" && root.watchedCount > 0 && root.watchedCount < root.episodes.length
                    options: [
                        {
                            value: "all",
                            label: "All"
                        },
                        {
                            value: "unwatched",
                            label: "Unwatched"
                        },
                        {
                            value: "watched",
                            label: "Watched"
                        }
                    ]
                    value: root.epFilter
                    onPicked: v => root.epFilter = v
                }

                StyledRect {
                    visible: root.section === "episodes"
                    implicitWidth: 164
                    implicitHeight: 36
                    radius: Theme.rounding.full
                    color: jumpField.activeFocus ? Theme.palette.surfaceContainerHighest : Theme.palette.surfaceContainerHigh
                    border.width: jumpField.activeFocus ? 2 : 1
                    border.color: jumpField.activeFocus ? Theme.palette.primary : Qt.alpha(Theme.palette.outlineVariant, 0.5)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padding.medium
                        anchors.rightMargin: Theme.padding.small
                        spacing: Theme.spacing.extraSmall

                        MaterialIcon {
                            text: "tag"
                            size: 13
                            color: jumpField.activeFocus ? Theme.palette.primary : Theme.palette.onSurfaceVariant
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
                                font: Theme.font.body.medium
                            }
                        }
                        IconButton {
                            visible: jumpField.text !== ""
                            type: IconButton.Text
                            icon: "close"
                            iconSize: 13
                            onClicked: {
                                jumpField.text = "";
                                jumpField.forceActiveFocus();
                            }
                        }
                    }
                }
                IconButton {
                    readonly property bool allWatched: root.watchedCount === root.episodes.length

                    visible: root.section === "episodes" && root.episodes.length > 0
                    disabled: !root.metaLoaded
                    type: IconButton.Tonal
                    icon: allWatched ? "remove_done" : "done_all"
                    ToolTip.visible: hovered
                    ToolTip.text: allWatched ? "Mark all unwatched" : "Mark all watched"
                    onClicked: {
                        markDialog.completed = !allWatched;
                        markDialog.open();
                    }
                }
                IconButton {
                    visible: root.section === "episodes"
                    type: IconButton.Tonal
                    icon: root.descending ? "arrow_upward" : "arrow_downward"
                    ToolTip.visible: hovered
                    ToolTip.text: root.descending ? "Sort oldest first" : "Sort newest first"
                    onClicked: root.descending = !root.descending
                }
            }

            // =========================================================================
            // TAB 1: EPISODES
            // =========================================================================
            GridLayout {
                visible: root.section === "episodes" && (root.loading || root.shownEpisodes.length > 0)
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
                        implicitHeight: 68
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
                visible: root.section === "episodes" && !root.loading && root.episodes.length === 0
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

            // =========================================================================
            // TAB 2: CAST & STAFF (AniList / MyAnimeList style)
            // =========================================================================
            ColumnLayout {
                visible: root.section === "cast"
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.extraLarge

                // Characters & Japanese Voice Actors
                ColumnLayout {
                    visible: root.shownCharacters.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    SectionHeader {
                        icon: "groups"
                        title: "Characters & Voice Actors"
                        badge: String(root.shownCharacters.length)
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor((width + columnSpacing) / (380 + columnSpacing)))
                        columnSpacing: Theme.spacing.medium
                        rowSpacing: Theme.spacing.medium

                        Repeater {
                            model: root.shownCharacters

                            StyledRect {
                                id: charCard

                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 88
                                radius: Theme.rounding.large
                                color: Theme.palette.surfaceContainer
                                border.width: 1
                                border.color: Qt.alpha(Theme.palette.outlineVariant, 0.35)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.padding.small
                                    spacing: Theme.spacing.medium

                                    // Character portrait
                                    StyledRect {
                                        Layout.preferredWidth: 56
                                        Layout.preferredHeight: 72
                                        radius: Theme.rounding.medium
                                        color: Theme.palette.surfaceContainerHigh

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: !charImg.visible || charImg.status !== Image.Ready
                                            text: "person"
                                            size: 20
                                            color: Theme.palette.onSurfaceVariant
                                        }
                                        ClippedImage {
                                            id: charImg

                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: source !== ""
                                            source: charCard.modelData.image ?? ""
                                        }
                                    }

                                    // Character name + role
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 3

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: charCard.modelData.name
                                            font: Theme.font.title.small
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: charCard.modelData.native_name ?? ""
                                            font: Theme.font.body.small
                                            color: Theme.palette.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                        StyledRect {
                                            visible: !!charCard.modelData.role
                                            implicitWidth: roleLabel.implicitWidth + 10
                                            implicitHeight: 18
                                            radius: Theme.rounding.extraSmall
                                            color: charCard.modelData.role === "MAIN" ? Theme.palette.secondaryContainer : Theme.palette.surfaceContainerHigh

                                            StyledText {
                                                id: roleLabel

                                                anchors.centerIn: parent
                                                text: root.prettyEnum(charCard.modelData.role ?? "")
                                                font: Theme.font.label.small
                                                color: charCard.modelData.role === "MAIN" ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                                            }
                                        }
                                    }

                                    // Subtle center divider when VA exists
                                    Rectangle {
                                        visible: (charCard.modelData.va_name ?? "") !== ""
                                        Layout.preferredWidth: 1
                                        Layout.fillHeight: true
                                        Layout.topMargin: Theme.padding.small
                                        Layout.bottomMargin: Theme.padding.small
                                        color: Qt.alpha(Theme.palette.outlineVariant, 0.35)
                                    }

                                    // Voice Actor (Seiyuu) name + language
                                    ColumnLayout {
                                        visible: (charCard.modelData.va_name ?? "") !== ""
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 3

                                        StyledText {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                            text: charCard.modelData.va_name ?? ""
                                            font: Theme.font.title.small
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            horizontalAlignment: Text.AlignRight
                                            text: charCard.modelData.va_native_name ?? ""
                                            font: Theme.font.body.small
                                            color: Theme.palette.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                            text: charCard.modelData.va_language || "Japanese"
                                            font: Theme.font.label.small
                                            color: Theme.palette.primary
                                        }
                                    }

                                    // Voice Actor portrait
                                    StyledRect {
                                        visible: (charCard.modelData.va_name ?? "") !== ""
                                        Layout.preferredWidth: 56
                                        Layout.preferredHeight: 72
                                        radius: Theme.rounding.medium
                                        color: Theme.palette.surfaceContainerHigh

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: !vaImg.visible || vaImg.status !== Image.Ready
                                            text: "mic"
                                            size: 18
                                            color: Theme.palette.onSurfaceVariant
                                        }
                                        ClippedImage {
                                            id: vaImg

                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: source !== ""
                                            source: charCard.modelData.va_image ?? ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Key Production Staff
                ColumnLayout {
                    visible: root.staffList.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    SectionHeader {
                        icon: "movie"
                        title: "Staff & Production"
                        badge: String(root.staffList.length)
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor((width + columnSpacing) / (260 + columnSpacing)))
                        columnSpacing: Theme.spacing.medium
                        rowSpacing: Theme.spacing.medium

                        Repeater {
                            model: root.staffList

                            StyledRect {
                                id: staffCard

                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 80
                                radius: Theme.rounding.large
                                color: Theme.palette.surfaceContainer
                                border.width: 1
                                border.color: Qt.alpha(Theme.palette.outlineVariant, 0.35)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.padding.small
                                    spacing: Theme.spacing.medium

                                    StyledRect {
                                        Layout.preferredWidth: 50
                                        Layout.preferredHeight: 64
                                        radius: Theme.rounding.medium
                                        color: Theme.palette.surfaceContainerHigh

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: !staffImg.visible || staffImg.status !== Image.Ready
                                            text: "person"
                                            size: 18
                                            color: Theme.palette.onSurfaceVariant
                                        }
                                        ClippedImage {
                                            id: staffImg

                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: source !== ""
                                            source: staffCard.modelData.image ?? ""
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: staffCard.modelData.name
                                            font: Theme.font.title.small
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: staffCard.modelData.native_name ?? ""
                                            font: Theme.font.body.small
                                            color: Theme.palette.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: staffCard.modelData.role ?? ""
                                            font: Theme.font.label.medium
                                            color: Theme.palette.primary
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: castEmpty.implicitHeight
                    Layout.topMargin: Theme.spacing.extraLarge
                    visible: root.characters.length === 0 && root.staffList.length === 0

                    EmptyState {
                        id: castEmpty

                        anchors.centerIn: parent
                        face: root.metaLoaded ? "(・・ )?" : "(◕‿◕✿)"
                        title: root.metaLoaded ? "No cast or staff metadata available" : "Loading cast & staff…"
                        message: root.metaLoaded ? "Try refreshing metadata or linking this anime to AniList." : ""
                    }
                }
            }

            // =========================================================================
            // TAB 3: DETAILS, TAGS, RELATIONS & RECOMMENDATIONS
            // =========================================================================
            ColumnLayout {
                visible: root.section === "details"
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.extraLarge

                // Anime Information Grid (AniList / MAL sidebar info)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.medium

                        SectionHeader {
                            icon: "info"
                            title: "Anime Information"
                        }

                        IconTextButton {
                            visible: (root.meta?.anilist_id ?? 0) > 0
                            type: TextButton.Tonal
                            icon: "open_in_new"
                            text: "AniList"
                            onClicked: Qt.openUrlExternally(`https://anilist.co/anime/${root.meta.anilist_id}`)
                        }
                        IconTextButton {
                            visible: (root.meta?.mal_id ?? 0) > 0
                            type: TextButton.Tonal
                            icon: "open_in_new"
                            text: "MyAnimeList"
                            onClicked: Qt.openUrlExternally(`https://myanimelist.net/anime/${root.meta.mal_id}`)
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: infoGridCol.implicitHeight + Theme.padding.large * 2
                        radius: Theme.rounding.largeIncreased
                        color: Theme.palette.surfaceContainer
                        border.width: 1
                        border.color: Qt.alpha(Theme.palette.outlineVariant, 0.35)

                        ColumnLayout {
                            id: infoGridCol

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.padding.large
                            spacing: Theme.spacing.medium

                            GridLayout {
                                Layout.fillWidth: true
                                columns: Math.max(2, Math.floor((width + columnSpacing) / (210 + columnSpacing)))
                                columnSpacing: Theme.spacing.medium
                                rowSpacing: Theme.spacing.medium

                                FactTile {
                                    label: "Format"
                                    icon: "tv"
                                    value: root.prettyEnum(root.meta?.format ?? "")
                                }
                                FactTile {
                                    label: "Episodes"
                                    icon: "video_library"
                                    value: (root.meta?.episodes ?? 0) > 0 ? String(root.meta.episodes) : root.episodes.length > 0 ? String(root.episodes.length) : ""
                                }
                                FactTile {
                                    label: "Episode Duration"
                                    icon: "schedule"
                                    value: (root.meta?.duration ?? 0) > 0 ? `${root.meta.duration} mins` : ""
                                }
                                FactTile {
                                    label: "Status"
                                    icon: "radio_button_checked"
                                    value: root.prettyEnum(root.meta?.status ?? "")
                                }
                                FactTile {
                                    label: "Season"
                                    icon: "calendar_month"
                                    value: root.seasonLabel()
                                }
                                FactTile {
                                    label: "Aired"
                                    icon: "event"
                                    value: {
                                        const start = root.meta?.start_date ?? "";
                                        const end = root.meta?.end_date ?? "";
                                        if (start && end && start !== end)
                                            return `${start}  →  ${end}`;
                                        return start || end;
                                    }
                                }
                                FactTile {
                                    label: "Source Material"
                                    icon: "menu_book"
                                    value: root.prettyEnum(root.meta?.source ?? "")
                                }
                                FactTile {
                                    label: "Main Studio"
                                    icon: "movie"
                                    value: (root.meta?.studios ?? []).join(", ")
                                }
                                FactTile {
                                    label: "Producers"
                                    icon: "business"
                                    value: (root.meta?.producers ?? []).slice(0, 4).join(", ")
                                }
                                FactTile {
                                    label: "Score"
                                    icon: "star"
                                    value: {
                                        const avg = root.meta?.score ?? 0;
                                        const mean = root.meta?.mean_score ?? 0;
                                        if (avg > 0 && mean > 0 && avg !== mean)
                                            return `${(avg / 10).toFixed(1)} / 10  (Mean ${mean}%)`;
                                        return avg > 0 ? `${(avg / 10).toFixed(1)} / 10  (${avg}%)` : "";
                                    }
                                }
                                FactTile {
                                    label: "Popularity"
                                    icon: "trending_up"
                                    value: (root.meta?.popularity ?? 0) > 0 ? `${Number(root.meta.popularity).toLocaleString()} members` : ""
                                }
                                FactTile {
                                    label: "Favorites"
                                    icon: "favorite"
                                    value: (root.meta?.favourites ?? 0) > 0 ? `${Number(root.meta.favourites).toLocaleString()} favorites` : ""
                                }
                            }

                            // Titles & Synonyms sub-row
                            Rectangle {
                                visible: (root.meta?.title_romaji ?? "") !== "" || (root.meta?.title_native ?? "") !== "" || (root.meta?.synonyms?.length ?? 0) > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Qt.alpha(Theme.palette.outlineVariant, 0.35)
                            }

                            GridLayout {
                                visible: (root.meta?.title_romaji ?? "") !== "" || (root.meta?.title_native ?? "") !== "" || (root.meta?.synonyms?.length ?? 0) > 0
                                Layout.fillWidth: true
                                columns: Math.max(1, Math.floor((width + columnSpacing) / (280 + columnSpacing)))
                                columnSpacing: Theme.spacing.medium
                                rowSpacing: Theme.spacing.small

                                ColumnLayout {
                                    visible: (root.meta?.title_romaji ?? "") !== ""
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Romaji Title"
                                        font: Theme.font.label.medium
                                        color: Theme.palette.onSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.meta?.title_romaji ?? ""
                                        font: Theme.font.body.medium
                                        wrapMode: Text.Wrap
                                    }
                                }
                                ColumnLayout {
                                    visible: (root.meta?.title_english ?? "") !== ""
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "English Title"
                                        font: Theme.font.label.medium
                                        color: Theme.palette.onSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.meta?.title_english ?? ""
                                        font: Theme.font.body.medium
                                        wrapMode: Text.Wrap
                                    }
                                }
                                ColumnLayout {
                                    visible: (root.meta?.title_native ?? "") !== ""
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Native Title"
                                        font: Theme.font.label.medium
                                        color: Theme.palette.onSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.meta?.title_native ?? ""
                                        font: Theme.font.body.medium
                                        wrapMode: Text.Wrap
                                    }
                                }
                                ColumnLayout {
                                    visible: (root.meta?.synonyms?.length ?? 0) > 0
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Synonyms"
                                        font: Theme.font.label.medium
                                        color: Theme.palette.onSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: (root.meta?.synonyms ?? []).slice(0, 5).join("  ·  ")
                                        font: Theme.font.body.medium
                                        color: Theme.palette.onSurfaceVariant
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }

                // Theme Tags
                ColumnLayout {
                    visible: root.tagsList.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    SectionHeader {
                        icon: "tag"
                        title: "Themes & Tags"
                        badge: String(root.tagsList.length)
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        Repeater {
                            model: root.tagsList

                            Chip {
                                required property var modelData

                                text: (modelData.rank ?? 0) > 0 ? `${modelData.name}  ·  ${modelData.rank}%` : modelData.name
                            }
                        }
                    }
                }

                // Relations (Prequel, Sequel, Side Story, Adaptation, etc.)
                ColumnLayout {
                    visible: root.relationsList.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    SectionHeader {
                        icon: "link"
                        title: "Related Media"
                        badge: String(root.relationsList.length)
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor((width + columnSpacing) / (340 + columnSpacing)))
                        columnSpacing: Theme.spacing.medium
                        rowSpacing: Theme.spacing.medium

                        Repeater {
                            model: root.relationsList

                            StyledRect {
                                id: relCard

                                required property var modelData
                                readonly property string displayTitle: modelData.title_english || modelData.title_romaji

                                Layout.fillWidth: true
                                implicitHeight: 104
                                radius: Theme.rounding.large
                                color: Theme.palette.surfaceContainer
                                border.width: 1
                                border.color: Qt.alpha(Theme.palette.outlineVariant, 0.35)

                                StateLayer {
                                    color: Theme.palette.onSurface
                                    onClicked: {
                                        if (relCard.modelData.media_type === "MANGA" && relCard.modelData.anilist_id > 0)
                                            Qt.openUrlExternally(`https://anilist.co/manga/${relCard.modelData.anilist_id}`);
                                        else
                                            root.app.searchFor(relCard.displayTitle);
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.padding.small
                                    spacing: Theme.spacing.medium

                                    ClippedImage {
                                        Layout.preferredWidth: 64
                                        Layout.preferredHeight: 88
                                        radius: Theme.rounding.medium
                                        source: relCard.modelData.cover ?? ""
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 4

                                        RowLayout {
                                            spacing: Theme.spacing.extraSmall

                                            StyledRect {
                                                implicitWidth: relBadge.implicitWidth + 10
                                                implicitHeight: 20
                                                radius: Theme.rounding.extraSmall
                                                color: Theme.palette.secondaryContainer

                                                StyledText {
                                                    id: relBadge

                                                    anchors.centerIn: parent
                                                    text: root.prettyEnum(relCard.modelData.relation ?? "")
                                                    font: Theme.font.label.small
                                                    color: Theme.palette.onSecondaryContainer
                                                }
                                            }
                                            StyledText {
                                                visible: (relCard.modelData.score ?? 0) > 0
                                                text: `★ ${(relCard.modelData.score / 10).toFixed(1)}`
                                                font: Theme.font.label.medium
                                                color: Theme.palette.tertiary
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: relCard.displayTitle
                                            font: Theme.font.title.small
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: [
                                                root.prettyEnum(relCard.modelData.format ?? ""),
                                                (relCard.modelData.episodes ?? 0) > 0 ? `${relCard.modelData.episodes} ep` : "",
                                                (relCard.modelData.year ?? 0) > 0 ? String(relCard.modelData.year) : "",
                                                root.prettyEnum(relCard.modelData.status ?? "")
                                            ].filter(Boolean).join("  ·  ")
                                            font: Theme.font.body.small
                                            color: Theme.palette.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MaterialIcon {
                                        Layout.rightMargin: Theme.padding.small
                                        text: relCard.modelData.media_type === "MANGA" ? "open_in_new" : "search"
                                        size: 16
                                        color: Theme.palette.onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }

                // Recommendations (Similar Anime)
                ColumnLayout {
                    visible: root.recommendationsList.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    SectionHeader {
                        icon: "auto_awesome"
                        title: "Recommendations"
                        badge: String(root.recommendationsList.length)
                    }

                    Flow {
                        id: recGrid

                        readonly property int columns: Math.max(2, Math.floor((width + spacing) / (168 + spacing)))
                        readonly property real cardWidth: (width - spacing * (columns - 1)) / columns

                        Layout.fillWidth: true
                        spacing: Theme.spacing.large

                        Repeater {
                            model: root.recommendationsList

                            PosterCard {
                                id: recCard

                                required property var modelData
                                readonly property string displayTitle: modelData.title_english || modelData.title_romaji

                                width: recGrid.cardWidth
                                height: implicitHeight + Theme.spacing.large
                                title: displayTitle
                                image: modelData.cover ?? ""
                                badge: (modelData.score ?? 0) > 0 ? `★ ${(modelData.score / 10).toFixed(1)}` : ""
                                subtitle: [
                                    root.prettyEnum(modelData.format ?? ""),
                                    (modelData.episodes ?? 0) > 0 ? `${modelData.episodes} ep` : "",
                                    (modelData.year ?? 0) > 0 ? String(modelData.year) : ""
                                ].filter(Boolean).join(" · ")
                                onClicked: root.app.searchFor(recCard.displayTitle)
                            }
                        }
                    }
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
                    progress: [root.progressRow(ep)],
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

    StyledDialog {
        id: markDialog

        property bool completed

        icon: completed ? "done_all" : "remove_done"
        title: `Mark all episodes ${completed ? "watched" : "unwatched"}?`
        text: completed ? "Your watchlist and trackers will be updated." : "Your watchlist and trackers won't change."
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: markDialog.close()
            },
            TextButton {
                type: TextButton.Tonal
                text: markDialog.completed ? "Mark watched" : "Mark unwatched"
                onClicked: {
                    root.markAll(markDialog.completed);
                    markDialog.close();
                }
            }
        ]
    }

    MatchDialog {
        id: matchDialog

        onLinked: m => {
            root.anime = Object.assign({}, root.anime, {
                anilistId: m.anilist_id
            });
            root.load(false);
            root.app.historyRevision++;
        }
    }
}
