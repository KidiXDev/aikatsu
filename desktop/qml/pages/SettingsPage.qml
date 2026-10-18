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
    property bool checkingPlugins
    property bool checkingApp
    property var account: Api.get("syncStatus")
    property real now: Date.now()
    property var tools: Api.get("tools")
    property var library: listOf(Api.get("library"))
    property real cacheBytes: Api.get("cacheSize")
    readonly property int sourcesOn: sources.filter(x => !disabled.includes(x.key)).length
    readonly property real downloadedBytes: library.reduce((n, x) => n + x.size, 0)
    readonly property int downloadedEpisodes: library.reduce((n, x) => n + x.episodes.length, 0)
    readonly property string version: Api.get("version")

    // Dev aid: `--room N` opens that room for screenshots.
    property int room: Qt.application.arguments.includes("--room") ? parseInt(Qt.application.arguments[Qt.application.arguments.indexOf("--room") + 1]) : 0
    readonly property var rooms: [
        {
            icon: "tune",
            title: "General",
            status: `${({ system: "System", dark: "Dark", light: "Light" })[s.theme] ?? "System"} theme`
        },
        {
            icon: "play_circle",
            title: "Watch",
            status: (s.quality === "best" ? "Auto quality" : s.quality) + (!s.anime4k || s.anime4k === "off" ? "" : ` · ${modes.find(m => m.key === s.anime4k)?.name ?? s.anime4k}`)
        },
        {
            icon: "video_library",
            title: "Library",
            status: downloadedEpisodes ? `${Theme.formatBytes(downloadedBytes)} · ${downloadedEpisodes} episode${downloadedEpisodes === 1 ? "" : "s"}` : "No downloads yet"
        },
        {
            icon: "extension",
            title: "Sources",
            status: sources.length === 0 ? "None installed" : sourcesOn === sources.length ? `${sources.length} on` : `${sourcesOn} of ${sources.length} on`,
            error: sourcesOn === 0
        },
        {
            icon: "account_circle",
            title: "Account",
            status: account.signedIn ? account.error || syncedLabel() : "Not signed in",
            error: !!account.error
        }
    ]
    readonly property var shortcuts: [
        { what: "Play or pause", keys: ["Space", "/", "K"] },
        { what: "Seek 5 seconds", keys: ["@arrow_back", "@arrow_forward", "/", "J", "L"] },
        { what: "Seek 85 seconds", keys: ["Shift", "+", "@arrow_back", "@arrow_forward"] },
        { what: "Volume", keys: ["@arrow_upward", "@arrow_downward"] },
        { what: "Mute", keys: ["M"] },
        { what: "Fullscreen", keys: ["F", "/", "Double-click"] },
        { what: "Next or previous episode", keys: ["N", "/", "P"] },
        { what: "Skip intro or outro", keys: ["S"] },
        ...(s.developerMode === "true" ? [{ what: "Show or toggle playback information", keys: ["I", "/", "Shift+I"] }] : []),
        { what: "Leave fullscreen, then close", keys: ["Esc"] }
    ]

    function listOf(v: var): var {
        return Array.isArray(v) ? v : [];
    }

    function set(key: string, value: var): void {
        Api.setSetting(key, value);
        s = Api.get("settings");
    }

    function refresh(): void {
        library = listOf(Api.get("library"));
        cacheBytes = Api.get("cacheSize");
        tools = Api.get("tools");
    }

    function toggleSource(key: string): void {
        const off = disabled.includes(key) ? disabled.filter(k => k !== key) : disabled.concat([key]);
        set("disabledSources", off.join(","));
    }

    function checkPlugins(): void {
        checkingPlugins = true;
        Api.call("checkPluginUpdates", {}, repos => {
            checkingPlugins = false;
            const count = repos.reduce((n, r) => n + (r.updates || 0), 0);
            ApplicationWindow.window.toast(repos.some(r => r.error) ? "Some repos couldn't be checked" : count > 0 ? `${count} plugin update${count === 1 ? "" : "s"} available` : "Plugins are up to date");
        }, e => {
            checkingPlugins = false;
            ApplicationWindow.window.toast(e);
        });
    }

    function checkApp(): void {
        checkingApp = true;
        Api.call("checkAppUpdate", {}, r => {
            checkingApp = false;
            if (r.newer)
                ApplicationWindow.window.offerAppUpdate(r);
            else
                ApplicationWindow.window.toast(`Aikatsu ${r.current} is up to date`);
        }, e => {
            checkingApp = false;
            ApplicationWindow.window.toast(e);
        });
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

    onVisibleChanged: if (visible)
        refresh()

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
            if (kind === "download" && data.state === "done")
                root.library = root.listOf(Api.get("library"));
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

    // One room of settings; scrolls on its own and keeps its place.
    component Room: StyledFlickable {
        id: roomRoot

        default property alias content: body.data
        property int index

        contentHeight: body.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: body

            x: Theme.padding.extraLarge
            y: Theme.padding.extraLarge
            width: Math.min(760, roomRoot.width - Theme.padding.extraLarge * 2)
            spacing: Theme.spacing.extraLarge

            RowLayout {
                spacing: Theme.spacing.large

                StyledRect {
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: Theme.rounding.large
                    color: Theme.palette.secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.rooms[roomRoot.index].icon
                        fill: 1
                        size: 20
                        color: Theme.palette.onSecondaryContainer
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.rooms[roomRoot.index].title
                    font: Theme.font.headline.medium
                }
            }
        }
    }

    // The room's lead: what is true right now, tinted apart from the settings below it.
    component Band: StyledRect {
        default property alias content: bandRow.data

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

    component Group: ColumnLayout {
        id: grp

        default property alias rows: list.data
        property string title

        Layout.fillWidth: true
        spacing: Theme.spacing.small

        StyledText {
            visible: grp.title !== ""
            Layout.leftMargin: Theme.padding.small
            text: grp.title
            font: Theme.font.title.medium
            color: Theme.palette.onSurfaceVariant
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: list.implicitHeight
            radius: Theme.rounding.largeIncreased
            color: Theme.palette.surfaceContainer

            ColumnLayout {
                id: list

                width: parent.width
                spacing: 0
            }
        }
    }

    // Label, a line of detail, then one control on the right.
    component SettingRow: Item {
        id: row

        default property alias trailing: trail.data
        property string label
        property string hint
        property color hintColor: Theme.palette.onSurfaceVariant
        property string icon
        property color iconColor: Theme.palette.onSurfaceVariant

        Layout.fillWidth: true
        implicitHeight: Math.max(60, line.implicitHeight + Theme.padding.large * 2)

        Rectangle {
            visible: row.y > 0
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
            id: line

            anchors.fill: parent
            anchors.leftMargin: Theme.padding.largeIncreased
            anchors.rightMargin: Theme.padding.large
            spacing: Theme.spacing.large

            MaterialIcon {
                visible: row.icon !== ""
                text: row.icon
                fill: 1
                size: 16
                color: row.iconColor
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: row.label
                    font: Theme.font.body.large
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: row.hint
                    color: row.hintColor
                    font: Theme.font.body.small
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                id: trail

                spacing: Theme.spacing.small
            }
        }
    }

    // A few fixed choices; the highlight slides to the picked one.
    component Segmented: StyledRect {
        id: seg

        property var options: [] // [value, label]
        property string value
        readonly property int current: options.findIndex(o => o[0] === value)
        readonly property real segWidth: 72

        signal picked(string value)

        implicitWidth: options.length * segWidth + 8
        implicitHeight: 36
        radius: Theme.rounding.full
        color: Theme.palette.surfaceContainerHighest
        border.width: activeFocus ? 2 : 0
        border.color: Theme.palette.primary
        activeFocusOnTab: true
        Keys.onLeftPressed: if (current > 0)
            picked(options[current - 1][0])
        Keys.onRightPressed: if (current < options.length - 1)
            picked(options[current + 1][0])

        StyledRect {
            visible: seg.current >= 0
            x: 4 + seg.current * seg.segWidth
            y: 4
            width: seg.segWidth
            height: seg.height - 8
            radius: Theme.rounding.full
            color: Theme.palette.secondaryContainer

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }

        Row {
            x: 4
            y: 4

            Repeater {
                model: seg.options

                Item {
                    id: option

                    required property var modelData
                    readonly property bool active: seg.value === modelData[0]

                    width: seg.segWidth
                    height: seg.height - 8
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData[1]
                    Accessible.checked: active

                    StyledText {
                        anchors.centerIn: parent
                        text: option.modelData[1]
                        font: Theme.font.label.large
                        color: option.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                    }
                    StateLayer {
                        radius: Theme.rounding.full
                        color: Theme.palette.onSurface
                        onClicked: seg.picked(option.modelData[0])
                    }
                }
            }
        }
    }

    component ModeTile: StyledRect {
        id: tile

        property string name
        property string description
        property bool selected

        signal picked

        Layout.fillWidth: true
        Layout.preferredHeight: 84
        radius: Theme.rounding.large
        color: selected ? Theme.palette.secondaryContainer : Theme.palette.surfaceContainer
        border.width: activeFocus ? 2 : 0
        border.color: Theme.palette.primary
        activeFocusOnTab: true
        Keys.onSpacePressed: picked()
        Keys.onReturnPressed: picked()
        Accessible.role: Accessible.RadioButton
        Accessible.name: name
        Accessible.checked: selected

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padding.medium + 2
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: tile.name
                    font: Theme.font.title.medium
                    color: tile.selected ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
                    elide: Text.ElideRight
                }
                MaterialIcon {
                    visible: tile.selected
                    text: "check_circle"
                    fill: 1
                    size: 14
                    color: Theme.palette.onSecondaryContainer
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: tile.description
                font: Theme.font.body.small
                color: tile.selected ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.85) : Theme.palette.onSurfaceVariant
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Item {
                Layout.fillHeight: true
            }
        }
        StateLayer {
            radius: tile.radius
            color: tile.selected ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
            onClicked: tile.picked()
        }
    }

    component KeyCap: StyledRect {
        id: cap

        property string key

        implicitWidth: key.startsWith("@") ? 28 : capText.implicitWidth + 16
        implicitHeight: 26
        radius: Theme.rounding.small
        color: Theme.palette.surfaceContainerHighest
        border.width: 1
        border.color: Theme.palette.outlineVariant

        StyledText {
            id: capText

            anchors.centerIn: parent
            visible: !cap.key.startsWith("@")
            text: cap.key
            font: Theme.font.label.large
            color: Theme.palette.onSurfaceVariant
        }
        MaterialIcon {
            anchors.centerIn: parent
            visible: cap.key.startsWith("@")
            text: cap.key.slice(1)
            size: 12
            color: Theme.palette.onSurfaceVariant
        }
    }

    component IconTile: StyledRect {
        id: iconTile

        property string icon
        property color tint: Theme.palette.surfaceContainerHighest
        property color onTint: Theme.palette.onSurfaceVariant

        implicitWidth: 44
        implicitHeight: 44
        radius: Theme.rounding.medium
        color: tint

        MaterialIcon {
            anchors.centerIn: parent
            text: iconTile.icon
            fill: 1
            size: 18
            color: iconTile.onTint
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
        readonly property bool ready: !busy && userField.text.trim() !== "" && passField.text !== "" && (!create || confirmField.text === passField.text)

        function show(create: bool): void {
            accountDialog.create = create;
            error = "";
            for (const f of [userField, passField, confirmField]) {
                f.text = "";
                f.isError = false;
            }
            open();
        }

        function submit(): void {
            if (!ready)
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
                passField.isError = true;
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
        PasswordField {
            id: passField

            Layout.fillWidth: true
            placeholderText: "Password"
            errorText: accountDialog.error
            onAccepted: accountDialog.create ? confirmField.forceActiveFocus() : accountDialog.submit()
        }
        PasswordField {
            id: confirmField

            Layout.fillWidth: true
            visible: accountDialog.create
            placeholderText: "Confirm password"
            matches: passField
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
                disabled: !accountDialog.ready
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
            serverUrlField.isError = false;
            open();
        }

        function submit(): void {
            Api.call("syncSetServer", {
                server: serverUrlField.text
            }, st => {
                root.account = st;
                close();
            }, e => {
                error = String(e);
                serverUrlField.isError = true;
            });
        }

        icon: "dns"
        title: "Server"
        onOpened: serverUrlField.forceActiveFocus()

        StyledTextField {
            id: serverUrlField

            Layout.fillWidth: true
            placeholderText: "Custom server"
            supportingText: serverUrlField.text.trim().startsWith("http://") ? "Unencrypted connection" : ""
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
        readonly property bool ready: !busy && currentField.text !== "" && newField.text !== "" && confirmNewField.text === newField.text

        function show(): void {
            error = "";
            for (const f of [currentField, newField, confirmNewField]) {
                f.text = "";
                f.isError = false;
            }
            open();
        }

        function submit(): void {
            if (!ready)
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
                newField.isError = true;
            });
        }

        icon: "password"
        title: "Change password"
        text: "Other devices will be signed out."
        onOpened: currentField.forceActiveFocus()

        PasswordField {
            id: currentField

            Layout.fillWidth: true
            placeholderText: "Current password"
            onAccepted: newField.forceActiveFocus()
        }
        PasswordField {
            id: newField

            Layout.fillWidth: true
            placeholderText: "New password"
            errorText: passwordDialog.error
            onAccepted: confirmNewField.forceActiveFocus()
        }
        PasswordField {
            id: confirmNewField

            Layout.fillWidth: true
            placeholderText: "Confirm new password"
            matches: newField
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
                disabled: !passwordDialog.ready
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
            deletePassField.isError = false;
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
                deletePassField.isError = true;
            });
        }

        icon: "delete_forever"
        title: "Delete account?"
        text: "Your synced data will be deleted from the server."
        onOpened: deletePassField.forceActiveFocus()

        PasswordField {
            id: deletePassField

            Layout.fillWidth: true
            placeholderText: "Password"
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        StyledRect {
            Layout.fillHeight: true
            implicitWidth: 280
            color: Theme.palette.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padding.large
                anchors.topMargin: Theme.padding.extraLarge
                spacing: 0

                StyledText {
                    Layout.leftMargin: Theme.padding.small
                    Layout.bottomMargin: Theme.spacing.extraLarge
                    text: "Settings"
                    font: Theme.font.headline.large
                }

                Item {
                    id: roomNav

                    Layout.fillWidth: true
                    implicitHeight: roomList.implicitHeight
                    activeFocusOnTab: true
                    Accessible.role: Accessible.PageTabList
                    Keys.onUpPressed: root.room = Math.max(0, root.room - 1)
                    Keys.onDownPressed: root.room = Math.min(root.rooms.length - 1, root.room + 1)

                    StyledRect {
                        width: parent.width
                        height: 60
                        y: root.room * (60 + Theme.spacing.extraSmall)
                        radius: Theme.rounding.large
                        color: Theme.palette.secondaryContainer
                        border.width: roomNav.activeFocus ? 2 : 0
                        border.color: Theme.palette.primary

                        Behavior on y {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    ColumnLayout {
                        id: roomList

                        width: parent.width
                        spacing: Theme.spacing.extraSmall

                        Repeater {
                            model: root.rooms

                            Item {
                                id: tab

                                required property var modelData
                                required property int index
                                readonly property bool active: root.room === index

                                Layout.fillWidth: true
                                implicitHeight: 60
                                Accessible.role: Accessible.PageTab
                                Accessible.name: modelData.title
                                Accessible.description: modelData.status

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.padding.medium
                                    anchors.rightMargin: Theme.padding.medium
                                    spacing: Theme.spacing.medium

                                    StyledRect {
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        radius: Theme.rounding.medium
                                        color: tab.active ? Theme.palette.primary : Theme.palette.surfaceContainerHighest

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: tab.modelData.icon
                                            fill: tab.active ? 1 : 0
                                            size: 16
                                            color: tab.active ? Theme.palette.onPrimary : Theme.palette.onSurfaceVariant

                                            Behavior on fill {
                                                Anim {
                                                    type: Anim.DefaultEffects
                                                }
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tab.modelData.title
                                            font: Theme.font.title.medium
                                            color: tab.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: tab.modelData.status
                                            font: Theme.font.body.small
                                            color: tab.active ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.8) : tab.modelData.error ? Theme.palette.error : Theme.palette.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                StateLayer {
                                    radius: Theme.rounding.large
                                    color: Theme.palette.onSurface
                                    onClicked: root.room = tab.index
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.room

            Room {
                index: 0

                Band {
                    Item {
                        implicitWidth: 44
                        implicitHeight: 44

                        Image {
                            anchors.fill: parent
                            source: "qrc:/icon.svg"
                            sourceSize: Qt.size(88, 88)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: `Aikatsu ${root.version}`
                            font: Theme.font.title.medium
                        }
                        StyledText {
                            text: "GPL-3.0  ·  (ﾉ´ヮ`)ﾉ*: ･ﾟ"
                            color: Theme.palette.onSurfaceVariant
                            font: Theme.font.body.medium
                        }
                    }
                    IconTextButton {
                        type: TextButton.Tonal
                        icon: "update"
                        text: root.checkingApp ? "Checking…" : "Check for updates"
                        disabled: root.checkingApp
                        onClicked: root.checkApp()
                    }
                    IconTextButton {
                        type: TextButton.Tonal
                        icon: "open_in_new"
                        text: "GitHub"
                        onClicked: Qt.openUrlExternally("https://github.com/KidiXDev/aikatsu")
                    }
                }

                Group {
                    title: "Updates"

                    SettingRow {
                        label: "Check for Aikatsu updates on startup"
                        hint: "Asks before downloading anything."

                        StyledSwitch {
                            checked: root.s.autoCheckAppUpdates === "true"
                            onToggled: root.set("autoCheckAppUpdates", checked)
                        }
                    }
                }

                Group {
                    title: "Appearance"

                    SettingRow {
                        label: "Theme"

                        Segmented {
                            options: [["system", "System"], ["dark", "Dark"], ["light", "Light"]]
                            value: root.s.theme
                            onPicked: v => root.set("theme", v)
                        }
                    }
                }

                Group {
                    title: "Integrations"

                    SettingRow {
                        label: "Discord status"
                        hint: "Shows what you're watching on your profile."

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
                }

                Group {
                    title: "Storage and logs"

                    SettingRow {
                        label: "Cached lookups"
                        hint: root.cacheBytes > 0 ? Theme.formatBytes(root.cacheBytes) : "Empty"

                        TextButton {
                            type: TextButton.Tonal
                            text: "Clear"
                            disabled: root.cacheBytes <= 0
                            onClicked: {
                                Api.get("clearCache");
                                root.cacheBytes = Api.get("cacheSize");
                                ApplicationWindow.window.toast("Cache cleared");
                            }
                        }
                    }
                    SettingRow {
                        label: "Developer Mode"
                        hint: "Enables advance feature"

                        StyledSwitch {
                            checked: root.s.developerMode === "true"
                            onToggled: root.set("developerMode", checked)
                        }
                    }
                    SettingRow {
                        label: "Debug logging"
                        hint: "Applies after a restart."

                        StyledSwitch {
                            checked: root.s.debug === "true"
                            onToggled: root.set("debug", checked)
                        }
                    }
                    SettingRow {
                        label: "Log"
                        visible: root.s.developerMode === "true"
                        hint: "Also opens with Ctrl+L."

                        TextButton {
                            type: TextButton.Tonal
                            text: "View"
                            onClicked: ApplicationWindow.window.openLog()
                        }
                    }
                }
            }

            Room {
                index: 1

                Band {
                    IconTile {
                        icon: "auto_awesome"
                        tint: Theme.palette.secondaryContainer
                        onTint: Theme.palette.onSecondaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: `${root.s.quality === "best" ? "Auto quality" : root.s.quality} · ${!root.s.anime4k || root.s.anime4k === "off" ? "No sharpening" : (root.modes.find(m => m.key === root.s.anime4k)?.name ?? root.s.anime4k) + " sharpening"}`
                            font: Theme.font.title.medium
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.shadersInstalled ? "Sharpening shaders are downloaded." : "Sharpening shaders download the first time a mode is used."
                            color: Theme.palette.onSurfaceVariant
                            font: Theme.font.body.medium
                            wrapMode: Text.Wrap
                        }
                    }
                    TextButton {
                        visible: !root.shadersInstalled
                        type: TextButton.Tonal
                        text: root.installingShaders ? "Downloading…" : "Download now"
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

                Group {
                    title: "Playback"

                    SettingRow {
                        label: "Autoplay next episode"

                        StyledSwitch {
                            checked: root.s.autoplay === "true"
                            onToggled: root.set("autoplay", checked)
                        }
                    }
                    SettingRow {
                        label: "Skip intro & outro"
                        hint: "When skip times are known for the episode."

                        StyledSwitch {
                            checked: root.s.autoSkip === "true"
                            onToggled: root.set("autoSkip", checked)
                        }
                    }
                    SettingRow {
                        label: "Preferred quality"
                        hint: "The nearest one plays when a source doesn't offer it."

                        Segmented {
                            options: [["best", "Auto"], ["1080p", "1080p"], ["720p", "720p"], ["480p", "480p"]]
                            value: root.s.quality
                            onPicked: v => root.set("quality", v)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    StyledText {
                        Layout.leftMargin: Theme.padding.small
                        text: "Sharpening (Anime4K)"
                        font: Theme.font.title.medium
                        color: Theme.palette.onSurfaceVariant
                    }
                    StyledText {
                        Layout.leftMargin: Theme.padding.small
                        Layout.fillWidth: true
                        text: "Runs on the graphics card. Heavier modes need a stronger one."
                        font: Theme.font.body.small
                        color: Theme.palette.onSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.small
                        columns: 3
                        columnSpacing: Theme.spacing.small
                        rowSpacing: Theme.spacing.small

                        ModeTile {
                            Layout.columnSpan: 3
                            Layout.preferredHeight: 64
                            name: "Off"
                            description: "The video as the source sends it"
                            selected: !root.s.anime4k || root.s.anime4k === "off"
                            onPicked: root.set("anime4k", "off")
                        }
                        Repeater {
                            model: root.modes

                            ModeTile {
                                required property var modelData

                                name: modelData.name
                                description: modelData.description
                                selected: root.s.anime4k === modelData.key
                                onPicked: root.set("anime4k", modelData.key)
                            }
                        }
                    }
                }

                Group {
                    title: "Player shortcuts"

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 640 ? 2 : 1
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            model: root.shortcuts

                            SettingRow {
                                id: shortcut

                                required property var modelData

                                Layout.preferredWidth: 1
                                implicitHeight: 48
                                label: modelData.what

                                Repeater {
                                    model: shortcut.modelData.keys

                                    Loader {
                                        id: part

                                        required property string modelData

                                        sourceComponent: modelData === "/" || modelData === "+" ? joiner : cap

                                        Component {
                                            id: cap

                                            KeyCap {
                                                key: part.modelData
                                            }
                                        }
                                        Component {
                                            id: joiner

                                            StyledText {
                                                text: part.modelData === "/" ? "or" : "+"
                                                font: Theme.font.body.small
                                                color: Theme.palette.onSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Room {
                index: 2

                Band {
                    IconTile {
                        icon: "folder"
                        tint: Theme.palette.secondaryContainer
                        onTint: Theme.palette.onSecondaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.downloadedEpisodes ? `${Theme.formatBytes(root.downloadedBytes)} in ${root.downloadedEpisodes} episode${root.downloadedEpisodes === 1 ? "" : "s"}` : "No downloads yet"
                            font: Theme.font.title.medium
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Api.get("downloadDir")
                            font: Theme.font.body.medium
                            color: Theme.palette.onSurfaceVariant
                            elide: Text.ElideMiddle
                        }
                    }
                    TextButton {
                        visible: root.s.downloadDir !== ""
                        type: TextButton.Text
                        text: "Reset"
                        onClicked: root.set("downloadDir", "")
                    }
                    TextButton {
                        visible: root.downloadedEpisodes > 0
                        type: TextButton.Text
                        text: "Open"
                        onClicked: Qt.openUrlExternally(Api.get("fileUrl", {
                            path: Api.get("downloadDir")
                        }))
                    }
                    TextButton {
                        type: TextButton.Tonal
                        text: "Change…"
                        onClicked: folderPicker.open()
                    }
                }

                Group {
                    title: "Tools"

                    SettingRow {
                        icon: root.tools.ffmpeg ? "check_circle" : "error"
                        iconColor: root.tools.ffmpeg ? Theme.palette.success : Theme.palette.error
                        label: "ffmpeg"
                        hint: root.tools.ffmpeg ? "Found. Downloads are saved as .mp4." : "Not found. Some episodes save as .ts instead of .mp4."

                        TextButton {
                            visible: !root.tools.ffmpeg
                            type: TextButton.Tonal
                            text: "Get ffmpeg"
                            onClicked: Qt.openUrlExternally("https://ffmpeg.org/download.html")
                        }
                    }
                    SettingRow {
                        icon: root.tools.ytdlp || root.tools.ytdlpFetched ? "check_circle" : "schedule"
                        iconColor: root.tools.ytdlp || root.tools.ytdlpFetched ? Theme.palette.success : Theme.palette.onSurfaceVariant
                        label: "yt-dlp"
                        hint: root.tools.ytdlp ? "Found." : root.tools.ytdlpFetched ? "Downloaded by Aikatsu." : "Downloads automatically when a source needs it."
                    }
                }

                Group {
                    title: "Season folders"

                    SettingRow {
                        label: "TMDB API key"
                        hint: "Sorts long shows into season folders."

                        PasswordField {
                            Layout.preferredWidth: 240
                            placeholderText: "Optional"
                            text: root.s.tmdbKey
                            onEditingFinished: root.set("tmdbKey", text)
                        }
                    }
                }
            }

            Room {
                index: 3

                Band {
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: root.sources.length === 0 ? "No sources installed" : `${root.sourcesOn} of ${root.sources.length} source${root.sources.length === 1 ? "" : "s"} on`
                            font: Theme.font.title.medium
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small

                            Repeater {
                                model: root.sources

                                Chip {
                                    required property var modelData

                                    text: modelData.name
                                    icon: root.disabled.includes(modelData.key) ? "" : "check"
                                    selected: !root.disabled.includes(modelData.key)
                                    clickable: true
                                    onClicked: root.toggleSource(modelData.key)
                                }
                            }
                            StyledText {
                                visible: root.sources.length === 0
                                text: "Add a plugin repo to start searching."
                                color: Theme.palette.onSurfaceVariant
                                font: Theme.font.body.medium
                            }
                        }
                    }
                    TextButton {
                        Layout.alignment: Qt.AlignTop
                        type: TextButton.Tonal
                        text: "Manage"
                        onClicked: ApplicationWindow.window.openPlugins()
                    }
                }

                Group {
                    title: "Updates"

                    SettingRow {
                        label: "Check for updates on startup"
                        hint: "Updates download only when you choose."

                        StyledSwitch {
                            checked: root.s.autoCheckPluginUpdates === "true"
                            onToggled: root.set("autoCheckPluginUpdates", checked)
                        }
                    }
                    SettingRow {
                        label: "Plugin updates"

                        TextButton {
                            type: TextButton.Tonal
                            text: root.checkingPlugins ? "Checking…" : "Check now"
                            disabled: root.checkingPlugins
                            onClicked: root.checkPlugins()
                        }
                    }
                }
            }

            Room {
                index: 4

                Band {
                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Theme.rounding.full
                        color: root.account.signedIn ? Theme.palette.primary : Theme.palette.surfaceContainerHighest

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.account.signedIn
                            text: (root.account.username || "?").charAt(0).toUpperCase()
                            font: Theme.font.title.large
                            color: Theme.palette.onPrimary
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: !root.account.signedIn
                            text: "person"
                            fill: 1
                            size: 18
                            color: Theme.palette.onSurfaceVariant
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.account.signedIn ? root.account.username : "Not signed in"
                            font: Theme.font.title.medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.account.signedIn ? root.account.error || root.syncedLabel() : root.account.error || "Sync watch history and settings between devices."
                            color: root.account.error ? Theme.palette.error : Theme.palette.onSurfaceVariant
                            font: Theme.font.body.medium
                            wrapMode: Text.Wrap
                        }
                    }
                    TextButton {
                        visible: !root.account.signedIn
                        type: TextButton.Text
                        text: "Create account"
                        onClicked: accountDialog.show(true)
                    }
                    TextButton {
                        visible: !root.account.signedIn
                        type: TextButton.Tonal
                        text: "Sign in"
                        onClicked: accountDialog.show(false)
                    }
                    TextButton {
                        visible: root.account.signedIn
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
                        visible: root.account.signedIn
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

                Group {
                    title: "Server"

                    SettingRow {
                        label: "Sync server"
                        hint: root.account.server ? root.host(root.account.server) : "Default"

                        TextButton {
                            type: TextButton.Tonal
                            text: "Change…"
                            disabled: root.account.signedIn
                            onClicked: serverDialog.show()
                        }
                    }
                }
            }
        }
    }
}
