import QtQuick
import Lumina 1.0
import "components"

// The authentication panel: avatar, display name, password field and an
// inline error line. Reveal state is driven by `reveal` (0 → 1) so the parent
// scene can animate fade + slide + scale in one place.
Item {
    id: auth

    property real unit: 1
    property real reveal: 0
    property string errorText: ""
    property bool authenticating: false

    signal submit(string password)
    signal cancel()

    opacity: reveal
    scale: 0.96 + 0.04 * reveal
    transform: Translate { y: (1 - reveal) * (26 * unit) }
    Behavior on reveal {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    width: 340 * unit
    height: column.height

    property string initial: {
        const n = LockSession.displayName.trim()
        return n.length > 0 ? n.charAt(0).toUpperCase() : "?"
    }

    Column {
        id: column
        width: parent.width
        spacing: 0

        // Avatar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72 * auth.unit
            height: 72 * auth.unit
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#5B76D8" }
                GradientStop { position: 1.0; color: "#3A4FA0" }
            }
            Text {
                anchors.centerIn: parent
                text: auth.initial
                color: "#FFFFFF"
                font.family: Theme.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: 30 * auth.unit
            }
        }

        Item { width: 1; height: 14 * auth.unit }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: LockSession.displayName
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.weight: Font.Medium
            font.pixelSize: 20 * auth.unit
        }

        Item { width: 1; height: 20 * auth.unit }

        PasswordField {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            unit: auth.unit
            placeholderText: "Password"
            error: auth.errorText !== ""
            busy: auth.authenticating
            onAccepted: auth.submit(field.text)
            onEscapePressed: auth.cancel()
            onTextEdited: auth.clearError()
        }

        Item { width: 1; height: 12 * auth.unit }

        // Inline error — never a modal MessageBox.
        Text {
            id: errorLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: auth.errorText
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 14 * auth.unit
            opacity: auth.errorText !== "" ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }
        }
    }

    function clearError() {
        auth.errorText = ""
    }

    function focusField() {
        field.focusField()
    }

    function clearAndShake() {
        field.text = ""
        shake.restart()
        field.focusField()
    }

    SequentialAnimation {
        id: shake
        property real d: 8 * auth.unit
        NumberAnimation { target: field; property: "x"; to: -shake.d; duration: 45 }
        NumberAnimation { target: field; property: "x"; to:  shake.d; duration: 45 }
        NumberAnimation { target: field; property: "x"; to: -shake.d * 0.6; duration: 45 }
        NumberAnimation { target: field; property: "x"; to:  shake.d * 0.6; duration: 45 }
        NumberAnimation { target: field; property: "x"; to: 0; duration: 45 }
    }
}
