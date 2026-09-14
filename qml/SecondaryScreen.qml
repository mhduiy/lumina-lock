import QtQuick
import Lumina 1.0

// Lightweight surface for non-primary monitors: wallpaper + clock, no
// authentication UI. Video decoding is intentionally disabled here so each
// extra screen does not spin up its own expensive decoder.
Window {
    id: root

    color: "#000000"
    visibility: Window.FullScreen
    title: "Lumina Lock"

    readonly property real u: height / 1080

    WallpaperHost {
        id: wallpaperHost
        anchors.fill: parent
        playVideo: false
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070D"
        opacity: 0.12
    }

    ClockView {
        unit: root.u
        compact: false
        glassSource: wallpaperHost
        glassRefreshToken: wallpaperHost.ready ? 1 : 0
        glassLive: WallpaperManager.isVideo
        anchors.centerIn: parent
    }
}
