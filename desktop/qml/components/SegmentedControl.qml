pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Aikatsu

// Sliding pill segmented control (M3 Expressive).
// `options` accepts `[value, label]` pairs or `{ value, label, icon?, count? }` objects.
// Set `segWidth > 0` for uniform segment widths (72px in Settings), or leave `0` to size each segment to its content.
StyledRect {
    id: root

    property var options: []
    property string value
    property real segWidth: 0
    property real horizontalPadding: Theme.padding.medium

    function valOf(o: var): string {
        return o?.value !== undefined ? String(o.value) : o?.[0] !== undefined ? String(o[0]) : "";
    }

    function labelOf(o: var): string {
        return o?.label !== undefined ? String(o.label) : o?.[1] !== undefined ? String(o[1]) : "";
    }

    function iconOf(o: var): string {
        return o?.icon !== undefined ? String(o.icon) : o?.[2] !== undefined ? String(o[2]) : "";
    }

    function countOf(o: var): int {
        if (o?.count !== undefined)
            return Number(o.count);
        if (o?.[3] !== undefined)
            return Number(o[3]);
        return -1;
    }

    readonly property int current: options.findIndex(o => root.valOf(o) === root.value)
    readonly property Item currentItem: current >= 0 && current < repeater.count ? repeater.itemAt(current) : null

    signal picked(string value)

    implicitWidth: track.implicitWidth + 8
    implicitHeight: 36
    radius: Theme.rounding.full
    color: Theme.palette.surfaceContainerHighest
    border.width: activeFocus ? 2 : 0
    border.color: Theme.palette.primary
    activeFocusOnTab: true
    Keys.onLeftPressed: if (current > 0)
        picked(valOf(options[current - 1]))
    Keys.onRightPressed: if (current < options.length - 1)
        picked(valOf(options[current + 1]))

    StyledRect {
        visible: root.currentItem !== null
        x: 4 + (root.currentItem ? root.currentItem.x : 0)
        y: 4
        width: root.currentItem ? root.currentItem.width : 0
        height: root.height - 8
        radius: Theme.rounding.full
        color: Theme.palette.secondaryContainer

        Behavior on x {
            Anim {
                type: Anim.FastSpatial
            }
        }
        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    Row {
        id: track

        x: 4
        y: 4
        spacing: 2

        Repeater {
            id: repeater

            model: root.options

            Item {
                id: option

                required property var modelData
                readonly property string optVal: root.valOf(modelData)
                readonly property string optLabel: root.labelOf(modelData)
                readonly property string optIcon: root.iconOf(modelData)
                readonly property int optCount: root.countOf(modelData)
                readonly property bool active: root.value === optVal

                width: root.segWidth > 0 ? root.segWidth : Math.max(64, inner.implicitWidth + root.horizontalPadding * 2)
                height: root.height - 8
                Accessible.role: Accessible.RadioButton
                Accessible.name: optCount >= 0 ? `${optLabel} (${optCount})` : optLabel
                Accessible.checked: active

                RowLayout {
                    id: inner

                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        visible: option.optIcon !== ""
                        text: option.optIcon
                        size: 13
                        fill: option.active ? 1 : 0
                        color: option.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant

                        Behavior on fill {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                    StyledText {
                        text: option.optLabel
                        font: Theme.font.label.large
                        color: option.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                    }
                    StyledRect {
                        visible: option.optCount >= 0
                        implicitWidth: Math.max(18, countLabel.implicitWidth + 8)
                        implicitHeight: 18
                        radius: Theme.rounding.full
                        color: option.active ? Qt.alpha(Theme.palette.onSecondaryContainer, 0.16) : Theme.palette.surfaceContainerHigh

                        StyledText {
                            id: countLabel

                            anchors.centerIn: parent
                            text: String(option.optCount)
                            font: Theme.font.label.small
                            color: option.active ? Theme.palette.onSecondaryContainer : Theme.palette.onSurfaceVariant
                        }
                    }
                }

                StateLayer {
                    radius: Theme.rounding.full
                    color: Theme.palette.onSurface
                    onClicked: root.picked(option.optVal)
                }
            }
        }
    }
}
