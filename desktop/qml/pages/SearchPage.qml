pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    readonly property Main app: ApplicationWindow.window as Main

    property int requestId: 0
    property string query
    property bool searching
    property var results: []
    property var status: ({}) // source key -> {name, state: loading|ok|error, count, error}
    property string filter: "" // source key or ""
    property var sources: Api.get("sources")
    property var disabled: (Api.setting("disabledSources") || "").split(",").map(x => x.trim()).filter(x => x)
    readonly property var enabledSources: sources.filter(s => !disabled.includes(s.key))
    readonly property var shown: filter ? results.filter(r => r.source === filter) : results
    readonly property var failures: Object.values(status).filter(s => s.state === "error")
    readonly property bool allFailed: !searching && failures.length > 0 && failures.length === Object.keys(status).length

    function refreshSources(): void {
        sources = Api.get("sources");
        disabled = (Api.setting("disabledSources") || "").split(",").map(x => x.trim()).filter(x => x);
    }

    function search(q: string): void {
        q = q.trim();
        if (q.length < 2)
            return;
        refreshSources();
        const request = ++requestId;
        query = q;
        results = [];
        const st = {};
        for (const s of enabledSources) {
            st[s.key] = {
                name: s.name,
                state: "loading",
                count: 0
            };
        }
        status = st;
        filter = "";
        searching = true;
        Api.call("search", {
            query: q,
            requestId: request
        }, () => {
            if (request !== root.requestId)
                return;
            root.searching = false;
            for (const k in root.status)
                if (root.status[k].state === "loading")
                    root.status[k].state = "error";
            root.status = Object.assign({}, root.status);
        }, () => {
            if (request === root.requestId)
                root.searching = false;
        });
    }

    // Dev aid: `--search <q> [--open]` searches on launch and opens the first hit.
    readonly property var devArgs: Qt.application.arguments
    Component.onCompleted: {
        const i = devArgs.indexOf("--search");
        if (i > 0) {
            root.app.tab = 1;
            search(devArgs[i + 1]);
        }
    }
    onVisibleChanged: if (visible) {
        refreshSources();
        field.forceActiveFocus();
    }
    onResultsChanged: if (results.length > 0 && devArgs.includes("--open") && !opened) {
        opened = true;
        root.app.openAnime(results[0], devArgs.includes("--play") ? -1 : 0);
    }
    property bool opened

    Connections {
        target: root.app

        function onSearchRequested(q: string): void {
            field.text = q;
            root.search(q);
        }
    }

    Connections {
        target: Api

        function onSettingChanged(key: string, value: string): void {
            if (key === "disabledSources")
                root.refreshSources();
        }

        function onPushed(kind: string, data: var): void {
            if (kind === "plugins") {
                root.refreshSources();
                return;
            }
            // Any source while searching: on first launch the plugins arrive during the search.
            if (kind !== "searchResult" || !root.searching || data.requestId !== root.requestId)
                return;
            const st = Object.assign({}, root.status);
            if (data.error)
                st[data.source] = {
                    name: data.name,
                    state: "error",
                    count: 0,
                    error: data.error
                };
            else {
                st[data.source] = {
                    name: data.name,
                    state: "ok",
                    count: data.items.length
                };
                root.results = root.results.concat(data.items);
            }
            root.status = st;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding.extraLarge
        spacing: Theme.spacing.large

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: "Search"
                font: Theme.font.headline.large
            }
            StyledText {
                text: root.enabledSources.length === 0 ? "No sources active" : `${root.enabledSources.length} source${root.enabledSources.length === 1 ? "" : "s"} active`
                color: root.enabledSources.length === 0 ? Theme.palette.error : Theme.palette.onSurfaceVariant
                font: Theme.font.label.large
            }
            IconTextButton {
                type: root.enabledSources.length === 0 ? TextButton.Tonal : TextButton.Text
                icon: "extension"
                text: "Plugins"
                onClicked: root.app.openPlugins()
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.maximumWidth: 760
            implicitHeight: 56
            radius: Theme.rounding.full
            color: field.activeFocus ? Theme.palette.surfaceContainerHighest : Theme.palette.surfaceContainerHigh
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Theme.palette.primary : Qt.alpha(Theme.palette.outlineVariant, 0.5)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padding.largeIncreased
                anchors.rightMargin: Theme.padding.small
                spacing: Theme.spacing.medium

                MaterialIcon {
                    text: "search"
                    size: 18
                    color: field.activeFocus ? Theme.palette.primary : Theme.palette.onSurfaceVariant
                }
                TextFieldBase {
                    id: field

                    Layout.fillWidth: true
                    placeholderText: "Search anime by English or Japanese title…"
                    focus: true
                    onAccepted: root.search(text)

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !field.text
                        text: field.placeholderText
                        color: Theme.palette.onSurfaceVariant
                        font: field.font
                    }
                }
                Loading {
                    visible: root.searching
                    size: 24
                }
                IconButton {
                    visible: field.text !== ""
                    type: IconButton.Text
                    icon: "close"
                    onClicked: {
                        field.text = "";
                        field.forceActiveFocus();
                    }
                }
                IconButton {
                    icon: "arrow_forward"
                    disabled: field.text.trim().length < 2
                    onClicked: root.search(field.text)
                }
            }
        }

        // per-source status, doubles as a filter
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium
            visible: Object.keys(root.status).length > 0

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                Chip {
                    text: `All  ${root.results.length}`
                    selected: root.filter === ""
                    clickable: true
                    onClicked: root.filter = ""
                }

                Repeater {
                    model: Object.keys(root.status)

                    Chip {
                        required property string modelData
                        readonly property var st: root.status[modelData]

                        text: st.state === "loading" ? `${st.name}  …` : st.state === "error" ? `${st.name}  !` : `${st.name}  ${st.count}`
                        icon: st.state === "error" ? "error" : st.state === "loading" ? "hourglass_top" : ""
                        selected: root.filter === modelData
                        clickable: st.state === "ok" && st.count > 0
                        onClicked: root.filter = root.filter === modelData ? "" : modelData
                        tint: st.state === "error" ? Theme.palette.errorContainer : Theme.palette.secondaryContainer

                        ToolTip.visible: st.error ? hov.hovered : false
                        ToolTip.text: st.error ? `${Api.describe(st.error)}\n${st.error}` : ""

                        HoverHandler {
                            id: hov
                        }
                    }
                }
            }

            StyledText {
                visible: root.shown.length > 0
                text: `${root.shown.length} result${root.shown.length === 1 ? "" : "s"}`
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.label.large
            }
        }

        GridView {
            id: grid

            readonly property int columns: Math.max(2, Math.floor(width / 176))

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shown.length > 0
            clip: true
            cellWidth: width / columns
            cellHeight: (cellWidth - Theme.spacing.large) * 1.45 + 80
            model: root.shown
            ScrollBar.vertical: StyledScrollBar {}

            add: Transition {
                Anim {
                    property: "opacity"
                    from: 0
                    to: 1
                    type: Anim.DefaultEffects
                }
                Anim {
                    property: "scale"
                    from: 0.9
                    to: 1
                    type: Anim.FastSpatial
                }
            }

            delegate: Item {
                id: cell

                required property var modelData

                width: grid.cellWidth
                height: grid.cellHeight

                PosterCard {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.large / 2
                    title: cell.modelData.name
                    image: cell.modelData.image
                    badge: root.status[cell.modelData.source]?.name ?? cell.modelData.source
                    onClicked: root.app.openAnime(cell.modelData, 0)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shown.length === 0

            EmptyState {
                anchors.centerIn: parent
                visible: !root.searching
                face: root.enabledSources.length === 0 ? "(・・ )?" : root.allFailed ? "(×﹏×)" : root.query ? "(╥﹏╥)" : "(◕‿◕✿)"
                tint: root.allFailed ? Theme.palette.error : Theme.palette.primary
                title: root.enabledSources.length === 0 ? "No sources enabled" : root.allFailed ? "Couldn't reach any source" : root.query ? `Nothing found for “${root.query}”` : "What do you want to watch?"
                message: root.enabledSources.length === 0 ? "Add or enable a plugin source to search for anime." : root.allFailed ? Api.describe(root.failures[0].error) : root.query ? "Try another spelling or the Japanese title." : "Search across your active sources at once."

                IconTextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    visible: root.enabledSources.length === 0
                    type: TextButton.Tonal
                    icon: "extension"
                    text: "Open plugins"
                    onClicked: root.app.openPlugins()
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    visible: root.allFailed
                    type: TextButton.Tonal
                    icon: "refresh"
                    text: "Try again"
                    onClicked: root.search(root.query)
                }
            }
            Loading {
                anchors.centerIn: parent
                visible: root.searching
                size: 56
            }
        }
    }
}
