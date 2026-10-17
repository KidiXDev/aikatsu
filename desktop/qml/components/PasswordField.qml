import QtQuick
import QtQuick.Controls
import Aikatsu

// Hidden text with a show/hide eye. With `matches` set it confirms that field.
StyledTextField {
    id: root

    property bool revealed
    property TextFieldBase matches

    echoMode: revealed ? TextInput.Normal : TextInput.Password
    trailingIcon: revealed ? "visibility_off" : "visibility"
    validate: matches ? t => t === matches.text : undefined
    errorText: matches ? "Passwords don't match" : ""
    onVisibleChanged: if (!visible)
        revealed = false

    // Editing the first field settles the confirmation's error either way.
    Connections {
        target: root.matches

        function onTextChanged(): void {
            if (root.isError && root.valid)
                root.isError = false;
        }

        function onEditingFinished(): void {
            if (root.text && !root.valid)
                root.isError = true;
        }
    }

    StateLayer {
        readonly property real iconWidth: root.trailingOffset - Theme.padding.medium

        anchors.fill: undefined
        x: root.width - Theme.padding.medium - iconWidth / 2 - width / 2
        y: (root.height - root.supportingTextOffset - height) / 2
        width: 32
        height: 32
        radius: Theme.rounding.full
        color: Theme.palette.onSurfaceVariant
        Accessible.role: Accessible.Button
        Accessible.name: root.revealed ? "Hide" : "Show"
        ToolTip.visible: containsMouse
        ToolTip.text: root.revealed ? "Hide" : "Show"
        onClicked: root.revealed = !root.revealed
    }
}
