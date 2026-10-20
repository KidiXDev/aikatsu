pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var series: []
    readonly property var hero: history.continuing.length > 0 ? history.continuing[0] : null
    property var heroMeta: null
    property bool autoplay: Api.setting("autoplay") === "true"
    property var discover: null // AniList schedule, trending and upcoming (see core meta::discover)
    property bool discoverFailed
    property real discoverAt // ms; Home re-reads it when shown 10 min later so "Up next" moves on
    readonly property var shelves: discover ? shelvesOf(discover) : []
    readonly property var spotlight: !hero && discover?.trending?.length > 0 ? discover.trending[0] : null
    readonly property string bannerSource: hero ? (heroMeta?.banner || heroMeta?.cover || hero.cover || "") : (spotlight?.banner || spotlight?.cover || "")
    readonly property string posterSource: hero ? (heroMeta?.cover || hero.cover || "") : (spotlight?.cover || "")
    readonly property string heroDescription: hero ? (heroMeta?.description ?? "") : (spotlight?.description ?? "")

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
                Layout.preferredHeight: 390

                ClippedImage {
                    id: banner

                    anchors.fill: parent
                    radius: 0
                    source: root.bannerSource
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: banner
                    autoPaddingEnabled: false // the padded blur halo shows as a line under the hero
                    blurEnabled: true
                    blur: (root.hero ? root.heroMeta?.banner : root.spotlight?.banner) ? 0.15 : 0.9
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
                            color: Qt.alpha(Theme.palette.surface, 0.12)
                        }
                        GradientStop {
                            position: 0.55
                            color: Qt.alpha(Theme.palette.surface, 0.58)
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
                            color: Qt.alpha(Theme.palette.surface, 0.88)
                        }
                        GradientStop {
                            position: 0.65
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
                        visible: root.posterSource !== ""
                        Layout.preferredWidth: 156
                        Layout.preferredHeight: 226
                        radius: Theme.rounding.large
                        source: root.posterSource

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
                            Layout.fillWidth: true
                            text: root.hero ? (root.heroMeta?.title_english || root.hero.title) : root.spotlight ? (root.spotlight.title_english || root.spotlight.title_romaji) : "Aikatsu"
                            font: Theme.font.display.medium
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            visible: root.hero !== null || root.spotlight !== null

                            Chip {
                                visible: root.hero !== null
                                selected: true
                                icon: "play_circle"
                                text: root.hero ? `Episode ${root.hero.continue_episode}` + (root.hero.total_episodes >= root.hero.continue_episode ? ` of ${root.hero.total_episodes}` : "") : ""
                            }
                            Chip {
                                visible: root.hero !== null
                                text: root.hero ? Api.sourceName(root.hero.source) : ""
                            }
                            Chip {
                                visible: root.hero === null && root.spotlight !== null
                                selected: true
                                icon: "local_fire_department"
                                text: "Trending now"
                            }
                            Chip {
                                readonly property int sc: (root.hero ? root.heroMeta?.score : root.spotlight?.score) ?? 0
                                visible: sc > 0
                                selected: true
                                tint: Theme.palette.tertiaryContainer
                                onTint: Theme.palette.onTertiaryContainer
                                text: `★ ${(sc / 10).toFixed(1)}`
                            }
                            Repeater {
                                model: ((root.hero ? root.heroMeta?.genres : root.spotlight?.genres) ?? []).slice(0, 3)

                                Chip {
                                    required property string modelData

                                    text: modelData
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 680
                            visible: text !== ""
                            text: root.hero || root.spotlight ? root.heroDescription : "Stream anime from your sources or local library, with watch progress and settings synced across devices."
                            color: Theme.palette.onSurfaceVariant
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font: Theme.font.body.large
                            lineHeight: 1.15
                        }

                        RowLayout {
                            Layout.topMargin: Theme.spacing.small
                            spacing: Theme.spacing.small

                            IconTextButton {
                                icon: root.hero ? "play_arrow" : "search"
                                text: root.hero ? `Continue  ·  Ep ${root.hero.continue_episode}` : root.spotlight ? "Search sources" : "Find something to watch"
                                verticalPadding: Theme.padding.medium
                                horizontalPadding: Theme.padding.large
                                onClicked: {
                                    if (root.hero)
                                        ApplicationWindow.window.openAnime(history.animeOf(root.hero), root.hero.continue_episode);
                                    else if (root.spotlight)
                                        ApplicationWindow.window.searchFor(root.spotlight.title_romaji || root.spotlight.title_english);
                                    else
                                        ApplicationWindow.window.goTab(1);
                                }
                            }
                            IconTextButton {
                                visible: root.hero !== null || root.spotlight !== null
                                type: TextButton.Tonal
                                icon: "info"
                                text: "Details"
                                verticalPadding: Theme.padding.medium
                                horizontalPadding: Theme.padding.large
                                onClicked: {
                                    if (root.hero)
                                        ApplicationWindow.window.openAnime(history.animeOf(root.hero), 0);
                                    else if (root.spotlight) {
                                        infoDialog.item = {
                                            meta: root.spotlight,
                                            note: ""
                                        };
                                        infoDialog.open();
                                    }
                                }
                            }
                            IconTextButton {
                                visible: root.hero === null && root.spotlight === null
                                type: TextButton.Tonal
                                icon: "folder_open"
                                text: "Open library"
                                verticalPadding: Theme.padding.medium
                                horizontalPadding: Theme.padding.large
                                onClicked: ApplicationWindow.window.goTab(2)
                            }
                        }
                    }
                }
            }

            HistoryGrid {
                id: history

                visible: root.series.length > 0
                series: root.series

                StyledRect {
                    implicitWidth: autoRow.implicitWidth + Theme.padding.medium * 2
                    implicitHeight: 36
                    radius: Theme.rounding.full
                    color: Theme.palette.surfaceContainer

                    RowLayout {
                        id: autoRow

                        anchors.centerIn: parent
                        spacing: Theme.spacing.small

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
                    }
                }
                IconTextButton {
                    visible: root.series.length > 0
                    type: TextButton.Text
                    icon: "delete_sweep"
                    text: "Clear all"
                    onClicked: clearDialog.open()
                }
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
            spacing: Theme.spacing.medium

            StyledRect {
                implicitWidth: 34
                implicitHeight: 34
                radius: Theme.rounding.medium
                color: Theme.palette.secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: shelf.modelData.icon
                    fill: 1
                    size: 16
                    color: Theme.palette.onSecondaryContainer
                }
            }
            StyledText {
                text: shelf.modelData.title
                font: Theme.font.title.large
            }
            StyledRect {
                implicitWidth: Math.max(24, countText.implicitWidth + 10)
                implicitHeight: 22
                radius: Theme.rounding.full
                color: Theme.palette.surfaceContainerHigh

                StyledText {
                    id: countText

                    anchors.centerIn: parent
                    text: String(shelf.modelData.items.length)
                    font: Theme.font.label.medium
                    color: Theme.palette.onSurfaceVariant
                }
            }
            Item {
                Layout.fillWidth: true
            }
            IconButton {
                type: IconButton.Tonal
                icon: "chevron_left"
                disabled: list.atXBeginning
                onClicked: list.page(-1)
            }
            IconButton {
                type: IconButton.Tonal
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

                Elevation {
                    z: -1
                    anchors.fill: parent
                    radius: parent.radius
                    level: 3
                }
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
                type: TextButton.Tonal
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
                type: TextButton.Tonal
                text: "Clear all"
                onClicked: {
                    Api.get("clearHistory");
                    clearDialog.close();
                    ApplicationWindow.window.historyRevision++;
                }
            }
        ]
    }
}
