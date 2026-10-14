pragma ComponentBehavior: Bound

import QtQuick
import Aikatsu
import QtQuick.Shapes

TextFieldBase {
    id: root

    enum TextFieldType {
        Outlined,
        Filled
    }

    property int type: StyledTextField.Outlined

    property int smallFontSize: Theme.font.label.small.pointSize
    readonly property real smallFontScale: smallFontSize / font.pointSize

    property int verticalPadding: Theme.padding.large
    property int horizontalPadding: Theme.padding.large
    property int radius: Theme.rounding.small
    readonly property int clampedRadius: Math.min(horizontalPadding, Math.min(width, height) / 2, radius)

    property string leadingIcon
    property string trailingIcon
    readonly property int leadingOffset: leadingIcon ? leadingIconLoader.width + leadingIconLoader.anchors.leftMargin : 0
    readonly property int trailingOffset: trailingIcon ? trailingIconLoader.width + trailingIconLoader.anchors.rightMargin : 0

    property string supportingText
    property string errorText
    property bool isError
    property bool emptyIsValid: true
    property var validate // Regex or function
    readonly property bool valid: !validate || (!text && emptyIsValid) || (validate instanceof RegExp ? validate.test(text) : !!validate(text))
    readonly property string effectiveSupportingText: isError && errorText ? errorText : supportingText
    readonly property int supportingTextOffset: effectiveSupportingText ? supportingTextLoader.height + Theme.spacing.extraSmall : 0

    readonly property int filledOffset: type === StyledTextField.Filled ? Theme.spacing.small : 0

    leftPadding: horizontalPadding + leadingOffset
    rightPadding: horizontalPadding + trailingOffset
    topPadding: verticalPadding + filledOffset
    bottomPadding: verticalPadding + supportingTextOffset - filledOffset

    onPressed: {
        if (!stateLayer.disabled)
            stateLayer.press(stateLayer.mouseX, stateLayer.mouseY);
    }
    onTextEdited: {
        if (isError)
            isError = false;
    }
    onEditingFinished: {
        if (!valid)
            isError = true;
    }

    background: Loader {
        anchors.fill: parent
        anchors.bottomMargin: root.supportingTextOffset

        sourceComponent: root.type === StyledTextField.Filled ? filledComp : outlineComp

        StateLayer {
            id: stateLayer

            topLeftRadius: root.clampedRadius
            topRightRadius: root.clampedRadius
            radius: root.type === StyledTextField.Outlined ? root.clampedRadius : 0

            cursorShape: Qt.IBeamCursor
            disabled: root.activeFocus
            manualPressOverride: tapHandler.pressed
            onClicked: root.focus = true
        }
    }

    Item {
        id: contentWrapper

        anchors.fill: parent
        anchors.bottomMargin: root.supportingTextOffset

        StyledText {
            id: placeholder

            font.family: root.font.family
            font.variableAxes: root.font.variableAxes
            font.pointSize: root.font.pointSize
            font.weight: root.font.weight

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.leftPadding
            anchors.topMargin: Theme.padding.extraSmall
            renderType: Text.QtRendering

            text: root.placeholderText
            color: root.isError ? Theme.palette.error : (root.activeFocus ? Theme.palette.primary : root.text ? Theme.palette.outline : root.placeholderTextColor)

            states: [
                State {
                    name: "smallOutlined"
                    when: root.type === StyledTextField.Outlined && (root.activeFocus || root.text)

                    PropertyChanges {
                        placeholder.scale: root.smallFontScale
                        placeholder.anchors.leftMargin: -(1 - root.smallFontScale) * placeholder.width / 2 + root.horizontalPadding + -Theme.spacing.extraSmall
                    }
                    AnchorChanges {
                        target: placeholder
                        anchors.verticalCenter: contentWrapper.top
                    }
                },
                State {
                    name: "smallFilled"
                    when: root.type === StyledTextField.Filled && (root.activeFocus || root.text)

                    PropertyChanges {
                        placeholder.scale: root.smallFontScale
                        placeholder.anchors.leftMargin: -(1 - root.smallFontScale) * placeholder.width / 2 + root.horizontalPadding + root.leadingOffset
                    }
                    AnchorChanges {
                        target: placeholder
                        anchors.top: contentWrapper.top
                        anchors.verticalCenter: undefined
                    }
                }
            ]

            transitions: Transition {
                Anim {
                    properties: "scale,leftMargin"
                    type: Anim.DefaultEffects
                }
                AnchorAnimation {
                    duration: Theme.anim.durations.expressiveDefaultEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.anim.expressiveDefaultEffects
                }
            }
        }

        Loader {
            id: leadingIconLoader

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.padding.medium
            active: root.leadingIcon

            sourceComponent: MaterialIcon {
                text: root.leadingIcon
                color: Theme.palette.onSurfaceVariant
                size: 14
            }
        }

        Loader {
            id: trailingIconLoader

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Theme.padding.medium
            active: root.trailingIcon

            sourceComponent: MaterialIcon {
                text: root.trailingIcon
                color: Theme.palette.onSurfaceVariant
                size: 14
            }
        }
    }

    Loader {
        id: supportingTextLoader

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        active: root.effectiveSupportingText

        sourceComponent: StyledText {
            text: root.effectiveSupportingText
            color: root.isError ? Theme.palette.error : Theme.palette.onSurfaceVariant
            font: Theme.font.label.small
        }
    }

    TapHandler {
        id: tapHandler
    }

    Component {
        id: outlineComp

        Shape {
            id: bg

            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                id: path

                readonly property real outlineGap: placeholder.width * root.smallFontScale + Theme.spacing.extraSmall * 2
                property real outlineGapScale: root.activeFocus || root.text ? 1 : 0
                readonly property real inset: strokeWidth / 2

                strokeWidth: root.activeFocus ? 2 : 1
                strokeColor: root.isError ? Theme.palette.error : (root.activeFocus ? Theme.palette.primary : Theme.palette.outline)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                startX: path.inset + root.horizontalPadding - root.clampedRadius + path.outlineGap * (1 - path.outlineGapScale) / 2 + path.outlineGap * path.outlineGapScale

                PathLine {
                    x: bg.width - path.inset - root.clampedRadius
                }
                PathArc {
                    x: bg.width - path.inset
                    y: path.inset + root.clampedRadius
                    radiusX: root.clampedRadius
                    radiusY: root.clampedRadius
                }
                PathLine {
                    x: bg.width - path.inset
                    y: bg.height - path.inset - root.clampedRadius
                }
                PathArc {
                    x: bg.width - path.inset - root.clampedRadius
                    y: bg.height - path.inset
                    radiusX: root.clampedRadius
                    radiusY: root.clampedRadius
                }
                PathLine {
                    x: path.inset + root.clampedRadius
                    y: bg.height - path.inset
                }
                PathArc {
                    x: path.inset
                    y: bg.height - path.inset - root.clampedRadius
                    radiusX: root.clampedRadius
                    radiusY: root.clampedRadius
                }
                PathLine {
                    x: path.inset
                    y: path.inset + root.clampedRadius
                }
                PathArc {
                    x: path.inset + root.clampedRadius
                    y: path.inset
                    radiusX: root.clampedRadius
                    radiusY: root.clampedRadius
                }
                PathLine {
                    x: path.inset + root.horizontalPadding - root.clampedRadius + path.outlineGap * (1 - path.outlineGapScale) / 2
                }

                Behavior on outlineGapScale {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on strokeWidth {
                    Anim {}
                }

                Behavior on strokeColor {
                    CAnim {}
                }
            }
        }
    }

    Component {
        id: filledComp

        StyledRect {
            topLeftRadius: root.clampedRadius
            topRightRadius: root.clampedRadius
            color: root.activeFocus ? Theme.palette.surfaceContainerHighest : Theme.palette.surfaceContainerHigh

            StyledRect {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: root.activeFocus ? 2 : 1
                color: root.isError ? Theme.palette.error : (root.activeFocus ? Theme.palette.primary : Theme.palette.outline)

                Behavior on implicitHeight {
                    Anim {}
                }
            }
        }
    }
}
