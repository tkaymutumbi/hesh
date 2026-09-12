import QtQuick
import QtQuick.Layouts
import Hesh 1.0

Item {
    id: root

    required property string deviceId
    required property string deviceName
    required property string deviceTypeLabel
    required property string deviceStatus
    required property var deviceObject
    property var device: deviceObject
    property var manager
    property bool selected: false
    property bool standalone: false
    // A device accent overrides the application accent for this card. The
    // device model stores "no accent" as an empty name and never reads
    // application preferences, so the fallback is resolved here.
    readonly property bool useDeviceAccent: root.device !== null && root.device.hasAccent
    readonly property color accentColor: root.useDeviceAccent ? root.device.accent : Theme.accent
    readonly property color accentSoftColor: root.useDeviceAccent ? root.device.accentSoft : Theme.accentSoft
    readonly property color accentBorderColor: root.useDeviceAccent ? root.device.accentBorder : Theme.accentBorder
    signal activated()
    signal openStandaloneRequested(var device)
    signal clearDataRequested(var device)
    signal deviceRemovalRequested(string deviceId)

    implicitHeight: 76
    width: ListView.view ? ListView.view.width : 220

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        radius: Theme.radiusSmall
        color: root.selected ? root.accentSoftColor
                             : (rowMouseArea.containsMouse ? Theme.panelRaised : "transparent")
        border.width: root.selected ? 1 : 0
        border.color: root.accentBorderColor

        Rectangle {
            width: 3
            height: parent.height - 18
            anchors.left: parent.left
            anchors.leftMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: root.selected ? root.accentColor : "transparent"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 9

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                    color: root.deviceStatus === "Running" ? Theme.success : Theme.textFaint
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: root.deviceName
                    color: Theme.text
                    elide: Text.ElideRight
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                RowLayout {
                    spacing: 7

                    Text {
                        text: root.deviceTypeLabel
                        color: root.selected ? root.accentColor : Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.deviceStatus
                        color: root.deviceStatus === "Running" ? Theme.success : Theme.textMuted
                        elide: Text.ElideMiddle
                        font.pixelSize: 11
                    }
                }
            }

        }

        MouseArea {
            id: rowMouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                root.activated()
                if (mouse.button === Qt.RightButton) {
                    deviceMenu.openAt(root, mouse.x, mouse.y)
                }
            }
        }
    }

    DeviceContextMenu {
        id: deviceMenu
        manager: root.manager
        deviceId: root.deviceId
        deviceName: root.deviceName
        deviceStatus: root.deviceStatus
        device: root.device
        standalone: root.standalone
        onOpenStandaloneRequested: (selectedDevice) => root.openStandaloneRequested(selectedDevice)
        onClearDataRequested: (selectedDevice) => root.clearDataRequested(selectedDevice)
        onDeviceRemovalRequested: (removedDeviceId) => root.deviceRemovalRequested(removedDeviceId)
    }
}
