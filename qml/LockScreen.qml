import QtQuick
import QtQuick.Effects
import Lumina 1.0
import "components"

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

    // Warm-up for the full-screen blur, performed once, after the entry
    // animation has settled. See the effect below for why it is needed and why
    // it has to happen at a moment when nothing else is animating.
    property bool blurWarmed: false
    property bool warmupActive: false
    property int warmupFrames: 0
    readonly property bool blurWarmup: root.warmupActive
    onFrameSwapped: {
        if (!root.warmupActive)
            return
        if (++root.warmupFrames >= 3) {
            root.warmupActive = false
            root.blurWarmed = true
        }
    }

    Timer {
        id: warmupDelay
        interval: 700
        onTriggered: {
            root.warmupFrames = 0
            root.warmupActive = true
        }
    }

    Connections {
        target: content
        function onSceneReadyChanged() {
            if (content.sceneReady && !root.blurWarmed)
                warmupDelay.restart()
        }
    }

    // --- Wallpaper (bottom) ---
    WallpaperHost {
        id: wallpaperHost
        anchors.fill: parent
        playVideo: true
    }

    // Soft blur over the wallpaper while authenticating.
    //
    // `blurEnabled` stays true from startup so this effect's blur items exist
    // and stay sized, and it is *drawn* for a few frames once the entry has
    // settled (at amount 0, which is a plain copy of the wallpaper) so the
    // level-3 blur shader is compiled and its multi-level FBO chain allocated
    // up front.
    //
    // Three timings were measured, and only one of them is acceptable:
    //   - lazily, on the first transition: froze that transition for ~150 ms
    //     (9 identical frames), because the shader compile and FBO allocation
    //     land inside the animation;
    //   - for the first frames the window renders: the *entry* then stutters,
    //     because the blur chain runs even at amount 0, so drawing it costs a
    //     full-screen multi-level blur on every one of those frames;
    //   - after the entry has settled (what this does): the cost is paid while
    //     the scene is static, where nobody can see it.
    // Leaving it drawn permanently is worse still: a video wallpaper dirties
    // the scene every frame, and an always-visible full-screen blur then runs
    // on every idle frame (~2.9 cores of software rasterisation, measured,
    // versus none for a static wallpaper).
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
            revealed: content.sceneReady
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: content.clockOffset
            opacity: content.sceneReady ? 1 : 0
            MotionBehavior on opacity { duration: 480; active: content.animating }
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

            // Rises into place while it fades in, then breathes gently, so the
            // prompt reads as alive instead of as a static label.
            property real reveal: content.state === "Idle" && content.sceneReady ? 1 : 0
            property real breathe: 1

            anchors.bottomMargin: root.height * 0.06 + (1 - hint.reveal) * 14 * root.u
            text: "Press any key or click to unlock"
            color: Theme.textTertiary
            font.family: Theme.fontFamily
            font.pixelSize: 13 * root.u
            opacity: hint.reveal * hint.breathe

            MotionBehavior on reveal { active: content.animating }

            SequentialAnimation on breathe {
                loops: Animation.Infinite
                running: hint.reveal > 0.01
                NumberAnimation { to: 0.45; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 1500; easing.type: Easing.InOutSine }
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

        MotionBehavior on dimOpacity { active: content.animating }
        MotionBehavior on blurAmount { active: content.animating }
        MotionBehavior on clockOffset { active: content.animating }
        MotionBehavior on authReveal { active: content.animating }
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
            if (content.state !== "Idle")
                return
            root.wake(root.printableText(event))
            event.accepted = true
        }
    }

    function wake(initialText) {
        if (root.unlocking)
            return
        content.state = "Authenticating"
        auth.focusField(initialText)
    }

    // The text a key press would have produced, or "" for anything that should
    // not land in a password (modifiers, Return, Tab, ...).
    function printableText(event) {
        if (event.text.length === 0)
            return ""
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return ""
        for (let i = 0; i < event.text.length; ++i) {
            const code = event.text.charCodeAt(i)
            if (code < 0x20 || code === 0x7f)
                return ""
        }
        return event.text
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
            duration: 220
            easing.bezierCurve: Theme.motionCurve
        }
        NumberAnimation {
            target: root; property: "opacity"; to: 0
            duration: 280
            easing.bezierCurve: Theme.motionCurve
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
                auth.playSuccess()
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
