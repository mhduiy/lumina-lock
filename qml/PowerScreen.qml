import QtQuick
import Lumina 1.0
import "components"

// The power menu, as an overlay on the lock's scene.
//
// dde-lock puts this in a second window; here it is a layer, so it inherits the
// lock's input grab, its per-screen behaviour and its typography. The layout is
// deliberately not dde-lock's grid of tiles: a vertical stack, one line each,
// with the selection carried by a marker that slides rather than by a highlight
// that jumps.
//
// The backdrop is a pair of soft gradient washes that drift slowly, and the
// rows arrive one after another. Both stop the moment the menu closes — a menu
// that is not on screen must not keep the compositor awake.
Item {
    id: root
    anchors.fill: parent

    property bool shown: false
    // True when this is being shown over an unlocked session: the surfaces it
    // borrows are brought up at the same moment, and the lock's own clock starts
    // its entry reveal behind it. The covers therefore snap instead of fading —
    // otherwise the clock is visible for a beat before the menu arrives, which
    // is exactly what it looks like: a clock, then the power page.
    property bool instant: false
    property real unit: 1
    property Item glassSource: null
    property int currentIndex: 0
    property string armedKey: ""
    property string note: ""

    // How long a destructive row has to be held before it acts.
    readonly property int armDuration: 1400

    signal activated(string key)

    readonly property var rows: Power.options
    readonly property bool interactive: shown

    // Visibility follows `shown` directly, never the animated opacity: gating it
    // on an animating value is how a surface ends up interactive but invisible.
    visible: shown
    opacity: shown ? 1 : 0
    // `active: false` rather than `duration: 0`: a zero-length animation is not
    // guaranteed to land the value at all, and an opacity that never arrives
    // leaves a surface that is logically up and visually absent.
    MotionBehavior on opacity { active: !root.instant; duration: 240 }

    // The lock routes nothing here: while the menu is up it is the focused item,
    // so the keys the window already receives land on it. Anything it does not
    // handle is let through, which is what keeps Escape-means-cancel working
    // through one code path (see cancel()).
    focus: true
    Keys.onPressed: (event) => {
        if (!root.shown)
            return
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Right)
            root.moveSelection(1)
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left)
            root.moveSelection(-1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                 || event.key === Qt.Key_Space)
            root.activateSelection()
        else if (event.key === Qt.Key_Escape)
            root.cancel()
        else
            return
        event.accepted = true
    }

    // --- backdrop -----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.04, 0.08, 0.985) }
            GradientStop { position: 0.5; color: Qt.rgba(0.05, 0.07, 0.14, 0.975) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.06, 0.99) }
        }
        opacity: root.shown ? 1 : 0
        MotionBehavior on opacity { active: !root.instant; duration: 320 }
        MouseArea { anchors.fill: parent }   // swallow clicks aimed past the rows
    }

    // Two washes, rotated so their linear gradients read as soft light rather
    // than as bands, drifting in opposite directions.
    Item {
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        MotionBehavior on opacity { duration: 600 }
        clip: true

        Rectangle {
            width: root.width * 1.7
            height: root.height * 1.9
            x: -root.width * 0.35
            y: -root.height * 0.45
            rotation: 16
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(0.29, 0.42, 0.85, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            transform: Translate {
                NumberAnimation on x {
                    from: -70 * root.unit
                    to: 70 * root.unit
                    duration: 11000
                    loops: Animation.Infinite
                    running: root.shown
                    easing.type: Easing.InOutSine
                }
            }
        }

        Rectangle {
            width: root.width * 1.7
            height: root.height * 1.8
            x: -root.width * 0.3
            y: -root.height * 0.4
            rotation: -13
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(0.54, 0.36, 0.85, 0.13) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            transform: Translate {
                NumberAnimation on x {
                    from: 60 * root.unit
                    to: -60 * root.unit
                    duration: 14000
                    loops: Animation.Infinite
                    running: root.shown
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    // --- content ------------------------------------------------------------
    Column {
        id: column
        anchors.centerIn: parent
        width: Math.min(460 * root.unit, root.width * 0.74)
        spacing: 0
        // One animated value for the group's arrival: the rows stagger on top
        // of it, so the whole thing reads as one gesture.
        property real entrance: root.shown ? 1 : 0
        MotionBehavior on entrance { duration: 400 }
        opacity: column.entrance
        transform: Translate { y: (1 - column.entrance) * 28 * root.unit }

        Text {
            text: qsTr("电源")
            color: Theme.textTertiary
            font.family: Theme.fontFamily
            font.pixelSize: 13 * root.unit
            font.letterSpacing: 6 * root.unit
        }

        Item {
            width: parent.width
            height: 18 * root.unit

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.22) }
                    GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.04) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Repeater {
            id: repeater
            model: root.rows

            delegate: Item {
                id: row
                required property int index
                required property var modelData

                readonly property bool selected: root.currentIndex === row.index
                readonly property bool armed: root.armedKey === row.modelData.key
                readonly property bool usable: row.modelData.enabled !== false

                width: column.width
                height: 68 * root.unit + 12 * root.unit

                // One animated value drives the row's arrival, so the stagger
                // and the rise cannot drift apart. The stagger is a timer per
                // row rather than a delay on MotionBehavior: the shared
                // component stays a plain transition.
                property real entrance: 0
                MotionBehavior on entrance { duration: 320 }

                Timer {
                    interval: Math.min(row.index, 7) * 45
                    running: root.shown
                    onTriggered: row.entrance = 1
                }
                Connections { target: root; function onShownChanged() { if (!root.shown) row.entrance = 0 } }

                opacity: row.entrance * (row.usable ? 1 : 0.42)
                transform: Translate { y: (1 - row.entrance) * 26 * root.unit }

                Rectangle {
                    id: surface
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 68 * root.unit
                    radius: 14 * root.unit
                    color: Theme.surface
                    border.width: 1
                    border.color: row.selected ? Theme.surfaceBorderFocus : Theme.surfaceBorder
                    Behavior on border.color { ColorAnimation { duration: 240 } }

                    // The armed fill sweeps the row from the leading edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: row.armed ? parent.width : 0
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0.56, 0.66, 0.94, 0.30) }
                            GradientStop { position: 1.0; color: Qt.rgba(0.56, 0.66, 0.94, 0.08) }
                        }
                        // Long, linear: this is a countdown, not a transition.
                        Behavior on width {
                            NumberAnimation { duration: row.armed ? root.armDuration : 140 }
                        }

                        onWidthChanged: {
                            if (row.armed && width >= parent.width)
                                root.activated(row.modelData.key)
                        }
                    }

                    // Marker: slides between rows instead of blinking on one.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.unit
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3 * root.unit
                        height: (row.selected ? 26 : 10) * root.unit
                        radius: width / 2
                        opacity: row.selected ? 1 : 0.35
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Theme.accent }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.55) }
                        }
                        MotionBehavior on height { duration: 260 }
                        MotionBehavior on opacity { duration: 260 }
                    }

                    Text {
                        id: label
                        anchors.left: parent.left
                        anchors.leftMargin: 32 * root.unit
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -8 * root.unit
                        text: row.modelData.label
                        color: row.selected ? Theme.textPrimary : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 21 * root.unit
                        Behavior on color { ColorAnimation { duration: 240 } }
                    }

                    Text {
                        anchors.left: label.left
                        anchors.top: label.bottom
                        anchors.topMargin: 3 * root.unit
                        text: row.armed ? qsTr("确认中…按 Esc 取消") : row.modelData.sub
                        color: row.armed ? Theme.accent : Theme.textTertiary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11 * root.unit
                        font.letterSpacing: 0.6 * root.unit
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 18 * root.unit
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 22 * root.unit
                        opacity: row.selected ? 1 : 0
                        transform: Translate { x: row.selected ? 0 : -8 * root.unit }
                        MotionBehavior on opacity { duration: 240 }
                        MotionBehavior on x { duration: 240 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.currentIndex = row.index
                        onClicked: root.confirm()
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 26 * root.unit
        }

        Text {
            id: noteText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.note
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 12 * root.unit
            opacity: root.note.length > 0 ? 1 : 0
            MotionBehavior on opacity { duration: 240 }
        }

        Item {
            width: parent.width
            height: 14 * root.unit
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("↑↓ 选择    Enter 确认    Esc 取消")
            color: Theme.textTertiary
            font.family: Theme.fontFamily
            font.pixelSize: 11 * root.unit
            font.letterSpacing: 1 * root.unit
            opacity: 0.75
        }
    }

    // --- behaviour ----------------------------------------------------------
    onShownChanged: {
        if (shown) {
            currentIndex = firstUsableIndex()
            armedKey = ""
            note = ""
            forceActiveFocus()
        } else {
            armedKey = ""
            note = ""
        }
    }

    function firstUsableIndex() {
        for (let i = 0; i < rows.length; ++i)
            if (rows[i].enabled !== false)
                return i
        return 0
    }

    function moveSelection(delta) {
        if (!shown || rows.length === 0)
            return
        // Moving is also how you take back an armed row.
        if (armedKey !== "")
            armedKey = ""

        let index = currentIndex
        for (let step = 0; step < rows.length; ++step) {
            index = (index + delta + rows.length) % rows.length
            if (rows[index].enabled !== false)
                break
        }
        currentIndex = index
        Power.highlight(rows[index].key)   // relays ChangKey on D-Bus
    }

    function activateSelection() {
        if (!shown || rows.length === 0)
            return
        confirm()
    }

    function confirm() {
        const row = rows[currentIndex]
        if (!row)
            return

        if (row.enabled === false) {
            note = row.note && row.note.length > 0 ? row.note : qsTr("该项当前不可用")
            return
        }

        // Destructive rows take two presses: the first arms them, and the row
        // fills for armDuration. Moving away or pressing Esc disarms.
        if (row.kind === "danger" && armedKey !== row.key) {
            note = ""
            armedKey = row.key
            return
        }

        armedKey = ""
        root.activated(row.key)
    }

    function cancel() {
        if (armedKey !== "") {
            armedKey = ""
            return
        }
        note = ""
        Power.dismiss()
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
                                  "rows", root.rows.length,
                                  "hasWindow", Window.window !== null,
                                  "window visible", Window.window ? Window.window.visible : false,
                                  "window visibility", Window.window ? Window.window.visibility : -1,
                                  "locked", LockSession.locked,
                                  "authScreen", Screens.authScreenName)
    }

    Connections {
        target: Power
        function onArmRequested(key) {
            for (let i = 0; i < root.rows.length; ++i) {
                if (root.rows[i].key === key) {
                    root.currentIndex = i
                    root.armedKey = key
                    return
                }
            }
        }
        function onFailed(reason) {
            root.note = reason
        }
    }
}
