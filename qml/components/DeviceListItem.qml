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
    // Reordering. The card is translated with the pointer rather than moved, so
    // the anchors that size it stay intact and the list does not reflow
    // mid-drag: the sidebar holds one drop boundary and every row draws the
    // insertion line for it.
    property int dropIndex: -1
    readonly property bool isDragging: dragHandler.active
    readonly property bool showDropLineAbove: !root.isDragging && root.dropIndex === index
    // The end-of-list boundary belongs under the last row only, or every row
    // would draw it.
    readonly property bool showDropLineBelow: {
        const view = root.ListView.view
        if (!view || root.isDragging || root.dropIndex < 0) return false
        return index === view.count - 1 && root.dropIndex === view.count
    }
    signal activated()
    signal openStandaloneRequested(var device)
    signal clearDataRequested(var device)
    signal deviceRemovalRequested(string deviceId)
    signal dragStarted(string deviceId, int dropIndex)
    signal dragUpdated(string deviceId, int dropIndex)
    signal dragFinished(string deviceId)

    implicitHeight: 76
    width: ListView.view ? ListView.view.width : 220
    // Delegates are siblings under the ListView content item, so raise the
    // whole dragged row above neighboring delegates while its card follows
    // the pointer.
    z: root.isDragging ? 2 : 0

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        radius: Theme.radiusSmall
        opacity: root.isDragging ? 0.92 : 1.0
        transform: Translate { y: root.isDragging ? dragHandler.activeTranslation.y : 0 }
        color: root.isDragging ? Theme.panelRaised
                               : root.selected ? root.accentSoftColor
                               : (rowMouseArea.containsMouse ? Theme.panelRaised : "transparent")
        border.width: root.selected || root.isDragging ? 1 : 0
        border.color: root.isDragging ? root.accentColor : root.accentBorderColor

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

    // Insertion boundary under the pointer, in list terms: the row the device
    // would land before, or the row count for the end of the list. Delegate
    // geometry and itemAtIndex use content coordinates, so the pointer is
    // clamped to the viewport and then translated by the scroll offset. Walking
    // visible delegates also makes the gaps between rows resolve to the nearest
    // boundary instead of jumping to the end of the list.
    function contentDropIndex() {
        const view = root.ListView.view
        if (!view) return index
        const point = root.mapToItem(view,
                                     dragHandler.centroid.position.x,
                                     dragHandler.centroid.position.y)
        const viewY = Math.max(0, Math.min(view.height, point.y))
        const pointerContentY = view.contentY + viewY
        let boundary = 0
        for (let row = 0; row < view.count; ++row) {
            const item = view.itemAtIndex(row)
            if (!item) continue
            boundary = row + 1
            if (pointerContentY < item.y + item.height / 2) return row
        }
        return Math.min(view.count, boundary)
    }

    // A plain pointer handler instead of Qt's drag-and-drop protocol: the drop
    // target is a row boundary in the same list, so mapping the pointer to an
    // index is the whole job, and the left button stays free for selection and
    // the context menu until the drag threshold is crossed.
    DragHandler {
        id: dragHandler
        acceptedButtons: Qt.LeftButton
        // The delegate is positioned by ListView. Move only the card's visual
        // Translate while dragging so Qt does not also move the delegate and
        // distort the pointer-to-content coordinate mapping.
        target: null

        onActiveChanged: {
            if (active) {
                const boundary = root.contentDropIndex()
                root.dragStarted(root.deviceId, boundary)
                root.dragUpdated(root.deviceId, boundary)
            } else {
                root.dragFinished(root.deviceId)
            }
        }

        onActiveTranslationChanged: {
            if (active) root.dragUpdated(root.deviceId, root.contentDropIndex())
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        y: -1
        height: 2
        radius: 1
        z: 4
        color: Theme.accent
        visible: root.showDropLineAbove
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        y: root.height - 1
        height: 2
        radius: 1
        z: 4
        color: Theme.accent
        visible: root.showDropLineBelow
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
