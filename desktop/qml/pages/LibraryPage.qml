pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var history: []
    property var library: ({
            folders: [],
            series: []
        })

    function refreshHistory(): void {
        history = Api.get("history");
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

    function addFolder(url: string): void {
        const r = Api.get("addLocalFolder", {
            path: Api.get("localPath", {
                url: url
            })
        });
        if (r?.error)
            ApplicationWindow.window.toast(r.error);
        else
            load();
    }

    function removeFolder(path: string): void {
        Api.get("removeLocalFolder", {
            path: path
        });
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
                    onClicked: folderPicker.open()
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
                icon: "folder"
                title: "Your folders"
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding.extraLarge
                Layout.rightMargin: Theme.padding.extraLarge
                visible: root.library.folders.length > 0
                spacing: Theme.spacing.small

                Repeater {
                    model: root.library.folders

                    StyledRect {
                        id: chip

                        required property var modelData

                        implicitWidth: chipRow.implicitWidth + Theme.padding.medium + Theme.padding.extraSmall
                        implicitHeight: 32
                        radius: Theme.rounding.small
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.palette.outlineVariant

                        RowLayout {
                            id: chipRow

                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.padding.medium
                            spacing: Theme.spacing.small

                            MaterialIcon {
                                text: chip.modelData.available ? "folder" : "folder_off"
                                size: 12
                                color: chip.modelData.available ? Theme.palette.onSurfaceVariant : Theme.palette.error
                            }
                            StyledText {
                                Layout.maximumWidth: 420
                                text: chip.modelData.available ? chip.modelData.path : `${chip.modelData.path}  ·  not connected`
                                font: Theme.font.label.large
                                color: Theme.palette.onSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                            IconButton {
                                type: IconButton.Text
                                icon: "close"
                                iconSize: 12
                                onClicked: root.removeFolder(chip.modelData.path)
                            }
                        }
                    }
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

    FolderDialog {
        id: folderPicker

        onAccepted: root.addFolder(selectedFolder.toString())
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
            }
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
        }
    }

    MatchDialog {
        id: matchDialog

        onLinked: root.load()
    }
}
