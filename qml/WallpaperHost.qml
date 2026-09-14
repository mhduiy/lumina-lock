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

    property bool videoFailed: false

    // True once the surface has something worth drawing. The lock scene uses
    // this to stage the clock in *after* the wallpaper has landed, so the clock
    // never pops in over a half-decoded image.
    readonly property bool ready: {
        if (root.isStatic)
            return staticImage.status === Image.Ready || staticImage.status === Image.Error
        if (root.isVideo)
            return root.videoFailed
                   || (videoLoader.item !== null && videoLoader.item.started)
                   || poster.status === Image.Ready || poster.status === Image.Error
        return true // built-in gradient only
    }

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
            else if (status === Image.Error)
                root.videoFailed = true
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
    // Also tied to the lock state: while unlocked the surfaces are hidden, so
    // the decoder is destroyed to release resources and recreated on re-lock.
    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.isVideo && root.playVideo && LockSession.locked
        sourceComponent: videoComponent
    }

    Component {
        id: videoComponent
        Item {
            id: videoItem
            property bool playing: false
            // Set once a frame has actually been shown, so the poster never
            // covers the video again.
            property bool started: false

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
                    if (videoItem.playing)
                        videoItem.started = true
                }
                onErrorOccurred: (error, errorString) => {
                    console.warn("WallpaperHost: video error:", errorString)
                    root.videoFailed = true
                }
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
                     || !videoLoader.item.started)
        source: WallpaperManager.poster
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: WallpaperManager.poster.toString() !== "" ? 1 : 0
    }
}
