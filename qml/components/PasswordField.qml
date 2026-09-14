import QtQuick
import QtQuick.Shapes
import Lumina 1.0

// A purpose-built password field: no default control chrome, just a rounded
// frosted glass pill with a dot-masked input and a busy arc.
Item {
    id: root

    property real unit: 1
    property alias text: input.text
    property string placeholderText: ""
    property bool error: false
    property bool busy: false

    // Frosted backdrop plumbing, forwarded from the scene. See GlassPanel for
    // why `glassOrigin` has to be a plain tracked-property binding.
    property Item glassSource: null
    property point glassOrigin: Qt.point(0, 0)
    property int glassRefreshToken: 0
    property bool glassLive: false
    property real glassDim: 0

    signal accepted()
    signal escapePressed()
    signal textEdited()

    width: 300 * unit
    height: 52 * unit

    GlassPanel {
        id: bg
        anchors.fill: parent
        radius: height / 2
        background: root.glassSource
        sourceOrigin: root.glassOrigin
        refreshToken: root.glassRefreshToken
        liveSource: root.glassLive
        dim: root.glassDim
        borderColor: root.error ? Theme.error
                                : (input.activeFocus ? Theme.surfaceBorderFocus
                                                     : Theme.surfaceBorder)
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        text: root.placeholderText
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 15 * root.unit
        visible: input.text.length === 0
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 20 * root.unit
        anchors.rightMargin: 44 * root.unit
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: 16 * root.unit
        echoMode: TextInput.Password
        passwordCharacter: "\u2022" // •
        passwordMaskDelay: 0
        activeFocusOnPress: true
        onAccepted: root.accepted()
        onTextEdited: root.textEdited()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                root.escapePressed()
        }
    }

    // "Authenticating…" indicator: a fifth of the ring sweeps around rather
    // than a single travelling dot, so the motion reads at a glance.
    Item {
        id: spinner
        anchors.right: parent.right
        anchors.rightMargin: 16 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        width: 18 * root.unit
        height: 18 * root.unit
        visible: root.busy

        readonly property real stroke: 2 * root.unit
        // Stroke centreline, so the arc rides exactly on the track ring.
        readonly property real ringRadius: width / 2 - stroke / 2

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: spinner.stroke
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: spinner.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: Math.round(spinner.width / 2)
                    centerY: Math.round(spinner.height / 2)
                    radiusX: spinner.ringRadius
                    radiusY: spinner.ringRadius
                    startAngle: 0
                    sweepAngle: 72 // a fifth of the circle
                }
            }
            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 1100
                loops: Animation.Infinite
                running: root.busy
            }
        }
    }

    function focusField() {
        input.forceActiveFocus()
    }
}
