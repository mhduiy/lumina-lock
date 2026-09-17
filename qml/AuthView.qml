import QtQuick
import QtQuick.Effects
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

    // Frosted backdrop plumbing, forwarded to the password pill.
    property Item glassSource: null
    property int glassRefreshToken: 0
    property bool glassLive: false
    property real glassDim: 0

    signal submit(string password)
    signal cancel()

    opacity: reveal
    scale: 0.96 + 0.04 * reveal
    transform: Translate { y: (1 - reveal) * (26 * unit) }

    // No Behavior here on purpose: `reveal` is already animated by the scene
    // (content.authReveal), and smoothing it a second time made this panel lag
    // a whole extra duration behind the clock — visibly out of sync when the
    // password field appears and when Escape returns to the idle state.

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

        // Avatar: the account's picture when it has one, the initial when it
        // does not. LockSession does the fetching and the validation (the file
        // has to exist and be non-empty) — the same source dde-lock uses — so by
        // the time this is non-empty it is worth drawing.
        Item {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72 * auth.unit
            height: 72 * auth.unit

            // The initial is also the base layer, so the circle is never empty
            // while the picture loads (or if it turns out to be unreadable).
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                // Rounded corners and a circle edge are jagged without this.
                antialiasing: true
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

            Image {
                id: picture
                anchors.fill: parent
                source: LockSession.avatarPath
                sourceSize.width: width * 2   // crisp on HiDPI, no giant decodes
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
                layer.enabled: visible
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: avatarMask
                }
            }

            // Round mask for the picture. Kept invisible but layered, which is
            // how MultiEffect takes a mask.
            //
            // A rounded Rectangle is what is available here: an inline fragment
            // shader is not an option in Qt 6 (fragmentShader is a URL to a .qsb
            // built by the Qt Shader Tools, and this project ships no precompiled
            // shaders), and without a mask the picture would be a square. Note
            // that Qt does not antialias this shape inside a layer, so the outer
            // edge of a *picture* avatar is a little stepped; the initial below
            // has no such problem because it is drawn normally.
            Item {
                id: avatarMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "white"
                }
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
            glassSource: auth.glassSource
            // The pill's top-left in wallpaper coordinates. Built only from
            // tracked properties; the reveal transform is deliberately ignored
            // (it is zero once the panel has settled).
            glassOrigin: Qt.point(auth.x + column.x + field.x,
                                  auth.y + column.y + field.y)
            glassRefreshToken: auth.glassRefreshToken
            glassLive: auth.glassLive
            glassDim: auth.glassDim
            onAccepted: auth.submit(field.text)
            onEscapePressed: auth.cancel()
            onTextEdited: auth.clearError()
        }
    }

    function clearError() {
        auth.errorText = ""
    }

    function reset() {
        auth.errorText = ""
        field.text = ""
    }

    function focusField(initialText) {
        field.focusField()
        // A printable key that woke the lock starts the password.
        field.appendText(initialText)
    }

    function clearAndShake() {
        field.text = ""
        field.bounceError()
        field.focusField()
    }

    function playSuccess() {
        field.playSuccess()
    }
}
