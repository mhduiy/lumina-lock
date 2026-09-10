import QtQuick
import Lumina 1.0

// The clock is the visual hero of the Idle state: large, light, and calm.
Item {
    id: root

    property real unit: 1
    property bool compact: false

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
        anchors.centerIn: parent
        spacing: 8 * root.unit

        Text {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            font.family: Theme.fontFamily
            font.weight: Font.Light
            font.pixelSize: (root.compact ? 96 : 150) * root.unit
            font.letterSpacing: -2 * root.unit
            color: Theme.textPrimary
            Behavior on font.pixelSize {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            font.family: Theme.fontFamily
            font.weight: Font.Medium
            font.pixelSize: (root.compact ? 22 : 27) * root.unit
            font.letterSpacing: 4 * root.unit
            color: Theme.textSecondary
            Behavior on font.pixelSize {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
        }
    }
}
