pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

StyledRect {
    id: root

    property int current: 0
    readonly property var items: [
        {
            icon: "home",
            label: "Home"
        },
        {
            icon: "search",
            label: "Search"
        },
        {
            icon: "video_library",
            label: "Library"
        },
        {
            icon: "download",
            label: "Downloads"
        },
        {
            icon: "settings",
            label: "Settings"
        }
    ]

    signal selected(int index)

    implicitWidth: 92
    color: Theme.palette.surfaceContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.padding.large
        anchors.bottomMargin: Theme.padding.large
        spacing: Theme.spacing.medium

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.spacing.large
            implicitWidth: 48
            implicitHeight: 48

            Image {
                id: logo

                anchors.fill: parent
                source: "qrc:/icon.svg"
                sourceSize: Qt.size(96, 96)

                RotationAnimation on rotation {
                    id: spin

                    running: false
                    from: 0
                    to: 360
                    duration: 900
                    easing.type: Easing.OutBack
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: spin.restart()
            }
        }

        Repeater {
            model: root.items

            Item {
                id: dest

                required property var modelData
                required property int index
                readonly property bool active: root.current === index

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 72
                implicitHeight: pill.height + label.implicitHeight + 4

                StyledRect {
                    id: pill

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: dest.active ? 56 : 32
                    height: 32
                    radius: Theme.rounding.full
                    color: dest.active ? Theme.palette.secondaryContainer : "transparent"

                    Behavior on width {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: dest.modelData.icon
                        size: 16
                        fill: dest.active ? 1 : 0
                        color: dest.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant

                        Behavior on fill {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: undefined
                        anchors.centerIn: parent
                        width: 56
                        height: parent.height
                        radius: Theme.rounding.full
                        color: Theme.palette.onSurface
                        onClicked: root.selected(dest.index)
                    }
                }

                StyledText {
                    id: label

                    anchors.top: pill.bottom
                    anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dest.modelData.label
                    font: Theme.font.label.medium
                    color: dest.active ? Theme.palette.onSurface : Theme.palette.onSurfaceVariant
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: Theme.dark ? "light_mode" : "dark_mode"
            iconSize: 16
            onClicked: Api.setSetting("theme", Theme.dark ? "light" : "dark")
        }
    }
}
