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

    readonly property color surface: Qt.rgba(1, 1, 1, 0.06)
    readonly property color surfaceBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color surfaceBorderFocus: Qt.rgba(1, 1, 1, 0.34)

    // Frosted glass: a faint lift plus a hairline, laid over a blurred sample
    // of the wallpaper (see components/GlassPanel.qml).
    readonly property color glassTint: Qt.rgba(1, 1, 1, 0.06)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.16)
    // Used when there is nothing blurrable behind the panel (video wallpaper).
    readonly property color glassFallback: Qt.rgba(1, 1, 1, 0.10)

    readonly property string fontFamily: "Noto Sans"

    // One duration for every state transition, so the clock, the auth panel and
    // the scene dimming move as a single gesture instead of three overlapping
    // animations that finish at different times.
    readonly property int motionDuration: 320

    // Scales a design value (authored against a 1080px-tall reference) to the
    // given window height. Avoids hard-coded pixel sizes across resolutions
    // and HiDPI scale factors.
    function size(base, windowHeight) {
        return base * windowHeight / 1080
    }
}
