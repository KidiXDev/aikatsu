pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import Aikatsu

ApplicationWindow {
    id: win

    property int tab: 0
    property int openedTabs: 1 // bit per tab: a tab is built the first time it's opened, then kept
    readonly property bool playing: playerLoader.active
    property bool developerMode: Api.setting("developerMode") === "true"
    property int windowedVisibility: Window.Windowed
    property string closeAction: Api.setting("closeAction")
    property bool airingAlerts: Api.setting("airingAlerts") === "true"
    property var upcoming: [] // upcomingEpisodes: watching and planned shows' next airings
    property real alertedUntil: Date.now() / 1000 // airings up to here have been announced
    property string alertKey // the show the last alert was about, for its click
    readonly property bool trayAvailable: tray.available
    property var lan: Api.get("lanStatus") // library sharing, for Settings and the tray
    property var downloadJobs: ({})
    readonly property int activeDownloads: Object.values(downloadJobs).filter(j => ["queued", "resolving", "downloading", "remuxing"].includes(j.state)).length

    onTabChanged: openedTabs |= 1 << tab
    onVisibilityChanged: {
        if (win.visibility === Window.Windowed || win.visibility === Window.Maximized)
            windowedVisibility = win.visibility;
    }

    // Bumped whenever watch history changes so pages can refresh.
    property int historyRevision: 0

    onHistoryRevisionChanged: refreshUpcoming()
    onAiringAlertsChanged: refreshUpcoming()

    function refreshUpcoming(): void {
        if (!airingAlerts) {
            upcoming = [];
            return;
        }
        Api.call("upcomingEpisodes", {}, episodes => {
            notifyDue(); // the new list leaves out what aired since the last check
            upcoming = airingAlerts ? episodes : [];
        });
    }

    function notifyDue(): void {
        const now = Date.now() / 1000;
        const due = upcoming.filter(e => e.airing_at > alertedUntil && e.airing_at <= now);
        alertedUntil = now;
        if (!due.length)
            return;
        alertKey = due.length === 1 ? due[0].key : "";
        const title = due.length === 1 ? due[0].title : `${due.length} new episodes`;
        if (tray.available && tray.supportsMessages)
            tray.showMessage(title, due.length === 1 ? `Episode ${due[0].episode} is out` : due.map(e => `${e.title} · Episode ${e.episode}`).join("\n"));
        else
            toast(due.length === 1 ? `${title} · Episode ${due[0].episode} is out` : title);
    }

    function openAlert(): void {
        showWindow();
        const w = Api.get("watchlist").find(w => w.series_key === alertKey);
        if (w && !playing)
            openAnime({
                name: w.title,
                url: w.series_url,
                image: w.cover,
                source: w.source,
                anilistId: w.anilist_id
            }, 0);
    }

    // Polled rather than one long timer: Qt timers stop while the computer sleeps.
    Timer {
        interval: 60000
        repeat: true
        running: win.airingAlerts
        onTriggered: win.notifyDue()
    }

    Timer {
        interval: 6 * 3600 * 1000
        repeat: true
        running: win.airingAlerts
        onTriggered: win.refreshUpcoming()
    }

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

    function openFolders(): void {
        if (stack.currentItem?.objectName !== "foldersPage")
            stack.push(foldersPage);
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

    // From the tray, or a second launch.
    function showWindow(): void {
        if (!visible)
            visibility = windowedVisibility;
        raise();
        requestActivate();
    }

    property bool quitting: false

    // Qt.quit() first closes every window, hidden ones too, so close-to-tray would veto it.
    function quit(): void {
        quitting = true;
        Qt.quit();
    }

    onClosing: close => {
        if (quitting || closeAction !== "tray" || !tray.available)
            return;
        close.accepted = false;
        if (playing)
            playerLoader.item.pause();
        hide();
    }

    function toggleFullScreen(): void {
        visibility = visibility === Window.FullScreen ? windowedVisibility : Window.FullScreen;
    }

    function openLog(): void {
        if (developerMode)
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
        const map = {};
        for (const j of Api.get("downloads"))
            map[j.id] = j;
        downloadJobs = map;
        // One dialog at a time: plugin updates can wait for the new version.
        if (Api.setting("autoCheckAppUpdates") === "true")
            Api.call("checkAppUpdate", {}, r => r.newer ? offerAppUpdate(r) : checkPluginUpdates(), () => checkPluginUpdates());
        else
            checkPluginUpdates();
        refreshUpcoming();
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
                type: TextButton.Tonal
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
                            win.quit();
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
                type: TextButton.Tonal
                text: "View updates"
                onClicked: {
                    pluginUpdatesDialog.close();
                    win.openPlugins();
                }
            }
        ]
    }

    // Dev aid: `aikatsu --screenshot out.png [--tab N | --plugins | --folders]` renders, saves, quits.
    Timer {
        readonly property var args: Qt.application.arguments
        readonly property int at: args.indexOf("--screenshot")

        running: at > 0
        interval: args.indexOf("--delay") > 0 ? parseInt(args[args.indexOf("--delay") + 1]) : 5000
        Component.onCompleted: {
            const t = args.indexOf("--tab");
            if (t > 0)
                win.tab = parseInt(args[t + 1]);
            if (args.includes("--search"))
                win.tab = 1; // Search runs it once it's built
            if (args.includes("--plugins"))
                win.openPlugins();
            if (args.includes("--folders"))
                win.openFolders();
            if (args.includes("--anime")) {
                win.openAnime({
                    name: "Sousou no Frieren",
                    url: "local:frieren",
                    image: "",
                    source: "local",
                    anilistId: 154587
                }, 0);
                const s = args.indexOf("--section");
                if (s > 0 && stack.currentItem)
                    stack.currentItem.section = args[s + 1];
            }
        }
        onTriggered: (win.playing ? playerLoader.item : shell).grabToImage(r => {
            r.saveToFile(args[at + 1]);
            win.quit();
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
            if (key === "developerMode") {
                win.developerMode = value === "true";
                if (!win.developerMode)
                    logs.close();
            }
            if (key === "closeAction")
                win.closeAction = value;
            if (key === "airingAlerts")
                win.airingAlerts = value === "true";
            if (key === "shareLibrary")
                win.lan = Api.get("lanStatus");
        }

        function onPushed(kind: string, data: var): void {
            if (kind === "sync") {
                if (data.history)
                    win.historyRevision++;
                win.lan = Api.get("lanStatus"); // its address may have reached the account
            } else if (kind === "lan")
                win.lan = data;
            else if (kind === "download") {
                const map = Object.assign({}, win.downloadJobs);
                map[data.id] = data;
                win.downloadJobs = map;
            } else if (kind === "show")
                win.showWindow();
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
                activeDownloads: win.activeDownloads
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

            Loader {
                active: (win.openedTabs & 1) !== 0
                sourceComponent: HomePage {}
            }
            Loader {
                active: (win.openedTabs & 2) !== 0
                sourceComponent: SearchPage {}
            }
            Loader {
                active: (win.openedTabs & 4) !== 0
                sourceComponent: LibraryPage {}
            }
            Loader {
                active: (win.openedTabs & 8) !== 0
                sourceComponent: DownloadsPage {}
            }
            Loader {
                active: (win.openedTabs & 16) !== 0
                sourceComponent: SettingsPage {}
            }
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

    Component {
        id: foldersPage

        FoldersPage {}
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
        interactive: win.developerMode
    }

    Shortcut {
        sequence: "Ctrl+L"
        enabled: win.developerMode
        onActivated: logs.visible ? logs.close() : logs.open()
    }

    Snackbar {
        id: snackbar
    }

    // macOS reopens a running app from the Dock without starting a second copy, so no launch asks to show it.
    Connections {
        target: Qt.application
        enabled: Qt.platform.os === "osx"

        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && !win.visible)
                win.showWindow();
        }
    }

    Platform.SystemTrayIcon {
        id: tray

        // Also for episode alerts, which show as its messages.
        visible: win.closeAction === "tray" || win.airingAlerts
        icon.source: "qrc:/icon.svg"
        tooltip: win.lan.state === "on" ? "Aikatsu · Sharing your folders" : "Aikatsu"
        onActivated: reason => {
            if (reason !== Platform.SystemTrayIcon.Context)
                win.showWindow();
        }
        onMessageClicked: win.openAlert()
        menu: Platform.Menu {
            Platform.MenuItem {
                text: "Show Aikatsu"
                onTriggered: win.showWindow()
            }
            Platform.MenuItem {
                text: "Quit"
                onTriggered: win.quit()
            }
        }
    }
}
