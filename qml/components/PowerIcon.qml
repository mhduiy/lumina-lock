import QtQuick
import QtQuick.Shapes
import Lumina 1.0

// The power menu's icons, drawn as paths.
//
// A path per icon is less machinery than an icon font or a pile of SVG files,
// and it gives what this set actually needs: crisp at any size, tinted by the
// theme, and no dependency on Qt's SVG plugin or on a system icon theme being
// installed. Everything is authored on a 24x24 grid and scaled to `size`.
//
// `fill` marks the one shape that is a silhouette (the crescent); the rest are
// strokes of the same weight, which is what makes them read as one set.
Item {
    id: root

    property string name: "power"
    property real size: 24
    property color color: Theme.textPrimary

    readonly property var table: ({
        power:   { path: "M12 3.6V11.4 M7.9 6.2A7.1 7.1 0 1 0 16.1 6.2", fill: false },
        restart: { path: "M12 4.7A7.3 7.3 0 1 1 5.9 8.4", fill: false,
                   head: "M10.9 1.9L15.2 4.7L10.9 7.5Z" },
        lock:    { path: "M8.3 11V8.3a3.7 3.7 0 0 1 7.4 0V11 M7.1 11h9.8a1.3 1.3 0 0 1 1.3 1.3v7.4a1.3 1.3 0 0 1-1.3 1.3H7.1a1.3 1.3 0 0 1-1.3-1.3v-7.4A1.3 1.3 0 0 1 7.1 11Z",
                   fill: false },
        moon:    { path: "M20.4 14.8A8.6 8.6 0 0 1 9.2 3.6A8.6 8.6 0 1 0 20.4 14.8Z", fill: true },
        snow:    { path: "M12 3.4V20.6 M4.6 7.7L19.4 16.3 M19.4 7.7L4.6 16.3", fill: false },
        update:  { path: "M12 3.8V14.4 M7.4 9.9L12 14.4L16.6 9.9 M4.6 19.6h14.8", fill: false },
        // The arrow leaves the door rather than entering it: this is logging
        // out, and an arrow pointing into the frame reads as logging in.
        logout:  { path: "M9.4 4.4h-4.2A1.4 1.4 0 0 0 3.8 5.8v12.4a1.4 1.4 0 0 0 1.4 1.4h4.2 M9.6 12h10 M15.8 8.4L19.4 12L15.8 15.6",
                   fill: false }
    })

    readonly property var shape: table[name] !== undefined ? table[name] : table.power
    readonly property bool hasHead: shape.head !== undefined

    width: size
    height: size

    Shape {
        anchors.fill: parent
        // Shape has no `antialiasing` — that switch belongs to the renderer, and
        // the default one draws the edges of a path without any: these icons came
        // out visibly stepped. The curve renderer antialiases them analytically,
        // which is what a stroked path needs.
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.x: 0; origin.y: 0; xScale: root.size / 24; yScale: root.size / 24 }

        ShapePath {
            strokeColor: root.shape.fill ? "transparent" : root.color
            strokeWidth: 1.85
            fillColor: root.shape.fill ? root.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.shape.path }
        }

        // The restart arrow needs a solid head, and one ShapePath can only be
        // either filled or stroked — so the head is a path of its own.
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.hasHead ? root.color : "transparent"
            PathSvg { path: root.hasHead ? root.shape.head : "" }
        }
    }
}
