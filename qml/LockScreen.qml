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

    // Frames rendered so far; the warm-up only has to happen once per window,
    // since Qt keeps the compiled program for the renderer's lifetime.
    // Counting *frames* rather than using a timer matters: the window's first
    // paint can land later than any wall clock window would allow for, and a
    // warm-up that ends before the first frame never draws the effect at all.
    property int warmupFrames: 0
    readonly property bool blurWarmup: root.warmupFrames < 12
    onFrameSwapped: if (root.warmupFrames < 12) root.warmupFrames++

    // --- Wallpaper (bottom) ---
    WallpaperHost {
        id: wallpaperHost
        anchors.fill: parent
        playVideo: true
    }

    // Soft blur over the wallpaper while authenticating.
    //
    // `blurEnabled` stays true from startup so this effect's blur items exist
    // and stay sized, and it is *drawn* for the first frames the window renders
    // (at amount 0, which is a plain copy of the wallpaper) so the level-3 blur
    // shader is compiled and its multi-level FBO chain allocated up front.
    //
    // Both matter: turning the effect on for the first time inside the
    // Idle -> Authenticating transition froze the animation for ~150 ms
    // (measured: 9 identical frames). But leaving it drawn permanently is worse
    // in the other direction — a video wallpaper dirties the scene every frame,
    // and an always-visible full-screen blur then runs on every idle frame
    // (measured: ~5 cores of software rasterisation versus none for a static
    // wallpaper).
    MultiEffect {
        id: blur
        anchors.fill: parent
        source: wallpaperHost
        blurEnabled: true
        blurMax: 40
        blur: content.blurAmount
        autoPaddingEnabled: false
        visible: root.blurWarmup || content.blurAmount > 0.001
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

        // Entry staging: the clock (and the glass behind it) only fades in once
        // the wallpaper has something to draw, so nothing pops in over a
        // half-decoded image.
        property bool sceneReady: false

        state: "Idle"

        ClockView {
            id: clock
            unit: root.u
            compact: content.state !== "Idle"
            glassSource: wallpaperHost
            glassRefreshToken: wallpaperHost.ready ? 1 : 0
            glassLive: WallpaperManager.isVideo
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: content.clockOffset
            opacity: content.sceneReady ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
            }
        }

        AuthView {
            id: auth
            unit: root.u
            reveal: content.authReveal
            authenticating: LockSession.authenticating
            glassSource: wallpaperHost
            glassRefreshToken: wallpaperHost.ready ? 1 : 0
            glassLive: WallpaperManager.isVideo
            glassDim: content.dimOpacity
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
            opacity: content.state === "Idle" && content.sceneReady ? 1 : 0
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
            NumberAnimation { duration: Theme.motionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on blurAmount {
            enabled: content.animating
            NumberAnimation { duration: Theme.motionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on clockOffset {
            enabled: content.animating
            NumberAnimation { duration: Theme.motionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on authReveal {
            enabled: content.animating
            NumberAnimation { duration: Theme.motionDuration; easing.type: Easing.OutCubic }
        }
    }

    // Entry staging. Polls instead of binding so the clock can wait for the
    // wallpaper yet still appear on a short fixed beat, with a hard deadline so
    // a wallpaper that never loads cannot leave the clock hidden.
    Timer {
        id: entryTimer
        interval: 240
        repeat: true
        property int ticks: 0
        onTriggered: {
            ++ticks
            if (!content.sceneReady && (wallpaperHost.ready || ticks >= 4)) {
                content.sceneReady = true
                stop()
            }
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
    // (or as) the surfaces are shown again, then replay the entry staging.
    function resetForLock() {
        content.animating = false
        root.unlocking = false
        content.state = "Idle"
        content.dimOpacity = 0
        content.blurAmount = 0
        content.clockOffset = 0
        content.authReveal = 0
        content.opacity = 1
        content.sceneReady = false
        root.opacity = 1
        auth.reset()
        keyCatcher.forceActiveFocus()
        entryTimer.ticks = 0
        entryTimer.restart()
        content.animating = true
    }

    // Natural exit: drop the content first (cheap — it takes the large clock
    // type off screen), then fade the window so the desktop shows through.
    // Deliberately no content scaling: rescaling the clock every frame while
    // the wallpaper was still landing is what made this stutter.
    SequentialAnimation {
        id: unlockAnim
        NumberAnimation {
            target: content; property: "opacity"; to: 0
            duration: 220; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "opacity"; to: 0
            duration: 280; easing.type: Easing.OutCubic
        }
        ScriptAction { script: LockSession.unlock() }
    }

    Connections {
        target: LockSession
        function onLockedChanged(locked) {
            if (locked)
                root.resetForLock()
        }
        function onShowAuthRequested() {
            root.wake()
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
        entryTimer.start()
    }
}
