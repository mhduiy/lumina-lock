import QtQuick
import Lumina 1.0

// The shared transition animation for a scene property.
//
// Every animated property of the lock/idle state change uses this, so they all
// share one duration and one curve and therefore stay in step. Putting the
// animation in one place also means the curve is chosen once rather than
// re-specified (and eventually diverging) at each call site.
Behavior {
    id: root

    // Lets a caller switch the animation off while the scene is being reset,
    // so a re-lock snaps back instead of animating from the previous state.
    property bool active: true

    // Overridable for the fades that are not state transitions (a wallpaper
    // dissolving in, an error message appearing). The curve stays shared.
    property int duration: Theme.motionDuration

    enabled: root.active

    NumberAnimation {
        duration: root.duration
        easing.bezierCurve: Theme.motionCurve
    }
}
