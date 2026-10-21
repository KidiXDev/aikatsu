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

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        StyledText {
            text: "Episodes"
            font: Theme.font.label.large
            color: Theme.palette.onSurfaceVariant
        }
        SegmentedControl {
            options: (root.single !== null ? [
                    {
                        value: "single",
                        label: `Ep ${root.single.num}`
                    }
                ] : []).concat([
                {
                    value: "range",
                    label: "Range"
                },
                {
                    value: "all",
                    label: "All",
                    count: root.episodes.length
                }
            ])
            value: root.mode
            onPicked: v => root.mode = v
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
            color: Theme.palette.onSurfaceVariant
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

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        StyledText {
            text: "Quality"
            font: Theme.font.label.large
            color: Theme.palette.onSurfaceVariant
        }
        SegmentedControl {
            options: [
                {
                    value: "best",
                    label: "Auto"
                },
                {
                    value: "1080p",
                    label: "1080p"
                },
                {
                    value: "720p",
                    label: "720p"
                },
                {
                    value: "480p",
                    label: "480p"
                },
                {
                    value: "360p",
                    label: "360p"
                }
            ]
            value: root.quality
            onPicked: v => root.quality = v
        }
    }

    actions: [
        TextButton {
            type: TextButton.Text
            text: "Cancel"
            onClicked: root.close()
        },
        TextButton {
            type: TextButton.Tonal
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
