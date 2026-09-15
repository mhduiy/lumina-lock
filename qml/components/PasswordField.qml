import QtQuick
import QtQuick.Shapes
import Lumina 1.0

// A purpose-built password field: no default control chrome, just a rounded
// frosted glass pill with a dot-masked input and a busy arc.
//
// The field owns its own feedback animations (character pop, error bounce,
// success flash). They run on a Translate rather than on `x`, because the pill
// is positioned by the parent's Column and an animation on `x` would fight
// those anchors and snap back at the end.
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

    // Overrides the border colour while feedback is playing.
    property color feedbackColor: "transparent"
    property real shakeDistance: 9 * unit

    signal accepted()
    signal escapePressed()
    signal textEdited()

    width: 300 * unit
    height: 52 * unit

    transform: Translate { id: shakeOffset }

    GlassPanel {
        id: bg
        anchors.fill: parent
        radius: height / 2
        background: root.glassSource
        sourceOrigin: root.glassOrigin
        refreshToken: root.glassRefreshToken
        liveSource: root.glassLive
        dim: root.glassDim
        borderColor: root.feedbackColor.a > 0
                     ? root.feedbackColor
                     : (root.error ? Theme.error
                                   : (input.activeFocus ? Theme.surfaceBorderFocus
                                                        : Theme.surfaceBorder))
    }

    Text {
        id: placeholder
        anchors.centerIn: parent
        text: root.placeholderText
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 15 * root.unit
        visible: input.text.length === 0
    }

    TextInput {
        id: input
        // Symmetric insets so the dots sit in the middle of the pill; the right
        // inset also keeps them clear of the busy arc.
        anchors.fill: parent
        anchors.leftMargin: 40 * root.unit
        anchors.rightMargin: 40 * root.unit
        horizontalAlignment: TextInput.AlignHCenter
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

    // Used when a printable key woke the lock: that character should become the
    // first character of the password rather than being swallowed.
    function appendText(suffix) {
        if (!suffix)
            return
        input.text = input.text + suffix
        input.cursorPosition = input.text.length
    }

    function bounceError() {
        errorBounce.restart()
    }

    function playSuccess() {
        successFlash.restart()
        successPulse.restart()
    }

    // A short squash on every new character, so typing feels responsive.
    Connections {
        target: input
        property int previousLength: 0
        function onTextChanged() {
            if (input.text.length > previousLength)
                charPop.restart()
            previousLength = input.text.length
        }
    }

    SequentialAnimation {
        id: charPop
        NumberAnimation {
            target: input; property: "scale"; to: 1.025
            duration: 60; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: input; property: "scale"; to: 1.0
            duration: 150; easing.type: Easing.OutBack
        }
    }

    // Wrong password: a decaying shake sideways plus a springy dip, so it reads
    // as a bounce rather than as a flat slide.
    ParallelAnimation {
        id: errorBounce

        SequentialAnimation {
            NumberAnimation { target: shakeOffset; property: "x"; to: -root.shakeDistance;      duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeOffset; property: "x"; to:  root.shakeDistance;      duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeOffset; property: "x"; to: -root.shakeDistance * 0.6; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeOffset; property: "x"; to:  root.shakeDistance * 0.6; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeOffset; property: "x"; to: 0;                        duration: 90; easing.type: Easing.OutBack }
        }

        SequentialAnimation {
            NumberAnimation { target: shakeOffset; property: "y"; to: 7 * root.unit; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeOffset; property: "y"; to: 0; duration: 460; easing.type: Easing.OutElastic }
        }

        SequentialAnimation {
            NumberAnimation { target: root; property: "scale"; to: 0.985; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "scale"; to: 1.0;   duration: 340; easing.type: Easing.OutElastic }
        }
    }

    // Accepted password: the border flashes the accent colour and the pill gives
    // one outward pulse, so the answer registers before the scene fades out.
    SequentialAnimation {
        id: successFlash
        ColorAnimation { target: root; property: "feedbackColor"; to: Theme.accent; duration: 90 }
        ColorAnimation { target: root; property: "feedbackColor"; to: "transparent"; duration: 340 }
    }

    SequentialAnimation {
        id: successPulse
        NumberAnimation { target: root; property: "scale"; to: 1.035; duration: 110; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1.0;   duration: 280; easing.type: Easing.OutBack }
    }
}
