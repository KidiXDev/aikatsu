pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Aikatsu

// Adds and removes the Library's folders, for the Library and Folders pages.
Item {
    id: root

    signal edited

    function add(): void {
        picker.open();
    }

    // One holding several anime asks first.
    function remove(folder: var): void {
        if (folder.anime > 1) {
            confirm.folder = folder;
            confirm.open();
        } else {
            drop(folder.path);
        }
    }

    function drop(path: string): void {
        Api.get("removeLocalFolder", {
            path: path
        });
        edited();
    }

    FolderDialog {
        id: picker

        onAccepted: {
            const r = Api.get("addLocalFolder", {
                path: Api.get("localPath", {
                    url: selectedFolder.toString()
                })
            });
            if (r?.error)
                ApplicationWindow.window.toast(r.error);
            else
                root.edited();
        }
    }

    StyledDialog {
        id: confirm

        property var folder

        icon: "folder_delete"
        title: "Remove folder?"
        text: `All ${folder?.anime ?? 0} anime in “${folder?.path ?? ""}” leave your library.`
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: confirm.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Remove"
                onClicked: {
                    root.drop(confirm.folder.path);
                    confirm.close();
                }
            }
        ]
    }
}
