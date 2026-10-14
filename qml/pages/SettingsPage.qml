pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Aikatsu

// Everything the CLI took as flags/env vars, persisted in the settings table.
Item {
    id: root

    property var s: Api.get("settings")
    readonly property var sources: Api.get("sources")
    readonly property var disabled: (s.disabledSources || "").split(",").map(x => x.trim()).filter(x => x)
    readonly property var modes: Api.get("anime4kModes")
    property bool installingShaders
    property bool shadersInstalled: Api.get("anime4kInstalled")
    readonly property var tools: Api.get("tools")

    function set(key: string, value: var): void {
        Api.setSetting(key, value);
        s = Api.get("settings");
    }

    function toggleSource(key: string, on: bool): void {
        const list = disabled.filter(k => k !== key);
        if (!on)
            list.push(key);
        set("disabledSources", list.join(","));
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
                    hint: "Sakura dark, sakura light, or follow the system."

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
                    hint: "Starts the next episode after a 5 second countdown."

                    StyledSwitch {
                        checked: root.s.autoplay === "true"
                        onToggled: root.set("autoplay", checked)
                    }
                }
                Row {
                    label: "Skip intro & outro automatically"
                    hint: "Uses AniSkip timestamps when the anime has a MyAnimeList id."

                    StyledSwitch {
                        checked: root.s.autoSkip === "true"
                        onToggled: root.set("autoSkip", checked)
                    }
                }
                Row {
                    label: "Preferred quality"
                    hint: "Also set from the player's quality menu."

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
                    label: "Anime4K real-time upscaling"
                    hint: root.shadersInstalled ? "Default shader mode for new playback. Change it any time from the player." : "Shaders download automatically the first time a mode is used."

                    TextButton {
                        visible: !root.shadersInstalled
                        type: TextButton.Tonal
                        text: root.installingShaders ? "Downloading…" : "Download now"
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
                            ToolTip.visible: hov.containsMouse
                            ToolTip.text: modelData.description

                            MouseArea {
                                id: hov

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }
                }
            }

            Section {
                title: "Sources"
                icon: "public"

                StyledText {
                    Layout.fillWidth: true
                    text: "Search queries every enabled source in parallel. A source that keeps failing is paused for 10 minutes."
                    color: Theme.palette.onSurfaceVariant
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: root.sources

                    Row {
                        required property var modelData

                        label: modelData.name

                        StyledSwitch {
                            checked: !root.disabled.includes(parent.modelData.key)
                            onToggled: root.toggleSource(parent.modelData.key, checked)
                        }
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
                    label: "Helpers"
                    hint: `ffmpeg: ${root.tools.ffmpeg ? "found" : "not found (HLS stays .ts)"}  ·  yt-dlp: ${root.tools.ytdlp ? "found" : "fetched automatically when needed"}`
                }
                Row {
                    label: "TMDB API key"
                    hint: "Optional. Improves season folders for long-running shows."

                    StyledTextField {
                        Layout.preferredWidth: 260
                        placeholderText: "API key"
                        text: root.s.tmdbKey
                        echoMode: TextInput.Password
                        onEditingFinished: root.set("tmdbKey", text)
                    }
                }
            }

            Section {
                title: "Integrations & diagnostics"
                icon: "tune"

                Row {
                    label: "Discord Rich Presence"
                    hint: "Show what you're watching on Discord."

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
                    hint: "Verbose logs (applies on next launch). Press Ctrl+L to view logs."

                    StyledSwitch {
                        checked: root.s.debug === "true"
                        onToggled: root.set("debug", checked)
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
