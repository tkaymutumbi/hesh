import QtQuick
import QtQuick.Layouts
import Hesh 1.0

pragma ComponentBehavior: Bound

Rectangle {
    id: root

    property var manager
    property var standaloneDeviceIds: ({})
    // Reordering state lives here rather than in each row: exactly one device is
    // dragged at a time, and every row needs the same insertion boundary to draw
    // its line.
    property string draggedDeviceId: ""
    property int dropBoundary: -1
    signal addDeviceRequested()
    signal openStandaloneRequested(var device)
    signal clearDataRequested(var device)
    signal deviceRemovalRequested(string deviceId)
    color: Theme.panel
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 26
        anchors.bottomMargin: 14
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 20

            Text {
                text: "DEVICES"
                color: Theme.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.manager ? root.manager.deviceCount : 0
                color: Theme.textFaint
                font.pixelSize: 11
            }
        }

        Item { Layout.preferredHeight: 16 }

        ListView {
            id: deviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.manager ? root.manager.devices : null

            delegate: DeviceListItem {
                manager: root.manager
                standalone: root.standaloneDeviceIds[deviceId] === true
                dropIndex: root.draggedDeviceId.length > 0 ? root.dropBoundary : -1
                selected: root.manager && root.manager.selectedDevice
                          && root.manager.selectedDevice.id === deviceId
                onActivated: if (root.manager) root.manager.selectDevice(deviceId)
                onDragStarted: (draggedId, boundary) => {
                    root.draggedDeviceId = draggedId
                    root.dropBoundary = boundary
                }
                onDragUpdated: (draggedId, boundary) => {
                    if (root.draggedDeviceId === draggedId) root.dropBoundary = boundary
                }
                onDragFinished: (draggedId) => {
                    const target = root.dropBoundary
                    root.draggedDeviceId = ""
                    root.dropBoundary = -1
                    // The order is part of the device records, so the manager
                    // persists it as soon as the row lands.
                    if (root.manager && draggedId) root.manager.moveDevice(draggedId, target)
                }
                onOpenStandaloneRequested: (selectedDevice) => root.openStandaloneRequested(selectedDevice)
                onClearDataRequested: (selectedDevice) => root.clearDataRequested(selectedDevice)
                onDeviceRemovalRequested: (removedDeviceId) => root.deviceRemovalRequested(removedDeviceId)
            }

            Text {
                anchors.centerIn: parent
                visible: deviceList.count === 0
                text: "Your devices will appear here"
                color: Theme.textFaint
                font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Item { Layout.preferredHeight: 12 }

        AppButton {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            text: "+  Add Device"
            secondary: true
            compact: true
            onClicked: root.addDeviceRequested()
        }
    }
}
