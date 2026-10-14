pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import Aikatsu

// M3 expressive slider: split track with a bar handle. `buffered` (0..1)
// shades the inactive track; `markers` [{from, to}] (0..1) highlight ranges.
T.Slider {
    id: root

    property real buffered
    property var markers: []
    property real trackHeight: 12
    readonly property alias hovering: hoverArea.containsMouse
    readonly property alias hoverX: hoverArea.mouseX

    implicitWidth: 200
    implicitHeight: 36
    padding: 0

    readonly property real handleGap: 5
    readonly property real px: visualPosition * width

    background: Item {
        Rectangle {
            x: 0
            y: (root.height - root.trackHeight) / 2
            width: Math.max(0, root.px - root.handleGap)
            height: root.trackHeight
            radius: Math.min(height / 2, 6)
            topRightRadius: 3
            bottomRightRadius: 3
            color: root.enabled ? Theme.palette.primary : Qt.alpha(Theme.palette.onSurface, 0.38)
        }

        Item {
            x: root.px + root.handleGap
            y: (root.height - root.trackHeight) / 2
            width: Math.max(0, root.width - x)
            height: root.trackHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, 6)
                topLeftRadius: 3
                bottomLeftRadius: 3
                color: Theme.palette.secondaryContainer
            }
            Rectangle {
                x: 0
                height: parent.height
                width: Math.max(0, root.buffered * root.width - parent.x)
                radius: 3
                color: Qt.alpha(Theme.palette.onSecondaryContainer, 0.25)
            }
        }

        Repeater {
            model: root.markers

            Rectangle {
                required property var modelData

                x: modelData.from * root.width
                width: Math.max(4, (modelData.to - modelData.from) * root.width)
                y: (root.height + root.trackHeight) / 2 + 3
                height: 3
                radius: 1.5
                color: Theme.palette.tertiary
            }
        }
    }

    handle: Rectangle {
        x: root.px - width / 2
        y: (root.height - height) / 2
        width: root.pressed ? 2 : 4
        height: root.trackHeight + 20
        radius: 2
        color: Theme.palette.primary

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    MouseArea {
        id: hoverArea

        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }
}
