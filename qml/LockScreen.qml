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

    // Visibility is owned by ScreenManager (showFullScreen / hide). Declaring
    // `visibility: Window.FullScreen` here fights that: the window states what it
    // wants to be, so hiding it from C++ does not stick and an empty window is
    // left mapped over the desktop after the first unlock.
    color: "#000000"

    // dde-lock parity: on X11 the lock windows are unmanaged and always on top,
    // so nothing can raise itself over the lock and the deepin WM does not
    // animate them. Declared here rather than set from C++: setting window flags
    // makes Qt destroy and recreate the native window, and whether the window
    // manager has already decided to manage it then depends on how that
    // recreation lines up with the mapping — the same race that made the power
    // menu animate open only some of the time. X11BypassWindowManagerHint means
    // nothing on Wayland and is ignored there.
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.X11BypassWindowManagerHint
    title: "Lumina Lock"

    readonly property real u: height / 1080
    property bool unlocking: false

    // Every screen runs this surface; exactly one of them carries the
    // interactive authentication UI at a time. Which one is global state owned
    // by ScreenManager (`Screens.authScreenName`) and is chosen by where the
    // user interacts: a click activates the screen that was clicked, a key
    // press activates the screen the pointer is on. All the other screens stay
    // in Idle — wallpaper, clock, hint — and can be woken at any moment.
    readonly property string screenName: root.screen ? root.screen.name : ""
    readonly property bool isAuthScreen: Screens.authScreenName.length > 0
                                         && Screens.authScreenName === root.screenName

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
        // 1 = 时间日期在场，0 = 认证时完全隐去。和 authReveal 反向，用同一套
        // MotionBehavior 驱动：密码框升起的同时时间日期上移淡出，收起时下移淡入。
        property real clockReveal: 1
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
            // 时间/日期位置：0 = 贴左/上边缘，50 = 居中（默认），100 = 贴右/下边缘。
            // 认证时**在这一份上渐隐**（同时按原设计上移 16%），而在标准位置（屏幕
            // 正中）上另有一份渐显 —— 两份同时进行，看起来就是"移到中间去了"。
            // 不做越界夹取：夹取会让位移量随字号和动画过程变化，看着就是顿。
            readonly property bool atCenter: Math.abs(LockAppearance.clockPositionX - 0.5) < 0.001
                                             && Math.abs(LockAppearance.clockPositionY - 0.5) < 0.001
            anchors.horizontalCenterOffset: (parent.width - clock.width)
                                            * (LockAppearance.clockPositionX - 0.5)
            anchors.verticalCenterOffset: (parent.height - clock.height)
                                          * (LockAppearance.clockPositionY - 0.5)
                                          + content.clockOffset
            // 位置没调过（就是默认正中）时保持原来的动画：只上移 16%，不淡出；
            // 调过位置时才有"这里渐隐 + 正中渐显"的交叉。
            opacity: content.sceneReady ? (atCenter ? 1 : content.clockReveal) : 0
            MotionBehavior on opacity { duration: 480; active: content.animating }
        }

        // 标准位置（屏幕正中）上的那一份：认证时在这里渐显，和上面那份的渐隐同时
        // 进行。位置本来就是正中时不用它 —— 两份重叠会看出重影。
        ClockView {
            id: clockCentered
            visible: !clock.atCenter
            unit: root.u
            compact: content.state !== "Idle"
            glassSource: wallpaperHost
            glassRefreshToken: wallpaperHost.ready ? 1 : 0
            glassLive: WallpaperManager.isVideo
            revealed: content.sceneReady
            anchors.centerIn: parent
            opacity: content.sceneReady ? content.authReveal : 0
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
                PropertyChanges { target: content; clockReveal: 1 }
                PropertyChanges { target: content; authReveal: 0 }
            },
            State {
                name: "Authenticating"
                PropertyChanges { target: content; dimOpacity: 0.42 }
                PropertyChanges { target: content; blurAmount: 0.75 }
                PropertyChanges { target: content; clockOffset: -root.height * 0.16 }
                PropertyChanges { target: content; clockReveal: 0 }
                PropertyChanges { target: content; authReveal: 1 }
            }
        ]

        MotionBehavior on dimOpacity { active: content.animating }
        MotionBehavior on blurAmount { active: content.animating }
        MotionBehavior on clockOffset { active: content.animating }
        MotionBehavior on clockReveal { active: content.animating }
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
    // Only an idle screen takes clicks: on the active screen this area is
    // disabled so the clicks reach the password field underneath it.
    MouseArea {
        id: wakeArea
        anchors.fill: parent
        enabled: !root.isAuthScreen && !root.unlocking
        property real pressY: 0
        onPressed: (mouse) => pressY = mouse.y
        onClicked: root.wake()
        onReleased: (mouse) => {
            if (content.state === "Idle" && mouse.y < pressY - 60 * root.u)
                root.wake()
        }
    }

    // --- Session controls (bottom right) ---
    // Two things have to be reachable without unlocking: shutting the machine
    // down, and handing the seat to someone else. They sit in the bottom-right
    // corner because that is where session controls are looked for, because the
    // corners are the only part of this layout nothing else wants — the clock and
    // the password panel are both centred — and because the scrim already
    // darkens the bottom of the screen, so they stay legible over any wallpaper.
    //
    // They belong to the password screen, not to the idle lock: idle is the
    // wallpaper and the clock, and nothing else. So they pop up when the field
    // does and drop away with it.
    //
    // Declared after the wake area so that a click here is a click on the
    // control and not a wake-up.
    Row {
        id: sessionControls
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.height * 0.045
        anchors.bottomMargin: root.height * 0.045
        spacing: 14 * root.u
        z: 10

        Repeater {
            model: [
                { action: "switchUser", icon: "user" },
                { action: "power", icon: "power" }
            ]

            delegate: Rectangle {
                id: control
                required property int index
                required property var modelData

                width: 36 * root.u
                height: width
                radius: width / 2
                antialiasing: true
                // Opacity, not visibility. A Row skips invisible children when
                // it lays out, so hiding this until it arrives lets the other
                // one take the empty place — and since the row is anchored to the
                // right edge, the one that arrives first appears where the second
                // belongs and is then pushed out of it. Both stay in the layout
                // from the start; only the click area is switched off while a
                // button is not really there.
                opacity: control.entrance
                color: hover.hovered ? Qt.rgba(1, 1, 1, 0.26) : Theme.surface
                border.width: 1 * root.u
                border.color: hover.hovered ? Theme.surfaceBorderFocus : Theme.controlBorder
                scale: hover.hovered ? 1.08 : 1
                transform: Translate { y: (1 - control.entrance) * 26 * root.u }

                // ColorAnimation, not MotionBehavior: that one is a
                // NumberAnimation and would interpolate a color as a number,
                // which lands on black. Scale is a number, so the shared
                // transition is fine there.
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }
                MotionBehavior on scale { duration: 160 }

                // The tail, on a beat. The field lands first — it has its own
                // 320 ms reveal — and these follow a third of a second later, so
                // the screen has one thing arriving and then something trailing
                // it, rather than three things moving at once. The 55 ms between
                // the two is what makes it a whip: not together, and not one
                // after the other either.
                property real entrance: 0
                Timer {
                    interval: 300 + control.index * 55
                    running: content.state !== "Idle"
                    onTriggered: popIn.restart()
                }
                Connections {
                    target: content
                    function onStateChanged() {
                        if (content.state === "Idle")
                            control.entrance = 0
                    }
                }
                NumberAnimation {
                    id: popIn
                    target: control
                    property: "entrance"
                    from: 0
                    to: 1
                    duration: 420
                    // Overshoot: it rises past where it belongs and settles back
                    // into it, which is what makes it pop up rather than slide.
                    easing.type: Easing.OutBack
                }

                PowerIcon {
                    anchors.centerIn: parent
                    name: control.modelData.icon
                    size: 22 * root.u
                    color: Theme.textPrimary
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: control.entrance > 0.5
                    onClicked: {
                        if (control.modelData.action === "power")
                            Power.show()
                        else
                            Power.switchUser()
                    }
                }
            }
        }
    }

    // --- Keyboard wake ---
    // There is no key handler here on purpose. The X11 grab delivers every
    // keystroke to the one window that holds it, so the decision of *which*
    // screen a key press belongs to is made in ScreenManager::eventFilter(),
    // which knows where the pointer is; while this screen owns the field its
    // own key events are simply let through to the password input.

    function wake(initialText) {
        if (root.unlocking)
            return
        if (!root.isAuthScreen) {
            // Hand the interactive UI to this screen. The resulting
            // authScreenChanged re-enters wake() with the state settled, so
            // there is exactly one code path that reveals the field.
            Screens.activateAuthForScreen(root.screenName)
            return
        }
        content.state = "Authenticating"
        auth.focusField(initialText)
    }

    function returnToIdle() {
        if (root.unlocking)
            return
        auth.clearError()
        content.state = "Idle"
        // Escape drops the field everywhere, so no screen keeps showing it.
        if (root.isAuthScreen)
            Screens.clearAuth()
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
        // Keystrokes from here on belong to the desktop that is about to
        // appear, not to the lock.
        Screens.setInteractive(false)
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
        content.clockReveal = 1
        content.authReveal = 0
        content.opacity = 1
        content.sceneReady = false
        root.opacity = 1
        auth.reset()
        Screens.setInteractive(true)
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
        function onAuthenticationFinished(success, message) {
            if (success) {
                // Every screen plays the exit fade (the desktop has to appear
                // on all of them); only the one holding the field shows the
                // accepted-password feedback.
                if (root.isAuthScreen)
                    auth.playSuccess()
                root.beginUnlock()
            } else if (root.isAuthScreen) {
                auth.errorText = message
                auth.clearAndShake()
            }
        }
    }

    // Which screen carries the interactive UI is global state (ScreenManager):
    // the screen that just got it reveals the field, every other one drops back
    // to Idle — including dropping a half-typed password it must not keep.
    Connections {
        target: Screens
        function onAuthScreenChanged() {
            if (root.isAuthScreen) {
                if (!root.unlocking)
                    root.wake(Screens.takePendingText())
            } else if (!root.unlocking) {
                auth.reset()
                root.returnToIdle()
            }
        }
    }

    Component.onCompleted: {
        entryTimer.start()
    }
}
