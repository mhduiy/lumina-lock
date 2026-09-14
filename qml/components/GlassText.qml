import QtQuick
import QtQuick.Effects
import Lumina 1.0

// Frosted-glass type: the glyphs themselves are translucent glass, so the
// wallpaper is visible *through* the letterforms (the iOS lock-screen clock
// look) — as opposed to a blurred card drawn behind the text.
//
// The glyphs are rendered once into a texture and used as a mask; the blurred,
// brightened wallpaper is kept only where the mask is opaque. Because the fill
// is the wallpaper itself the type reads as translucent glass rather than as a
// flat colour, and a soft glyph-shaped shadow keeps it separable from a
// wallpaper of any brightness.
//
// The font is spelled out as scalar properties rather than aliased to the
// child Text, so callers can put a Behavior on `pixelSize` and animate the type
// (an alias to a grouped property cannot be animated).
//
// `sourceOriginBase` is the top-left of this item's *parent* coordinate system
// expressed in `background` coordinates. Callers must build it out of tracked
// QML properties only (see ClockView.qml): item transforms are invisible to the
// binding machinery, so a mapToItem() lookup would silently go stale.
Item {
    id: root

    property string text
    property string fontFamily: Theme.fontFamily
    property int fontWeight: Font.Normal
    property real pixelSize: 16
    property real letterSpacing: 0

    property Item background: null
    property point sourceOriginBase: Qt.point(0, 0)
    property int refreshToken: 0
    property bool liveSource: false

    property real blurAmount: 0.85
    // Lifts and whitens the sampled wallpaper so the glass reads as light.
    property real brighten: 0.38
    property real tintAmount: 0.35
    property color tint: "#FFFFFF"
    property real glassOpacity: 0.95
    property real shadowOpacity: 0.5
    // Softening applied to the glyph mask.
    //
    // Antialiasing at a fixed output resolution is a ~1px ramp, and no amount
    // of supersampling widens it (rendering at 2x and scaling down only
    // re-derives the same per-pixel coverage), so the only way to make a large
    // display glyph read smoother than its own coverage is to spread the edge
    // in space. That is a straight trade against sharpness, so keep it small:
    // around 1.5px here, which drops the steepest edge steps by ~20% while the
    // letterform stays crisp. Raising it to ~4px removes the steps completely
    // but the type visibly goes out of focus.
    property real maskSoftness: 0.11

    // MultiEffect is a ShaderEffect and needs a shader-capable scene graph
    // backend; the mask path also needs something to sample.
    readonly property bool effectsAvailable:
        GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool sampling: effectsAvailable
                                     && background !== null
                                     && width > 0 && height > 0

    readonly property point sourceOrigin:
        Qt.point(sourceOriginBase.x + x, sourceOriginBase.y + y)

    implicitWidth: glyphs.implicitWidth
    implicitHeight: glyphs.implicitHeight

    // Glyph mask; only ever sampled as a mask, never drawn by itself.
    //
    // The blur lives *inside* the mask layer rather than in `layer.effect`:
    // a layer effect is applied while nesting the layer into the scene, and
    // this item is never drawn, so a `layer.effect` here would silently do
    // nothing (measured: identical pixels with and without it).
    Item {
        id: glyphMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Text {
            id: glyphs
            anchors.fill: parent
            text: root.text
            font.family: root.fontFamily
            font.weight: root.fontWeight
            font.pixelSize: root.pixelSize
            font.letterSpacing: root.letterSpacing
            color: "white"
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: glyphs
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

    // Soft shadow shaped like the glyphs. Without it the glass type disappears
    // over a wallpaper whose brightness matches the glass lift.
    Item {
        id: shadow
        anchors.fill: parent
        visible: root.sampling
        opacity: root.shadowOpacity
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.22
            blurMax: 32
            autoPaddingEnabled: false
        }

        Text {
            anchors.fill: parent
            text: root.text
            font.family: root.fontFamily
            font.weight: root.fontWeight
            font.pixelSize: root.pixelSize
            font.letterSpacing: root.letterSpacing
            color: "#000000"
        }
    }

    // Sampled + blurred wallpaper, clipped to the glyphs. The layer is what
    // stops the square sample from being drawn as a bright rectangle: without
    // it the unblurred region would show through wherever the scene above the
    // wallpaper (the dim layer during authentication) is not itself opaque.
    Item {
        id: glass
        anchors.fill: parent
        visible: root.sampling
        opacity: root.glassOpacity
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: glyphMask
            // The mask already carries a soft, spatially wide ramp; a wider
            // threshold ramp here would only wash the strokes out.
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
            brightness: root.brighten
            colorization: root.tintAmount
            colorizationColor: root.tint
        }
    }

    // Readable fallback when the glass cannot be rendered.
    Text {
        anchors.fill: parent
        visible: !root.sampling
        text: root.text
        font.family: root.fontFamily
        font.weight: root.fontWeight
        font.pixelSize: root.pixelSize
        font.letterSpacing: root.letterSpacing
        color: Theme.textPrimary
    }

    Connections {
        target: root
        function onRefreshTokenChanged() { sample.scheduleUpdate() }
        function onSamplingChanged() { if (root.sampling) sample.scheduleUpdate() }
    }
}
