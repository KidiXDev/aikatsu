import QtQuick
import QtQuick.Templates as T
import Aikatsu

T.ScrollBar {
    id: root

    implicitWidth: Theme.padding.extraSmall + 2
    minimumSize: 0.05

    contentItem: StyledRect {
        radius: Theme.rounding.full
        color: Theme.palette.secondary
        opacity: root.size >= 1 ? 0 : root.pressed ? 1 : root.hovered ? 0.8 : root.active ? 0.6 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
