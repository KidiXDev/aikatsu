pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

StyledRect {
    id: root

    property int current: 0
    property int activeDownloads: 0
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
            label: "Downloads",
            badge: activeDownloads
        },
        {
            icon: "settings",
            label: "Settings"
        }
    ]

    signal selected(int index)

    implicitWidth: 92
    color: Theme.palette.surfaceContainer
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTabList
    Keys.onUpPressed: if (current > 0)
        selected(current - 1)
    Keys.onDownPressed: if (current < items.length - 1)
        selected(Math.max(0, current + 1))

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: Theme.palette.outlineVariant
        opacity: 0.35
    }

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
                readonly property int badgeCount: modelData.badge ?? 0

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 76
                implicitHeight: pillHit.height + label.implicitHeight + 6
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.label
                Accessible.checked: active

                Item {
                    id: pillHit

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 32

                    StyledRect {
                        anchors.centerIn: parent
                        width: dest.active ? 56 : hitLayer.containsMouse ? 40 : 28
                        height: 32
                        radius: Theme.rounding.full
                        color: dest.active ? Theme.palette.secondaryContainer : "transparent"
                        border.width: dest.active && root.activeFocus ? 2 : 0
                        border.color: Theme.palette.primary

                        Behavior on width {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    StateLayer {
                        id: hitLayer

                        anchors.fill: parent
                        radius: Theme.rounding.full
                        color: dest.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
                        onClicked: root.selected(dest.index)
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: dest.modelData.icon
                        size: 16
                        fill: dest.active ? 1 : 0
                        color: dest.active ? Theme.palette.onSecondaryContainer : hitLayer.containsMouse ? Theme.palette.onSurface : Theme.palette.onSurfaceVariant

                        Behavior on fill {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    StyledRect {
                        visible: dest.badgeCount > 0
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 6
                        anchors.topMargin: -2
                        implicitWidth: Math.max(16, badgeLabel.implicitWidth + 6)
                        implicitHeight: 16
                        radius: Theme.rounding.full
                        color: Theme.palette.primary

                        StyledText {
                            id: badgeLabel

                            anchors.centerIn: parent
                            text: String(dest.badgeCount)
                            font: Theme.font.label.small
                            color: Theme.palette.onPrimary
                        }
                    }
                }

                StyledText {
                    id: label

                    anchors.top: pillHit.bottom
                    anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dest.modelData.label
                    font: Theme.font.label.medium
                    color: dest.active ? Theme.palette.onSurface : hitLayer.containsMouse ? Theme.palette.onSurface : Theme.palette.onSurfaceVariant
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        IconButton {
            id: themeBtn

            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: Theme.dark ? "light_mode" : "dark_mode"
            iconSize: 16
            ToolTip.visible: hovered
            ToolTip.text: Theme.dark ? "Switch to light theme" : "Switch to dark theme"
            onClicked: Api.setSetting("theme", Theme.dark ? "light" : "dark")
        }
    }
}
