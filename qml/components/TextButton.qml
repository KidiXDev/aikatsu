import QtQuick
import Aikatsu

ButtonBase {
    id: root

    property alias text: label.text
    readonly property alias label: label

    horizontalPadding: Theme.padding.medium
    verticalPadding: Theme.padding.small

    activeColour: type === TextButton.Filled ? Theme.palette.primary : Theme.palette.secondary
    inactiveColour: {
        if (!isToggle && type === TextButton.Filled)
            return Theme.palette.primary;
        return type === TextButton.Filled ? Theme.palette.surfaceContainer : Theme.palette.secondaryContainer;
    }
    activeOnColour: {
        if (type === TextButton.Text)
            return Theme.palette.primary;
        return type === TextButton.Filled ? Theme.palette.onPrimary : Theme.palette.onSecondary;
    }
    inactiveOnColour: {
        if (!isToggle && type === TextButton.Filled)
            return Theme.palette.onPrimary;
        if (type === TextButton.Text)
            return Theme.palette.primary;
        return type === TextButton.Filled ? Theme.palette.onSurface : Theme.palette.onSecondaryContainer;
    }

    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2

    StyledText {
        id: label

        anchors.centerIn: parent
        color: root.onColour
        font: root.font
    }
}
