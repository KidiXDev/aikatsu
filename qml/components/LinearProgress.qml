import QtQuick
import Aikatsu

// M3 linear progress: track + indicator with a small gap; indeterminate sweeps.
Item {
    id: root

    property real value // 0..1
    property bool indeterminate
    property color color: Theme.palette.primary
    property color trackColor: Theme.palette.secondaryContainer

    implicitHeight: 4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        id: bar

        height: parent.height
        radius: height / 2
        color: root.color
        x: root.indeterminate ? sweep.x : 0
        width: root.indeterminate ? root.width * 0.35 : Math.max(height, root.width * Math.max(0, Math.min(1, root.value)))
        visible: root.indeterminate || root.value > 0

        Behavior on width {
            enabled: !root.indeterminate

            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    QtObject {
        id: sweep

        property real x
    }

    NumberAnimation {
        target: sweep
        property: "x"
        from: -root.width * 0.35
        to: root.width
        duration: 1200
        loops: Animation.Infinite
        running: root.indeterminate && root.visible
        easing.type: Easing.InOutCubic
    }

    clip: true
}
