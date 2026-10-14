import QtQuick
import Aikatsu

ColorAnimation {
    duration: Theme.anim.durations.expressiveSlowEffects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.anim.expressiveSlowEffects
}
