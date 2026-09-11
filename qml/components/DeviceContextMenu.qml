import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

Popup {
    id: root

    property var manager
    property string deviceId: ""
    property string deviceName: ""
    property string deviceStatus: "Stopped"
    property var device
    property bool standalone: false
    signal openStandaloneRequested(var device)
    signal clearDataRequested(var device)
    signal deviceRemovalRequested(string deviceId)

    parent: Overlay.overlay
    width: 224
    padding: 7
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.panelRaised
        border.width: 1
        border.color: Theme.borderStrong
        radius: Theme.radiusSmall
    }

    function openAt(anchor, localX, localY) {
        const point = anchor.mapToItem(Overlay.overlay, localX, localY)
        x = Math.max(10, Math.min(point.x, Overlay.overlay.width - width - 10))
        y = Math.max(10, Math.min(point.y, Overlay.overlay.height - height - 10))
        open()
    }

    function toggleDevice() {
        if (!root.manager || root.deviceId.length === 0) {
            return
        }
        close()
        if (root.deviceStatus === "Running") {
            root.manager.stopDevice(root.deviceId)
        } else {
            root.manager.startDevice(root.deviceId)
        }
    }

    function removeDevice() {
        if (!root.manager || root.deviceId.length === 0) {
            return
        }
        close()
        root.deviceRemovalRequested(root.deviceId)
        root.manager.removeDevice(root.deviceId)
    }

    contentItem: ColumnLayout {
        spacing: 3

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 9
            Layout.rightMargin: 9
            Layout.topMargin: 4
            Layout.bottomMargin: 3
            text: root.deviceName
            color: Theme.textMuted
            elide: Text.ElideRight
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 5
            color: toggleMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.deviceStatus === "Running" ? "Stop Device" : "Start Device"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: toggleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDevice()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 5
            color: windowMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.standalone ? "Focus Window" : "Open in Window"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: windowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.openStandaloneRequested(root.device)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 5
            color: clearMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear Data"
                color: Theme.warning
                font.pixelSize: 12
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.clearDataRequested(root.device)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 5
            color: removeMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove Device"
                color: Theme.error
                font.pixelSize: 12
            }

            MouseArea {
                id: removeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removeDevice()
            }
        }
    }
}
