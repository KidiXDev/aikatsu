pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var series: []
    property int tabIndex: 0 // 0 Continue, 1 Recent
    readonly property var continuing: series.filter(s => !s.finished)
    readonly property var shown: tabIndex === 0 ? continuing : series
    readonly property var hero: continuing.length > 0 ? continuing[0] : null
    property var heroMeta: null
    property bool autoplay: Api.setting("autoplay") === "true"
    property var discover: null // AniList schedule, trending and upcoming (see core meta::discover)
    property bool discoverFailed
    property real discoverAt // ms; Home re-reads it when shown 10 min later so "Up next" moves on
    readonly property var shelves: discover ? shelvesOf(discover) : []

    function refresh(): void {
        series = Api.get("history");
    }

    function show(): void {
        refresh();
        if (Date.now() - discoverAt > 10 * 60000)
            loadDiscover(false);
    }

    function loadDiscover(refresh: bool): void {
        discoverAt = Date.now();
        discoverFailed = false;
        Api.call("discover", {
            refresh: refresh
        }, d => root.discover = d, () => {
            root.discoverAt = 0;
            root.discoverFailed = true;
        });
    }

    // When a scheduled episode airs: "45m ago", "3h ago", "21:30" later today, "Tomorrow 08:00".
    function airingLabel(at: real, now: date): string {
        const ago = Math.floor((now.getTime() - at * 1000) / 60000);
        if (ago >= 0)
            return ago < 60 ? `${Math.max(ago, 1)}m ago` : `${Math.floor(ago / 60)}h ago`;
        const t = new Date(at * 1000);
        const hhmm = Qt.formatTime(t, "hh:mm");
        return t.toDateString() === now.toDateString() ? hhmm : `Tomorrow ${hhmm}`;
    }

    function shelvesOf(d: var): var {
        const now = new Date();
        const genre = m => m.genres.slice(0, 2).join(" · ");
        const airing = a => {
            const label = airingLabel(a.airing_at, now);
            return {
                meta: a.anime,
                badge: `Ep ${a.episode}`,
                subtitle: label,
                note: `Episode ${a.episode} · ${label.endsWith("ago") ? "aired" : "airs"} ${label}`
            };
        };
        return [
            {
                title: "Out today",
                icon: "new_releases",
                items: d.schedule.filter(a => a.airing_at * 1000 <= now.getTime()).reverse().map(airing) // newest first
            },
            {
                title: "Up next",
                icon: "schedule",
                items: d.schedule.filter(a => a.airing_at * 1000 > now.getTime()).map(airing)
            },
            {
                title: "Trending now",
                icon: "local_fire_department",
                items: d.trending.map(m => ({
                            meta: m,
                            badge: m.score > 0 ? `★ ${(m.score / 10).toFixed(1)}` : "",
                            subtitle: genre(m),
                            note: ""
                        }))
            },
            {
                title: "Coming soon",
                icon: "event",
                items: d.coming_soon.map(m => ({
                            meta: m,
                            badge: m.year > 0 ? `${m.year}` : "",
                            subtitle: genre(m),
                            note: "Not out yet"
                        }))
            }
        ];
    }

    function animeOf(s: var): var {
        return {
            name: s.title,
            url: s.url,
            image: s.cover,
            source: s.source,
            anilistId: s.anilist_id
        };
    }

    function progressOf(s: var): real {
        const ep = s.episodes.find(e => e.episode_number === s.continue_episode);
        return ep && ep.duration > 0 ? ep.playback_time / ep.duration : 0;
    }

    Component.onCompleted: show()
    onVisibleChanged: if (visible)
        show()
    onHeroChanged: {
        heroMeta = null;
        if (hero && hero.anilist_id > 0) {
            const key = hero.key;
            Api.call("enrich", {
                anilistId: hero.anilist_id
            }, m => {
                if (root.hero && root.hero.key === key)
                    root.heroMeta = m;
            });
        }
    }

    Connections {
        target: root.ApplicationWindow.window

        function onHistoryRevisionChanged(): void {
            root.refresh();
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: content.implicitHeight + Theme.padding.extraLarge
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: content

            width: flick.width
            spacing: Theme.spacing.extraLarge

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 380

                ClippedImage {
                    id: banner

                    anchors.fill: parent
                    radius: 0
                    source: root.heroMeta?.banner || root.heroMeta?.cover || root.hero?.cover || ""
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: banner
                    autoPaddingEnabled: false // the padded blur halo shows as a line under the hero
                    blurEnabled: true
                    blur: root.heroMeta?.banner ? 0.15 : 0.9
                    blurMax: 48
                    saturation: 0.1
                    opacity: banner.status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.SlowEffects
                        }
                    }
                }

                // Fallback gradient when there is no art (fresh install).
                Rectangle {
                    anchors.fill: parent
                    visible: banner.status !== Image.Ready
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Theme.palette.secondaryContainer
                        }
                        GradientStop {
                            position: 1
                            color: Theme.palette.surfaceContainer
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha(Theme.palette.surface, 0.15)
                        }
                        GradientStop {
                            position: 0.55
                            color: Qt.alpha(Theme.palette.surface, 0.55)
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
                            color: Qt.alpha(Theme.palette.surface, 0.85)
                        }
                        GradientStop {
                            position: 0.6
                            color: "transparent"
                        }
                    }
                }

                SakuraFall {
                    rate: 4
                }

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.padding.extraLarge
                    spacing: Theme.spacing.extraLarge

                    ClippedImage {
                        visible: root.hero !== null
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 218
                        radius: Theme.rounding.large
                        source: root.heroMeta?.cover || root.hero?.cover || ""

                        Elevation {
                            z: -1
                            anchors.fill: parent
                            radius: parent.radius
                            level: 4
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        StyledText {
                            text: root.hero ? "CONTINUE WATCHING" : "おかえり · WELCOME"
                            font: Theme.font.label.large
                            color: Theme.palette.primary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.hero ? (root.heroMeta?.title_english || root.hero.title) : "Aikatsu"
                            font: Theme.font.display.medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.hero ? `Episode ${root.hero.continue_episode}` + (root.hero.total_episodes >= root.hero.continue_episode ? ` of ${root.hero.total_episodes}` : "") + (root.heroMeta?.genres?.length ? "  ·  " + root.heroMeta.genres.slice(0, 3).join(" · ") : "") : "Watch anime with Indonesian subtitles and pick up right where you left off."
                            color: Theme.palette.onSurfaceVariant
                            wrapMode: Text.Wrap
                            font: Theme.font.body.large
                        }
                        RowLayout {
                            Layout.topMargin: Theme.spacing.medium
                            spacing: Theme.spacing.small

                            IconTextButton {
                                icon: root.hero ? "play_arrow" : "search"
                                text: root.hero ? `Continue  ·  Ep ${root.hero.continue_episode}` : "Find something to watch"
                                verticalPadding: Theme.padding.medium
                                horizontalPadding: Theme.padding.large
                                onClicked: root.hero ? ApplicationWindow.window.openAnime(root.animeOf(root.hero), root.hero.continue_episode) : ApplicationWindow.window.goTab(1)
                            }
                            IconTextButton {
                                visible: root.hero !== null
                                type: TextButton.Tonal
                                icon: "info"
                                text: "Details"
                                verticalPadding: Theme.padding.medium
                                horizontalPadding: Theme.padding.large
                                onClicked: ApplicationWindow.window.openAnime(root.animeOf(root.hero), 0)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.small

                Chip {
                    text: `Continue  ${root.continuing.length}`
                    icon: "play_circle"
                    selected: root.tabIndex === 0
                    clickable: true
                    onClicked: root.tabIndex = 0
                }
                Chip {
                    text: `Recent  ${root.series.length}`
                    icon: "history"
                    selected: root.tabIndex === 1
                    clickable: true
                    onClicked: root.tabIndex = 1
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledText {
                    text: "Autoplay"
                    color: Theme.palette.onSurfaceVariant
                    font: Theme.font.label.large
                }
                StyledSwitch {
                    checked: root.autoplay
                    onToggled: {
                        root.autoplay = checked;
                        Api.setSetting("autoplay", checked);
                    }
                }
                IconTextButton {
                    Layout.leftMargin: Theme.spacing.medium
                    visible: root.series.length > 0
                    type: TextButton.Text
                    icon: "delete_sweep"
                    text: "Clear all"
                    onClicked: clearDialog.open()
                }
            }

            Flow {
                id: grid

                readonly property int columns: Math.max(2, Math.floor((width + spacing) / (168 + spacing)))
                readonly property real cardWidth: (width - spacing * (columns - 1)) / columns

                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.large
                visible: root.shown.length > 0

                Repeater {
                    model: root.shown

                    PosterCard {
                        required property var modelData

                        width: grid.cardWidth
                        height: implicitHeight + Theme.spacing.large
                        title: modelData.title
                        subtitle: modelData.finished ? "Finished ✓" : `Episode ${modelData.continue_episode}` + (modelData.total_episodes >= modelData.continue_episode ? ` / ${modelData.total_episodes}` : "")
                        image: modelData.cover
                        badge: modelData.source
                        progress: modelData.finished ? -1 : root.progressOf(modelData)
                        onClicked: ApplicationWindow.window.openAnime(root.animeOf(modelData), 0)
                        onRightClicked: (x, y) => {
                            cardMenu.target = modelData;
                            const p = mapToItem(root, x, y);
                            cardMenu.x = p.x;
                            cardMenu.y = p.y;
                            cardMenu.open();
                        }
                    }
                }
            }

            // A fresh install has no history: the shelves below fill Home instead.
            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge
                visible: root.shown.length === 0 && root.series.length > 0
                face: "٩(◕‿◕｡)۶"
                title: "All caught up!"
                message: "You've finished everything you started. Check Recent to rewatch."
            }

            Repeater {
                model: root.shelves

                Shelf {
                    onOpened: item => {
                        infoDialog.item = item;
                        infoDialog.open();
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge
                visible: root.discover === null
                spacing: Theme.spacing.medium

                Loading {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.discoverFailed
                }
                StyledText {
                    visible: root.discoverFailed
                    text: "Couldn't load what's airing."
                    color: Theme.palette.onSurfaceVariant
                }
                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.discoverFailed
                    type: TextButton.Tonal
                    text: "Try again"
                    onClicked: root.loadDiscover(true)
                }
            }
        }
    }

    // A titled row of AniList posters, hidden when empty. The wheel scrolls the
    // page, so ‹ › page it sideways (drag and touchpad swipes work too).
    component Shelf: ColumnLayout {
        id: shelf

        required property var modelData // {title, icon, items: [{meta, badge, subtitle, note}]}

        signal opened(var item)

        Layout.fillWidth: true
        visible: modelData.items.length > 0
        spacing: Theme.spacing.medium

        RowLayout {
            Layout.leftMargin: Theme.padding.extraLarge
            Layout.rightMargin: Theme.padding.extraLarge
            spacing: Theme.spacing.small

            MaterialIcon {
                text: shelf.modelData.icon
                fill: 1
                color: Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                text: shelf.modelData.title
                font: Theme.font.title.large
            }
            IconButton {
                type: IconButton.Text
                icon: "chevron_left"
                disabled: list.atXBeginning
                onClicked: list.page(-1)
            }
            IconButton {
                type: IconButton.Text
                icon: "chevron_right"
                disabled: list.atXEnd
                onClicked: list.page(1)
            }
        }

        ListView {
            id: list

            function page(dir: int): void {
                const min = originX - leftMargin, max = originX + contentWidth + rightMargin - width;
                scroll.to = Math.max(min, Math.min(max, contentX + dir * width * 0.8));
                scroll.restart();
            }

            Layout.fillWidth: true
            Layout.preferredHeight: sizer.implicitHeight
            orientation: ListView.Horizontal
            leftMargin: Theme.padding.extraLarge
            rightMargin: Theme.padding.extraLarge
            spacing: Theme.spacing.large
            boundsBehavior: Flickable.StopAtBounds
            model: shelf.modelData.items

            delegate: PosterCard {
                required property var modelData

                title: modelData.meta.title_english || modelData.meta.title_romaji
                subtitle: modelData.subtitle
                image: modelData.meta.cover
                badge: modelData.badge
                onClicked: shelf.opened(modelData)
            }

            Anim {
                id: scroll

                target: list
                property: "contentX"
                type: Anim.Emphasized
            }
        }

        // The tallest card (two-line title), so a shelf keeps its height as it scrolls.
        PosterCard {
            id: sizer

            visible: false
            title: "\n"
            subtitle: " "
        }
    }

    // Details only: Aikatsu can't stream from AniList, so the way on is a source search.
    StyledDialog {
        id: infoDialog

        property var item: null
        readonly property var m: item?.meta ?? ({})
        readonly property string name: m.title_english || m.title_romaji || ""
        readonly property var chips: [m.score > 0 ? {
                text: `★ ${(m.score / 10).toFixed(1)}`,
                accent: true
            } : null, m.year > 0 ? {
                text: `${m.year}`,
                icon: "calendar_month"
            } : null, m.episodes > 0 ? {
                text: `${m.episodes} eps`,
                icon: "video_library"
            } : null, m.status ? {
                text: m.status.replace(/_/g, " ").toLowerCase()
            } : null, ...(m.genres ?? []).map(g => ({
                    text: g
                }))].filter(c => c)

        width: Math.min(640, parent ? parent.width - 48 : 640)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.extraLarge

            ClippedImage {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 120
                Layout.preferredHeight: 174
                radius: Theme.rounding.large
                source: infoDialog.m.cover ?? ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: infoDialog.name
                    font: Theme.font.headline.small
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: [infoDialog.m.title_romaji, infoDialog.m.title_native].filter(t => t && t !== infoDialog.name).join("  ·  ")
                    color: Theme.palette.onSurfaceVariant
                    wrapMode: Text.Wrap
                }
                StyledText {
                    visible: text !== ""
                    text: infoDialog.item?.note ?? ""
                    font: Theme.font.label.large
                    color: Theme.palette.primary
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    spacing: Theme.spacing.small

                    Repeater {
                        model: infoDialog.chips

                        Chip {
                            required property var modelData

                            text: modelData.text
                            icon: modelData.icon ?? ""
                            selected: modelData.accent ?? false
                            tint: Theme.palette.tertiaryContainer
                            onTint: Theme.palette.onTertiaryContainer
                        }
                    }
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: infoDialog.m.description ?? ""
            color: Theme.palette.onSurfaceVariant
            font: Theme.font.body.large
            wrapMode: Text.Wrap
            maximumLineCount: 8
            elide: Text.ElideRight
            lineHeight: 1.15
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Close"
                onClicked: infoDialog.close()
            },
            IconTextButton {
                icon: "search"
                text: "Search sources"
                onClicked: {
                    infoDialog.close();
                    // The sources mostly use romaji names.
                    ApplicationWindow.window.searchFor(infoDialog.m.title_romaji || infoDialog.name);
                }
            }
        ]
    }

    StyledMenu {
        id: cardMenu

        property var target

        model: [
            {
                text: "Open",
                icon: "open_in_new",
                value: "open"
            },
            {
                text: "Continue episode",
                icon: "play_arrow",
                value: "play"
            },
            {
                text: "Remove from history",
                icon: "delete",
                value: "delete"
            }
        ]
        onTriggered: item => {
            if (item.value === "open")
                ApplicationWindow.window.openAnime(root.animeOf(target), 0);
            else if (item.value === "play")
                ApplicationWindow.window.openAnime(root.animeOf(target), target.continue_episode);
            else if (item.value === "delete") {
                deleteDialog.target = target;
                deleteDialog.open();
            }
        }
    }

    StyledDialog {
        id: deleteDialog

        property var target

        icon: "delete"
        title: "Remove from history?"
        text: `All saved progress for “${target?.title ?? ""}” will be deleted.`
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: deleteDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Remove"
                onClicked: {
                    Api.get("deleteSeries", {
                        key: deleteDialog.target.key
                    });
                    deleteDialog.close();
                    root.refresh();
                }
            }
        ]
    }

    StyledDialog {
        id: clearDialog

        icon: "delete_sweep"
        title: "Clear all history?"
        text: "Every series and its progress will be removed. This can't be undone."
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: clearDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Clear all"
                onClicked: {
                    Api.get("clearHistory");
                    clearDialog.close();
                    root.refresh();
                }
            }
        ]
    }
}
