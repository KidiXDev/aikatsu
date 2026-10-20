pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var jobs: ({}) // id -> job
    property string filter: "all" // all | active | finished
    readonly property var allJobs: Object.values(jobs).sort((a, b) => b.id - a.id)
    readonly property var activeList: allJobs.filter(j => ["queued", "resolving", "downloading", "remuxing"].includes(j.state))
    readonly property var finishedList: allJobs.filter(j => !["queued", "resolving", "downloading", "remuxing"].includes(j.state))
    readonly property var shownJobs: filter === "active" ? activeList : filter === "finished" ? finishedList : allJobs
    readonly property real totalSpeed: activeList.reduce((n, j) => n + (j.speed || 0), 0)
    property string downloadDir: Api.get("downloadDir")

    function reload(): void {
        const map = {};
        for (const j of Api.get("downloads"))
            map[j.id] = j;
        jobs = map;
        downloadDir = Api.get("downloadDir");
    }

    Component.onCompleted: reload()
    onVisibleChanged: if (visible)
        reload()

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

        StyledText {
            Layout.fillWidth: true
            text: "Downloads"
            font: Theme.font.headline.large
        }

        StateBand {
            StyledRect {
                implicitWidth: 44
                implicitHeight: 44
                radius: Theme.rounding.medium
                color: root.activeList.length > 0 ? Theme.palette.primary : Theme.palette.surfaceContainerHighest

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.activeList.length > 0 ? "downloading" : "download"
                    fill: 1
                    size: 20
                    color: root.activeList.length > 0 ? Theme.palette.onPrimary : Theme.palette.onSurfaceVariant
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.activeList.length > 0
                        ? `${root.activeList.length} active download${root.activeList.length === 1 ? "" : "s"}` + (root.totalSpeed > 0 ? `  ·  ${Theme.formatBytes(root.totalSpeed)}/s` : "")
                        : root.allJobs.length > 0
                            ? `${root.finishedList.length} completed or stopped`
                            : "No active downloads"
                    font: Theme.font.title.medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.downloadDir
                    color: Theme.palette.onSurfaceVariant
                    font: Theme.font.body.small
                    elide: Text.ElideMiddle
                }
            }

            TextButton {
                visible: root.finishedList.length > 0
                type: TextButton.Text
                text: "Clear finished"
                onClicked: {
                    Api.get("clearDownloads");
                    root.reload();
                }
            }
            IconTextButton {
                type: TextButton.Tonal
                icon: "folder_open"
                text: "Open folder"
                onClicked: Qt.openUrlExternally(Api.get("fileUrl", {
                    path: root.downloadDir
                }))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.allJobs.length > 0

            SegmentedControl {
                options: [
                    {
                        value: "all",
                        label: "All",
                        count: root.allJobs.length
                    },
                    {
                        value: "active",
                        label: "Active",
                        count: root.activeList.length
                    },
                    {
                        value: "finished",
                        label: "Finished",
                        count: root.finishedList.length
                    }
                ]
                value: root.filter
                onPicked: v => root.filter = v
            }
            Item {
                Layout.fillWidth: true
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacing.medium
            model: root.shownJobs
            visible: count > 0
            ScrollBar.vertical: StyledScrollBar {}

            delegate: StyledRect {
                id: row

                required property var modelData
                readonly property bool active: ["queued", "resolving", "downloading", "remuxing"].includes(modelData.state)

                width: list.width - 8
                implicitHeight: col.implicitHeight + Theme.padding.large * 2
                radius: Theme.rounding.largeIncreased
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
                            size: 18
                            fill: 1
                            color: row.modelData.state === "done" ? Theme.palette.onPrimary : row.modelData.state === "failed" ? Theme.palette.onErrorContainer : Theme.palette.onSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        id: col

                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font: Theme.font.title.medium
                                elide: Text.ElideRight
                            }
                            Chip {
                                text: `Ep ${row.modelData.episode}`
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.state === "failed" ? Api.describe(row.modelData.error) : row.modelData.state === "downloading" ? `${Theme.formatBytes(row.modelData.bytes)} of ${Theme.formatBytes(row.modelData.total)}  ·  ${Theme.formatBytes(row.modelData.speed)}/s` : row.modelData.state === "done" ? row.modelData.path : ({
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
                        type: IconButton.Tonal
                        icon: "close"
                        ToolTip.visible: hovered
                        ToolTip.text: "Cancel download"
                        onClicked: Api.get("cancelDownload", {
                            id: row.modelData.id
                        })
                    }
                    IconButton {
                        visible: row.modelData.state === "done"
                        type: IconButton.Tonal
                        icon: "folder_open"
                        ToolTip.visible: hovered
                        ToolTip.text: "Show in folder"
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
                title: root.allJobs.length === 0 ? "No downloads" : root.filter === "active" ? "No active downloads" : "No finished downloads"
                message: root.allJobs.length === 0 ? "Save episodes for offline watching from any anime page." : ""
            }
        }
    }
}
