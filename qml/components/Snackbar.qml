import QtQuick
import Aikatsu

// Bottom-center transient message.
StyledRect {
    id: root

    function show(message: string): void {
        label.text = message;
        open = true;
        hide.restart();
    }

    property bool open

    anchors.horizontalCenter: parent.horizontalCenter
    y: open ? parent.height - height - 24 : parent.height + 12
    z: 1000
    implicitWidth: Math.min(560, label.implicitWidth + Theme.padding.large * 2)
    implicitHeight: label.implicitHeight + Theme.padding.medium * 2
    radius: Theme.rounding.small
    color: Theme.palette.inverseSurface

    Behavior on y {
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
