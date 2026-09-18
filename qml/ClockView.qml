import QtQuick
import Lumina 1.0
import "components"

// The clock is the visual hero of the Idle state: large, calm, and made of
// frosted glass — the numerals are translucent so the wallpaper reads through
// the letterforms.
Item {
    id: root

    property real unit: 1
    property bool compact: false

    // Backdrop plumbing, forwarded from the scene.
    property Item glassSource: null
    property int glassRefreshToken: 0
    property bool glassLive: false
    // False until the scene is revealed (wired to the scene's sceneReady).
    property bool revealed: true

    // --- Type size --------------------------------------------------------
    // `size` is a pure function of `unit` and the two dimensionless progress
    // values below; nothing animates the pixel size itself. A Behavior on
    // `size` does not work here: the window has no height until it is laid
    // out, so `unit` is 0 on the first frame, and an always-on Behavior
    // animated the type out of nothing on every lock. Gating that Behavior
    // instead does not work either — the gate and the value it guards are
    // released by the same signal, Qt assigns the new size before the gate
    // opens, and the growth snaps.
    property real entryProgress: 1                    // 0 = undersized, 1 = settled
    property real compactProgress: compact ? 1 : 0    // 0 = idle, 1 = authenticating

    // 0.82, not a token 0.98: an ease-in-out fade keeps the clock invisible for
    // roughly its first 40%, so only the tail of the growth is ever on screen.
    // A gentle scale would be over before it could be seen.
    readonly property real entryFactor: 0.82 + 0.18 * entryProgress

    // The authenticating fraction of the idle size, for one element's ratio.
    function stateFactor(ratio) {
        return ratio + (1 - ratio) * (1 - root.compactProgress)
    }

    onRevealedChanged: {
        if (root.revealed) {
            entryAnim.restart()
        } else {
            // Snap back while still hidden, so the next reveal always starts
            // the growth from the same place.
            entryAnim.stop()
            root.entryProgress = 1
        }
    }

    // Slightly longer than the scene's 480 ms reveal fade, so the growth is
    // still settling as the clock finishes arriving.
    NumberAnimation {
        id: entryAnim
        target: root
        property: "entryProgress"
        from: 0
        to: 1
        duration: 560
        easing.bezierCurve: Theme.motionCurve
    }

    MotionBehavior on compactProgress { active: root.revealed }

    // Type sizes come from the control center, expressed in reference pixels at
    // a 1080px-tall screen, and are scaled to this window — so one setting looks
    // proportionally identical on any resolution.
    readonly property real clockTypeSize: LockAppearance.clockFontSize * unit
    readonly property real dateTypeSize: LockAppearance.dateFontSize * unit
    // The authenticating sizes stay a fixed fraction of the idle ones, so a
    // custom size keeps the same relationship between the two states.
    readonly property real clockCompactRatio: 0.64   // 96 / 150
    readonly property real dateCompactRatio: 0.815   // 22 / 27

    // 这一组（时间 + 日期）自己的尺寸：外面的 LockScreen 按百分比摆放它（0 = 贴左/上，
    // 50 = 居中，100 = 贴右/下），所以这里用内容的实际大小，而不是一个固定的框 ——
    // 否则「贴左」贴的是框的左边，而不是字的左边。
    width: column.implicitWidth
    height: column.implicitHeight

    property string timeText: Qt.formatTime(new Date(), "HH:mm")
    property string dateText: Qt.formatDate(new Date(), "dddd, MMMM d")

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.timeText = Qt.formatTime(now, "HH:mm")
            root.dateText = Qt.formatDate(now, "dddd, MMMM d")
        }
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 8 * root.unit

        GlassText {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            fontFamily: Theme.fontFamily
            fontWeight: LockAppearance.clockWeight
            size: root.clockTypeSize * root.stateFactor(root.clockCompactRatio)
                  * root.entryFactor
            letterSpacing: -2 * root.unit
            background: root.glassSource
            // The Column's origin in wallpaper coordinates; this item adds its
            // own offset inside the Column.
            sourceOriginBase: Qt.point(root.x + column.x, root.y + column.y)
            refreshToken: root.glassRefreshToken
            liveSource: root.glassLive
            // The numerals are thin strokes, so they need more lift than the
            // date to stay readable on a dark wallpaper.
            brighten: 0.34
            tintAmount: 0.34
        }

        GlassText {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            fontFamily: Theme.fontFamily
            fontWeight: LockAppearance.dateWeight
            size: root.dateTypeSize * root.stateFactor(root.dateCompactRatio)
                  * root.entryFactor
            letterSpacing: 4 * root.unit
            background: root.glassSource
            sourceOriginBase: Qt.point(root.x + column.x, root.y + column.y)
            refreshToken: root.glassRefreshToken
            liveSource: root.glassLive
            // Thin strokes carry much less glass than the numerals, so they get
            // more lift to stay readable over a busy wallpaper.
            brighten: 0.46
            tintAmount: 0.5
            shadowOpacity: 0.6
        }
    }
}
