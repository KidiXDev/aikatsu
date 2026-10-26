pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

// Details only: Aikatsu can't stream from AniList, so the way on is a source search.
StyledDialog {
    id: root

    property var item: null // {meta: AniList Meta, note}
    readonly property var m: item?.meta ?? ({})
    readonly property string name: m.title_english || m.title_romaji || ""
    readonly property var chips: [m.score > 0 ? {
            text: `★ ${(m.score / 10).toFixed(1)}`,
            accent: true
        } : null, m.year > 0 ? {
            text: `${m.year}`,
            icon: "calendar_month"
        } : null, m.episodes > 0 ? {
            text: `${m.episodes} eps`,
            icon: "video_library"
        } : null, m.status ? {
            text: m.status.replace(/_/g, " ").toLowerCase()
        } : null, ...(m.genres ?? []).map(g => ({
                text: g
            }))].filter(c => c)

    width: Math.min(640, parent ? parent.width - 48 : 640)

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.extraLarge

        ClippedImage {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 120
            Layout.preferredHeight: 174
            radius: Theme.rounding.large
            source: root.m.cover ?? ""

            Elevation {
                z: -1
                anchors.fill: parent
                radius: parent.radius
                level: 3
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Theme.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.name
                font: Theme.font.headline.small
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: [root.m.title_romaji, root.m.title_native].filter(t => t && t !== root.name).join("  ·  ")
                color: Theme.palette.onSurfaceVariant
                wrapMode: Text.Wrap
            }
            StyledText {
                visible: text !== ""
                text: root.item?.note ?? ""
                font: Theme.font.label.large
                color: Theme.palette.primary
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                Repeater {
                    model: root.chips

                    Chip {
                        required property var modelData

                        text: modelData.text
                        icon: modelData.icon ?? ""
                        selected: modelData.accent ?? false
                        tint: Theme.palette.tertiaryContainer
                        onTint: Theme.palette.onTertiaryContainer
                    }
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.m.description ?? ""
        color: Theme.palette.onSurfaceVariant
        font: Theme.font.body.large
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
        lineHeight: 1.15
    }

    actions: [
        TextButton {
            type: TextButton.Text
            text: "Close"
            onClicked: root.close()
        },
        IconTextButton {
            type: TextButton.Tonal
            icon: "search"
            text: "Search sources"
            onClicked: {
                root.close();
                // The sources mostly use romaji names.
                (ApplicationWindow.window as Main).searchFor(root.m.title_romaji || root.name);
            }
        }
    ]
}
