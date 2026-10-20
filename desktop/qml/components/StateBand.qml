pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

// Tinted status band at the top of a room or page: shows what is true right now + primary actions.
StyledRect {
    id: root

    default property alias content: bandRow.data
    property alias spacing: bandRow.spacing

    Layout.fillWidth: true
    implicitHeight: bandRow.implicitHeight + Theme.padding.largeIncreased * 2
    radius: Theme.rounding.largeIncreased
    color: Qt.alpha(Theme.palette.secondaryContainer, Theme.dark ? 0.4 : 0.5)

    RowLayout {
        id: bandRow

        anchors.fill: parent
        anchors.margins: Theme.padding.largeIncreased
        spacing: Theme.spacing.large
    }
}
