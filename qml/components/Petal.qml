import QtQuick
import QtQuick.Shapes
import Aikatsu

// One sakura petal (same path as assets/sakura.svg), notch at the top.
Shape {
    id: root

    property color color: Theme.palette.primary

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        scale: Qt.size(root.width / 100, root.height / 100)

        PathSvg {
            path: "M50 96C24 80 10 50 26 18c4-7 10-9 15-5l9 12 9-12c5-4 11-2 15 5 16 32 2 62-24 78z"
        }
    }
}
