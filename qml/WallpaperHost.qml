import QtQuick
import QtMultimedia
import "components"
import Lumina 1.0

// Renders the active wallpaper. This is the *only* place that knows how a
// wallpaper is drawn; LockScreen.qml stays wallpaper-agnostic.
//
// - Static images use Image with aspect-crop.
// - Video uses MediaPlayer + VideoOutput (looped, muted) with a poster frame
//   kept on top until the first frame has actually been rendered.
//
// The stack is ordered static image, video, poster, and a plain gradient on
// top of all of it. Everything is revealed by fading the layer above it OUT,
// never by fading content in: a Rectangle's and an Image's opacity reliably
// blend, while a VideoOutput's does not. Fading the video in against the
// gradient looks like it should work and does not — the QML opacity animates
// from 0 to 1 while the composited output changes in a single frame. Keeping
// the video at full opacity and dissolving what is above it gets the same
// result through an opacity that does blend.
//
// `playVideo` lets secondary screens show only the poster instead of spinning
// up a second, expensive video decoder per monitor.
Item {
    id: root

    property bool playVideo: true

    readonly property bool isVideo: WallpaperManager.isVideo
    readonly property bool isStatic: WallpaperManager.type === "static"

    property bool videoFailed: false

    // --- Static image ---
    Image {
        id: staticImage
        anchors.fill: parent
        visible: root.isStatic
        source: root.isStatic ? WallpaperManager.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
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

            // Set once the sink has delivered a frame, which is what "the video
            // is on screen" means. The playback state is not a usable
            // substitute: it is reached before anything is rendered, so a
            // dissolve started on it runs out against an empty sink and the
            // video then arrives in a single frame.
            property bool frameSeen: false

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

            Connections {
                target: videoOutput.videoSink
                function onVideoFrameChanged() {
                    videoItem.frameSeen = true
                }
            }
        }
    }

    // --- Poster ---
    // Above the video, so it masks the empty sink before the first frame, and
    // the only content drawn when playVideo is false (secondary screens).
    //
    // `visible` follows the opacity, which keeps the item alive for the length
    // of the fade.
    Image {
        id: poster
        anchors.fill: parent
        visible: root.isVideo && (!root.playVideo || poster.opacity > 0.001)
        source: WallpaperManager.poster
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: (root.videoShowing || WallpaperManager.poster.toString() === "") ? 0 : 1
        MotionBehavior on opacity { duration: 500 }
    }

    // --- Cover ---
    // Last child on purpose: it sits on top of the stack and hides it until
    // there is something worth showing, so the lock never opens on a black or
    // half-decoded frame. It is the layer that dissolves away.
    Rectangle {
        id: cover
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0A0F26" }
            GradientStop { position: 1.0; color: "#16294D" }
        }
        opacity: root.covered ? 1 : 0
        visible: opacity > 0.001
        MotionBehavior on opacity { duration: 500 }
    }

    // True once the video has delivered a frame.
    readonly property bool videoFrameReady: root.isVideo && root.playVideo
                                            && videoLoader.item !== null
                                            && videoLoader.item.frameSeen

    // The first frame is also where the one-off cost of bringing the video's
    // texture and material up lands, and that cost is paid on the render
    // thread. Hold the cover for a beat after the first frame so the cost is
    // paid behind it rather than in the middle of the dissolve.
    property bool videoSettled: false

    Timer {
        id: settleDelay
        interval: 600
        onTriggered: root.videoSettled = true
    }

    onVideoFrameReadyChanged: {
        if (root.videoFrameReady)
            settleDelay.restart()
    }

    // What the poster and the cover key off: the video is not merely ready to
    // draw, it has been drawing.
    readonly property bool videoShowing: root.videoFrameReady && root.videoSettled

    readonly property bool staticReady: staticImage.status === Image.Ready
                                        || staticImage.status === Image.Error

    readonly property bool posterReady: WallpaperManager.poster.toString() !== ""
                                        && (poster.status === Image.Ready
                                            || poster.status === Image.Error)

    // Whether the cover is still hiding the stack. A failed video has nothing
    // behind it, so the cover stays up for good: a flat gradient beats a black
    // rectangle.
    readonly property bool covered: {
        if (root.isStatic)
            return !root.staticReady
        if (root.isVideo)
            return !(root.videoShowing || root.posterReady)
        return true // built-in gradient only
    }

    // True once the wallpaper has actually landed, which is when the clock is
    // allowed to start arriving. It waits for the cover to finish dissolving
    // rather than merely to start: the clock is glass that samples this item,
    // and a sample taken mid-dissolve bakes the cover's colour into the
    // letterforms until the next refresh.
    readonly property bool ready: !root.covered && cover.opacity <= 0.001
}
