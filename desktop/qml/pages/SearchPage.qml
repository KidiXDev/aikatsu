pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

Item {
    id: root

    property string query
    property bool searching
    property var results: []
    property var status: ({}) // source key -> {name, state: loading|ok|error, count, error}
    property string filter: "" // source key or ""
    readonly property var shown: filter ? results.filter(r => r.source === filter) : results
    readonly property var failures: Object.values(status).filter(s => s.state === "error")
    readonly property bool allFailed: !searching && failures.length > 0 && failures.length === Object.keys(status).length

    function search(q: string): void {
        q = q.trim();
        if (q.length < 2)
            return;
        query = q;
        results = [];
        const st = {};
        for (const s of Api.get("sources")) {
            const disabled = (Api.setting("disabledSources") || "").split(",").map(x => x.trim());
            if (!disabled.includes(s.key))
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
            query: q
        }, () => {
            root.searching = false;
            for (const k in root.status)
                if (root.status[k].state === "loading")
                    root.status[k].state = "error";
            root.status = Object.assign({}, root.status);
        }, () => root.searching = false);
    }

    // Dev aid: `--search <q> [--open]` searches on launch and opens the first hit.
    readonly property var devArgs: Qt.application.arguments
    Component.onCompleted: {
        const i = devArgs.indexOf("--search");
        if (i > 0) {
            ApplicationWindow.window.tab = 1;
            search(devArgs[i + 1]);
        }
    }
    onResultsChanged: if (results.length > 0 && devArgs.includes("--open") && !opened) {
        opened = true;
        ApplicationWindow.window.openAnime(results[0], devArgs.includes("--play") ? -1 : 0);
    }
    property bool opened

    Connections {
        target: root.ApplicationWindow.window // via root: attached to a Connections it is null

        function onSearchRequested(q: string): void {
            field.text = q;
            root.search(q);
        }
    }

    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind !== "searchResult" || !root.status[data.source])
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

        StyledText {
            text: "Search"
            font: Theme.font.headline.large
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.maximumWidth: 760
            implicitHeight: 56
            radius: Theme.rounding.full
            color: Theme.palette.surfaceContainerHigh
            border.width: field.activeFocus ? 2 : 0
            border.color: Theme.palette.primary

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padding.large
                anchors.rightMargin: Theme.padding.small
                spacing: Theme.spacing.medium

                MaterialIcon {
                    text: "search"
                    size: 16
                    color: Theme.palette.onSurfaceVariant
                }
                TextFieldBase {
                    id: field

                    Layout.fillWidth: true
                    placeholderText: "Search anime… (e.g. Frieren, One Piece)"
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
                    onClicked: root.search(field.text)
                }
            }
        }

        // per-source status, doubles as a filter
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            visible: Object.keys(root.status).length > 0

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
                    onClicked: root.filter = modelData
                    tint: st.state === "error" ? Theme.palette.errorContainer : Theme.palette.secondaryContainer

                    ToolTip.visible: st.error ? hov.hovered : false
                    ToolTip.text: st.error ? `${Api.describe(st.error)}\n${st.error}` : ""

                    HoverHandler {
                        id: hov
                    }
                }
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
                    onClicked: ApplicationWindow.window.openAnime(cell.modelData, 0)
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
                face: root.allFailed ? "(×﹏×)" : root.query ? "(╥﹏╥)" : "(◕‿◕✿)"
                tint: root.allFailed ? Theme.palette.error : Theme.palette.primary
                title: root.allFailed ? "Couldn't reach any source" : root.query ? `Nothing found for “${root.query}”` : "What do you want to watch?"
                message: root.allFailed ? Api.describe(root.failures[0].error) : root.query ? "Try another spelling, or the Japanese title (e.g. Shingeki no Kyojin)." : "Type a title and press Enter. Results show up as each site answers."

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
