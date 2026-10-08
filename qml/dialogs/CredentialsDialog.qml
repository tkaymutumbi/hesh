import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

Popup {
    id: root
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(540, (Overlay.overlay ? Overlay.overlay.width : 580) - 40)
    height: Math.min(580, (Overlay.overlay ? Overlay.overlay.height : 620) - 40)
    padding: 24
    property string pending: ""
    property string message: ""
    property var savedAccounts: []
    background: Rectangle { color: Theme.panel; radius: 14; border.color: Theme.borderStrong }
    Overlay.modal: Rectangle { color: "#99080a0e" }
    function send(command) {
        root.pending = "vault-ui-" + Date.now()
        root.message = "Working with your desktop keyring…"
        Automation.request(root.pending, command)
        password.text = ""
    }
    onOpened: {
        root.savedAccounts = Automation.accounts()
        accountChoice.currentIndex = -1
        var d = deviceManager.selectedDevice
        site.text = d ? d.url : ""
        root.message = ""
    }
    onClosed: password.text = ""
    Connections {
        target: Automation
        function onFinished(token, reply) {
            if (token !== root.pending) return
            root.pending = ""
            root.message = reply.ok ? (reply.filled ? "Login filled. Review the page and sign in." : "Saved logins updated.") : reply.error
            root.savedAccounts = Automation.accounts()
        }
    }
    component LoginField: TextField {
        Layout.fillWidth: true
        implicitHeight: 38
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font.pixelSize: 12
        selectByMouse: true
        leftPadding: 12
        rightPadding: 12
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.input
            border.color: parent.activeFocus ? Theme.accentStrong : Theme.border
        }
    }
    contentItem: ScrollView {
        clip: true
        ColumnLayout {
            width: root.availableWidth
            spacing: 12
            Text { text: "Saved logins"; color: Theme.text; font.pixelSize: 20 }
            Text {
                Layout.fillWidth: true
                text: "Passwords stay in your desktop keyring. Fill uses the matching HTTPS site and leaves sign-in to you or the agent."
                color: Theme.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap
            }
            ComboBox {
                id: accountChoice
                implicitHeight: 38
                leftPadding: 12
                rightPadding: 28
                contentItem: Text {
                    text: accountChoice.displayText
                    color: Theme.text
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: Text {
                    x: accountChoice.width - 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⌄"
                    color: Theme.textMuted
                }
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.input
                    border.color: accountChoice.activeFocus ? Theme.accentStrong : Theme.border
                }
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: accountChoice.width
                    highlighted: accountChoice.highlightedIndex === index
                    contentItem: Text {
                        text: modelData.email + " · " + modelData.origin
                        color: Theme.text
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    background: Rectangle { color: parent.highlighted ? Theme.panelSoft : Theme.panelRaised }
                }
                popup: Popup {
                    y: accountChoice.height + 4
                    width: accountChoice.width
                    padding: 4
                    contentItem: ListView {
                        implicitHeight: Math.min(contentHeight, 200)
                        model: accountChoice.popup.visible ? accountChoice.delegateModel : null
                        clip: true
                    }
                    background: Rectangle { color: Theme.panelRaised; radius: Theme.radiusSmall; border.color: Theme.border }
                }
                Layout.fillWidth: true
                model: root.savedAccounts
                textRole: "email"
                displayText: currentIndex >= 0 && root.savedAccounts.length > 0 ? root.savedAccounts[currentIndex].email + " · " + root.savedAccounts[currentIndex].origin : "Choose a saved login"
                onActivated: {
                    site.text = root.savedAccounts[currentIndex].origin
                    email.text = root.savedAccounts[currentIndex].email
                }
            }
            LoginField { id: site; Layout.fillWidth: true; placeholderText: "HTTPS site, e.g. https://example.com" }
            LoginField { id: email; Layout.fillWidth: true; placeholderText: "Email / username" }
            LoginField { id: password; Layout.fillWidth: true; placeholderText: "Password (to save or update)"; echoMode: TextInput.Password; selectByMouse: true }
            RowLayout {
                Layout.fillWidth: true
                AppButton {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Save"; compact: true; enabled: !root.pending && password.text.length > 0
                    onClicked: root.send({action: "credential_save", origin: site.text, email: email.text, password: password.text})
                }
                AppButton {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Fill login"; compact: true; enabled: !root.pending && !!deviceManager.selectedDevice
                    onClicked: root.send({action: "credential_fill", id: deviceManager.selectedDevice.id, origin: site.text, email: email.text,
                        emailSelector: emailSelector.text, passwordSelector: passwordSelector.text})
                }
                AppButton {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Delete"; compact: true; secondary: true; enabled: !root.pending
                    onClicked: root.send({action: "credential_delete", origin: site.text, email: email.text})
                }
            }
            Text { text: "Optional field selectors for unusual login forms"; color: Theme.textMuted; font.pixelSize: 11 }
            LoginField { id: emailSelector; Layout.fillWidth: true; placeholderText: "Email CSS selector (automatic when empty)" }
            LoginField { id: passwordSelector; Layout.fillWidth: true; placeholderText: "Password CSS selector (automatic when empty)" }
            Text { Layout.fillWidth: true; text: root.message; color: Theme.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap }
            AppButton { text: "Close"; compact: true; secondary: true; onClicked: root.close() }
        }
    }
}
