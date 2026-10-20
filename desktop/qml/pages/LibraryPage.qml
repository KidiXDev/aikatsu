pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var history: []
    property var watchlist: []
    property string watchTab: "watching"
    // The chosen status, else the first one with shows in it.
    readonly property string shownStatus: watchlist.some(w => w.status === watchTab) ? watchTab : (Api.watchStatuses.find(s => watchlist.some(w => w.status === s.value))?.value ?? "")
    property var library: ({
            folders: [],
            series: []
        })

    function refreshHistory(): void {
        history = Api.get("history");
        watchlist = Api.get("watchlist");
    }

    function load(): void {
        Api.call("localLibrary", {}, lib => {
            root.library = lib;
            if (lib.series.some(s => s.available && !s.meta))
                Api.call("matchLocal", {});
        });
    }

    function show(): void {
        refreshHistory();
        load();
    }

    function titleOf(s: var): string {
        return s.meta?.title_english || s.meta?.title_romaji || s.name;
    }

    function open(s: var): void {
        if (!s.available) {
            ApplicationWindow.window.toast(`Connect the drive with “${s.path}” first`);
            return;
        }
        ApplicationWindow.window.openAnime({
            name: s.name,
            url: s.path,
            image: s.meta?.cover ?? "",
            source: "local",
            anilistId: s.meta?.anilist_id ?? 0
        }, 0);
    }

    Component.onCompleted: show()
    onVisibleChanged: if (visible)
        show()

    Connections {
        target: root.ApplicationWindow.window

        function onHistoryRevisionChanged(): void {
            root.refreshHistory();
        }
    }

    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind === "local")
                root.load();
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: content.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: content

            y: Theme.padding.extraLarge
            width: flick.width
            spacing: Theme.spacing.extraLarge

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge

                StyledText {
                    Layout.fillWidth: true
                    text: "Library"
                    font: Theme.font.headline.large
                }
                IconTextButton {
                    type: TextButton.Tonal
                    icon: "create_new_folder"
                    text: "Add folder"
                    onClicked: localFolders.add()
                }
            }

            Section {
                visible: root.history.length > 0
                icon: "history"
                title: "Continue watching"
            }
            HistoryGrid {
                visible: root.history.length > 0
                series: root.history
            }

            Section {
                visible: root.watchlist.length > 0
                icon: "bookmark"
                title: "Watchlist"
            }
            RowLayout {
                visible: root.watchlist.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.small

                Repeater {
                    model: Api.watchStatuses.filter(s => root.watchlist.some(w => w.status === s.value))

                    Chip {
                        required property var modelData

                        text: `${modelData.text}  ${root.watchlist.filter(w => w.status === modelData.value).length}`
                        icon: modelData.icon
                        selected: root.shownStatus === modelData.value
                        clickable: true
                        onClicked: root.watchTab = modelData.value
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            Flow {
                id: watchGrid

                readonly property int columns: Math.max(2, Math.floor((width + spacing) / (168 + spacing)))
                readonly property real cardWidth: (width - spacing * (columns - 1)) / columns

                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                spacing: Theme.spacing.large
                visible: root.watchlist.length > 0

                Repeater {
                    model: root.watchlist.filter(w => w.status === root.shownStatus)

                    PosterCard {
                        required property var modelData

                        width: watchGrid.cardWidth
                        height: implicitHeight + Theme.spacing.large
                        title: modelData.title
                        subtitle: modelData.total_episodes > 0 ? `${modelData.total_episodes} episodes` : ""
                        image: modelData.cover
                        onClicked: ApplicationWindow.window.openAnime({
                            name: modelData.title,
                            url: modelData.series_url,
                            image: modelData.cover,
                            source: modelData.source,
                            anilistId: modelData.anilist_id
                        }, 0)
                    }
                }
            }

            Section {
                icon: "folder"
                title: "Your folders"

                StyledText {
                    visible: text !== ""
                    text: root.library.unreachable?.length ? `Can't reach ${root.library.unreachable.join(", ")}` : ""
                    color: Theme.palette.onSurfaceVariant
                    font: Theme.font.body.medium
                }
                TextButton {
                    visible: root.library.folders.length > 0
                    type: TextButton.Text
                    text: "Manage"
                    onClicked: ApplicationWindow.window.openFolders()
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
                visible: root.library.series.length > 0

                Repeater {
                    model: root.library.series

                    PosterCard {
                        required property var modelData

                        width: grid.cardWidth
                        height: implicitHeight + Theme.spacing.large
                        opacity: modelData.available ? 1 : 0.5
                        title: root.titleOf(modelData)
                        subtitle: !modelData.available ? "Drive not connected" : !modelData.meta ? "Choose anime" : `${modelData.episodes} episode${modelData.episodes === 1 ? "" : "s"}`
                        image: modelData.meta?.cover ?? ""
                        onClicked: root.open(modelData)
                        onRightClicked: (x, y) => {
                            seriesMenu.target = modelData;
                            const p = mapToItem(root, x, y);
                            seriesMenu.x = p.x;
                            seriesMenu.y = p.y;
                            seriesMenu.open();
                        }
                    }
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                visible: root.library.folders.length === 0
                face: "( ˘▽˘)っ♨"
                title: "Bring your own anime"
                message: "Add a folder of videos and pick which anime it is. Episodes play here with your progress saved."
            }
        }
    }

    component Section: RowLayout {
        id: section

        property string icon
        property string title

        Layout.fillWidth: true
        Layout.leftMargin: Theme.padding.extraLarge
        Layout.rightMargin: Theme.padding.extraLarge
        spacing: Theme.spacing.small

        MaterialIcon {
            text: section.icon
            fill: 1
            color: Theme.palette.primary
        }
        StyledText {
            Layout.fillWidth: true
            text: section.title
            font: Theme.font.title.large
        }
    }

    LocalFolders {
        id: localFolders

        onEdited: root.load()
    }

    StyledMenu {
        id: seriesMenu

        property var target

        model: [
            {
                text: "Open",
                icon: "open_in_new",
                value: "open"
            },
            {
                text: "Choose anime…",
                icon: "link",
                value: "match"
            },
            {
                text: "Show in folder",
                icon: "folder_open",
                value: "show"
            },
            ...(target && !target.host ? [
                    {
                        text: "Remove from library",
                        icon: "folder_delete",
                        value: "remove"
                    }
                ] : [])
        ]
        onTriggered: item => {
            if (item.value === "open")
                root.open(target);
            else if (item.value === "match")
                matchDialog.openFor(target.path, target.name);
            else if (item.value === "show")
                Qt.openUrlExternally(Api.get("fileUrl", {
                    path: target.path
                }));
            else if (item.value === "remove")
                localFolders.remove(root.library.folders.find(f => f.path === target.root));
        }
    }

    MatchDialog {
        id: matchDialog

        onLinked: root.load()
    }
}
