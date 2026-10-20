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
    readonly property int totalPlugins: repos.reduce((n, r) => n + (r.plugins?.length || 0), 0)

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
            spacing: Theme.spacing.extraLarge

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                IconButton {
                    type: IconButton.Tonal
                    icon: "arrow_back"
                    iconSize: 18
                    onClicked: root.StackView.view.pop()
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Plugins"
                    font: Theme.font.headline.large
                }
            }

            StateBand {
                StyledRect {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Theme.rounding.medium
                    color: Theme.palette.primary

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "extension"
                        fill: 1
                        size: 20
                        color: Theme.palette.onPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.repos.length === 0
                            ? "No plugin repositories installed"
                            : `${root.totalPlugins} source${root.totalPlugins === 1 ? "" : "s"} across ${root.repos.length} repo${root.repos.length === 1 ? "" : "s"}` + (root.updates > 0 ? `  ·  ${root.updates} update${root.updates === 1 ? "" : "s"} available` : "")
                        font: Theme.font.title.medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.updates > 0
                            ? "Updates are ready to download and install."
                            : "Plugin repositories provide site scrapers for Search and video playback."
                        color: root.updates > 0 ? Theme.palette.primary : Theme.palette.onSurfaceVariant
                        font: Theme.font.body.medium
                        wrapMode: Text.Wrap
                    }
                }

                TextButton {
                    visible: root.repos.length > 0
                    type: TextButton.Text
                    text: root.syncing ? "Checking…" : "Check updates"
                    disabled: root.syncing
                    onClicked: root.checkUpdates(false)
                }
                IconTextButton {
                    visible: root.updates > 0
                    type: TextButton.Tonal
                    icon: "download"
                    text: `Update (${root.updates})`
                    disabled: root.syncing
                    onClicked: root.checkUpdates(true)
                }
                IconTextButton {
                    type: root.updates > 0 ? TextButton.Text : TextButton.Tonal
                    icon: "add"
                    text: "Add repo"
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

                ColumnLayout {
                    id: card

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.padding.small
                        Layout.rightMargin: Theme.padding.small
                        spacing: Theme.spacing.medium

                        StyledText {
                            text: card.modelData.name
                            font: Theme.font.title.medium
                            elide: Text.ElideRight
                        }
                        Chip {
                            text: card.modelData.official ? "Official" : "Third-party"
                            selected: true
                            tint: card.modelData.official ? Theme.palette.secondaryContainer : Theme.palette.tertiaryContainer
                            onTint: card.modelData.official ? Theme.palette.onSecondaryContainer : Theme.palette.onTertiaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.error ? `Couldn't update · ${card.modelData.error}` : card.modelData.short
                            color: card.modelData.error ? Theme.palette.error : Theme.palette.onSurfaceVariant
                            font: Theme.font.body.small
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: (card.modelData.updates || 0) > 0
                            text: `${card.modelData.updates} update${card.modelData.updates === 1 ? "" : "s"}`
                            font: Theme.font.label.large
                            color: Theme.palette.primary
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

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: pluginCol.implicitHeight
                        radius: Theme.rounding.largeIncreased
                        color: Theme.palette.surfaceContainer

                        ColumnLayout {
                            id: pluginCol

                            width: parent.width
                            spacing: 0

                            Item {
                                visible: (card.modelData.plugins?.length ?? 0) === 0
                                Layout.fillWidth: true
                                implicitHeight: 60

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.padding.largeIncreased
                                    anchors.rightMargin: Theme.padding.large
                                    spacing: Theme.spacing.large

                                    StyledRect {
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        radius: Theme.rounding.medium
                                        color: card.modelData.error ? Theme.palette.errorContainer : Theme.palette.surfaceContainerHighest

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: card.modelData.error ? "cloud_off" : "extension_off"
                                            fill: 1
                                            size: 16
                                            color: card.modelData.error ? Theme.palette.onErrorContainer : Theme.palette.onSurfaceVariant
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.modelData.error ? "Repository unreachable. Check your connection and refresh." : "No sources loaded from this repository yet."
                                        color: Theme.palette.onSurfaceVariant
                                        font: Theme.font.body.medium
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Repeater {
                                model: card.modelData.plugins

                                Item {
                                    id: plugin

                                    required property var modelData
                                    required property int index
                                    readonly property bool enabledPlugin: plugin.modelData.loaded && !root.disabled.includes(plugin.modelData.key)

                                    Layout.fillWidth: true
                                    implicitHeight: 60

                                    Rectangle {
                                        visible: plugin.index > 0
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: Theme.padding.largeIncreased
                                        anchors.rightMargin: Theme.padding.largeIncreased
                                        height: 1
                                        color: Theme.palette.outlineVariant
                                        opacity: 0.6
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padding.largeIncreased
                                        anchors.rightMargin: Theme.padding.large
                                        spacing: Theme.spacing.large

                                        StyledRect {
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            radius: Theme.rounding.medium
                                            color: !plugin.modelData.loaded ? Theme.palette.errorContainer : plugin.enabledPlugin ? Theme.palette.secondaryContainer : Theme.palette.surfaceContainerHighest

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: plugin.modelData.loaded ? "public" : "error"
                                                fill: 1
                                                size: 16
                                                color: !plugin.modelData.loaded ? Theme.palette.onErrorContainer : plugin.enabledPlugin ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: plugin.modelData.name
                                                font: Theme.font.body.large
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: !plugin.modelData.loaded || plugin.modelData.updateAvailable
                                                text: !plugin.modelData.loaded
                                                    ? (plugin.modelData.compatible ? plugin.modelData.updateAvailable ? "Download update to enable" : "Couldn't load" : "Needs a newer Aikatsu")
                                                    : "Update available"
                                                color: !plugin.modelData.loaded ? Theme.palette.error : Theme.palette.primary
                                                font: Theme.font.body.small
                                                elide: Text.ElideRight
                                            }
                                        }

                                        StyledSwitch {
                                            visible: plugin.modelData.loaded
                                            checked: plugin.enabledPlugin
                                            onToggled: root.toggle(plugin.modelData.key, checked)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.extraLarge * 2
                visible: root.repos.length === 0
                face: "(・・ )?"
                title: "No plugins"
                message: "Add the official Kyoko repository or a custom plugin source to start searching."

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
                type: TextButton.Tonal
                text: "Add official Kyoko repo"
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
                type: TextButton.Tonal
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
                type: TextButton.Tonal
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
                type: TextButton.Tonal
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
