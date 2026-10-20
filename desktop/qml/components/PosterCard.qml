pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property string title
    property string subtitle
    property string image
    property string badge
    property real progress: -1 // 0..1, hidden when < 0
    property bool hovered: mouse.containsMouse
    readonly property bool active: hovered || activeFocus

    signal clicked
    signal rightClicked(real x, real y)

    implicitWidth: 156
    implicitHeight: cover.height + info.implicitHeight + Theme.spacing.small
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: subtitle ? `${title}, ${subtitle}` : title
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Item {
        id: lift

        width: parent.width
        height: parent.height
        y: root.active ? -6 : 0
        scale: mouse.pressed ? 0.97 : 1

        Behavior on y {
            Anim {
                type: Anim.FastSpatial
            }
        }
        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Elevation {
            anchors.fill: cover
            radius: cover.radius
            level: root.active ? 4 : 1
        }

        ClippedImage {
            id: cover

            width: parent.width
            height: width * 1.45
            radius: Theme.rounding.large
            source: root.image

            // Bottom scrim so progress bars stay legible on bright cover art
            Rectangle {
                visible: root.progress >= 0 || root.active
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 44
                bottomLeftRadius: parent.radius
                bottomRightRadius: parent.radius
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.palette.surface, root.progress >= 0 ? 0.82 : 0.45)
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: root.active ? 2 : 1
                border.color: root.active ? Theme.palette.primary : Qt.alpha(Theme.palette.outlineVariant, 0.35)

                Behavior on border.width {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }

            StyledRect {
                visible: root.badge !== ""
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.spacing.small
                implicitWidth: badgeText.implicitWidth + Theme.padding.small * 2
                implicitHeight: badgeText.implicitHeight + Theme.padding.extraSmall + 2
                radius: Theme.rounding.small
                color: Theme.palette.tertiaryContainer

                Elevation {
                    z: -1
                    anchors.fill: parent
                    radius: parent.radius
                    level: 1
                }

                StyledText {
                    id: badgeText

                    anchors.centerIn: parent
                    text: root.badge
                    font: Theme.font.label.medium
                    color: Theme.palette.onTertiaryContainer
                }
            }

            LinearProgress {
                visible: root.progress >= 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacing.small + 2
                value: root.progress
                trackColor: Qt.alpha(Theme.palette.surfaceContainerHighest, 0.75)
            }

            StyledRect {
                anchors.centerIn: parent
                width: 48
                height: 48
                radius: 24
                color: Theme.palette.primary
                opacity: root.active ? 1 : 0
                scale: root.active ? 1 : 0.6

                Elevation {
                    z: -1
                    anchors.fill: parent
                    radius: parent.radius
                    level: 2
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    size: 20
                    color: Theme.palette.onPrimary
                }
            }
        }

        ColumnLayout {
            id: info

            anchors.top: cover.bottom
            anchors.topMargin: Theme.spacing.small
            width: parent.width
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font: Theme.font.title.small
                color: root.active ? Theme.palette.primary : Theme.palette.onSurface
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                font: Theme.font.label.medium
                color: Theme.palette.onSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked(e.x, e.y) : root.clicked()
    }
}
