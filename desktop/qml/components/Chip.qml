pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

StyledRect {
    id: root

    property string text
    property string icon
    property bool selected
    property bool clickable: false
    property color tint: Theme.palette.secondaryContainer
    property color onTint: Theme.palette.onSecondaryContainer
    readonly property color resolvedOnTint: {
        if (onTint.r > 0 || onTint.g > 0 || onTint.b > 0)
            return onTint;
        if (tint === Theme.palette.tertiaryContainer)
            return Theme.palette.onTertiaryContainer;
        if (tint === Theme.palette.errorContainer)
            return Theme.palette.onErrorContainer;
        if (tint === Theme.palette.primaryContainer)
            return Theme.palette.onPrimaryContainer;
        if (tint === Theme.palette.surfaceContainerHigh || tint === Theme.palette.surfaceContainerHighest)
            return Theme.palette.onSurfaceVariant;
        return Theme.palette.onSecondaryContainer;
    }

    signal clicked

    implicitHeight: 28
    implicitWidth: row.implicitWidth + Theme.padding.medium * 2
    radius: Theme.rounding.small
    color: selected ? tint : "transparent"
    border.width: selected ? 0 : 1
    border.color: Theme.palette.outlineVariant

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing.extraSmall

        MaterialIcon {
            visible: root.icon !== ""
            text: root.icon
            size: 12
            fill: root.selected ? 1 : 0
            color: root.selected ? root.resolvedOnTint : Theme.palette.onSurfaceVariant
        }
        StyledText {
            text: root.text
            font: Theme.font.label.large
            color: root.selected ? root.resolvedOnTint : Theme.palette.onSurfaceVariant
        }
    }

    StateLayer {
        visible: root.clickable
        color: root.selected ? root.resolvedOnTint : Theme.palette.onSurfaceVariant
        onClicked: root.clicked()
    }
}
