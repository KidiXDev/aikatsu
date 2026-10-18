pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Aikatsu

// Plugin repos and the sources each brings, opened from Settings.
Item {
    id: root
    objectName: "pluginsPage"

    property var repos: Api.get("repos")
    property var disabled: (Api.setting("disabledSources") || "").split(",").map(x => x.trim()).filter(x => x)
    property bool syncing
    property bool developerMode: Api.setting("developerMode") === "true"
    readonly property int updates: repos.reduce((n, r) => n + (r.updates || 0), 0)

    function refresh(): void {
        repos = Api.get("repos");
    }

    function toggle(key: string, on: bool): void {
        const list = disabled.filter(k => k !== key);
        if (!on)
            list.push(key);
        Api.setSetting("disabledSources", list.join(","));
        disabled = list;
    }

    function checkUpdates(download: bool): void {
        if (syncing)
            return;
        syncing = true;
        Api.call(download ? "syncPlugins" : "checkPluginUpdates", {}, result => {
            syncing = false;
            repos = download ? result.repos : result;
            ApplicationWindow.window.toast(repos.some(r => r.error)
                ? download ? "Some repos couldn't update" : "Some repos couldn't be checked"
                : download && result.updated ? "Plugins updated"
                : updates > 0 ? `${updates} plugin update${updates === 1 ? "" : "s"} available` : "Plugins are up to date");
        }, e => {
            syncing = false;
            ApplicationWindow.window.toast(e);
        });
    }

    // Kyoko goes straight in; any other repo asks for trust first.
    function check(input: string): void {
        const url = input.trim();
        if (!url || addDialog.busy)
            return;
        addDialog.busy = true;
        addDialog.error = "";
        Api.call("previewRepo", {
            url: url
        }, preview => {
            addDialog.busy = false;
            addDialog.close();
            if (preview.official)
                add(preview.url, preview.name);
            else {
                trustDialog.preview = preview;
                trustDialog.open();
            }
        }, e => {
            addDialog.busy = false;
            addDialog.error = e;
        });
    }

    function add(url: string, name: string): void {
        if (syncing)
            return;
        syncing = true;
        Api.call("addRepo", {
            url: url
        }, list => {
            syncing = false;
            repos = list;
            ApplicationWindow.window.toast(list.some(r => r.url === url && r.error) ? `Added ${name}; some plugins could not load` : `Added ${name}`);
        }, e => {
            syncing = false;
            ApplicationWindow.window.toast(e);
        });
    }

    Connections {
        target: Api

        function onSettingChanged(key: string, value: string): void {
            if (key === "developerMode")
                root.developerMode = value === "true";
        }

        function onPushed(kind: string, data: var): void {
            if (kind === "plugins")
                root.refresh();
        }
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col

            x: (flick.width - width) / 2
            y: Theme.padding.extraLarge
            width: Math.min(820, flick.width - Theme.padding.extraLarge * 2)
            spacing: Theme.spacing.large

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    iconSize: 18
                    onClicked: root.StackView.view.pop()
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Plugins"
                    font: Theme.font.headline.large
                }
                IconButton {
                    visible: root.updates > 0
                    type: IconButton.Text
                    icon: "download"
                    iconSize: 18
                    disabled: root.syncing
                    ToolTip.visible: hovered
                    ToolTip.text: `Download ${root.updates} plugin update${root.updates === 1 ? "" : "s"}`
                    onClicked: root.checkUpdates(true)
                }
                IconButton {
                    id: refreshButton

                    type: IconButton.Text
                    icon: "refresh"
                    iconSize: 18
                    disabled: root.syncing
                    ToolTip.visible: hovered
                    ToolTip.text: "Check for updates"
                    onClicked: root.checkUpdates(false)

                    RotationAnimator {
                        target: refreshButton.label
                        running: root.syncing
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running)
                            refreshButton.label.rotation = 0
                    }
                }
                IconTextButton {
                    type: TextButton.Filled
                    icon: "add"
                    text: "Add"
                    disabled: root.syncing
                    onClicked: {
                        addDialog.error = "";
                        urlField.text = "";
                        addDialog.open();
                    }
                }
            }

            Repeater {
                model: root.repos

                StyledRect {
                    id: card

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: inner.implicitHeight + Theme.padding.extraLarge * 2
                    radius: Theme.rounding.extraLarge
                    color: Theme.palette.surfaceContainer

                    ColumnLayout {
                        id: inner

                        anchors.fill: parent
                        anchors.margins: Theme.padding.extraLarge
                        spacing: Theme.spacing.medium

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Theme.spacing.small
                            spacing: Theme.spacing.medium

                            // Names and links come from repo authors, so both elide.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    font: Theme.font.title.large
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.error ? `Couldn't update · ${card.modelData.error}` : card.modelData.short
                                    color: card.modelData.error ? Theme.palette.error : Theme.palette.onSurfaceVariant
                                    font: Theme.font.body.small
                                    elide: Text.ElideRight
                                }
                            }
                            Chip {
                                visible: !card.modelData.official
                                text: "Third-party"
                                selected: true
                                tint: Theme.palette.tertiaryContainer
                                onTint: Theme.palette.onTertiaryContainer
                            }
                            TextButton {
                                type: TextButton.Text
                                text: "Remove"
                                disabled: root.syncing
                                onClicked: {
                                    removeDialog.repo = card.modelData;
                                    removeDialog.open();
                                }
                            }
                        }
                        Repeater {
                            model: card.modelData.plugins

                            RowLayout {
                                id: plugin

                                required property var modelData

                                Layout.fillWidth: true
                                spacing: Theme.spacing.large

                                StyledText {
                                    Layout.fillWidth: true
                                    text: plugin.modelData.name
                                    font: Theme.font.body.large
                                }
                                StyledText {
                                    visible: !plugin.modelData.loaded
                                    text: plugin.modelData.compatible ? plugin.modelData.updateAvailable ? "Download to enable" : "Couldn't load" : "Needs a newer Aikatsu"
                                    color: Theme.palette.onSurfaceVariant
                                    font: Theme.font.body.small
                                }
                                StyledSwitch {
                                    visible: plugin.modelData.loaded
                                    checked: !root.disabled.includes(plugin.modelData.key)
                                    onToggled: root.toggle(plugin.modelData.key, checked)
                                }
                            }
                        }
                        StyledText {
                            visible: (card.modelData.updates || 0) > 0
                            text: `${card.modelData.updates} plugin update${card.modelData.updates === 1 ? "" : "s"} available`
                            font: Theme.font.body.small
                            color: Theme.palette.primary
                        }
                    }
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge * 3
                visible: root.repos.length === 0
                face: "(・・ )?"
                title: "No plugins"
                message: "Search needs at least one."

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    type: TextButton.Tonal
                    text: "Add Kyoko"
                    disabled: root.syncing
                    onClicked: root.add(Api.get("officialRepo"), "Kyoko")
                }
            }
            TextButton {
                visible: root.repos.length > 0 && !root.repos.some(r => r.official)
                type: TextButton.Text
                text: "Add Kyoko"
                disabled: root.syncing
                onClicked: root.add(Api.get("officialRepo"), "Kyoko")
            }
        }
    }

    FolderDialog {
        id: repoFolderPicker

        title: "Choose plugin repo folder"
        onAccepted: {
            urlField.text = selectedFolder.toString().replace(/\/$/, "") + "/index.json";
            root.check(urlField.text);
        }
    }

    StyledDialog {
        id: addDialog

        property bool busy
        property string error

        icon: "extension"
        title: "Add plugins"
        onOpened: urlField.forceActiveFocus()

        StyledTextField {
            id: urlField

            Layout.fillWidth: true
            placeholderText: "https://github.com/user/repo"
            isError: addDialog.error !== ""
            errorText: addDialog.error
            onAccepted: root.check(text)
        }

        IconTextButton {
            visible: root.developerMode
            type: TextButton.Tonal
            icon: "folder_open"
            text: "Choose folder"
            disabled: addDialog.busy
            onClicked: repoFolderPicker.open()
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.developerMode
            text: "Choose a folder containing index.json, or paste its file:// URL above."
            font: Theme.font.body.small
            color: Theme.palette.onSurfaceVariant
            wrapMode: Text.WordWrap
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: addDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: addDialog.busy ? "Checking…" : "Add"
                disabled: addDialog.busy || !urlField.text.trim()
                onClicked: root.check(urlField.text)
            }
        ]
    }

    StyledDialog {
        id: trustDialog

        property var preview: ({})

        icon: "gpp_maybe"
        title: "Trust this repo?"
        text: `${preview.short ?? ""} can see what you search and watch, open any website, and choose the videos you play. Only add repos you trust.`

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            Repeater {
                model: trustDialog.preview.plugins ?? []

                Chip {
                    required property var modelData

                    text: modelData.name
                }
            }
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: trustDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Trust and add"
                onClicked: {
                    trustDialog.close();
                    root.add(trustDialog.preview.url, trustDialog.preview.name);
                }
            }
        ]
    }

    StyledDialog {
        id: removeDialog

        property var repo: ({})

        icon: "delete"
        title: `Remove ${repo.name ?? ""}?`
        text: "Its sources will be removed from search."
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: removeDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Remove"
                onClicked: {
                    if (root.syncing)
                        return;
                    root.syncing = true;
                    Api.call("removeRepo", {
                        url: removeDialog.repo.url
                    }, list => {
                        root.syncing = false;
                        root.repos = list;
                    }, e => {
                        root.syncing = false;
                        ApplicationWindow.window.toast(e);
                    });
                    removeDialog.close();
                }
            }
        ]
    }
}
