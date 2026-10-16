pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property var s: Api.get("settings")
    property var sources: Api.get("sources")
    readonly property var disabled: (s.disabledSources || "").split(",").map(x => x.trim()).filter(x => x)
    readonly property var modes: Api.get("anime4kModes")
    property bool installingShaders
    property bool shadersInstalled: Api.get("anime4kInstalled")
    property var account: Api.get("syncStatus")
    property real now: Date.now()
    readonly property var tools: Api.get("tools")
    readonly property int sourcesOn: sources.filter(x => !disabled.includes(x.key)).length

    function set(key: string, value: var): void {
        Api.setSetting(key, value);
        s = Api.get("settings");
    }

    function host(url: string): string {
        return url.replace(/^https?:\/\//, "");
    }

    function syncedLabel(): string {
        if (!account.lastSync)
            return "Not synced yet";
        const mins = Math.floor((now - account.lastSync * 1000) / 60000);
        if (mins < 1)
            return "Synced just now";
        if (mins < 60)
            return `Synced ${mins} min ago`;
        return mins < 1440 ? `Synced ${Math.floor(mins / 60)} h ago` : `Synced ${new Date(account.lastSync * 1000).toLocaleDateString()}`;
    }

    Timer {
        interval: 30000
        running: root.visible && root.account.signedIn
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // The Plugins page changes these while Settings stays loaded underneath.
    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind === "plugins")
                root.sources = Api.get("sources");
            if (kind === "sync") {
                root.account = data;
                root.now = Date.now();
                if (data.settings)
                    root.s = Api.get("settings");
            }
        }

        function onSettingChanged(key: string, value: string): void {
            root.s = Api.get("settings");
        }
    }

    component Section: StyledRect {
        id: sec

        default property alias content: inner.data
        property string title
        property string icon

        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + Theme.padding.extraLarge * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainer

        ColumnLayout {
            id: inner

            anchors.fill: parent
            anchors.margins: Theme.padding.extraLarge
            spacing: Theme.spacing.large

            RowLayout {
                spacing: Theme.spacing.medium

                MaterialIcon {
                    text: sec.icon
                    fill: 1
                    color: Theme.palette.primary
                }
                StyledText {
                    text: sec.title
                    font: Theme.font.title.large
                }
            }
        }
    }

    component Row: RowLayout {
        id: rowRoot

        property string label
        property string hint

        Layout.fillWidth: true
        spacing: Theme.spacing.large

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: rowRoot.label
                font: Theme.font.body.large
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: rowRoot.hint
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.body.small
                wrapMode: Text.Wrap
            }
        }
    }

    FolderDialog {
        id: folderPicker

        onAccepted: root.set("downloadDir", Api.get("localPath", {
                url: selectedFolder.toString()
            }))
    }

    StyledDialog {
        id: accountDialog

        property bool create
        property bool busy
        property string error

        function show(create: bool): void {
            accountDialog.create = create;
            error = "";
            userField.text = "";
            passField.text = "";
            open();
        }

        function submit(): void {
            if (busy || !userField.text.trim() || !passField.text)
                return;
            busy = true;
            error = "";
            Api.call("syncSignIn", {
                username: userField.text.trim(),
                password: passField.text,
                create: create
            }, st => {
                busy = false;
                root.account = st;
                close();
                ApplicationWindow.window.toast(create ? "Account created" : "Signed in");
            }, e => {
                busy = false;
                error = String(e);
            });
        }

        icon: "sync"
        title: create ? "Create account" : "Sign in"
        onOpened: userField.forceActiveFocus()

        StyledTextField {
            id: userField

            Layout.fillWidth: true
            placeholderText: "Username"
            onAccepted: passField.forceActiveFocus()
        }
        StyledTextField {
            id: passField

            Layout.fillWidth: true
            placeholderText: "Password"
            echoMode: TextInput.Password
            isError: accountDialog.error !== ""
            errorText: accountDialog.error
            onAccepted: accountDialog.submit()
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: accountDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: accountDialog.busy ? "Please wait…" : accountDialog.create ? "Create" : "Sign in"
                disabled: accountDialog.busy || !userField.text.trim() || !passField.text
                onClicked: accountDialog.submit()
            }
        ]
    }

    StyledDialog {
        id: serverDialog

        property string error

        function show(): void {
            error = "";
            serverUrlField.text = root.account.server;
            open();
        }

        function submit(): void {
            Api.call("syncSetServer", {
                server: serverUrlField.text
            }, st => {
                root.account = st;
                close();
            }, e => error = String(e));
        }

        icon: "dns"
        title: "Server"
        onOpened: serverUrlField.forceActiveFocus()

        StyledTextField {
            id: serverUrlField

            Layout.fillWidth: true
            placeholderText: "Custom server"
            supportingText: serverUrlField.text.trim().startsWith("http://") ? "Unencrypted connection" : ""
            isError: serverDialog.error !== ""
            errorText: serverDialog.error
            onAccepted: serverDialog.submit()
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: serverDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Save"
                onClicked: serverDialog.submit()
            }
        ]
    }

    StyledDialog {
        id: passwordDialog

        property bool busy
        property string error

        function show(): void {
            error = "";
            currentField.text = "";
            newField.text = "";
            open();
        }

        function submit(): void {
            if (busy || !currentField.text || !newField.text)
                return;
            busy = true;
            error = "";
            Api.call("syncChangePassword", {
                current: currentField.text,
                password: newField.text
            }, () => {
                busy = false;
                close();
                ApplicationWindow.window.toast("Password changed");
            }, e => {
                busy = false;
                error = String(e);
            });
        }

        icon: "password"
        title: "Change password"
        text: "Other devices will be signed out."
        onOpened: currentField.forceActiveFocus()

        StyledTextField {
            id: currentField

            Layout.fillWidth: true
            placeholderText: "Current password"
            echoMode: TextInput.Password
            onAccepted: newField.forceActiveFocus()
        }
        StyledTextField {
            id: newField

            Layout.fillWidth: true
            placeholderText: "New password"
            echoMode: TextInput.Password
            isError: passwordDialog.error !== ""
            errorText: passwordDialog.error
            onAccepted: passwordDialog.submit()
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: passwordDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: passwordDialog.busy ? "Please wait…" : "Change"
                disabled: passwordDialog.busy || !currentField.text || !newField.text
                onClicked: passwordDialog.submit()
            }
        ]
    }

    StyledDialog {
        id: signOutDialog

        icon: "logout"
        title: "Sign out?"
        text: "Your history stays on this device."
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: signOutDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "Sign out"
                onClicked: {
                    signOutDialog.close();
                    Api.call("syncSignOut", {}, st => root.account = st);
                }
            }
        ]
    }

    StyledDialog {
        id: deleteAccountDialog

        property bool busy
        property string error

        function show(): void {
            error = "";
            deletePassField.text = "";
            open();
        }

        function submit(): void {
            if (busy || !deletePassField.text)
                return;
            busy = true;
            error = "";
            Api.call("syncDeleteAccount", {
                password: deletePassField.text
            }, st => {
                busy = false;
                root.account = st;
                close();
                ApplicationWindow.window.toast("Account deleted");
            }, e => {
                busy = false;
                error = String(e);
            });
        }

        icon: "delete_forever"
        title: "Delete account?"
        text: "Your synced data will be deleted from the server."
        onOpened: deletePassField.forceActiveFocus()

        StyledTextField {
            id: deletePassField

            Layout.fillWidth: true
            placeholderText: "Password"
            echoMode: TextInput.Password
            isError: deleteAccountDialog.error !== ""
            errorText: deleteAccountDialog.error
            onAccepted: deleteAccountDialog.submit()
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "Cancel"
                onClicked: deleteAccountDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: deleteAccountDialog.busy ? "Please wait…" : "Delete"
                disabled: deleteAccountDialog.busy || !deletePassField.text
                onClicked: deleteAccountDialog.submit()
            }
        ]
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

            StyledText {
                text: "Settings"
                font: Theme.font.headline.large
            }

            Section {
                title: "Sync"
                icon: "sync"

                Row {
                    visible: !root.account.signedIn
                    label: "Not signed in"
                    hint: root.account.error

                    TextButton {
                        type: TextButton.Text
                        text: "Create account"
                        onClicked: accountDialog.show(true)
                    }
                    TextButton {
                        type: TextButton.Tonal
                        text: "Sign in"
                        onClicked: accountDialog.show(false)
                    }
                }
                Row {
                    visible: root.account.signedIn
                    label: `Signed in as ${root.account.username}`
                    hint: root.account.error || root.syncedLabel()

                    TextButton {
                        type: TextButton.Tonal
                        text: root.account.syncing ? "Syncing…" : "Sync now"
                        disabled: root.account.syncing
                        onClicked: {
                            root.account = Object.assign({}, root.account, {
                                syncing: true
                            });
                            Api.call("syncNow", {}, st => root.account = st);
                        }
                    }
                    IconButton {
                        type: IconButton.Text
                        icon: "more_vert"
                        onClicked: accountMenu.toggle()

                        StyledMenu {
                            id: accountMenu

                            x: parent.width - width
                            y: parent.height + 4
                            model: [
                                {
                                    text: "Change password",
                                    icon: "password",
                                    value: "password"
                                },
                                {
                                    text: "Sign out",
                                    icon: "logout",
                                    value: "signOut"
                                },
                                {
                                    text: "Delete account",
                                    icon: "delete_forever",
                                    value: "delete"
                                }
                            ]
                            onTriggered: item => {
                                if (item.value === "password")
                                    passwordDialog.show();
                                else if (item.value === "signOut")
                                    signOutDialog.open();
                                else
                                    deleteAccountDialog.show();
                            }
                        }
                    }
                }
                Row {
                    label: "Server"
                    hint: root.account.server ? root.host(root.account.server) : "Default"

                    TextButton {
                        type: TextButton.Text
                        text: "Change…"
                        disabled: root.account.signedIn
                        onClicked: serverDialog.show()
                    }
                }
            }

            Section {
                title: "Appearance"
                icon: "palette"

                Row {
                    label: "Theme"

                    Repeater {
                        model: [["system", "System"], ["dark", "Dark"], ["light", "Light"]]

                        Chip {
                            required property var modelData

                            text: modelData[1]
                            selected: root.s.theme === modelData[0]
                            clickable: true
                            onClicked: root.set("theme", modelData[0])
                        }
                    }
                }
            }

            Section {
                title: "Playback"
                icon: "play_circle"

                Row {
                    label: "Autoplay next episode"

                    StyledSwitch {
                        checked: root.s.autoplay === "true"
                        onToggled: root.set("autoplay", checked)
                    }
                }
                Row {
                    label: "Skip intro & outro"

                    StyledSwitch {
                        checked: root.s.autoSkip === "true"
                        onToggled: root.set("autoSkip", checked)
                    }
                }
                Row {
                    label: "Preferred quality"

                    Repeater {
                        model: ["best", "1080p", "720p", "480p"]

                        Chip {
                            required property string modelData

                            text: modelData === "best" ? "Auto" : modelData
                            selected: root.s.quality === modelData
                            clickable: true
                            onClicked: root.set("quality", modelData)
                        }
                    }
                }
                Row {
                    label: "Sharpen video (Anime4K)"

                    TextButton {
                        visible: !root.shadersInstalled
                        type: TextButton.Tonal
                        text: root.installingShaders ? "Downloading…" : "Download"
                        disabled: root.installingShaders
                        onClicked: {
                            root.installingShaders = true;
                            Api.call("installShaders", {
                                gan: false
                            }, () => {
                                root.installingShaders = false;
                                root.shadersInstalled = true;
                            }, e => {
                                root.installingShaders = false;
                                ApplicationWindow.window.toast(e);
                            });
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    Chip {
                        text: "Off"
                        selected: !root.s.anime4k || root.s.anime4k === "off"
                        clickable: true
                        onClicked: root.set("anime4k", "off")
                    }
                    Repeater {
                        model: root.modes

                        Chip {
                            required property var modelData

                            text: modelData.name
                            selected: root.s.anime4k === modelData.key
                            clickable: true
                            onClicked: root.set("anime4k", modelData.key)
                            ToolTip.visible: hov.hovered
                            ToolTip.text: modelData.description

                            HoverHandler {
                                id: hov
                            }
                        }
                    }
                }
            }

            Section {
                title: "Sources"
                icon: "public"

                Row {
                    label: "Plugins"
                    hint: {
                        const n = root.sources.length, noun = n === 1 ? "source" : "sources";
                        return n === 0 ? "None installed" : root.sourcesOn === n ? `${n} ${noun}` : `${root.sourcesOn} of ${n} ${noun} on`;
                    }

                    TextButton {
                        type: TextButton.Tonal
                        text: "Manage"
                        onClicked: ApplicationWindow.window.openPlugins()
                    }
                }
                Row {
                    label: "Check for plugin updates on startup"
                    hint: "Updates are downloaded only when you choose."

                    StyledSwitch {
                        checked: root.s.autoCheckPluginUpdates === "true"
                        onToggled: root.set("autoCheckPluginUpdates", checked)
                    }
                }
            }

            Section {
                title: "Downloads"
                icon: "download"

                Row {
                    label: "Download folder"
                    hint: Api.get("downloadDir")

                    TextButton {
                        type: TextButton.Tonal
                        text: "Change…"
                        onClicked: folderPicker.open()
                    }
                    TextButton {
                        visible: root.s.downloadDir !== ""
                        type: TextButton.Text
                        text: "Reset"
                        onClicked: root.set("downloadDir", "")
                    }
                }
                Row {
                    visible: !root.tools.ffmpeg
                    label: "ffmpeg isn't installed"
                    hint: "Some episodes save as .ts instead of .mp4."
                }
                Row {
                    label: "TMDB API key"
                    hint: "Sorts long shows into season folders."

                    StyledTextField {
                        Layout.preferredWidth: 260
                        placeholderText: "Optional"
                        text: root.s.tmdbKey
                        echoMode: TextInput.Password
                        onEditingFinished: root.set("tmdbKey", text)
                    }
                }
            }

            Section {
                title: "Other"
                icon: "tune"

                Row {
                    label: "Discord status"

                    StyledSwitch {
                        checked: root.s.discord === "true"
                        onToggled: {
                            root.set("discord", checked);
                            if (!checked)
                                Api.get("presence", {
                                    clear: true
                                });
                        }
                    }
                }
                Row {
                    label: "Debug logging"
                    hint: "Applies after a restart. Ctrl+L opens the log."

                    StyledSwitch {
                        checked: root.s.debug === "true"
                        onToggled: root.set("debug", checked)
                    }
                }
                Row {
                    label: "Cache"

                    TextButton {
                        type: TextButton.Tonal
                        text: "Clear"
                        onClicked: {
                            Api.get("clearCache");
                            ApplicationWindow.window.toast("Cache cleared");
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.large
                text: `Aikatsu ${Api.get("version")}  ·  GPL-3.0  ·  (ﾉ´ヮ\`)ﾉ*: ･ﾟ`
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.label.large
            }
        }
    }
}
