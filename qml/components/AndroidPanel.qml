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
    function takeScreenshot() {}

    implicitWidth: 360
    implicitHeight: 300
    width: 360
    height: 300
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
            text: root.status === "Running" ? "Android 15 · running"
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
