import QtQuick
import Aikatsu

ButtonBase {
    id: root

    property alias icon: label.text
    readonly property alias label: label

    property real iconSize: 15
    padding: type === IconButton.Text ? Theme.padding.extraSmall / 2 : Theme.padding.small

    activeColour: type === IconButton.Filled ? Theme.palette.primary : Theme.palette.secondary
    inactiveColour: {
        if (!isToggle && type === IconButton.Filled)
            return Theme.palette.primary;
        return type === IconButton.Filled ? Theme.palette.surfaceContainer : Theme.palette.secondaryContainer;
    }
    activeOnColour: type === IconButton.Filled ? Theme.palette.onPrimary : type === IconButton.Tonal ? Theme.palette.onSecondary : Theme.palette.primary
    inactiveOnColour: {
        if (!isToggle && type === IconButton.Filled)
            return Theme.palette.onPrimary;
        return type === IconButton.Tonal ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant;
    }

    implicitWidth: implicitHeight
    implicitHeight: {
        // Ensure even size so icon is centered properly
        const h = label.implicitHeight + padding * 2;
        if (h % 2 !== 0)
            return h + 1;
        return h;
    }

    MaterialIcon {
        id: label

        anchors.centerIn: parent
        color: root.onColour
        size: root.iconSize
        fill: !root.isToggle || root.internalChecked ? 1 : 0

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
