pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

// The folders the Library reads, opened from the Library page.
Item {
    id: root
    objectName: "foldersPage"

    property var folders: []

    function load(): void {
        Api.call("localLibrary", {
            lan: false
        }, lib => root.folders = lib.folders);
    }

    function nameOf(path: string): string {
        return path.split(/[\\/]/).filter(x => x).pop() ?? path;
    }

    Component.onCompleted: load()

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col

            x: (flick.width - width) / 2
            y: Theme.padding.extraLarge
            width: Math.min(820, flick.width - Theme.padding.extraLarge * 2)
            spacing: Theme.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.medium

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    iconSize: 18
                    onClicked: root.StackView.view.pop()
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Folders"
                    font: Theme.font.headline.large
                }
                IconTextButton {
                    type: TextButton.Filled
                    icon: "create_new_folder"
                    text: "Add folder"
                    onClicked: localFolders.add()
                }
            }

            Repeater {
                model: root.folders

                StyledRect {
                    id: card

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: row.implicitHeight + Theme.padding.large * 2
                    radius: Theme.rounding.extraLarge
                    color: Theme.palette.surfaceContainer

                    RowLayout {
                        id: row

                        anchors.fill: parent
                        anchors.margins: Theme.padding.large
                        anchors.leftMargin: Theme.padding.extraLarge
                        spacing: Theme.spacing.large

                        MaterialIcon {
                            text: card.modelData.available ? "folder" : "folder_off"
                            fill: 1
                            size: 22
                            color: card.modelData.available ? Theme.palette.primary : Theme.palette.error
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: root.nameOf(card.modelData.path)
                                font: Theme.font.title.medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.path
                                font: Theme.font.body.small
                                color: Theme.palette.onSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                        }
                        StyledText {
                            text: !card.modelData.available ? "Not connected" : card.modelData.anime ? `${card.modelData.anime} anime` : "No videos"
                            font: Theme.font.label.large
                            color: card.modelData.available ? Theme.palette.onSurfaceVariant : Theme.palette.error
                        }
                        TextButton {
                            visible: card.modelData.available
                            type: TextButton.Text
                            text: "Open"
                            onClicked: Qt.openUrlExternally(Api.get("fileUrl", {
                                path: card.modelData.path
                            }))
                        }
                        TextButton {
                            type: TextButton.Text
                            text: "Remove"
                            onClicked: localFolders.remove(card.modelData)
                        }
                    }
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge * 3
                visible: root.folders.length === 0
                face: "( ˘▽˘)っ♨"
                title: "No folders yet"
            }
        }
    }

    LocalFolders {
        id: localFolders

        onEdited: root.load()
    }
}
