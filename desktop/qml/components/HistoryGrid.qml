pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

ColumnLayout {
    id: root

    property var series: []
    property int tabIndex: 0 // 0 Continue, 1 Recent
    readonly property var continuing: series.filter(s => !s.finished)
    readonly property var shown: tabIndex === 0 ? continuing : series
    default property alias controls: chipRow.data

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

    Layout.fillWidth: true
    spacing: Theme.spacing.extraLarge

    RowLayout {
        id: chipRow

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
                badge: Api.sourceName(modelData.source)
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
        visible: root.shown.length === 0 && root.series.length > 0
        face: "٩(◕‿◕｡)۶"
        title: "All caught up!"
        message: "Check Recent to rewatch."
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
                    ApplicationWindow.window.historyRevision++;
                }
            }
        ]
    }
}
