import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// Overflow for the device workspace toolbar. On narrow windows the inline
// action buttons no longer fit next to the URL field, so they collapse into
// this menu instead of squeezing the field and clipping the last button.
Popup {
    id: root

    property var device: null
    property bool standalone: false
    property bool showDevTools: false
    property bool canReload: false

    signal reloadRequested()
    signal devToolsToggled()
    signal openStandaloneRequested()

    parent: Overlay.overlay
    width: 190
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.panelRaised
        border.width: 1
        border.color: Theme.borderStrong
        radius: Theme.radiusSmall
    }

    function openAt(anchor) {
        const point = anchor.mapToItem(Overlay.overlay, anchor.width, anchor.height + 4)
        x = Math.max(8, Math.min(point.x - width, Overlay.overlay.width - width - 8))
        y = Math.max(8, Math.min(point.y, Overlay.overlay.height - height - 8))
        open()
    }

    function rowColor(mouse, enabled) {
        if (!enabled) return "transparent"
        return mouse.containsMouse ? Theme.panelSoft : "transparent"
    }

    contentItem: ColumnLayout {
        spacing: 2

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 5
            color: root.rowColor(reloadMouse, root.canReload)
            opacity: root.canReload ? 1.0 : 0.45
            visible: !root.standalone

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Reload"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: reloadMouse
                anchors.fill: parent
                enabled: root.canReload
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.reloadRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 5
            color: root.rowColor(devToolsMouse, true)
            visible: !root.standalone

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.showDevTools ? "Hide DevTools" : "DevTools"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: devToolsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.devToolsToggled()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 5
            color: root.rowColor(windowMouse, true)
            visible: root.device !== null

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
                    root.openStandaloneRequested()
                }
            }
        }
    }
}
