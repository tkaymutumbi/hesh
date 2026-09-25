import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

Popup {
    id: root

    property var manager
    signal deviceCreated(var device)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    // Stay inside the window on narrow workspaces instead of clipping the
    // fields and the action buttons.
    width: Math.min(560, (Overlay.overlay ? Overlay.overlay.width : 560) - 40)
    height: Math.min(530, (Overlay.overlay ? Overlay.overlay.height : 530) - 40)
    padding: 0

    Overlay.modal: Rectangle { color: "#99080a0e" }

    background: Rectangle {
        id: dialogBackground
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

    // The defaults live in Preferences so the dialog starts from the user's
    // choice instead of a hardcoded profile and URL.
    function reset() {
        nameField.text = Preferences.newDeviceName
        urlField.text = Preferences.newDeviceUrl
        profileCombo.currentIndex = indexOfProfile(Preferences.newDeviceProfile)
    }

    function indexOfProfile(name) {
        const profiles = root.manager ? root.manager.availableProfiles : []
        for (let i = 0; i < profiles.length; ++i) {
            if (profiles[i].name === name) return i
        }
        return 0
    }

    onOpened: reset()
    onClosed: reset()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 0

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Create Device"
                    color: Theme.text
                    font.pixelSize: 19
                    font.weight: Font.Medium
                }

                Text {
                    text: "Set the viewport and starting URL."
                    color: Theme.textMuted
                    font.pixelSize: 12
                }
            }

        }

        Item { Layout.preferredHeight: 26 }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            Text {
                text: "Name"
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            TextField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: 38
                color: Theme.text
                font.pixelSize: 12
                selectByMouse: true
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.input
                    border.width: 1
                    border.color: parent.activeFocus ? Theme.accentStrong : Theme.border
                }
                leftPadding: 12
                rightPadding: 12
            }

            Text {
                text: "Device profile"
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            ComboBox {
                id: profileCombo
                Layout.fillWidth: true
                implicitHeight: 38
                model: root.manager ? root.manager.availableProfiles : []
                textRole: "name"
                valueRole: "name"
                leftPadding: 12
                rightPadding: 32
                contentItem: Text {
                    text: profileCombo.displayText
                    color: Theme.text
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 12
                }
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.input
                    border.width: 1
                    border.color: profileCombo.activeFocus ? Theme.accentStrong : Theme.border
                }
                popup: Popup {
                    y: profileCombo.height + 4
                    width: profileCombo.width
                    padding: 4
                    contentItem: ListView {
                        implicitHeight: Math.min(contentHeight, 250)
                        model: profileCombo.popup.visible ? profileCombo.delegateModel : null
                        clip: true
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.panelRaised
                        border.width: 1
                        border.color: Theme.borderStrong
                    }
                }
            }

            Text {
                text: "URL"
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            TextField {
                id: urlField
                Layout.fillWidth: true
                implicitHeight: 38
                color: Theme.text
                font.pixelSize: 12
                selectByMouse: true
                inputMethodHints: Qt.ImhUrlCharactersOnly
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.input
                    border.width: 1
                    border.color: parent.activeFocus ? Theme.accentStrong : Theme.border
                }
                leftPadding: 12
                rightPadding: 12
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Text {
                    text: "Viewport"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Text {
                    text: profileCombo.currentIndex >= 0 && root.manager
                          ? root.manager.availableProfiles[profileCombo.currentIndex].width + " × "
                            + root.manager.availableProfiles[profileCombo.currentIndex].height
                          : ""
                    color: Theme.text
                    font.pixelSize: 11
                }

                // The user agent is a single long line. Without a width cap its
                // implicit width widens the whole layout past the dialog edge.
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    text: profileCombo.currentIndex >= 0 && root.manager
                          ? root.manager.availableProfiles[profileCombo.currentIndex].userAgent.split(" Chrome")[0]
                          : ""
                    color: Theme.textFaint
                    elide: Text.ElideRight
                    font.pixelSize: 10
                }
            }
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
                text: "Create Device"
                compact: true
                onClicked: {
                    if (root.manager) {
                        root.deviceCreated(root.manager.createWebDevice(nameField.text,
                                                                        profileCombo.currentText,
                                                                        urlField.text))
                    }
                    root.close()
                }
            }
        }
    }

}
