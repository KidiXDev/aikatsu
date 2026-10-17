pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

ApplicationWindow {
    id: win

    property int tab: 0
    readonly property bool playing: playerLoader.active
    property int windowedVisibility: Window.Windowed

    onVisibilityChanged: {
        if (visibility === Window.Windowed || visibility === Window.Maximized)
            windowedVisibility = visibility;
    }

    // Bumped whenever watch history changes so pages can refresh.
    property int historyRevision: 0

    function openAnime(anime: var, autoplayEpisode: int): void {
        if (stack.currentItem?.anime?.url === anime.url)
            return; // double-click on a card
        stack.push(animePage, {
            anime: anime,
            autoplayEpisode: autoplayEpisode ?? 0
        });
    }

    function openPlugins(): void {
        if (stack.currentItem?.objectName !== "pluginsPage")
            stack.push(pluginsPage);
    }

    function goTab(i: int): void {
        if (stack.depth > 1)
            stack.pop(null);
        tab = i;
    }

    signal searchRequested(string query)

    // Search tab, running `query` (Home's discover cards).
    function searchFor(query: string): void {
        goTab(1);
        searchRequested(query);
    }

    // page: the AnimePage (anime, meta, episodes, progress keys); index: episode to start
    function play(page: var, index: int): void {
        playerLoader.page = page;
        playerLoader.index = index;
        playerLoader.active = true;
    }

    function closePlayer(): void {
        if (visibility === Window.FullScreen)
            toggleFullScreen();
        playerLoader.active = false;
        historyRevision++;
        Api.call("syncNow", {});
    }

    function toggleFullScreen(): void {
        visibility = visibility === Window.FullScreen ? windowedVisibility : Window.FullScreen;
    }

    function openLog(): void {
        logs.open();
    }

    function toast(message: string): void {
        snackbar.show(message);
    }

    // release: checkAppUpdate's result.
    function offerAppUpdate(release: var): void {
        appUpdateDialog.release = release;
        appUpdateDialog.open();
    }

    function checkPluginUpdates(): void {
        if (Api.setting("autoCheckPluginUpdates") !== "true")
            return;
        Api.call("checkPluginUpdates", {}, repos => {
            const count = repos.reduce((n, r) => n + (r.updates || 0), 0);
            if (count > 0) {
                pluginUpdatesDialog.count = count;
                pluginUpdatesDialog.open();
            }
        });
    }

    width: 1360
    height: 840
    minimumWidth: 960
    minimumHeight: 600
    visible: false // shown after the saved window state is restored
    title: "Aikatsu"
    color: Theme.palette.surface

    Component.onCompleted: {
        Theme.mode = Api.setting("theme");
        // One dialog at a time: plugin updates can wait for the new version.
        if (Api.setting("autoCheckAppUpdates") === "true")
            Api.call("checkAppUpdate", {}, r => r.newer ? offerAppUpdate(r) : checkPluginUpdates(), () => checkPluginUpdates());
        else
            checkPluginUpdates();
    }

    StyledDialog {
        id: appUpdateDialog
        objectName: "appUpdateDialog"

        property var release: ({})
        property real progress: -1 // 0..1 while downloading
        readonly property bool busy: progress >= 0

        icon: "system_update"
        title: `Aikatsu ${release.version} is available`
        text: busy ? `Downloading… ${Math.round(progress * 100)}%` : `You have ${release.current}. ` + (release.installable ? "Aikatsu closes to install it, then opens again." : "Download it from the release page.")
        closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside

        LinearProgress {
            Layout.fillWidth: true
            visible: appUpdateDialog.busy
            value: appUpdateDialog.progress
        }

        actions: [
            TextButton {
                type: TextButton.Text
                text: "What's new"
                onClicked: Qt.openUrlExternally(appUpdateDialog.release.page)
            },
            TextButton {
                type: TextButton.Text
                text: "Later"
                disabled: appUpdateDialog.busy
                onClicked: appUpdateDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: appUpdateDialog.release.installable ? "Update" : "Download"
                disabled: appUpdateDialog.busy
                onClicked: {
                    if (!appUpdateDialog.release.installable) {
                        Qt.openUrlExternally(appUpdateDialog.release.page);
                        appUpdateDialog.close();
                        return;
                    }
                    appUpdateDialog.progress = 0;
                    Api.call("installAppUpdate", {}, r => {
                        if (r.quit)
                            Qt.quit();
                    }, e => {
                        appUpdateDialog.progress = -1;
                        win.toast(`Couldn't update: ${e}`);
                    });
                }
            }
        ]
    }

    StyledDialog {
        id: pluginUpdatesDialog
        objectName: "pluginUpdatesDialog"

        property int count: 0
        icon: "download"
        title: `${count} plugin update${count === 1 ? "" : "s"} available`
        text: "Open Plugins to review and download updates."
        actions: [
            TextButton {
                type: TextButton.Text
                text: "Later"
                onClicked: pluginUpdatesDialog.close()
            },
            TextButton {
                type: TextButton.Text
                text: "View updates"
                onClicked: {
                    pluginUpdatesDialog.close();
                    win.openPlugins();
                }
            }
        ]
    }

    // Dev aid: `aikatsu --screenshot out.png [--tab N | --plugins]` renders, saves, quits.
    Timer {
        readonly property var args: Qt.application.arguments
        readonly property int at: args.indexOf("--screenshot")

        running: at > 0
        interval: args.indexOf("--delay") > 0 ? parseInt(args[args.indexOf("--delay") + 1]) : 5000
        Component.onCompleted: {
            const t = args.indexOf("--tab");
            if (t > 0)
                win.tab = parseInt(args[t + 1]);
            if (args.includes("--plugins"))
                win.openPlugins();
        }
        onTriggered: (win.playing ? playerLoader.item : shell).grabToImage(r => {
            r.saveToFile(args[at + 1]);
            Qt.quit();
        })
    }

    FontLoader {
        source: "qrc:/fonts/GoogleSansFlex.ttf"
    }
    FontLoader {
        source: "qrc:/fonts/MaterialSymbolsRounded.ttf"
    }

    Connections {
        target: Api

        function onSettingChanged(key: string, value: string): void {
            if (key === "theme")
                Theme.mode = value;
        }

        function onPushed(kind: string, data: var): void {
            if (kind === "sync" && data.history)
                win.historyRevision++;
            else if (kind === "appUpdate")
                appUpdateDialog.progress = data.done / Math.max(1, data.total);
        }
    }

    Rectangle {
        id: shell

        anchors.fill: parent
        color: Theme.palette.surface
        visible: !win.playing

        RowLayout {
            anchors.fill: parent
            spacing: 0

            NavRail {
                Layout.fillHeight: true
                current: stack.depth > 1 ? -1 : win.tab
                onSelected: i => win.goTab(i)
            }

            StackView {
                id: stack

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                initialItem: tabs

                pushEnter: Transition {
                    Anim {
                        property: "x"
                        from: 80
                        to: 0
                        type: Anim.DefaultSpatial
                    }
                    Anim {
                        property: "opacity"
                        from: 0
                        to: 1
                        type: Anim.DefaultEffects
                    }
                }
                pushExit: Transition {
                    Anim {
                        property: "opacity"
                        to: 0
                        type: Anim.FastEffects
                    }
                }
                popEnter: Transition {
                    Anim {
                        property: "opacity"
                        from: 0
                        to: 1
                        type: Anim.DefaultEffects
                    }
                }
                popExit: Transition {
                    Anim {
                        property: "x"
                        to: 80
                        type: Anim.FastSpatial
                    }
                    Anim {
                        property: "opacity"
                        to: 0
                        type: Anim.FastEffects
                    }
                }
            }
        }
    }

    Component {
        id: tabs

        StackLayout {
            currentIndex: win.tab

            HomePage {}
            SearchPage {}
            DownloadsPage {}
            SettingsPage {}
        }
    }

    Component {
        id: animePage

        AnimePage {}
    }

    Component {
        id: pluginsPage

        PluginsPage {}
    }

    Loader {
        id: playerLoader

        property var page
        property int index

        anchors.fill: parent
        active: false
        focus: active
        sourceComponent: PlayerPage {
            page: playerLoader.page
            index: playerLoader.index
        }
    }

    LogDrawer {
        id: logs
    }

    Shortcut {
        sequence: "Ctrl+L"
        onActivated: logs.visible ? logs.close() : logs.open()
    }

    Snackbar {
        id: snackbar
    }
}
