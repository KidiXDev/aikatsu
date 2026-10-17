import QtQuick
import QtQuick.Shapes
import Aikatsu

// Rounded image with a placeholder while loading.
Item {
    id: root

    property alias source: img.source
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
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
    }

    // Fills from the image's texture directly; a layer mask would cost two offscreen buffers per image.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: img.status === Image.Ready ? 1 : 0

        ShapePath {
            // The fill is the whole picture at its own size, so crop it here as PreserveAspectCrop would.
            readonly property real crop: img.implicitWidth > 0 ? Math.max(root.width / img.implicitWidth, root.height / img.implicitHeight) : 1

            strokeWidth: -1
            fillItem: img
            fillTransform: PlanarTransform.fromAffineMatrix(crop, 0, 0, crop, (root.width - img.implicitWidth * crop) / 2, (root.height - img.implicitHeight * crop) / 2)

            PathRectangle {
                width: root.width
                height: root.height
                radius: root.radius
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
}
