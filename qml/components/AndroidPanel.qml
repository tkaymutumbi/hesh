import QtQuick
import QtQuick.Layouts
import Hesh 1.0

// Workspace view for a real Android device. The screen itself is a scrcpy
// window; this panel shows what the emulator is doing and offers the controls.
Rectangle {
    id: root

    property var device

    // The web frame's shortcuts call these on whatever the workspace loaded.
    function reloadPage() {}
    function takeScreenshot() { if (device) device.screenshot() }
    property string note: ""
    Connections {
        target: root.device
        function onScreenshotSaved(path) { root.note = "Saved " + path.split("/").pop() }
    }

    implicitWidth: 380
    implicitHeight: 470
    width: 380
    height: 470
    radius: Theme.radiusMedium
    color: Theme.panel
    border.width: 1
    border.color: Theme.borderStrong

    readonly property string status: device ? device.status : ""

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 48
        spacing: 12

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.device ? root.device.name : ""
            color: Theme.text
            font.pixelSize: 17
            font.weight: Font.Medium
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.status === "Running" ? "Phone · connected"
                : root.status === "Starting" ? "Starting"
                : root.status === "Error" ? "Cannot start" : "Stopped"
            color: root.status === "Error" ? Theme.warning : Theme.textMuted
            font.pixelSize: 12
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: text.length > 0
            text: root.device ? root.device.statusDetail : ""
            color: Theme.textMuted
            font.pixelSize: 11
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: root.status === "Running"
            text: root.device ? "adb " + root.device.serial : ""
            color: Theme.textMuted
            font.pixelSize: 11
            font.family: "monospace"
        }
        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.status === "Running"
            columns: 4
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: [["Back", "back"], ["Home", "home"], ["Recents", "recents"], ["Rotate", "rotate"],
                        ["Vol +", "volume_up"], ["Vol -", "volume_down"], ["Power", "power"], ["Notifs", "notifications"]]
                AppButton {
                    required property var modelData
                    text: modelData[0]
                    secondary: true
                    compact: true
                    onClicked: root.device.press(modelData[1])
                }
            }
        }
        AppButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.status === "Running"
            text: "Screenshot"
            secondary: true
            compact: true
            onClicked: root.takeScreenshot()
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
            text: root.note
            color: Theme.textMuted
            font.pixelSize: 11
        }
        Text {
            Layout.fillWidth: true
            visible: root.status === "Running"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.textMuted
            font.pixelSize: 10
            lineHeight: 1.3
            text: "On the screen window: drag to swipe, scroll wheel to scroll, right-click = Back, middle-click = Home, "
                + "Ctrl + drag = pinch, Alt+S = Recents, Alt+N = notifications, Alt+R = rotate, Alt+P = power"
        }
        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.status === "Running"
            columns: 4
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: [["Back", "back"], ["Home", "home"], ["Recents", "recents"], ["Notifs", "notifications"],
                        ["Vol +", "volume_up"], ["Vol -", "volume_down"], ["Power", "power"]]
                AppButton {
                    required property var modelData
                    text: modelData[0]
                    secondary: true
                    compact: true
                    onClicked: root.device.press(modelData[1])
                }
            }
            AppButton {
                text: "Screenshot"
                secondary: true
                compact: true
                onClicked: root.takeScreenshot()
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
            text: root.note
            color: Theme.textMuted
            font.pixelSize: 11
        }
        Text {
            Layout.fillWidth: true
            visible: root.status === "Running"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.textMuted
            font.pixelSize: 10
            lineHeight: 1.3
            text: "On the screen window: drag to swipe, scroll wheel to scroll, right-click = Back, middle-click = Home, "
                + "Ctrl + drag = pinch, Alt+S = Recents, Alt+N = notifications, Alt+P = power, Alt+Up/Down = volume"
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            AppButton {
                visible: root.status === "Running"
                text: "Show Screen"
                compact: true
                onClicked: root.device.showScreen()
            }
            AppButton {
                visible: root.status === "Stopped" || root.status === "Error"
                text: "Start Device"
                compact: true
                onClicked: root.device.start()
            }
            AppButton {
                visible: root.status === "Running" || root.status === "Starting"
                text: "Stop"
                secondary: true
                compact: true
                onClicked: root.device.stop()
            }
        }
    }
}
