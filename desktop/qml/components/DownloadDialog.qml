pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

StyledDialog {
    id: root

    property var anime
    property var meta
    property var episodes: []
    property var single: null
    property string mode: "range" // single | range | all
    property string quality: Api.setting("quality") || "best"

    function openFor(ep: var): void {
        single = ep;
        mode = ep ? "single" : "range";
        fromField.text = episodes.length ? String(episodes[0].num) : "1";
        toField.text = episodes.length ? String(episodes[episodes.length - 1].num) : "1";
        open();
    }

    readonly property var selection: {
        if (mode === "single")
            return single ? [single] : [];
        if (mode === "all")
            return episodes;
        const a = parseInt(fromField.text), b = parseInt(toField.text);
        return episodes.filter(e => e.num >= Math.min(a, b) && e.num <= Math.max(a, b));
    }

    icon: "download"
    title: "Download episodes"

    RowLayout {
        spacing: Theme.spacing.small
        visible: root.single !== null

        Chip {
            text: `Episode ${root.single?.num ?? ""}`
            selected: root.mode === "single"
            clickable: true
            onClicked: root.mode = "single"
        }
        Chip {
            text: "Range"
            selected: root.mode === "range"
            clickable: true
            onClicked: root.mode = "range"
        }
        Chip {
            text: `All ${root.episodes.length}`
            selected: root.mode === "all"
            clickable: true
            onClicked: root.mode = "all"
        }
    }
    RowLayout {
        spacing: Theme.spacing.small
        visible: root.single === null

        Chip {
            text: "Range"
            selected: root.mode === "range"
            clickable: true
            onClicked: root.mode = "range"
        }
        Chip {
            text: `All ${root.episodes.length}`
            selected: root.mode === "all"
            clickable: true
            onClicked: root.mode = "all"
        }
    }

    RowLayout {
        visible: root.mode === "range"
        spacing: Theme.spacing.medium

        StyledTextField {
            id: fromField

            Layout.preferredWidth: 120
            placeholderText: "From"
            validator: IntValidator {
                bottom: 0
            }
        }
        StyledText {
            text: "–"
        }
        StyledTextField {
            id: toField

            Layout.preferredWidth: 120
            placeholderText: "To"
            validator: IntValidator {
                bottom: 0
            }
        }
    }

    StyledText {
        text: "Quality"
        font: Theme.font.label.large
        color: Theme.palette.onSurfaceVariant
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        Repeater {
            model: ["best", "1080p", "720p", "480p", "360p"]

            Chip {
                required property string modelData

                text: modelData === "best" ? "Auto" : modelData
                selected: root.quality === modelData
                clickable: true
                onClicked: root.quality = modelData
            }
        }
    }

    actions: [
        TextButton {
            type: TextButton.Text
            text: "Cancel"
            onClicked: root.close()
        },
        TextButton {
            disabled: root.selection.length === 0
            text: root.selection.length > 1 ? `Download ${root.selection.length} episodes` : "Download"
            onClicked: {
                Api.get("download", {
                    source: root.anime.source,
                    name: root.anime.name,
                    url: root.anime.url,
                    quality: root.quality,
                    meta: root.meta && root.meta.anilist_id !== undefined ? root.meta : null,
                    episodes: root.selection.map(e => ({
                                num: e.num,
                                url: e.url
                            }))
                });
                root.close();
                ApplicationWindow.window.toast(root.selection.length > 1 ? `Downloading ${root.selection.length} episodes` : "Download started");
            }
        }
    ]
}
