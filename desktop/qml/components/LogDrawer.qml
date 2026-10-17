import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Aikatsu

// Ctrl+L: the end of this run's log file.
Drawer {
    id: root
    property bool exporting: false

    edge: Qt.BottomEdge
    width: parent.width
    height: parent.height * 0.5
    onOpened: refresh()

    function refresh(): void {
        const result = Api.get("logTail");
        logText.text = result?.error ?? result;
        Qt.callLater(() => flick.contentY = Math.max(0, flick.contentHeight - flick.height));
    }

    FileDialog {
        id: exportDialog

        title: "Export log"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Text files (*.txt)"]
        defaultSuffix: "txt"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        selectedFile: currentFolder + "/aikatsu-log.txt"
        onAccepted: {
            root.exporting = true;
            Api.call("exportLog", {path: Api.get("localPath", {url: selectedFile.toString()})}, () => {
                root.exporting = false;
                ApplicationWindow.window.toast("Log saved. Attach the .txt file to your GitHub issue.");
            }, error => {
                root.exporting = false;
                ApplicationWindow.window.toast("Couldn't export log: " + error);
            });
        }
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
                icon: "save_alt"
                disabled: root.exporting
                Accessible.name: "Export log"
                ToolTip.visible: hovered
                ToolTip.text: "Export log"
                onClicked: {
                    // Windows may not show a native dialog over the fullscreen GL window (see aikatsu_engine_init).
                    if (Qt.platform.os === "windows" && ApplicationWindow.window.visibility === Window.FullScreen)
                        ApplicationWindow.window.toggleFullScreen();
                    exportDialog.open();
                }
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
