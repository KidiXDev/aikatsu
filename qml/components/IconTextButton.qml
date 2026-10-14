import QtQuick
import Aikatsu
import QtQuick.Layouts

ButtonBase {
    id: root

    property alias icon: iconLabel.text
    property alias text: label.text
    property alias spacing: row.spacing

    readonly property alias iconLabel: iconLabel
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

    implicitWidth: row.implicitWidth + horizontalPadding * 2
    implicitHeight: row.implicitHeight + verticalPadding * 2

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing.small

        MaterialIcon {
            id: iconLabel

            Layout.alignment: Qt.AlignVCenter
            color: root.onColour
            fill: root.internalChecked ? 1 : 0
            size: Math.round(root.font.pointSize * 1.35)

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledText {
            id: label

            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: 1
            color: root.onColour
            font: root.font
        }
    }
}
