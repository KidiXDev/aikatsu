import QtQuick
import QtQuick.Layouts
import Aikatsu

// Centered kaomoji + message for empty/error states.
ColumnLayout {
    property string face: "(｡•́︿•̀｡)"
    property string title
    property string message
    property color tint: Theme.palette.primary

    spacing: Theme.spacing.small

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: parent.face
        font: Theme.font.headline.large
        color: parent.tint
    }
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        visible: text !== ""
        text: parent.title
        font: Theme.font.title.large
    }
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 420
        visible: text !== ""
        text: parent.message
        color: Theme.palette.onSurfaceVariant
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
}
