pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

ApplicationWindow {
    id: win

    property int tab: 0
    readonly property bool playing: playerLoader.active

    // Bumped whenever watch history changes so pages can refresh.
    property int historyRevision: 0

    function openAnime(anime: var, autoplayEpisode: int): void {
        stack.push(animePage, {
            anime: anime,
            autoplayEpisode: autoplayEpisode ?? 0
        });
    }

    function goTab(i: int): void {
        if (stack.depth > 1)
            stack.pop(null);
        tab = i;
    }

    // ctx: {anime, meta, episodes, index, episodeInfo}
    function play(ctx: var): void {
        playerLoader.ctx = ctx;
        playerLoader.active = true;
    }

    function closePlayer(): void {
        if (visibility === Window.FullScreen)
            showNormal();
        playerLoader.active = false;
        historyRevision++;
    }

    function toggleFullScreen(): void {
        visibility = visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
    }

    function toast(message: string): void {
        snackbar.show(message);
    }

    width: 1360
    height: 840
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    title: "Aikatsu"
    color: Theme.palette.surface

    Component.onCompleted: Theme.mode = Api.setting("theme")

    // Dev aid: `aikatsu --screenshot out.png [--tab N]` renders, saves, quits.
    Timer {
        readonly property var args: Qt.application.arguments
        readonly property int at: args.indexOf("--screenshot")

        running: at > 0
        interval: args.indexOf("--delay") > 0 ? parseInt(args[args.indexOf("--delay") + 1]) : 5000
        Component.onCompleted: {
            const t = args.indexOf("--tab");
            if (t > 0)
                win.tab = parseInt(args[t + 1]);
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

    Loader {
        id: playerLoader

        property var ctx

        anchors.fill: parent
        active: false
        focus: active
        sourceComponent: PlayerPage {
            ctx: playerLoader.ctx
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
