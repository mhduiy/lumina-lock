import QtQuick
import Lumina 1.0

// The power menu's own surface.
//
// It is deliberately not a layer on the lock screen. The lock's windows are
// hidden and re-shown around every lock and unlock, and on some window managers
// they do not come back cleanly — a surface drawn into one of those inherits
// whatever state it was left in, which is how "the menu is up and nothing is on
// screen" happens. A window that only ever shows the menu has nothing else to
// go wrong.
Window {
    id: root

    // Transparent, and it fades in: the menu should read as arriving out of the
    // desktop rather than as a window opening. The window itself is
    // override-redirect (set in ScreenManager, matching the lock's own windows),
    // so the window manager neither animates it in nor lists it.
    // Visibility is owned by ScreenManager, not declared here — see LockScreen.
    color: "transparent"
    title: "Lumina Power"

    PowerScreen {
        id: menu
        anchors.fill: parent
        unit: root.height / 1080
        shown: Power.visible
        instant: false
        onActivated: (key) => Power.activate(key)
    }
}
