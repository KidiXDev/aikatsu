import QtQuick
import Aikatsu

StyledRect {
    id: root

    function show(message: string): void {
        label.text = message;
        open = true;
        hide.restart();
    }

    property bool open
    // Animated instead of y: animating y would also animate window resizes, sliding a closed snackbar into view.
    property real lift: open ? height + 24 : -12

    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - lift
    z: 1000
    implicitWidth: Math.min(560, label.implicitWidth + Theme.padding.large * 2)
    implicitHeight: label.implicitHeight + Theme.padding.medium * 2
    radius: Theme.rounding.small
    color: Theme.palette.inverseSurface

    Behavior on lift {
        Anim {
            type: Anim.FastSpatial
        }
    }

    StyledText {
        id: label

        anchors.fill: parent
        anchors.margins: Theme.padding.medium
        anchors.leftMargin: Theme.padding.large
        anchors.rightMargin: Theme.padding.large
        color: Theme.palette.inverseOnSurface
        wrapMode: Text.Wrap
        verticalAlignment: Text.AlignVCenter
    }

    Timer {
        id: hide

        interval: 4000
        onTriggered: root.open = false
    }
}
