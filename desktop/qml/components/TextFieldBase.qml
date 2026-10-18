import QtQuick
import Aikatsu
import QtQuick.Templates as T

T.TextField {
    id: root

    implicitWidth: contentWidth + leftPadding + rightPadding
    implicitHeight: contentHeight + topPadding + bottomPadding

    color: Theme.palette.onSurface
    placeholderTextColor: Theme.palette.onSurfaceVariant // No anim cause placeholder is custom
    selectionColor: Qt.alpha(Theme.palette.primary, 0.4)
    selectedTextColor: color

    font: Theme.font.body.large
    renderType: Qt.platform.os === "windows" || echoMode === T.TextField.Password ? T.TextField.QtRendering : T.TextField.NativeRendering
    cursorVisible: !readOnly
    verticalAlignment: TextInput.AlignVCenter

    cursorDelegate: Item {}

    Behavior on color {
        CAnim {}
    }

    Behavior on selectionColor {
        CAnim {}
    }

    StyledRect {
        id: cursor

        property bool disableBlink

        x: root.cursorRectangle.x
        y: root.cursorRectangle.y
        implicitWidth: 1.5
        implicitHeight: root.cursorRectangle.height

        color: Theme.palette.primary
        radius: Theme.rounding.large

        Connections {
            function onCursorPositionChanged(): void {
                if (root.activeFocus && root.cursorVisible) {
                    cursor.opacity = 1;
                    cursor.disableBlink = true;
                    enableBlink.restart();
                }
            }

            target: root
        }

        Timer {
            id: enableBlink

            interval: 500
            onTriggered: cursor.disableBlink = false
        }

        Timer {
            running: root.activeFocus && root.cursorVisible && !cursor.disableBlink
            repeat: true
            triggeredOnStart: true
            interval: 500
            onTriggered: parent.opacity = parent.opacity === 1 ? 0 : 1
        }

        Binding {
            when: !root.activeFocus || !root.cursorVisible
            cursor.opacity: 0
        }

        Behavior on x {
            Anim {
                easing.bezierCurve: [0.2, 1, 0.21, 1, 1, 1] // Damped variant of fast spatial curve
                duration: Theme.anim.durations.expressiveFastEffects
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }
    }
}
