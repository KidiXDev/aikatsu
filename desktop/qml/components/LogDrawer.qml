import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

// Ctrl+L: the end of this run's log file.
Drawer {
    id: root

    edge: Qt.BottomEdge
    width: parent.width
    height: parent.height * 0.5
    onOpened: refresh()

    function refresh(): void {
        const result = Api.get("logTail");
        logText.text = result?.error ?? result;
        Qt.callLater(() => flick.contentY = Math.max(0, flick.contentHeight - flick.height));
    }

    background: StyledRect {
        color: Theme.palette.surfaceContainerHigh
        topLeftRadius: Theme.rounding.extraLarge
        topRightRadius: Theme.rounding.extraLarge
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding.large

        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "terminal"
                color: Theme.palette.primary
            }
            StyledText {
                Layout.fillWidth: true
                text: "Logs"
                font: Theme.font.title.medium
            }
            IconButton {
                type: IconButton.Text
                icon: "refresh"
                onClicked: root.refresh()
            }
            IconButton {
                type: IconButton.Text
                icon: "close"
                onClicked: root.close()
            }
        }

        StyledFlickable {
            id: flick

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: logText.implicitHeight
            ScrollBar.vertical: StyledScrollBar {}

            TextEdit {
                id: logText

                width: flick.width
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                font.family: "monospace"
                font.pointSize: 9
                color: Theme.palette.onSurfaceVariant
                selectionColor: Qt.alpha(Theme.palette.primary, 0.4)
            }
        }
    }
}
