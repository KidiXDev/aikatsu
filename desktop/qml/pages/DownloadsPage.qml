pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var jobs: ({}) // id -> job

    function sorted(): var {
        return Object.values(jobs).sort((a, b) => b.id - a.id);
    }

    function fmtBytes(n: real): string {
        if (!n)
            return "0 MB";
        return n > 1073741824 ? (n / 1073741824).toFixed(2) + " GB" : (n / 1048576).toFixed(1) + " MB";
    }

    Component.onCompleted: {
        const map = {};
        for (const j of Api.get("downloads"))
            map[j.id] = j;
        jobs = map;
    }

    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind !== "download")
                return;
            const map = Object.assign({}, root.jobs);
            map[data.id] = data;
            root.jobs = map;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding.extraLarge
        spacing: Theme.spacing.large

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: "Downloads"
                font: Theme.font.headline.large
            }
            IconTextButton {
                type: TextButton.Text
                icon: "folder_open"
                text: "Open folder"
                onClicked: Qt.openUrlExternally(Api.get("fileUrl", {
                    path: Api.get("downloadDir")
                }))
            }
            IconTextButton {
                type: TextButton.Tonal
                icon: "clear_all"
                text: "Clear finished"
                onClicked: {
                    Api.get("clearDownloads");
                    const map = {};
                    for (const j of Api.get("downloads"))
                        map[j.id] = j;
                    root.jobs = map;
                }
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacing.medium
            model: root.sorted()
            visible: count > 0
            ScrollBar.vertical: StyledScrollBar {}

            delegate: StyledRect {
                id: row

                required property var modelData
                readonly property bool active: ["queued", "resolving", "downloading", "remuxing"].includes(modelData.state)

                width: list.width - 8
                implicitHeight: col.implicitHeight + Theme.padding.large * 2
                radius: Theme.rounding.large
                color: Theme.palette.surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padding.large
                    spacing: Theme.spacing.large

                    StyledRect {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: Theme.rounding.medium
                        color: row.modelData.state === "done" ? Theme.palette.primary : row.modelData.state === "failed" ? Theme.palette.errorContainer : Theme.palette.secondaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: ({
                                    done: "check",
                                    failed: "error",
                                    cancelled: "block",
                                    queued: "schedule",
                                    resolving: "travel_explore",
                                    remuxing: "movie_edit"
                                })[row.modelData.state] ?? "download"
                            size: 16
                            color: row.modelData.state === "done" ? Theme.palette.onPrimary : row.modelData.state === "failed" ? Theme.palette.onErrorContainer : Theme.palette.onSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        id: col

                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            text: `${row.modelData.title}  ·  Episode ${row.modelData.episode}`
                            font: Theme.font.title.medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.state === "failed" ? Api.describe(row.modelData.error) : row.modelData.state === "downloading" ? `${root.fmtBytes(row.modelData.bytes)} of ${root.fmtBytes(row.modelData.total)}  ·  ${root.fmtBytes(row.modelData.speed)}/s` : row.modelData.state === "done" ? row.modelData.path : ({
                                    queued: "Queued",
                                    resolving: "Finding video…",
                                    remuxing: "Finishing…",
                                    cancelled: "Cancelled"
                                })[row.modelData.state] ?? ""
                            color: row.modelData.state === "failed" ? Theme.palette.error : Theme.palette.onSurfaceVariant
                            font: Theme.font.label.large
                            elide: Text.ElideMiddle
                        }
                        LinearProgress {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: row.active
                            indeterminate: row.modelData.state !== "downloading" || row.modelData.total === 0
                            value: row.modelData.progress
                        }
                    }

                    StyledText {
                        visible: row.modelData.state === "downloading" && row.modelData.total > 0
                        text: `${Math.round(row.modelData.progress * 100)}%`
                        font: Theme.font.title.medium
                        color: Theme.palette.primary
                    }
                    IconButton {
                        visible: row.active
                        type: IconButton.Text
                        icon: "close"
                        onClicked: Api.get("cancelDownload", {
                            id: row.modelData.id
                        })
                    }
                    IconButton {
                        visible: row.modelData.state === "done"
                        type: IconButton.Text
                        icon: "folder"
                        onClicked: Qt.openUrlExternally(Api.get("fileUrl", {
                            path: row.modelData.path,
                            parent: true
                        }))
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: list.count === 0

            EmptyState {
                anchors.centerIn: parent
                face: "( ˘▽˘)っ♨"
                title: "No downloads"
                message: "Start one from an anime's page."
            }
        }
    }
}
