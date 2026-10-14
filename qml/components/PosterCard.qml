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

    signal clicked
    signal rightClicked(real x, real y)

    implicitWidth: 156
    implicitHeight: cover.height + info.implicitHeight + Theme.spacing.small

    Item {
        id: lift

        width: parent.width
        height: parent.height
        y: root.hovered ? -6 : 0
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
            level: root.hovered ? 4 : 1
        }

        ClippedImage {
            id: cover

            width: parent.width
            height: width * 1.45
            radius: Theme.rounding.large
            source: root.image

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: root.hovered ? 2 : 0
                border.color: Theme.palette.primary

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
                implicitHeight: badgeText.implicitHeight + Theme.padding.extraSmall
                radius: Theme.rounding.small
                color: Theme.palette.tertiaryContainer

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
                anchors.margins: Theme.spacing.small
                value: root.progress
                trackColor: Qt.alpha("#000000", 0.45)
            }

            StyledRect {
                anchors.centerIn: parent
                width: 48
                height: 48
                radius: 24
                color: Qt.alpha(Theme.palette.primary, 0.92)
                opacity: root.hovered ? 1 : 0
                scale: root.hovered ? 1 : 0.6

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
                color: root.hovered ? Theme.palette.primary : Theme.palette.onSurface
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
