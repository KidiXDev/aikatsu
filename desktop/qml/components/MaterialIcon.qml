import QtQuick
import Aikatsu

StyledText {
    property real fill
    property int grade: Theme.dark ? -25 : 0
    property real size: 15
    property int weight: 400

    renderType: Text.QtRendering
    font.family: Theme.iconFamily
    font.pointSize: size
    font.variableAxes: ({
            "FILL": fill,
            "GRAD": grade,
            "opsz": Math.max(20, Math.min(48, size * 4 / 3)),
            "wght": weight
        })
}
