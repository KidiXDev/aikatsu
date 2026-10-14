import QtQuick
import QtQuick.Effects
import Aikatsu

// Image with rounded corners (MultiEffect mask), a tinted placeholder while
// loading, and a fade-in once ready.
Item {
    id: root

    property alias source: img.source
    property alias fillMode: img.fillMode
    property alias status: img.status
    property real radius: Theme.rounding.medium
    property color placeholder: Theme.palette.surfaceContainerHighest

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.placeholder
        visible: img.status !== Image.Ready

        MaterialIcon {
            anchors.centerIn: parent
            text: img.status === Image.Error ? "broken_image" : "image"
            color: Theme.palette.onSurfaceVariant
            opacity: 0.4
            size: Math.max(8, Math.min(28, root.height / 4))
        }
    }

    Image {
        id: img

        anchors.fill: parent
        visible: false
        layer.enabled: true // else MultiEffect samples the raw texture, ignoring fillMode, and stretches it
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        opacity: img.status === Image.Ready ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }
}
