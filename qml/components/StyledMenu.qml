pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Aikatsu

// Popup menu. model: [{text, icon?, checked?, value?}]; emits triggered(item).
T.Popup {
    id: root

    property var model: []
    property string header

    signal triggered(var item)

    padding: Theme.padding.small
    // Templates popups have no implicit size of their own (styles add it).
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, implicitContentHeight + topPadding + bottomPadding)
    margins: Theme.spacing.small // keep inside the window
    width: Math.max(200, col.implicitWidth + padding * 2)
    focus: true

    enter: Transition {
        Anim {
            property: "opacity"
            from: 0
            to: 1
            type: Anim.FastEffects
        }
        Anim {
            property: "scale"
            from: 0.92
            to: 1
            type: Anim.FastSpatial
        }
    }
    exit: Transition {
        Anim {
            property: "opacity"
            to: 0
            type: Anim.FastEffects
        }
    }

    background: StyledRect {
        radius: Theme.rounding.large
        color: Theme.palette.surfaceContainer

        Elevation {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            level: 2
        }
    }

    contentItem: ColumnLayout {
        id: col

        spacing: 2

        StyledText {
            visible: root.header !== ""
            Layout.leftMargin: Theme.padding.medium
            Layout.topMargin: Theme.padding.extraSmall
            Layout.bottomMargin: Theme.padding.extraSmall
            text: root.header
            font: Theme.font.label.large
            color: Theme.palette.onSurfaceVariant
        }

        Repeater {
            model: root.model

            StyledRect {
                id: item

                required property var modelData

                Layout.fillWidth: true
                implicitWidth: row.implicitWidth + Theme.padding.medium * 2
                implicitHeight: 40
                radius: Theme.rounding.medium
                color: modelData.checked ? Theme.palette.secondaryContainer : "transparent"

                RowLayout {
                    id: row

                    anchors.fill: parent
                    anchors.leftMargin: Theme.padding.medium
                    anchors.rightMargin: Theme.padding.medium
                    spacing: Theme.spacing.medium

                    MaterialIcon {
                        visible: !!item.modelData.icon || !!item.modelData.checked
                        text: item.modelData.checked ? "check" : (item.modelData.icon ?? "")
                        size: 14
                        color: item.modelData.checked ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: item.modelData.text
                        font: Theme.font.label.large
                        color: item.modelData.checked ? Theme.palette.onSecondaryContainer : Theme.palette.onSurface
                        elide: Text.ElideRight
                    }
                }

                StateLayer {
                    color: Theme.palette.onSurface
                    onClicked: {
                        root.triggered(item.modelData);
                        root.close();
                    }
                }
            }
        }
    }
}
