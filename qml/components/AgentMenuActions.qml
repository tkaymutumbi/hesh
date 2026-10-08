import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

ColumnLayout {
    id: root
    property var device: null
    property bool standalone: false
    signal dismissRequested()
    spacing: 2

    Repeater {
        model: [
            {label: "Copy agent prompt", action: "prompt"},
            {label: "Copy device ID", action: "id"},
            {label: "Saved logins…", action: "logins"},
            {label: Automation.paused ? "Resume AI control" : "Pause AI control", action: "pause"}
        ]
        delegate: Rectangle {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 5
            enabled: entry.modelData.action === "pause" || !!root.device
            opacity: enabled ? 1 : 0.45
            color: mouse.containsMouse ? Theme.panelSoft : "transparent"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.label
                color: Theme.text
                font.pixelSize: 12
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const action = entry.modelData.action
                    if (action === "prompt") Automation.copyAgentPrompt(root.device, root.standalone)
                    else if (action === "id") Automation.copyDeviceId(root.device.id)
                    else if (action === "pause") Automation.paused = !Automation.paused
                    root.dismissRequested()
                    if (action === "logins") Qt.callLater(function() { Automation.openLogins(root.device.id) })
                }
            }
        }
    }
}
