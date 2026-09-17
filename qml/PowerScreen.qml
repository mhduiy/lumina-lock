import QtQuick
import QtQuick.Shapes
import Lumina 1.0
import "components"

// The power menu: a slide-to-power-off control over a row of buttons.
//
// The shape of it follows from what each action costs. Shutting down is the only
// thing here that cannot be taken back, so it is the only thing behind a gesture
// that has to be carried through — pull the knob to the far end and let go, or
// hold Enter — and the whole screen dims as the knob travels, so the price of
// the gesture is visible instead of described. Restart is the other
// irreversible one: it is a button, but a button that counts, holding fills a
// ring around it and letting go switches it off. Everything else acts on the
// press, because everything else can be undone.
//
// The menu draws in its own window (see PowerWindow.qml), so it never inherits
// the lock's window lifecycle — the surfaces the lock owns are hidden and
// re-shown around every unlock and do not always come back cleanly.
Item {
    id: root
    anchors.fill: parent

    property bool shown: false
    // True when this is being shown over an unlocked session: the surfaces it
    // borrows are brought up at the same moment, and the desktop behind is what
    // the slide dims, so the covers snap rather than fade.
    property bool instant: false
    property real unit: 1
    property Item glassSource: null
    property string note: ""

    signal activated(string key)

    // 0 = the slider, 1 = the buttons. Opening focuses the first *button*, never
    // the slider: a default selection is a guess at intent, and the only guess
    // worth making is the cheapest thing on the screen. Shutting down is not one
    // keystroke away from an idle press.
    property int focusRow: 1
    property int currentIndex: 0
    property string heldKey: ""
    property bool firing: false
    property string pendingKey: ""

    // How long a button has to be held before it acts, and how long the slider
    // takes to fill under the keyboard. Both are "keep doing it or it stops".
    readonly property int holdDuration: 900
    readonly property int slideDuration: 1100

    // Shutdown is the slider, so it is not in the row. Everything the machine
    // cannot do is already absent — the backend leaves those out rather than
    // handing over a disabled entry to draw.
    readonly property var split: {
        const buttons = []
        let shutdown = null
        const all = Power.options
        for (let i = 0; i < all.length; ++i) {
            if (all[i].key === "shutdown")
                shutdown = all[i]
            else
                buttons.push(all[i])
        }
        return { buttons: buttons, shutdown: shutdown }
    }
    readonly property var buttons: split.buttons
    readonly property var shutdown: split.shutdown
    readonly property var current: buttons.length > 0
                                   ? buttons[Math.min(currentIndex, buttons.length - 1)]
                                   : null

    // The slider and the buttons are one block, so the slider is exactly as wide
    // as the row it sits over — a wide bar over a narrow set of buttons reads as
    // two unrelated things stacked up. The floor keeps it from collapsing when
    // the machine offers only one or two actions.
    readonly property real controlWidth: Math.min(
        Math.max(buttons.length * 64 * root.unit
                 + Math.max(0, buttons.length - 1) * 14 * root.unit,
                 300 * root.unit),
        root.width * 0.8)

    visible: shown || opacity > 0.001
    opacity: shown ? 1 : 0
    // `active: false` rather than `duration: 0`: a zero-length animation is not
    // guaranteed to land the value at all, and an opacity that never arrives
    // leaves a surface that is logically up and visually absent.
    MotionBehavior on opacity { active: !root.instant; duration: 240 }

    // --- backdrop -----------------------------------------------------------
    // Deliberately translucent: the desktop, or the lock's own wallpaper, stays
    // visible behind it, because the slide below dims *that*. A dim you cannot
    // see is not a confirmation of anything.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.06, 1)
        opacity: root.shown ? 0.42 : 0
        MotionBehavior on opacity { active: !root.instant; duration: 300 }
        // Blank space is "get me out of here": clicking past the controls
        // dismisses the menu.
        MouseArea {
            anchors.fill: parent
            onClicked: Power.dismiss()
        }
    }

    // What the slide pulls down. The darker it gets, the closer the machine is
    // to going away — this is the whole confirmation, so it is tied to the
    // knob's travel and to nothing else.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: slider.progress * 0.55
    }

    // --- content ------------------------------------------------------------
    // One wrapper so the press can dim everything at once, without the group
    // entrance and the per-item stagger having to share a property.
    Item {
        id: content
        anchors.fill: parent
        opacity: root.firing ? 0.22 : 1
        MotionBehavior on opacity { duration: 160 }

        Column {
            id: column
            anchors.centerIn: parent
            width: root.controlWidth
            spacing: 0
            property real entrance: root.shown ? 1 : 0
            MotionBehavior on entrance { duration: 300 }
            transform: Translate { y: (1 - column.entrance) * 30 * root.unit }

            // --- slide to power off ----------------------------------------
            Item {
                id: slider
                width: parent.width
                height: 60 * root.unit
                // A machine that cannot be powered off gets no slider. An
                // invisible child is skipped by the Column, so the row closes up.
                visible: root.shutdown !== null

                readonly property real inset: 5 * root.unit
                readonly property real knobSize: height - inset * 2
                readonly property real travel: width - knobSize - inset * 2
                readonly property bool focused: root.focusRow === 0
                property real progress: 0

                // Where the knob is is the state; nothing else tracks it.
                function begin() {
                    if (root.firing)
                        return
                    fillAnim.restart()
                }

                function end() {
                    fillAnim.stop()
                    if (progress >= 0.97) {
                        root.fire("shutdown")
                        return
                    }
                    progress = 0 // springs back
                }

                // A drag is 1:1 with the pointer — smoothing it would make the
                // knob lag the finger. The animation is for the spring-back and
                // for the keyboard fill.
                MotionBehavior on progress {
                    active: !drag.dragging && !fillAnim.running
                    duration: 240
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    antialiasing: true
                    color: Qt.rgba(1, 1, 1, 0.055)
                    border.width: 1 * root.unit
                    border.color: slider.focused ? Theme.surfaceBorderFocus : Theme.surfaceBorder
                    MotionBehavior on border.color { duration: 200 }
                }

                // What has been pulled across so far, under the knob.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: slider.inset + slider.knobSize + slider.travel * slider.progress
                    radius: height / 2
                    antialiasing: true
                    color: Qt.rgba(0.56, 0.66, 0.94, 0.08 + 0.26 * slider.progress)
                }

                Text {
                    anchors.centerIn: parent
                    // The label carries the update merge: "关机" on a machine
                    // with nothing to install, "更新并关机" when lastore has
                    // something to run first.
                    text: qsTr("滑动以") + root.shutdown.label
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15 * root.unit
                    font.letterSpacing: 1.5 * root.unit
                    // Gone by the time the knob is halfway: a gesture should not
                    // have to be read while it is being performed.
                    opacity: Math.max(0, 1 - slider.progress * 2.4)
                }

                Rectangle {
                    id: knob
                    width: slider.knobSize
                    height: slider.knobSize
                    x: slider.inset + slider.travel * slider.progress
                    anchors.verticalCenter: parent.verticalCenter
                    radius: width / 2
                    antialiasing: true
                    color: Qt.rgba(1, 1, 1, 0.10 + 0.10 * slider.progress)
                    border.width: 1 * root.unit
                    border.color: slider.progress > 0.02 ? Theme.accent : Theme.surfaceBorder

                    PowerIcon {
                        anchors.centerIn: parent
                        name: "power"
                        size: 26 * root.unit
                        color: slider.progress > 0.02 ? Theme.textPrimary : Theme.textSecondary
                    }
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    property bool dragging: false

                    // Follows the pointer rather than dragging the knob: a drag
                    // target writes x imperatively and would break the binding
                    // that the keyboard fill drives.
                    function place(mx) {
                        slider.progress = Math.max(0, Math.min(1,
                            (mx - slider.inset - slider.knobSize / 2) / slider.travel))
                    }

                    onPressed: (mouse) => { dragging = true; place(mouse.x) }
                    onPositionChanged: (mouse) => { if (dragging) place(mouse.x) }
                    onReleased: { dragging = false; slider.end() }
                    onCanceled: { dragging = false; slider.end() }
                }

                NumberAnimation {
                    id: fillAnim
                    target: slider
                    property: "progress"
                    from: 0
                    to: 1
                    duration: root.slideDuration
                    easing.type: Easing.InOutSine
                    onFinished: if (slider.progress >= 0.999) root.fire("shutdown")
                }
            }

            Item {
                width: parent.width
                height: 30 * root.unit
                visible: root.shutdown !== null
            }

            // --- the buttons -----------------------------------------------
            Row {
                id: buttonRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14 * root.unit

                Repeater {
                    id: repeater
                    model: root.buttons

                    delegate: Item {
                        id: button
                        required property int index
                        required property var modelData

                        readonly property bool selected: root.focusRow === 1
                                                         && root.currentIndex === button.index
                        readonly property bool dangerous: button.modelData.kind === "danger"
                        readonly property bool held: root.heldKey === button.modelData.key

                        width: 64 * root.unit
                        height: width + 26 * root.unit

                        // One animated value per button drives the ring, so the
                        // countdown and the action cannot drift apart.
                        property real hold: 0
                        property real entrance: 0

                        MotionBehavior on entrance { duration: 240 }
                        MotionBehavior on hold { active: !ringAnim.running; duration: 180 }

                        // A fresh hold always counts from the start: cancelling
                        // one and starting again must not resume where the last
                        // one stopped, which reads as the countdown being flaky.
                        onHeldChanged: {
                            if (held) {
                                hold = 0
                                ringAnim.restart()
                            } else {
                                ringAnim.stop()
                                hold = 0
                            }
                        }

                        // The stagger is a timer per button rather than a delay
                        // on MotionBehavior, which keeps the shared component a
                        // plain transition.
                        Timer {
                            interval: Math.min(button.index, 6) * 22
                            running: root.shown
                            onTriggered: button.entrance = 1
                        }
                        Connections {
                            target: root
                            function onShownChanged() { if (!root.shown) button.entrance = 0 }
                        }

                        opacity: button.entrance
                        transform: Translate { y: (1 - button.entrance) * 18 * root.unit }

                        Rectangle {
                            id: disc
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: parent.width
                            radius: width / 2
                            // A circular control with a border is jagged
                            // without this.
                            antialiasing: true
                            color: Theme.surface
                            border.width: 1 * root.unit
                            border.color: button.selected ? Theme.surfaceBorderFocus : Theme.surfaceBorder
                            scale: button.selected ? 1.06 : 1
                            MotionBehavior on border.color { duration: 200 }
                            MotionBehavior on scale { duration: 200 }

                            PowerIcon {
                                anchors.centerIn: parent
                                name: button.modelData.icon
                                size: 26 * root.unit
                                color: button.selected ? Theme.textPrimary : Theme.textSecondary
                            }
                        }

                        // The countdown, as a ring around the disc rather than a
                        // bar inside it: the hold *is* the gesture, so its
                        // progress should trace the thing being held.
                        Shape {
                            anchors.fill: disc
                            visible: button.hold > 0.001

                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 2.4 * root.unit
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: disc.width / 2
                                    centerY: disc.height / 2
                                    radiusX: disc.width / 2 - 1.4 * root.unit
                                    radiusY: disc.height / 2 - 1.4 * root.unit
                                    startAngle: -90
                                    sweepAngle: 360 * button.hold
                                }
                            }
                        }

                        Text {
                            anchors.top: disc.bottom
                            anchors.topMargin: 7 * root.unit
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: button.modelData.label
                            color: button.selected ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12 * root.unit
                            MotionBehavior on color { duration: 200 }
                        }

                        NumberAnimation {
                            id: ringAnim
                            target: button
                            property: "hold"
                            from: 0
                            to: 1
                            duration: root.holdDuration
                            onFinished: if (button.held) root.fire(button.modelData.key)
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { root.focusRow = 1; root.currentIndex = button.index }
                            onPressed: {
                                root.focusRow = 1
                                root.currentIndex = button.index
                                // A dangerous button starts counting here and
                                // only here; a quick click never arms it.
                                if (button.dangerous)
                                    root.heldKey = button.modelData.key
                            }
                            onReleased: { if (button.held) root.heldKey = "" }
                            onClicked: { if (!button.dangerous) root.fire(button.modelData.key) }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 20 * root.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.note
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: 12 * root.unit
                opacity: root.note.length > 0 ? 1 : 0
                MotionBehavior on opacity { duration: 200 }
            }

            Item { width: parent.width; height: 12 * root.unit }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("↑↓ 切换    ←→ 选择    按住确认    Esc 取消")
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 11 * root.unit
                font.letterSpacing: 1 * root.unit
                opacity: 0.7
            }
        }
    }

    // The window is hidden once this has played. A timer rather than an
    // animation's finished signal because the exit is several fades at once; it
    // only has to outlast the longest of them.
    Timer {
        interval: 340
        running: !root.shown
        onTriggered: Power.exitFinished()
    }

    // --- keys ---------------------------------------------------------------
    // The lock routes nothing here: while the menu is up it is the focused item,
    // so the keys the window already receives land on it. Anything it does not
    // handle is let through, which is what keeps Escape-means-cancel working
    // through one code path.
    focus: true
    Keys.onPressed: (event) => {
        if (!root.shown || root.firing)
            return
        // A held key is one press, not a burst of them: the hold below is what
        // decides, and auto-repeat would restart it continuously.
        if (event.isAutoRepeat) {
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down) {
            if (root.focusRow === 0) {
                root.focusRow = 1
                root.announce()
            }
        } else if (event.key === Qt.Key_Up) {
            if (root.focusRow === 1) {
                root.focusRow = 0
                Power.highlight("shutdown")
            }
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            if (root.focusRow === 1)
                root.moveSelection(event.key === Qt.Key_Right ? 1 : -1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            if (root.focusRow === 0)
                slider.begin()
            else
                root.press()
        } else if (event.key === Qt.Key_Escape) {
            Power.dismiss()
        } else {
            return
        }
        event.accepted = true
    }

    Keys.onReleased: (event) => {
        if (!root.shown)
            return
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
                && event.key !== Qt.Key_Space)
            return
        event.accepted = true
        if (event.isAutoRepeat)
            return
        if (root.focusRow === 0)
            slider.end()
        else
            root.heldKey = "" // letting go is cancelling
    }

    // --- behaviour ----------------------------------------------------------
    onShownChanged: {
        if (shown) {
            currentIndex = 0 // the cheapest button, not the slider
            focusRow = 1
            heldKey = ""
            pendingKey = ""
            firing = false
            note = ""
            slider.progress = 0
            forceActiveFocus()
        } else {
            heldKey = ""
            note = ""
        }
    }

    function moveSelection(delta) {
        if (!shown || buttons.length === 0)
            return
        // Moving is also how you take back a hold in progress.
        heldKey = ""
        currentIndex = (currentIndex + delta + buttons.length) % buttons.length
        announce()
    }

    function announce() {
        Power.highlight(current ? current.key : "")
    }

    // Enter on a button. Cheap actions happen on the press; the expensive one
    // starts counting and waits for the key to come back up.
    function press() {
        const button = current
        if (!button)
            return
        if (button.kind !== "danger") {
            fire(button.key)
            return
        }
        heldKey = button.key
    }

    // Everything that acts goes through here, so the press has one place to be
    // acknowledged. The menu stays up for a beat first: acting on the same frame
    // as the gesture gives no sign the gesture landed.
    function fire(key) {
        if (firing)
            return
        firing = true
        pendingKey = key
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: 170
        onTriggered: Power.activate(root.pendingKey)
    }

    // A press has to be let go of even when nothing came of it. If the action
    // failed, or there was nothing for it to do, the menu stays up — and with
    // `firing` still set it would stay dimmed and ignoring every key, with no
    // way back to a usable surface. Same reasoning as the window-hide fallback.
    Timer {
        interval: 1200
        running: root.firing
        onTriggered: {
            root.firing = false
            root.pendingKey = ""
        }
    }

    Connections {
        target: Power
        function onArmRequested(key) {
            // A request from elsewhere opens the menu on the control that would
            // carry it out — and stops there. Whoever is at the machine still
            // has to perform the gesture.
            if (key === "shutdown") {
                root.focusRow = 0
                return
            }
            for (let i = 0; i < root.buttons.length; ++i) {
                if (root.buttons[i].key === key) {
                    root.focusRow = 1
                    root.currentIndex = i
                    return
                }
            }
        }
        function onFailed(reason) {
            root.note = reason
        }
    }

    // One line per opening, once things have settled. If the menu is ever
    // reported as "not appearing", this says whether the scene got there and
    // what the window it draws into looked like.
    Timer {
        interval: 600
        running: root.shown
        onTriggered: console.warn("PowerScreen settled: shown", root.shown,
                                  "opacity", root.opacity.toFixed(2),
                                  "size", root.width + "x" + root.height,
                                  "buttons", root.buttons.length,
                                  "shutdown", root.shutdown ? root.shutdown.label : "-",
                                  "locked", LockSession.locked,
                                  "authScreen", Screens.authScreenName)
    }
}
