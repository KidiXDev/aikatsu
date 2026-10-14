import QtQuick
import QtQuick.Layouts
import Aikatsu

// M3 assist/filter chip; `selected` fills it with secondaryContainer.
StyledRect {
    id: root

    property string text
    property string icon
    property bool selected
    property bool clickable: false
    property color tint: Theme.palette.secondaryContainer
    property color onTint: Theme.palette.onSecondaryContainer

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
            color: root.selected ? root.onTint : Theme.palette.onSurfaceVariant
        }
        StyledText {
            text: root.text
            font: Theme.font.label.large
            color: root.selected ? root.onTint : Theme.palette.onSurfaceVariant
        }
    }

    StateLayer {
        visible: root.clickable
        color: root.selected ? root.onTint : Theme.palette.onSurfaceVariant
        onClicked: root.clicked()
    }
}
