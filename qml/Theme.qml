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

    readonly property string fontFamily: "Noto Sans"

    // Scales a design value (authored against a 1080px-tall reference) to the
    // given window height. Avoids hard-coded pixel sizes across resolutions
    // and HiDPI scale factors.
    function size(base, windowHeight) {
        return base * windowHeight / 1080
    }
}
