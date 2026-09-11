import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

pragma ComponentBehavior: Bound

Item {
    id: root

    property var device: null
    property var manager
    // Toolbar density. The metric labels and the inline action buttons each
    // need room next to the URL field; below these widths they collapse
    // instead of squeezing the field and pushing the last button off-screen.
    // At the default window size the workspace is ~990px, which still fits the
    // metric labels.
    readonly property bool showMetrics: width >= 950
    readonly property bool inlineActions: width >= 740
    property bool showDevTools: false
    property bool standalone: false
    property bool frameEnabled: true
    signal openStandaloneRequested(var device)

    // WebEngine does not reliably receive application-level accelerators when
    // a QML control owns focus. Keep these at the workspace level so the same
    // browser behaviour works whether the page or the URL field is focused.
    Shortcut {
        sequence: "Ctrl+R"
        context: Qt.ApplicationShortcut
        enabled: root.visible && !root.standalone && deviceLoader.item !== null
        onActivated: deviceLoader.item.reloadPage(false)
    }

    Shortcut {
        sequence: "Ctrl+Shift+R"
        context: Qt.ApplicationShortcut
        enabled: root.visible && !root.standalone && deviceLoader.item !== null
        onActivated: deviceLoader.item.reloadPage(true)
    }

    onDeviceChanged: {
        // A Loader otherwise reuses the same DeviceFrame when selection
        // changes. Recreating it also recreates the WebEngineProfile binding,
        // keeping each device's browser data isolated.
        // Skip the toggle entirely when the new device is detached to a
        // standalone window – the embedded Loader is already inactive and
        // toggling would leave frameEnabled false after the window closes
        // (black placeholder bug seen in the screenshot).
        if (root.standalone) return
        // Capture the device that triggered this change; if the user
        // switches again before the callLater fires, ignore the stale
        // callback so we don't clobber the newer toggle.
        var expectedId = root.device ? root.device.id : ""
        root.frameEnabled = false
        Qt.callLater(function() {
            if (root.standalone) return
            if (root.device && expectedId && root.device.id !== expectedId) return
            root.frameEnabled = true
        })
    }

    onStandaloneChanged: {
        // When a standalone window closes, the embedded host must be
        // re-enabled even if the last onDeviceChanged was skipped.
        if (!root.standalone && !root.frameEnabled) {
            root.frameEnabled = true
        }
    }

    // Clearing a device's data destroys its WebEngineProfile before the storage
    // directories are removed, and the same profile path cannot be reopened
    // until that profile is gone. Release the frame for the wipe, then rebuild
    // it so the profile and the page session are fresh.
    Connections {
        target: root.device

        function onDataClearing() {
            root.frameEnabled = false
        }

        function onDataCleared() {
            Qt.callLater(function() { root.frameEnabled = true })
        }
    }

    DeviceToolbarMenu {
        id: toolbarMenu
        device: root.device
        standalone: root.standalone
        showDevTools: root.showDevTools
        canReload: root.device !== null && !root.standalone && deviceLoader.item !== null
        onReloadRequested: if (deviceLoader.item) deviceLoader.item.reloadPage(false)
        onDevToolsToggled: root.showDevTools = !root.showDevTools
        onOpenStandaloneRequested: root.openStandaloneRequested(root.device)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: Theme.window

                Text {
                    anchors.centerIn: parent
                    visible: !root.device && !root.standalone
                    text: "Select a device to begin"
                    color: Theme.textFaint
                    font.pixelSize: 13
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    visible: root.device !== null && root.standalone

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "OPEN IN STANDALONE WINDOW"
                        color: Theme.accent
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.5
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.device ? root.device.name : ""
                        color: Theme.textMuted
                        font.pixelSize: 12
                    }

                    AppButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Focus Window"
                        compact: true
                        onClicked: root.openStandaloneRequested(root.device)
                    }
                }
            }

            Loader {
                id: deviceLoader
                anchors.centerIn: parent
                active: root.device !== null && !root.standalone && root.frameEnabled
                sourceComponent: deviceFrameComponent

                Component {
                    id: deviceFrameComponent

                    DeviceFrame {
                        device: root.device
                        availableWidth: stage.width
                        availableHeight: stage.height
                        showDevTools: root.showDevTools

                        Behavior on presentationScale {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: Theme.panel
            border.width: 1
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 28
                spacing: 18

                TextField {
                    id: urlField
                    Layout.fillWidth: true
                    text: root.device ? root.device.url : ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    selectByMouse: true
                    placeholderText: "Enter a URL"
                    placeholderTextColor: Theme.textFaint
                    background: Rectangle {
                        color: Theme.input
                        border.width: urlField.activeFocus ? 1 : 0
                        border.color: Theme.accentStrong
                        radius: Theme.radiusSmall
                    }
                    leftPadding: 10
                    rightPadding: 10
                    onAccepted: {
                        if (root.device && text.trim().length > 0) root.device.url = text.trim()
                    }
                }

                AppButton {
                    compact: true
                    text: "Go"
                    onClicked: {
                        if (root.device && urlField.text.trim().length > 0) {
                            root.device.url = urlField.text.trim()
                            urlField.focus = false
                        }
                    }
                }

                AppButton {
                    compact: true
                    text: "Reload"
                    secondary: true
                    visible: root.device !== null && !root.standalone && root.inlineActions
                    onClicked: if (deviceLoader.item) deviceLoader.item.reloadPage(false)
                }

                AppButton {
                    compact: true
                    text: root.showDevTools ? "Hide DevTools" : "DevTools"
                    secondary: true
                    visible: !root.standalone && root.inlineActions
                    onClicked: root.showDevTools = !root.showDevTools
                }

                AppButton {
                    compact: true
                    text: root.standalone ? "Focus Window" : "Open in Window"
                    secondary: root.standalone
                    visible: root.device !== null && root.inlineActions
                    onClicked: root.openStandaloneRequested(root.device)
                }

                IconButton {
                    id: overflowButton
                    visible: !root.inlineActions
                    iconText: "⋯"
                    tooltip: "More actions"
                    onClicked: toolbarMenu.openAt(overflowButton)
                }

                Text {
                    visible: root.showMetrics
                    text: root.device ? root.device.viewportWidth + " × " + root.device.viewportHeight : ""
                    color: Theme.text
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Text {
                    visible: root.showMetrics
                    text: root.device ? "DPR " + Number(root.device.devicePixelRatio).toFixed(2) : ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                }

                Text {
                    visible: root.showMetrics
                    text: deviceLoader.item ? deviceLoader.item.presentationMode : "Fit"
                    color: Theme.textMuted
                    font.pixelSize: 11
                }

                Text {
                    visible: root.showMetrics
                    text: deviceLoader.item ? deviceLoader.item.presentationPercent + "%" : ""
                    color: Theme.accent
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
