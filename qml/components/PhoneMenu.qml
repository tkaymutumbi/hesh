import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// Right-click menu for a phone mirror. scrcpy owns the mirror window, so
// Hyprland opens this small window at the pointer instead. Back, Home and the
// rest live here, so right-click is never a hidden "Back".
Window {
    id: root

    property var device: null
    readonly property var entries: [
        {label: "Back", action: "back"},
        {label: "Home", action: "home"},
        {label: "Recents", action: "recents"},
        {label: "Notifications", action: "notifications"},
        {label: "Volume up", action: "volume_up"},
        {label: "Volume down", action: "volume_down"},
        {label: "Power", action: "power"},
        {label: "Screenshot", action: "screenshot"}
    ]

    visible: false
    // The title must not end with " — Hesh", or the device-window rule would centre it.
    title: "Hesh phone menu"
    flags: Qt.Window | Qt.FramelessWindowHint
    // Independent of the main window, which may be hidden in background mode.
    transientParent: null
    color: "transparent"
    width: 200
    height: menuColumn.implicitHeight + 14

    function openFor(phone) {
        root.device = phone
        root.visible = false
        root.visible = true
        root.requestActivate()
    }

    // Close when focus leaves, but not before the window has been focused once:
    // the compositor maps it unfocused for a moment.
    property bool wasActive: false
    onActiveChanged: {
        if (active) wasActive = true
        else if (wasActive && visible) visible = false
    }
    onVisibleChanged: if (!visible) wasActive = false

    function run(action) {
        if (!root.device) return
        if (action === "screenshot") root.device.screenshot()
        else if (action === "toggle_screen") root.device.setMode(root.device.mode === "dark" ? "mirror" : "dark")
        else if (action === "show") root.device.showScreen()
        else if (action === "stop") root.device.stop()
        else root.device.press(action)
        root.visible = false
    }

    Shortcut { sequence: "Escape"; onActivated: root.visible = false }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.panelRaised
        border.width: 1
        border.color: Theme.borderStrong

        ColumnLayout {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 7
            spacing: 2

            Text {
                Layout.leftMargin: 8
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                text: root.device ? root.device.name : ""
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Repeater {
                model: root.entries
                delegate: MenuRow {
                    required property var modelData
                    label: modelData.label
                    onTriggered: root.run(modelData.action)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

            MenuRow {
                label: root.device && root.device.mode === "dark" ? "Turn phone screen on" : "Turn phone screen off"
                onTriggered: root.run("toggle_screen")
            }
            MenuRow { label: "Stop"; onTriggered: root.run("stop") }
        }
    }

    component MenuRow: Rectangle {
        id: row
        property string label: ""
        signal triggered()
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 5
        color: mouse.containsMouse ? Theme.panelSoft : "transparent"
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: Theme.text
            font.pixelSize: 12
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.triggered()
        }
    }
}
