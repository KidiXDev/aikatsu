pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

StyledDialog {
    id: root

    property string path
    property var results: []
    property bool searching
    property string error
    property int request: 0

    signal linked(var meta)

    function openFor(folder: string, query: string): void {
        path = folder;
        field.text = query;
        results = [];
        open();
        search();
    }

    function search(): void {
        searching = true;
        error = "";
        Api.forget(request);
        request = Api.call("searchAnime", {
            query: field.text
        }, list => {
            root.results = list;
            root.searching = false;
        }, e => {
            root.error = Api.describe(e);
            root.searching = false;
        });
    }

    function pick(m: var): void {
        Api.call("linkLocal", {
            path: root.path,
            anilistId: m.anilist_id
        }, meta => {
            root.linked(meta);
            root.close();
        }, e => ApplicationWindow.window.toast(`Couldn't link it: ${Api.describe(e)}`));
    }

    icon: "link"
    title: "Choose anime"
    width: Math.min(560, parent ? parent.width - 48 : 560)
    onClosed: Api.forget(request)

    StyledTextField {
        id: field

        Layout.fillWidth: true
        leadingIcon: "search"
        placeholderText: "Search AniList"
        onTextEdited: typing.restart()
        onAccepted: root.search()
    }

    Timer {
        id: typing

        interval: 400
        onTriggered: root.search()
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: 360
        visible: root.results.length > 0
        clip: true
        spacing: Theme.spacing.extraSmall
        model: root.results

        delegate: StyledRect {
            id: row

            required property var modelData

            width: ListView.view.width
            implicitHeight: 72
            radius: Theme.rounding.medium
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padding.small
                spacing: Theme.spacing.medium

                ClippedImage {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 58
                    radius: Theme.rounding.small
                    source: row.modelData.cover
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.title_english || row.modelData.title_romaji
                        font: Theme.font.title.small
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [row.modelData.year || "", row.modelData.episodes ? `${row.modelData.episodes} episodes` : "", row.modelData.title_english ? row.modelData.title_romaji : ""].filter(t => t).join("  ·  ")
                        font: Theme.font.label.medium
                        color: Theme.palette.onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            StateLayer {
                color: Theme.palette.onSurface
                onClicked: root.pick(row.modelData)
            }
        }
    }

    Loading {
        Layout.alignment: Qt.AlignHCenter
        visible: root.searching && root.results.length === 0
    }
    StyledText {
        Layout.fillWidth: true
        visible: !root.searching && root.results.length === 0
        text: root.error || "No matches. Try the English or Japanese title."
        color: Theme.palette.onSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    actions: [
        TextButton {
            type: TextButton.Text
            text: "Cancel"
            onClicked: root.close()
        }
    ]
}
