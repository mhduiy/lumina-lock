import QtQuick
import Lumina 1.0
import "components"

// The clock is the visual hero of the Idle state: large, calm, and made of
// frosted glass — the numerals are translucent so the wallpaper reads through
// the letterforms.
Item {
    id: root

    property real unit: 1
    property bool compact: false

    // Backdrop plumbing, forwarded from the scene.
    property Item glassSource: null
    property int glassRefreshToken: 0
    property bool glassLive: false

    width: 800 * unit
    height: 240 * unit

    property string timeText: Qt.formatTime(new Date(), "HH:mm")
    property string dateText: Qt.formatDate(new Date(), "dddd, MMMM d")

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.timeText = Qt.formatTime(now, "HH:mm")
            root.dateText = Qt.formatDate(now, "dddd, MMMM d")
        }
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 8 * root.unit

        GlassText {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            fontFamily: Theme.fontFamily
            fontWeight: LockAppearance.clockWeight
            pixelSize: (root.compact ? 96 : 150) * root.unit
            letterSpacing: -2 * root.unit
            background: root.glassSource
            // The Column's origin in wallpaper coordinates; this item adds its
            // own offset inside the Column.
            sourceOriginBase: Qt.point(root.x + column.x, root.y + column.y)
            refreshToken: root.glassRefreshToken
            liveSource: root.glassLive
            // The numerals are thin strokes, so they need more lift than the
            // date to stay readable on a dark wallpaper.
            brighten: 0.34
            tintAmount: 0.34
            Behavior on pixelSize {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        GlassText {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            fontFamily: Theme.fontFamily
            fontWeight: LockAppearance.dateWeight
            pixelSize: (root.compact ? 22 : 27) * root.unit
            letterSpacing: 4 * root.unit
            background: root.glassSource
            sourceOriginBase: Qt.point(root.x + column.x, root.y + column.y)
            refreshToken: root.glassRefreshToken
            liveSource: root.glassLive
            // Thin strokes carry much less glass than the numerals, so they get
            // more lift to stay readable over a busy wallpaper.
            brighten: 0.46
            tintAmount: 0.5
            shadowOpacity: 0.6
            Behavior on pixelSize {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
