import QtQuick
import QtQuick.Layouts
import Aikatsu

// Centered kaomoji + message for empty/error states. Extra children (e.g. a
// retry button) stack underneath.
ColumnLayout {
    property string face: "(｡•́︿•̀｡)"
    property string title
    property string message
    property string details // raw error text, small and selectable
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
    TextEdit {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 480
        visible: text !== ""
        text: parent.details
        readOnly: true
        selectByMouse: true
        color: Qt.alpha(Theme.palette.onSurfaceVariant, 0.7)
        selectionColor: Theme.palette.secondaryContainer
        font: Theme.font.body.small
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
}
