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

    // Opaque, and it never fades in as a whole: the menu covers the screen on
    // its first frame so neither the desktop nor the borrowed lock scene is
    // visible behind it for even a moment.
    color: "#05070D"
    visibility: Window.FullScreen
    title: "Lumina Power"

    PowerScreen {
        id: menu
        anchors.fill: parent
        unit: root.height / 1080
        shown: Power.visible
        instant: true
        onActivated: (key) => Power.activate(key)
    }
}
