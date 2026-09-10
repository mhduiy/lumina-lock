import QtQuick
import Lumina 1.0

// A purpose-built password field: no default control chrome, just a rounded
// glassy pill with a dot-masked input and a tiny busy spinner.
Item {
    id: root

    property real unit: 1
    property alias text: input.text
    property string placeholderText: ""
    property bool error: false
    property bool busy: false

    signal accepted()
    signal escapePressed()
    signal textEdited()

    width: 300 * unit
    height: 52 * unit

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: root.error ? Theme.error
                                 : (input.activeFocus ? Theme.surfaceBorderFocus
                                                      : Theme.surfaceBorder)
        Behavior on border.color {
            ColorAnimation { duration: 200 }
        }
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        text: root.placeholderText
        color: Theme.textTertiary
        font.family: Theme.fontFamily
        font.pixelSize: 15 * root.unit
        visible: input.text.length === 0
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 20 * root.unit
        anchors.rightMargin: 44 * root.unit
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: 16 * root.unit
        echoMode: TextInput.Password
        passwordCharacter: "\u2022" // •
        passwordMaskDelay: 0
        activeFocusOnPress: true
        onAccepted: root.accepted()
        onTextEdited: root.textEdited()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                root.escapePressed()
        }
    }

    // Small orbiting dot used as an "authenticating…" spinner.
    Item {
        id: spinner
        anchors.right: parent.right
        anchors.rightMargin: 18 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        width: 14 * root.unit
        height: 14 * root.unit
        visible: root.busy
        rotation: 0

        Rectangle {
            anchors.centerIn: parent
            width: 14 * root.unit
            height: 14 * root.unit
            radius: width / 2
            color: "transparent"
            border.width: 2 * root.unit
            border.color: Qt.rgba(1, 1, 1, 0.20)
        }
        Rectangle {
            x: parent.width / 2 - 1.5 * root.unit
            y: -1.5 * root.unit
            width: 3 * root.unit
            height: 3 * root.unit
            radius: width / 2
            color: Theme.accent
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: root.busy
        }
    }

    function focusField() {
        input.forceActiveFocus()
    }
}
