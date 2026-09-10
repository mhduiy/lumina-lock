import QtQuick
import QtQuick.Effects
import Lumina 1.0

// The single, unified lock scene for the primary screen.
//
// There are no separate "pages"; Idle and Authenticating are states of one
// scene, so the transition between them is a continuous cross-fade of the
// same objects rather than a hard page swap.
Window {
    id: root

    color: "#000000"
    visibility: Window.FullScreen
    title: "Lumina Lock"

    readonly property real u: height / 1080
    property bool unlocking: false

    // Grabbing live video frames for a shader blur is unreliable across Qt
    // video backends, so blur is only enabled for static image wallpapers.
    readonly property bool blurAvailable: !WallpaperManager.isVideo

    // --- Wallpaper (bottom) ---
    WallpaperHost {
        id: wallpaperHost
        anchors.fill: parent
        playVideo: true
    }

    // Soft blur over the wallpaper while authenticating.
    MultiEffect {
        id: blur
        anchors.fill: parent
        source: wallpaperHost
        blurEnabled: content.blurAmount > 0.001
        blurMax: 40
        blur: content.blurAmount
        autoPaddingEnabled: false
        visible: root.blurAvailable && content.blurAmount > 0.001
    }

    // Dim layer.
    Rectangle {
        id: dim
        anchors.fill: parent
        color: "#05070D"
        opacity: content.dimOpacity
    }

    // Top/bottom scrim for text legibility over any wallpaper.
    Rectangle {
        id: scrim
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.32) }
            GradientStop { position: 0.22; color: "transparent" }
            GradientStop { position: 0.78; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.42) }
        }
    }

    // --- Content (owns the state machine, since only Item has state/states) ---
    Item {
        id: content
        anchors.fill: parent

        property real dimOpacity: 0
        property real blurAmount: 0
        property real clockOffset: 0
        property real authReveal: 0

        // Toggled off while a re-lock resets the scene, so the layout snaps
        // back to Idle instantly instead of animating from the previous state.
        property bool animating: true

        state: "Idle"

        ClockView {
            id: clock
            unit: root.u
            compact: content.state !== "Idle"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: content.clockOffset
        }

        AuthView {
            id: auth
            unit: root.u
            reveal: content.authReveal
            authenticating: LockSession.authenticating
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.height * 0.14
            onSubmit: (password) => root.submit(password)
            onCancel: root.returnToIdle()
        }

        Text {
            id: hint
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.height * 0.06
            text: "Press any key or click to unlock"
            color: Theme.textTertiary
            font.family: Theme.fontFamily
            font.pixelSize: 13 * root.u
            opacity: content.state === "Idle" ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 250 }
            }
        }

        states: [
            State {
                name: "Idle"
                PropertyChanges { target: content; dimOpacity: 0 }
                PropertyChanges { target: content; blurAmount: 0 }
                PropertyChanges { target: content; clockOffset: 0 }
                PropertyChanges { target: content; authReveal: 0 }
            },
            State {
                name: "Authenticating"
                PropertyChanges { target: content; dimOpacity: 0.42 }
                PropertyChanges { target: content; blurAmount: 0.75 }
                PropertyChanges { target: content; clockOffset: -root.height * 0.16 }
                PropertyChanges { target: content; authReveal: 1 }
            }
        ]

        Behavior on dimOpacity {
            enabled: content.animating
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on blurAmount {
            enabled: content.animating
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        Behavior on clockOffset {
            enabled: content.animating
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        Behavior on authReveal {
            enabled: content.animating
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    // --- Wake input (click / swipe-up) ---
    MouseArea {
        id: wakeArea
        anchors.fill: parent
        enabled: content.state === "Idle" && !root.unlocking
        property real pressY: 0
        onPressed: (mouse) => pressY = mouse.y
        onClicked: root.wake()
        onReleased: (mouse) => {
            if (content.state === "Idle" && mouse.y < pressY - 60 * root.u)
                root.wake()
        }
    }

    // --- Keyboard wake ---
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        enabled: content.state === "Idle"
        Keys.onPressed: (event) => {
            if (content.state === "Idle")
                root.wake()
        }
    }

    function wake() {
        if (root.unlocking)
            return
        content.state = "Authenticating"
        auth.focusField()
    }

    function returnToIdle() {
        if (root.unlocking)
            return
        auth.clearError()
        content.state = "Idle"
        keyCatcher.forceActiveFocus()
    }

    function submit(password) {
        if (root.unlocking || password.length === 0)
            return
        LockSession.authenticate(password)
    }

    function beginUnlock() {
        if (root.unlocking)
            return
        root.unlocking = true
        unlockAnim.start()
    }

    // Re-lock: snap the scene back to Idle and restore full opacity before
    // (or as) the surfaces are shown again.
    function resetForLock() {
        content.animating = false
        root.unlocking = false
        content.state = "Idle"
        content.dimOpacity = 0
        content.blurAmount = 0
        content.clockOffset = 0
        content.authReveal = 0
        root.opacity = 1
        content.scale = 1
        auth.reset()
        keyCatcher.forceActiveFocus()
        content.animating = true
    }

    // Natural exit: fade the whole surface and scale the content slightly,
    // then notify the session.
    SequentialAnimation {
        id: unlockAnim
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "opacity"; to: 0
                duration: 440; easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                target: content; property: "scale"; to: 1.04
                duration: 440; easing.type: Easing.InOutCubic
            }
        }
        ScriptAction { script: LockSession.unlock() }
    }

    Connections {
        target: LockSession
        function onLockedChanged(locked) {
            if (locked)
                root.resetForLock()
        }
        function onAuthenticationFinished(success, message) {
            if (success) {
                root.beginUnlock()
            } else {
                auth.errorText = message
                auth.clearAndShake()
            }
        }
    }

    Component.onCompleted: {
        keyCatcher.forceActiveFocus()
    }
}
