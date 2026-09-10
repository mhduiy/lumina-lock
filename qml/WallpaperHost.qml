import QtQuick
import QtMultimedia
import Lumina 1.0

// Renders the active wallpaper. This is the *only* place that knows how a
// wallpaper is drawn; LockScreen.qml stays wallpaper-agnostic.
//
// - Static images use Image with aspect-crop and a soft fade-in.
// - Video uses MediaPlayer + VideoOutput (looped, muted) and keeps a poster
//   frame on top until playback actually starts, so there is no black flash.
//
// `playVideo` lets secondary screens show only the poster instead of spinning
// up a second, expensive video decoder per monitor.
Item {
    id: root

    property bool playVideo: true

    readonly property bool isVideo: WallpaperManager.isVideo
    readonly property bool isStatic: WallpaperManager.type === "static"

    // Base layer: never show a pure black frame while content loads.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0A0F26" }
            GradientStop { position: 1.0; color: "#16294D" }
        }
    }

    // --- Static image ---
    Image {
        id: staticImage
        anchors.fill: parent
        visible: root.isStatic
        source: root.isStatic ? WallpaperManager.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
        onStatusChanged: {
            if (status === Image.Ready)
                staticImage.opacity = 1
        }
        Connections {
            target: WallpaperManager
            function onWallpaperChanged() {
                if (root.isStatic)
                    staticImage.opacity = 0
            }
        }
    }

    // --- Video (only instantiated when actually allowed to decode) ---
    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.isVideo && root.playVideo
        sourceComponent: videoComponent
    }

    Component {
        id: videoComponent
        Item {
            id: videoItem
            property bool playing: false

            MediaPlayer {
                id: player
                source: WallpaperManager.source
                videoOutput: videoOutput
                audioOutput: AudioOutput {
                    muted: true
                    volume: 0
                }
                loops: MediaPlayer.Infinite
                autoPlay: true
                onPlaybackStateChanged: {
                    videoItem.playing = (player.playbackState === MediaPlayer.PlayingState)
                }
                onErrorOccurred: (error, errorString) => {
                    console.warn("WallpaperHost: video error:", errorString)
                }
                Component.onDestruction: player.stop()
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }

    // --- Poster / fallback ---
    // Kept *above* the video so it masks the black pre-roll frames. It is also
    // the only content shown when playVideo is false (secondary screens).
    Image {
        id: poster
        anchors.fill: parent
        visible: root.isVideo
                 && (!root.playVideo
                     || !videoLoader.active
                     || videoLoader.item === null
                     || !videoLoader.item.playing)
        source: WallpaperManager.poster
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: WallpaperManager.poster.toString() !== "" ? 1 : 0
    }
}
