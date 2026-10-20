pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

StyledRect {
    id: root

    property int num
    property string title
    property bool filler
    property bool recap
    property var record: null // progress row
    property bool current
    readonly property bool hovered: stateLayer.containsMouse

    readonly property bool completed: record?.completed ?? false
    readonly property real fraction: record && record.duration > 0 ? record.playback_time / record.duration : 0

    signal clicked
    signal rightClicked(real x, real y)

    implicitHeight: 68
    radius: Theme.rounding.large
    color: current ? Theme.palette.secondaryContainer : hovered ? Theme.palette.surfaceContainerHigh : Theme.palette.surfaceContainer
    border.width: activeFocus ? 2 : current ? 0 : 1
    border.color: activeFocus ? Theme.palette.primary : hovered ? Theme.palette.outline : Qt.alpha(Theme.palette.outlineVariant, 0.5)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: `${title || `Episode ${num}`}, ${completed ? "Watched" : current ? "Up next" : `Episode ${num}`}`
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padding.medium
        anchors.rightMargin: Theme.padding.medium
        spacing: Theme.spacing.medium

        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Theme.rounding.medium
            color: root.completed || root.current ? Theme.palette.primary : root.hovered ? Theme.palette.secondaryContainer : Theme.palette.surfaceContainerHighest

            StyledText {
                anchors.centerIn: parent
                visible: !root.completed
                text: String(root.num)
                font: Theme.font.title.medium
                color: root.current ? Theme.palette.onPrimary : root.hovered ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: root.completed
                text: "check"
                weight: 700
                size: 16
                color: Theme.palette.onPrimary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.title || `Episode ${root.num}`
                    font: Theme.font.title.small
                    color: root.current ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
                    elide: Text.ElideRight
                }
                StyledRect {
                    visible: root.filler || root.recap
                    implicitWidth: badge.implicitWidth + 10
                    implicitHeight: badge.implicitHeight + 4
                    radius: Theme.rounding.extraSmall
                    color: Theme.palette.tertiaryContainer

                    StyledText {
                        id: badge

                        anchors.centerIn: parent
                        text: root.recap ? "RECAP" : "FILLER"
                        font: Theme.font.label.small
                        color: Theme.palette.onTertiaryContainer
                    }
                }
            }
            StyledText {
                visible: !root.fraction || root.completed
                text: root.completed ? "Watched" : root.current ? "Up next" : `Episode ${root.num}`
                font: Theme.font.label.medium
                color: root.current ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.8) : Theme.palette.onSurfaceVariant
            }
            RowLayout {
                visible: root.fraction > 0 && !root.completed
                spacing: Theme.spacing.small

                LinearProgress {
                    Layout.preferredWidth: 96
                    value: root.fraction
                    trackColor: root.current ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.22) : Theme.palette.secondaryContainer
                }
                StyledText {
                    text: `${Math.round(root.fraction * 100)}%`
                    font: Theme.font.label.small
                    color: root.current ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.85) : Theme.palette.onSurfaceVariant
                }
            }
        }

        MaterialIcon {
            visible: root.hovered || root.current
            text: "play_arrow"
            fill: 1
            size: 16
            color: root.current ? Theme.palette.onSecondaryContainer : Theme.palette.primary
            opacity: root.hovered || root.current ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }

    StateLayer {
        id: stateLayer

        acceptedButtons: Qt.LeftButton | Qt.RightButton
        color: root.current ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked(e.x, e.y) : root.clicked()
    }
}
