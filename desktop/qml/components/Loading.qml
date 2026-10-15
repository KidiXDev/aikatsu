import QtQuick
import Aikatsu

Item {
    id: root

    property real size: 40
    property color color: Theme.palette.primary
    property bool running: visible

    implicitWidth: size
    implicitHeight: size

    Item {
        anchors.fill: parent

        Repeater {
            model: 5

            Petal {
                required property int index

                width: root.size * 0.46
                height: width
                x: (root.size - width) / 2
                y: root.size / 2 - height * 0.98
                transformOrigin: Item.Bottom
                rotation: index * 72
                color: root.color
                opacity: 0.55 + index * 0.1
            }
        }

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 2400
            loops: Animation.Infinite
            running: root.running
        }

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: root.running

            NumberAnimation {
                to: 0.8
                duration: 600
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1
                duration: 600
                easing.type: Easing.InOutSine
            }
        }
    }
}
