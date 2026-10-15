import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Aikatsu

// M3 basic dialog. Put body items as children; actions via `actions`.
T.Popup {
    id: root

    property string title
    property string icon
    property string text
    default property alias body: bodyCol.data
    property alias actions: actionRow.data

    parent: T.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    width: Math.min(460, parent ? parent.width - 48 : 460)
    padding: 24
    // Templates popups have no implicit size of their own (styles add it).
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, implicitContentHeight + topPadding + bottomPadding)
    margins: Theme.spacing.small // keep inside the window

    T.Overlay.modal: Rectangle {
        color: Qt.alpha(Theme.palette.scrim, 0.45)

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    enter: Transition {
        Anim {
            property: "opacity"
            from: 0
            to: 1
            type: Anim.DefaultEffects
        }
        Anim {
            property: "scale"
            from: 0.9
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
        radius: Theme.rounding.extraLarge
        color: Theme.palette.surfaceContainerHigh

        Elevation {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            level: 3
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.large

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: root.icon !== ""
            text: root.icon
            size: 18
            color: Theme.palette.secondary
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.title !== ""
            text: root.title
            font: Theme.font.headline.small
            horizontalAlignment: root.icon !== "" ? Text.AlignHCenter : Text.AlignLeft
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.text !== ""
            text: root.text
            color: Theme.palette.onSurfaceVariant
            wrapMode: Text.Wrap
        }
        ColumnLayout {
            id: bodyCol

            Layout.fillWidth: true
            spacing: Theme.spacing.medium
        }
        RowLayout {
            id: actionRow

            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Theme.spacing.small
            spacing: Theme.spacing.small
        }
    }
}
