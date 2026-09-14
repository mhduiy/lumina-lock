import QtQuick
import QtQuick.Effects
import Lumina 1.0

// Frosted glass for the elements that sit directly on the wallpaper (the clock
// and the password pill).
//
// The panel re-samples *only the wallpaper region it covers* instead of
// blurring a full-screen copy. A full-screen blur would have to be regenerated
// on every frame, which is exactly the kind of work that makes a lock screen
// stutter; a panel-sized region costs a fraction of that.
//
// Static wallpapers sample on demand (`live: false` plus explicit updates), so
// a settled lock screen renders no blur work at all; video wallpapers set
// `liveSource` and pay one small re-sample per frame.
//
// `sourceOrigin` is this panel's top-left expressed in `background`
// coordinates. Callers must build that binding out of *tracked* QML properties:
// item transforms are invisible to the binding machinery, so a mapToItem()
// lookup would silently go stale whenever an ancestor moved.
Item {
    id: root

    property Item background: null
    property point sourceOrigin: Qt.point(0, 0)
    // Bump to re-take the sample when the wallpaper *content* changes
    // (asynchronous image load, wallpaper switch) rather than its geometry.
    property int refreshToken: 0
    // Video wallpaper: the source changes every frame, so the sample has to be
    // re-taken every frame too. Static wallpapers stay on the cheap path.
    property bool liveSource: false
    // 0..1 scene dimming, mirrored into the glass. The sampled wallpaper is not
    // dimmed on screen, so without this the panel stays glaringly bright while
    // the rest of the scene darkens.
    property real dim: 0
    property real radius: height / 2
    property real blurAmount: 0.9
    property color tint: Theme.glassTint
    property color borderColor: Theme.glassBorder
    property real borderWidth: 1
    // Softening applied to the shape mask; see GlassText.maskSoftness for why
    // this is a trade against sharpness and why it is kept small.
    property real maskSoftness: 0.11

    // MultiEffect is a ShaderEffect, so it needs a shader-capable scene graph
    // backend. Where it is missing the panel still renders, just unblurred.
    readonly property bool effectsAvailable:
        GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool sampling: effectsAvailable
                                     && background !== null
                                     && width > 0 && height > 0

    // Fallback surface: the whole panel when nothing can be sampled (no
    // background, software scene-graph backend), otherwise just the backdrop
    // under the glass.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        color: root.sampling ? "transparent" : Theme.glassFallback
        opacity: 1 - root.dim
    }

    // Sample + blur + rounded mask. Applied as a layer effect so the square
    // corners of the sampled region never reach the screen.
    Item {
        id: glass
        anchors.fill: parent
        visible: root.sampling
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskHolder
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ShaderEffectSource {
            id: sample
            anchors.fill: parent
            sourceItem: root.background
            sourceRect: Qt.rect(root.sourceOrigin.x, root.sourceOrigin.y,
                                root.width, root.height)
            live: root.liveSource
            smooth: true
            onSourceRectChanged: scheduleUpdate()
            Component.onCompleted: scheduleUpdate()
        }

        MultiEffect {
            anchors.fill: parent
            source: sample
            blurEnabled: true
            blur: root.blurAmount
            blurMax: 32
            autoPaddingEnabled: false
        }

        // Match the scene dimming, which this glass does not otherwise inherit
        // (it samples the wallpaper, not the composed scene).
        Rectangle {
            anchors.fill: parent
            color: "#05070D"
            opacity: root.dim
        }
    }

    // Rounded shape used as the mask. Its position is irrelevant — the mask is
    // stretched over the source. The blur has to live inside the layer: a
    // `layer.effect` would never run for an item that is not drawn.
    Item {
        id: maskHolder
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            id: maskShape
            anchors.fill: parent
            radius: root.radius
            antialiasing: true
            color: "white"
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: maskShape
            blurEnabled: true
            blur: root.maskSoftness
            // blurMax <= 16 keeps the blur at level 1 (one downsample). At
            // blurMax 32 the blur runs at quarter resolution, which quantises
            // the amount into coarse steps - 0.08 and 0.16 rendered
            // identically.
            blurMax: 16
            autoPaddingEnabled: false
        }
    }

    // Tint + hairline drawn over the glass, so the panel reads as a surface no
    // matter what it happens to be blurring. Supersampled: a one-pixel stroke
    // on a large radius is otherwise visibly dotted.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(width * 2, height * 2)
        color: root.sampling
               ? Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tint.a * (1 - root.dim))
               : "transparent"
        border.width: root.borderWidth
        border.color: root.borderColor
        Behavior on border.color {
            ColorAnimation { duration: 200 }
        }
    }

    Connections {
        target: root
        function onRefreshTokenChanged() { sample.scheduleUpdate() }
        function onSamplingChanged() { if (root.sampling) sample.scheduleUpdate() }
    }
}
