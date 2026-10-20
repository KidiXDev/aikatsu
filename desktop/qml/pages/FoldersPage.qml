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
    readonly property int totalAnime: folders.reduce((n, f) => n + (f.anime || 0), 0)

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
            spacing: Theme.spacing.extraLarge

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                IconButton {
                    type: IconButton.Tonal
                    icon: "arrow_back"
                    iconSize: 18
                    onClicked: root.StackView.view.pop()
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Folders"
                    font: Theme.font.headline.large
                }
            }

            StateBand {
                StyledRect {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Theme.rounding.medium
                    color: Theme.palette.primary

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "folder"
                        fill: 1
                        size: 20
                        color: Theme.palette.onPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.folders.length === 0 ? "No folders added" : `${root.folders.length} folder${root.folders.length === 1 ? "" : "s"}  ·  ${root.totalAnime} series`
                        font: Theme.font.title.medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Subfolders with video files appear in Library and link to AniList metadata."
                        color: Theme.palette.onSurfaceVariant
                        font: Theme.font.body.medium
                        wrapMode: Text.Wrap
                    }
                }

                IconTextButton {
                    type: TextButton.Tonal
                    icon: "create_new_folder"
                    text: "Add folder"
                    onClicked: localFolders.add()
                }
            }

            StyledRect {
                visible: root.folders.length > 0
                Layout.fillWidth: true
                implicitHeight: folderList.implicitHeight
                radius: Theme.rounding.largeIncreased
                color: Theme.palette.surfaceContainer

                ColumnLayout {
                    id: folderList

                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.folders

                        Item {
                            id: card

                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: Math.max(72, row.implicitHeight + Theme.padding.large * 2)

                            Rectangle {
                                visible: card.index > 0
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.padding.largeIncreased
                                anchors.rightMargin: Theme.padding.largeIncreased
                                height: 1
                                color: Theme.palette.outlineVariant
                                opacity: 0.6
                            }

                            RowLayout {
                                id: row

                                anchors.fill: parent
                                anchors.leftMargin: Theme.padding.largeIncreased
                                anchors.rightMargin: Theme.padding.large
                                spacing: Theme.spacing.large

                                StyledRect {
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    radius: Theme.rounding.medium
                                    color: card.modelData.available ? Theme.palette.surfaceContainerHighest : Theme.palette.errorContainer

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: card.modelData.available ? "folder" : "folder_off"
                                        fill: 1
                                        size: 18
                                        color: card.modelData.available ? Theme.palette.primary : Theme.palette.onErrorContainer
                                    }
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
                                Chip {
                                    text: !card.modelData.available ? "Disconnected" : card.modelData.anime ? `${card.modelData.anime} anime` : "No videos"
                                    selected: !card.modelData.available
                                    tint: Theme.palette.errorContainer
                                    onTint: Theme.palette.onErrorContainer
                                }
                                TextButton {
                                    visible: card.modelData.available
                                    type: TextButton.Tonal
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
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge * 2
                visible: root.folders.length === 0
                face: "( ˘▽˘)っ♨"
                title: "No folders yet"
                message: "Add a folder containing your downloaded or local anime episodes."
            }
        }
    }

    LocalFolders {
        id: localFolders

        onEdited: root.load()
    }
}
