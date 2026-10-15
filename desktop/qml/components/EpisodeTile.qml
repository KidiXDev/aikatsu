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

    readonly property bool completed: record?.completed ?? false
    readonly property real fraction: record && record.duration > 0 ? record.playback_time / record.duration : 0

    signal clicked
    signal rightClicked(real x, real y)

    implicitHeight: 64
    radius: Theme.rounding.large
    color: current ? Theme.palette.secondaryContainer : Theme.palette.surfaceContainer
    border.width: current ? 0 : 1
    border.color: Qt.alpha(Theme.palette.outlineVariant, 0.5)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padding.medium
        anchors.rightMargin: Theme.padding.medium
        spacing: Theme.spacing.medium

        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Theme.rounding.medium
            color: root.completed ? Theme.palette.primary : root.current ? Theme.palette.primaryContainer : Theme.palette.surfaceContainerHighest

            StyledText {
                anchors.centerIn: parent
                visible: !root.completed
                text: root.num
                font: Theme.font.title.medium
                color: root.current ? Theme.palette.onPrimaryContainer : Theme.palette.onSurface
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
                color: Theme.palette.onSurfaceVariant
            }
            RowLayout {
                visible: root.fraction > 0 && !root.completed
                spacing: Theme.spacing.small

                LinearProgress {
                    Layout.preferredWidth: 90
                    value: root.fraction
                }
                StyledText {
                    text: `${Math.round(root.fraction * 100)}%`
                    font: Theme.font.label.small
                    color: Theme.palette.onSurfaceVariant
                }
            }
        }
    }

    StateLayer {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        color: Theme.palette.onSurface
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked(e.x, e.y) : root.clicked()
    }
}
