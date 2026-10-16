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
    readonly property var tools: Api.get("tools")
    readonly property int sourcesOn: sources.filter(x => !disabled.includes(x.key)).length

    function set(key: string, value: var): void {
        Api.setSetting(key, value);
        s = Api.get("settings");
    }

    // The Plugins page changes these while Settings stays loaded underneath.
    Connections {
        target: Api

        function onPushed(kind: string, data: var): void {
            if (kind === "plugins")
                root.sources = Api.get("sources");
        }

        function onSettingChanged(key: string, value: string): void {
            root.s = Api.get("settings");
        }
    }

    component Section: StyledRect {
        id: sec

        default property alias content: inner.data
        property string title
        property string icon

        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + Theme.padding.extraLarge * 2
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainer

        ColumnLayout {
            id: inner

            anchors.fill: parent
            anchors.margins: Theme.padding.extraLarge
            spacing: Theme.spacing.large

            RowLayout {
                spacing: Theme.spacing.medium

                MaterialIcon {
                    text: sec.icon
                    fill: 1
                    color: Theme.palette.primary
                }
                StyledText {
                    text: sec.title
                    font: Theme.font.title.large
                }
            }
        }
    }

    component Row: RowLayout {
        id: rowRoot

        property string label
        property string hint

        Layout.fillWidth: true
        spacing: Theme.spacing.large

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: rowRoot.label
                font: Theme.font.body.large
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: rowRoot.hint
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.body.small
                wrapMode: Text.Wrap
            }
        }
    }

    FolderDialog {
        id: folderPicker

        onAccepted: root.set("downloadDir", Api.get("localPath", {
                url: selectedFolder.toString()
            }))
    }

    StyledFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: col

            x: (flick.width - width) / 2
            y: Theme.padding.extraLarge
            width: Math.min(820, flick.width - Theme.padding.extraLarge * 2)
            spacing: Theme.spacing.large

            StyledText {
                text: "Settings"
                font: Theme.font.headline.large
            }

            Section {
                title: "Appearance"
                icon: "palette"

                Row {
                    label: "Theme"

                    Repeater {
                        model: [["system", "System"], ["dark", "Dark"], ["light", "Light"]]

                        Chip {
                            required property var modelData

                            text: modelData[1]
                            selected: root.s.theme === modelData[0]
                            clickable: true
                            onClicked: root.set("theme", modelData[0])
                        }
                    }
                }
            }

            Section {
                title: "Playback"
                icon: "play_circle"

                Row {
                    label: "Autoplay next episode"

                    StyledSwitch {
                        checked: root.s.autoplay === "true"
                        onToggled: root.set("autoplay", checked)
                    }
                }
                Row {
                    label: "Skip intro & outro"

                    StyledSwitch {
                        checked: root.s.autoSkip === "true"
                        onToggled: root.set("autoSkip", checked)
                    }
                }
                Row {
                    label: "Preferred quality"

                    Repeater {
                        model: ["best", "1080p", "720p", "480p"]

                        Chip {
                            required property string modelData

                            text: modelData === "best" ? "Auto" : modelData
                            selected: root.s.quality === modelData
                            clickable: true
                            onClicked: root.set("quality", modelData)
                        }
                    }
                }
                Row {
                    label: "Sharpen video (Anime4K)"

                    TextButton {
                        visible: !root.shadersInstalled
                        type: TextButton.Tonal
                        text: root.installingShaders ? "Downloading…" : "Download"
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
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    Chip {
                        text: "Off"
                        selected: !root.s.anime4k || root.s.anime4k === "off"
                        clickable: true
                        onClicked: root.set("anime4k", "off")
                    }
                    Repeater {
                        model: root.modes

                        Chip {
                            required property var modelData

                            text: modelData.name
                            selected: root.s.anime4k === modelData.key
                            clickable: true
                            onClicked: root.set("anime4k", modelData.key)
                            ToolTip.visible: hov.hovered
                            ToolTip.text: modelData.description

                            HoverHandler {
                                id: hov
                            }
                        }
                    }
                }
            }

            Section {
                title: "Sources"
                icon: "public"

                Row {
                    label: "Plugins"
                    hint: {
                        const n = root.sources.length, noun = n === 1 ? "source" : "sources";
                        return n === 0 ? "None installed" : root.sourcesOn === n ? `${n} ${noun}` : `${root.sourcesOn} of ${n} ${noun} on`;
                    }

                    TextButton {
                        type: TextButton.Tonal
                        text: "Manage"
                        onClicked: ApplicationWindow.window.openPlugins()
                    }
                }
            }

            Section {
                title: "Downloads"
                icon: "download"

                Row {
                    label: "Download folder"
                    hint: Api.get("downloadDir")

                    TextButton {
                        type: TextButton.Tonal
                        text: "Change…"
                        onClicked: folderPicker.open()
                    }
                    TextButton {
                        visible: root.s.downloadDir !== ""
                        type: TextButton.Text
                        text: "Reset"
                        onClicked: root.set("downloadDir", "")
                    }
                }
                Row {
                    visible: !root.tools.ffmpeg
                    label: "ffmpeg isn't installed"
                    hint: "Some episodes save as .ts instead of .mp4."
                }
                Row {
                    label: "TMDB API key"
                    hint: "Sorts long shows into season folders."

                    StyledTextField {
                        Layout.preferredWidth: 260
                        placeholderText: "Optional"
                        text: root.s.tmdbKey
                        echoMode: TextInput.Password
                        onEditingFinished: root.set("tmdbKey", text)
                    }
                }
            }

            Section {
                title: "Other"
                icon: "tune"

                Row {
                    label: "Discord status"

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
                Row {
                    label: "Debug logging"
                    hint: "Applies after a restart. Ctrl+L opens the log."

                    StyledSwitch {
                        checked: root.s.debug === "true"
                        onToggled: root.set("debug", checked)
                    }
                }
                Row {
                    label: "Cache"

                    TextButton {
                        type: TextButton.Tonal
                        text: "Clear"
                        onClicked: {
                            Api.get("clearCache");
                            ApplicationWindow.window.toast("Cache cleared");
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing.large
                text: `Aikatsu ${Api.get("version")}  ·  GPL-3.0  ·  (ﾉ´ヮ\`)ﾉ*: ･ﾟ`
                color: Theme.palette.onSurfaceVariant
                font: Theme.font.label.large
            }
        }
    }
}
