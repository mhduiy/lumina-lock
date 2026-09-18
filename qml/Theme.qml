pragma Singleton
import QtQuick

// Central visual tokens. Kept free of any screen/window logic so it can be
// reused across every surface (primary + secondary screens).
QtObject {
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.62)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, 0.38)

    readonly property color accent: "#8FA9F0"
    readonly property color error: "#FF6B6B"

    // A control you are aiming at has to read as a surface, not as a film of
    // light over whatever is behind it: 6% white looked like nothing at all
    // against a backdrop this dark. Used by the power menu's buttons and its
    // slider track.
    readonly property color surface: Qt.rgba(1, 1, 1, 0.12)
    readonly property color surfaceBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color surfaceBorderFocus: Qt.rgba(1, 1, 1, 0.34)
    // The rim of a filled control. Brighter than surfaceBorder on purpose: at
    // 0.14 it is the same value as the fill and the edge disappears.
    readonly property color controlBorder: Qt.rgba(1, 1, 1, 0.22)

    // Frosted glass: a faint lift plus a hairline, laid over a blurred sample
    // of the wallpaper (see components/GlassPanel.qml).
    readonly property color glassTint: Qt.rgba(1, 1, 1, 0.06)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.16)
    // Used when there is nothing blurrable behind the panel (video wallpaper).
    readonly property color glassFallback: Qt.rgba(1, 1, 1, 0.10)

    readonly property string fontFamily: "Noto Sans"

    // One duration and one curve for every state transition, so the clock, the
    // auth panel and the scene dimming move as a single gesture instead of
    // three overlapping animations that finish at different times.
    //
    // The curve is a standard ease-in-out, cubic-bezier(0.4, 0, 0.2, 1), picked
    // over the Easing.OutCubic it replaces: OutCubic spends ~58% of the motion
    // in the first quarter of the time, which reads as "jump, then creep" when
    // a large element both moves and resizes. This one leaves gently, carries
    // the motion through the middle and lands softly, and it never overshoots —
    // an overshoot would be wrong for the dim and blur that run alongside.
    readonly property int motionDuration: 320
    // The curve in the six-number form QML's easing value type expects: the
    // three control points of one cubic segment, the last pair being the end
    // point. This is cubic-bezier(0.4, 0, 0.2, 1).
    //
    // Note it is set via `easing.bezierCurve` and *not* `easing.type`: the type
    // setter builds a fresh QEasingCurve and would discard the control points.
    readonly property var motionCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]

    // Scales a design value (authored against a 1080px-tall reference) to the
    // given window height. Avoids hard-coded pixel sizes across resolutions
    // and HiDPI scale factors.
    function size(base, windowHeight) {
        return base * windowHeight / 1080
    }
}
