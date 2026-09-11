import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// Destructive confirmation for the device menu's Clear Data action. The wipe
// itself lives in Device::clearData(); this dialog only gates the call.
Popup {
    id: root

    property var manager
    property var device: null

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    // Never wider than the window: a fixed width would push the buttons off a
    // narrow workspace.
    width: Math.min(470, (Overlay.overlay ? Overlay.overlay.width : 470) - 48)
    // The popup takes its height from the content below, so the content must
    // not be anchored: an anchored contentItem contributes no implicit size and
    // the dialog collapses around it.
    padding: 28

    Overlay.modal: Rectangle { color: "#99080a0e" }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: Theme.panel
        border.width: 1
        border.color: Theme.borderStrong

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 12
            anchors.rightMargin: 12
            iconText: "×"
            tooltip: "Close"
            onClicked: root.close()
        }
    }

    function clearData() {
        if (root.manager && root.device) root.manager.clearDeviceData(root.device.id)
        root.close()
    }

    contentItem: ColumnLayout {
        spacing: 0

        Text {
            Layout.fillWidth: true
            text: "Clear Device Data"
            color: Theme.text
            font.pixelSize: 19
            font.weight: Font.Medium
        }

        Item { Layout.preferredHeight: 14 }

        Text {
            Layout.fillWidth: true
            text: root.device
                  ? "Delete the browser data stored for \"" + root.device.name + "\"?"
                  : "Delete the browser data stored for this device?"
            color: Theme.text
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            Layout.fillWidth: true
            text: "Cookies, local storage, IndexedDB, and cached files are removed. "
                  + "The preview reloads with a fresh session and this cannot be undone."
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Item { Layout.preferredHeight: 24 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            Item { Layout.fillWidth: true }

            AppButton {
                text: "Cancel"
                secondary: true
                compact: true
                onClicked: root.close()
            }

            AppButton {
                text: "Clear Data"
                destructive: true
                compact: true
                onClicked: root.clearData()
            }
        }
    }
}
