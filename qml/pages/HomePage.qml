pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Aikatsu

// Watch Hub: hero for the latest unfinished series, Continue / Recent grids.
Item {
    id: root

    property var series: []
    property int tabIndex: 0 // 0 Continue, 1 Recent
    readonly property var continuing: series.filter(s => !s.finished)
    readonly property var shown: tabIndex === 0 ? continuing : series
    readonly property var hero: continuing.length > 0 ? continuing[0] : null
    property var heroMeta: null
    property bool autoplay: Api.setting("autoplay") === "true"

    function refresh(): void {
        series = Api.get("history");
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

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible)
        refresh()
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
        target: ApplicationWindow.window

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

            // ---- hero
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
                            text: root.hero ? `Episode ${root.hero.continue_episode}` + (root.hero.total_episodes >= root.hero.continue_episode ? ` of ${root.hero.total_episodes}` : "") + (root.heroMeta?.genres?.length ? "  ·  " + root.heroMeta.genres.slice(0, 3).join(" · ") : "") : "Search Indonesian-sub anime across six sources and pick up right where you left off."
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

            // ---- tabs + actions
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

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge
                visible: root.shown.length === 0
                face: root.series.length === 0 ? "(っ˘ω˘ς )" : "٩(◕‿◕｡)۶"
                title: root.series.length === 0 ? "Nothing watched yet" : "All caught up!"
                message: root.series.length === 0 ? "Your watch history shows up here. Search for an anime to begin." : "Every series in your history is finished. Check Recent for rewatches."
            }
        }
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
