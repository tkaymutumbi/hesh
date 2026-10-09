import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Hesh 1.0

pragma ComponentBehavior: Bound

// Saved logins live in their own top-level window, so opening them from a
// standalone device never drags the main Hesh window onto the screen. The title
// deliberately does not end in " — Hesh": that suffix is what the Hyprland rules
// use for device windows, which open unfocused.
Window {
    id: root

    property var manager: null
    property string deviceId: ""
    readonly property var device: root.manager && root.deviceId ? root.manager.deviceById(root.deviceId) : null
    property string pending: ""
    property string message: ""
    property bool failed: false
    property var savedAccounts: []
    property int selected: -1
    property bool showAdvanced: false

    visible: false
    title: "Hesh logins"
    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: null
    color: Theme.window
    width: 440
    height: 580
    minimumWidth: 380
    minimumHeight: 480

    function hostOf(origin) { return String(origin).replace(/^https?:\/\//, "") }

    function openFor(id) {
        root.deviceId = id || ""
        root.savedAccounts = Automation.accounts()
        root.selected = -1
        root.message = ""
        root.failed = false
        password.text = ""
        email.text = ""
        privateSwitch.checked = false
        var d = root.device
        var url = d && d.url ? String(d.url) : ""
        var m = url.match(/^(https:\/\/[^\/?#]+|http:\/\/(localhost|127\.0\.0\.1|[^\/?#:]+\.localhost)(:\d+)?)/)
        site.text = m ? m[0] : ""
        root.show()
        root.raise()
        root.requestActivate()
        Qt.callLater(function() { (site.text ? email : site).forceActiveFocus() })
    }

    function select(index) {
        root.selected = index
        if (index < 0) return
        var a = root.savedAccounts[index]
        site.text = a.origin
        email.text = a.email
        password.text = ""
        privateSwitch.checked = !!a.private
    }

    function send(command) {
        root.pending = "vault-ui-" + Date.now()
        root.failed = false
        root.message = "Working with your keyring…"
        Automation.request(root.pending, command)
        password.text = ""
    }

    onClosing: password.text = ""

    Connections {
        target: Automation
        function onFinished(token, reply) {
            if (token !== root.pending) return
            root.pending = ""
            root.failed = !reply.ok
            root.message = reply.ok ? (reply.filled ? "Filled. Review the page, then sign in." : "Saved.") : reply.error
            root.savedAccounts = Automation.accounts()
        }
    }

    Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; onActivated: root.close() }

    component Field: TextField {
        Layout.fillWidth: true
        implicitHeight: 40
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font.pixelSize: 13
        selectByMouse: true
        leftPadding: 14
        rightPadding: 14
        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.input
            border.color: parent.activeFocus ? Theme.accentStrong : Theme.border
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Logins"; color: Theme.text; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true
                    text: root.device ? "Filling into " + root.device.name : "Saved in your desktop keyring"
                    color: Theme.textMuted; font.pixelSize: 12; elide: Text.ElideRight
                }
            }
            IconButton { iconText: "×"; tooltip: "Close"; onClicked: root.close() }
        }

        // Accounts
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            radius: Theme.radiusMedium
            color: Theme.panel
            border.color: Theme.border
            clip: true

            Text {
                anchors.centerIn: parent
                visible: root.savedAccounts.length === 0
                text: "No saved logins yet"
                color: Theme.textFaint; font.pixelSize: 13
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2
                clip: true
                model: root.savedAccounts
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 54
                    radius: Theme.radiusSmall
                    color: root.selected === row.index ? Theme.accentSoft
                           : rowArea.containsMouse ? Theme.panelRaised : "transparent"
                    border.width: root.selected === row.index ? 1 : 0
                    border.color: Theme.accentBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 16
                            color: Theme.panelSoft
                            Text {
                                anchors.centerIn: parent
                                text: root.hostOf(row.modelData.origin).charAt(0).toUpperCase()
                                color: Theme.accent; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { Layout.fillWidth: true; text: row.modelData.email; color: Theme.text; font.pixelSize: 13; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: root.hostOf(row.modelData.origin); color: Theme.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        Rectangle {
                            visible: !!row.modelData.private
                            implicitWidth: lockLabel.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: Theme.accentSoft
                            Text { id: lockLabel; anchors.centerIn: parent; text: "Only me"; color: Theme.accent; font.pixelSize: 11 }
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(row.index)
                    }
                }
            }
        }

        // Form
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Field { id: site; placeholderText: "https://example.com or http://localhost:3000" }
            Field { id: email; placeholderText: "Email or username" }
            Field { id: password; placeholderText: root.selected >= 0 ? "New password (leave empty to keep)" : "Password"; echoMode: TextInput.Password }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Only me"; color: Theme.text; font.pixelSize: 13 }
                    Text {
                        Layout.fillWidth: true
                        text: "Hidden from AI agents. They can't see, fill or replace it."
                        color: Theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap
                    }
                }
                SettingSwitch { id: privateSwitch; onToggled: checked = !checked }
            }

            Text {
                text: root.showAdvanced ? "Hide form selectors ▴" : "Form selectors ▾"
                color: Theme.textMuted; font.pixelSize: 11
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.showAdvanced = !root.showAdvanced }
            }
            Field { id: emailSelector; visible: root.showAdvanced; placeholderText: "Email CSS selector (automatic when empty)" }
            Field { id: passwordSelector; visible: root.showAdvanced; placeholderText: "Password CSS selector (automatic when empty)" }
        }

        Text {
            Layout.fillWidth: true
            visible: root.message.length > 0
            text: root.message
            color: root.failed ? Theme.error : Theme.textMuted
            font.pixelSize: 12; wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            AppButton {
                Layout.fillWidth: true
                text: root.device ? "Fill" : "Fill (no device)"
                enabled: !root.pending && !!root.device && site.text.length > 0 && email.text.length > 0
                onClicked: root.send({action: "credential_fill", id: root.deviceId, origin: site.text, email: email.text,
                    emailSelector: emailSelector.text, passwordSelector: passwordSelector.text})
            }
            AppButton {
                Layout.fillWidth: true
                text: "Save"
                secondary: true
                // Saving needs a password, or an existing account whose flag changes.
                enabled: !root.pending && site.text.length > 0 && email.text.length > 0 && password.text.length > 0
                onClicked: root.send({action: "credential_save", origin: site.text, email: email.text,
                    password: password.text, "private": privateSwitch.checked})
            }
            AppButton {
                text: "Delete"
                secondary: true
                destructive: true
                enabled: !root.pending && root.selected >= 0
                onClicked: { root.send({action: "credential_delete", origin: site.text, email: email.text}); root.selected = -1 }
            }
        }
    }
}
