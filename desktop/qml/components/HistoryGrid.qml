pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

ColumnLayout {
    id: root

    readonly property Main app: ApplicationWindow.window as Main

    property var series: []
    property int tabIndex: 0 // 0 Continue, 1 Recent
    readonly property var continuing: series.filter(s => !s.finished)
    readonly property var shown: tabIndex === 0 ? continuing : series
    default property alias controls: trailRow.data

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
    spacing: Theme.spacing.large

    RowLayout {
        Layout.fillWidth: true
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
                text: "history"
                fill: 1
                size: 16
                color: Theme.palette.onSecondaryContainer
            }
        }
        StyledText {
            text: "Watch history"
            font: Theme.font.title.large
        }

        SegmentedControl {
            Layout.leftMargin: Theme.spacing.small
            options: [
                {
                    value: "0",
                    label: "Continue",
                    icon: "play_circle",
                    count: root.continuing.length
                },
                {
                    value: "1",
                    label: "Recent",
                    icon: "history",
                    count: root.series.length
                }
            ]
            value: String(root.tabIndex)
            onPicked: v => root.tabIndex = parseInt(v)
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            id: trailRow

            spacing: Theme.spacing.small
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
                onClicked: root.app.openAnime(root.animeOf(modelData), 0)
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
        Layout.topMargin: Theme.spacing.large
        Layout.bottomMargin: Theme.spacing.medium
        visible: root.shown.length === 0 && root.series.length > 0
        face: "٩(◕‿◕｡)۶"
        title: "All caught up!"
        message: "Switch to Recent to rewatch a finished series."
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
                root.app.openAnime(root.animeOf(target), 0);
            else if (item.value === "play")
                root.app.openAnime(root.animeOf(target), target.continue_episode);
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
                type: TextButton.Tonal
                text: "Remove"
                onClicked: {
                    Api.get("deleteSeries", {
                        key: deleteDialog.target.key
                    });
                    deleteDialog.close();
                    root.app.historyRevision++;
                }
            }
        ]
    }
}
