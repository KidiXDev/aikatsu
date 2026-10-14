import QtQuick
import QtQuick.Particles
import Aikatsu

// Petals drifting down across the parent; tinted with the palette.
ParticleSystem {
    id: root

    property int rate: 6
    property color color: Theme.palette.primary

    anchors.fill: parent

    ImageParticle {
        source: "qrc:/sakura.svg"
        color: Qt.alpha(root.color, 0.75)
        colorVariation: 0.08
        alpha: 0.85
        rotation: 0
        rotationVariation: 180
        rotationVelocity: 30
        rotationVelocityVariation: 60
        entryEffect: ImageParticle.Fade
    }

    Emitter {
        width: parent.width * 1.2
        x: -parent.width * 0.1
        y: -20
        height: 1
        emitRate: root.rate
        lifeSpan: 9000
        lifeSpanVariation: 2500
        size: 16
        sizeVariation: 8
        velocity: AngleDirection {
            angle: 100
            angleVariation: 20
            magnitude: 45
            magnitudeVariation: 20
        }
        acceleration: PointDirection {
            x: -6
            xVariation: 12
            y: 4
        }
    }

    Wander {
        xVariance: 40
        pace: 60
    }
}
