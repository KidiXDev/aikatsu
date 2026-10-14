import QtQuick
import Aikatsu
import QtQuick.Shapes
import QtQuick.Templates as T

T.Switch {
    id: root

    property int cLayer: 1
    property bool disabled

    enabled: !disabled

    implicitWidth: implicitIndicatorWidth
    implicitHeight: implicitIndicatorHeight

    indicator: StyledRect {
        radius: Theme.rounding.full
        color: {
            if (root.disabled)
                return root.checked ? Qt.alpha(Theme.palette.onSurface, 0.12) : Qt.alpha(Theme.palette.surfaceContainerHighest, 0.38);
            return root.checked ? Theme.palette.primary : Theme.palette.surfaceContainerHighest;
        }

        implicitWidth: implicitHeight * 1.7
        implicitHeight: Theme.font.body.medium.pointSize + Theme.padding.small * 2

        StyledRect {
            readonly property real nonAnimWidth: root.pressed ? implicitHeight * 1.2 : implicitHeight

            radius: Theme.rounding.full
            color: {
                if (root.disabled)
                    return root.checked ? Theme.palette.surface : Qt.alpha(Theme.palette.onSurface, 0.12);
                return root.checked ? Theme.palette.onPrimary : Theme.palette.outline;
            }

            x: root.checked ? parent.implicitWidth - nonAnimWidth - Theme.padding.extraSmall / 2 : Theme.padding.extraSmall / 2
            implicitWidth: nonAnimWidth
            implicitHeight: parent.implicitHeight - Theme.padding.extraSmall
            anchors.verticalCenter: parent.verticalCenter

            StyledRect {
                anchors.fill: parent
                radius: parent.radius

                color: root.checked ? Theme.palette.primary : Theme.palette.onSurface
                opacity: root.pressed ? 0.1 : root.hovered ? 0.08 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            Shape {
                id: icon

                property point start1: {
                    if (root.pressed)
                        return Qt.point(width * 0.2, height / 2);
                    if (root.checked)
                        return Qt.point(width * 0.15, height / 2);
                    return Qt.point(width * 0.15, height * 0.15);
                }
                property point end1: {
                    if (root.pressed) {
                        if (root.checked)
                            return Qt.point(width * 0.4, height / 2);
                        return Qt.point(width * 0.8, height / 2);
                    }
                    if (root.checked)
                        return Qt.point(width * 0.4, height * 0.7);
                    return Qt.point(width * 0.85, height * 0.85);
                }
                property point start2: {
                    if (root.pressed) {
                        if (root.checked)
                            return Qt.point(width * 0.4, height / 2);
                        return Qt.point(width * 0.2, height / 2);
                    }
                    if (root.checked)
                        return Qt.point(width * 0.4, height * 0.7);
                    return Qt.point(width * 0.15, height * 0.85);
                }
                property point end2: {
                    if (root.pressed)
                        return Qt.point(width * 0.8, height / 2);
                    if (root.checked)
                        return Qt.point(width * 0.85, height * 0.2);
                    return Qt.point(width * 0.85, height * 0.15);
                }

                anchors.centerIn: parent
                width: height
                height: parent.implicitHeight - Theme.padding.medium
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                ShapePath {
                    strokeWidth: Theme.font.body.large.pointSize * 0.15
                    strokeColor: {
                        if (root.disabled)
                            return root.checked ? Theme.palette.outline : Theme.palette.surfaceContainer;
                        return root.checked ? Theme.palette.primary : Theme.palette.surfaceContainerHighest;
                    }
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    startX: icon.start1.x
                    startY: icon.start1.y

                    PathLine {
                        x: icon.end1.x
                        y: icon.end1.y
                    }
                    PathMove {
                        x: icon.start2.x
                        y: icon.start2.y
                    }
                    PathLine {
                        x: icon.end2.x
                        y: icon.end2.y
                    }

                    Behavior on strokeColor {
                        CAnim {}
                    }
                }

                Behavior on start1 {
                    PropAnim {}
                }
                Behavior on end1 {
                    PropAnim {}
                }
                Behavior on start2 {
                    PropAnim {}
                }
                Behavior on end2 {
                    PropAnim {}
                }
            }

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on implicitWidth {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: false
    }

    component PropAnim: PropertyAnimation {
        duration: Theme.anim.durations.expressiveFastSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.anim.expressiveFastSpatial
    }
}
