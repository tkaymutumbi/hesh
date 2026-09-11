import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

pragma ComponentBehavior: Bound

ApplicationWindow {
    id: window

    visible: true
    width: 1240
    height: 780
    minimumWidth: 360
    minimumHeight: 520
    color: Theme.window
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Hesh"

    property bool maximized: false
    readonly property bool compactWindow: width < 760
    // Presentation is session-only. The maps are replaced (rather than
    // mutated in place) so all QML bindings observing them are invalidated.
    property var standaloneWindows: ({})
    property var detachedDeviceIds: ({})
    property var pendingStandaloneIds: ({})
    property bool shuttingDown: false

    function copyMap(source) {
        var result = {}
        for (var key in source) result[key] = source[key]
        return result
    }

    function setDetached(deviceId, detached) {
        if (!deviceId) return
        var next = copyMap(window.detachedDeviceIds)
        if (detached) next[deviceId] = true
        else delete next[deviceId]
        window.detachedDeviceIds = next
    }

    function setPending(deviceId, pending) {
        if (!deviceId) return
        var next = copyMap(window.pendingStandaloneIds)
        if (pending) next[deviceId] = true
        else delete next[deviceId]
        window.pendingStandaloneIds = next
    }

    function isDeviceDetached(deviceId) {
        return !!(deviceId && window.detachedDeviceIds[deviceId] === true)
    }

    function rememberStandalone(deviceId, host) {
        var next = copyMap(window.standaloneWindows)
        next[deviceId] = host
        window.standaloneWindows = next
    }

    function forgetStandalone(deviceId) {
        var next = copyMap(window.standaloneWindows)
        delete next[deviceId]
        window.standaloneWindows = next
    }

    function finishStandalone(deviceId, host) {
        if (!deviceId) return
        var current = window.standaloneWindows[deviceId]
        if (current && current !== host) return
        if (host) {
            // Release the WebEngine surface first. This guarantees the
            // embedded Loader cannot create a second live page while the
            // standalone object's deferred destruction is pending.
            host.releaseBrowserSurface()
            host.suppressCloseSignal = true
            host.destroy()
        }
        forgetStandalone(deviceId)
        setDetached(deviceId, false)
    }

    function closeStandaloneForDevice(deviceId) {
        var host = window.standaloneWindows[deviceId]
        if (!host) {
            setPending(deviceId, false)
            setDetached(deviceId, false)
            return
        }
        host.releaseBrowserSurface()
        host.suppressCloseSignal = true
        host.close()
        host.destroy()
        forgetStandalone(deviceId)
        setDetached(deviceId, false)
    }

    function requestClearData(device) {
        if (!device) return
        clearDataDialog.device = device
        clearDataDialog.open()
    }

    function openStandaloneForDevice(device) {
        if (!device || !device.id) return
        var deviceId = device.id
        var existing = window.standaloneWindows[deviceId]
        if (existing) {
            existing.focusWindow()
            return
        }
        if (window.pendingStandaloneIds[deviceId]) return

        // Detach first. The actual Window is created on the next turn, after
        // DeviceWorkspace's Loader has synchronously torn down its WebEngineView.
        setPending(deviceId, true)
        setDetached(deviceId, true)
        Qt.callLater(function() {
            if (!window.detachedDeviceIds[deviceId]) {
                setPending(deviceId, false)
                return
            }
            setPending(deviceId, false)
            if (window.shuttingDown || !device || !device.id) {
                setDetached(deviceId, false)
                return
            }
            if (window.standaloneWindows[deviceId]) {
                window.standaloneWindows[deviceId].focusWindow()
                return
            }
            var host = standaloneWindowComponent.createObject(null, { device: device })
            if (!host) {
                setDetached(deviceId, false)
                return
            }
            rememberStandalone(deviceId, host)
            host.closedByUser.connect(function(closedId) {
                window.finishStandalone(closedId || deviceId, host)
            })
            host.deviceUnavailable.connect(function(unavailableId) {
                window.finishStandalone(unavailableId || deviceId, host)
            })
            host.mainWindowRequested.connect(function(requestedId) {
                window.finishStandalone(requestedId || deviceId, host)
                window.raise()
                window.requestActivate()
            })
            host.show()
            host.focusWindow()
        })
    }

    function closeAllStandaloneWindows() {
        var snapshot = copyMap(window.standaloneWindows)
        for (var deviceId in snapshot) {
            var host = snapshot[deviceId]
            if (!host) continue
            host.releaseBrowserSurface()
            host.suppressCloseSignal = true
            host.close()
            host.destroy()
        }
        window.standaloneWindows = ({})
        window.pendingStandaloneIds = ({})
        // Keep the embedded loaders detached while the main window is
        // shutting down; restoring a WebEngineView here would only create a
        // transient browser surface during application teardown.
    }

    onClosing: {
        window.shuttingDown = true
        window.closeAllStandaloneWindows()
    }

    Connections {
        target: Qt.application
        function onAboutToQuit() {
            if (!window.shuttingDown) {
                window.shuttingDown = true
                window.closeAllStandaloneWindows()
            }
        }
    }

    function toggleMaximize() {
        if (maximized) {
            showNormal()
            maximized = false
        } else {
            showMaximized()
            maximized = true
        }
    }

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--maximized") >= 0) {
            showMaximized()
            maximized = true
        }
    }

    Rectangle {
        id: shell
        anchors.fill: parent
        color: Theme.window
        border.width: 1
        border.color: Theme.borderStrong
        radius: 8
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: titlebar
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                color: Theme.panel
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 12
                    spacing: 14

                    Image {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        source: "qrc:/qt/qml/Hesh/assets/icons/hesh.png"
                        sourceSize.width: 64
                        sourceSize.height: 64
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: "HESH"
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2.0
                    }

                    Text {
                        text: "DEVICE DEVELOPMENT"
                        color: Theme.textFaint
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.0
                        visible: !window.compactWindow
                    }

                    Item { Layout.fillWidth: true }

                    AppButton {
                        text: window.compactWindow ? "+  New" : "+  New Device"
                        compact: true
                        onClicked: createDeviceDialog.open()
                    }

                    AppButton {
                        text: "Settings"
                        compact: true
                        secondary: true
                        visible: !window.compactWindow
                    }

                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    acceptedButtons: Qt.LeftButton
                    onPressed: window.startSystemMove()
                    onDoubleClicked: window.toggleMaximize()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Sidebar {
                    id: sidebar
                    Layout.fillHeight: true
                    Layout.preferredWidth: 252
                    visible: !window.compactWindow
                    manager: deviceManager
                    onAddDeviceRequested: createDeviceDialog.open()
                    standaloneDeviceIds: window.detachedDeviceIds
                    onOpenStandaloneRequested: (device) => window.openStandaloneForDevice(device)
                    onClearDataRequested: (device) => window.requestClearData(device)
                    onDeviceRemovalRequested: (deviceId) => window.closeStandaloneForDevice(deviceId)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.window

                    EmptyState {
                        anchors.fill: parent
                        visible: deviceManager.deviceCount === 0
                        onCreateRequested: createDeviceDialog.open()
                    }

                    DeviceWorkspace {
                        anchors.fill: parent
                        visible: deviceManager.deviceCount > 0
                        manager: deviceManager
                        device: deviceManager.selectedDevice
                        standalone: deviceManager.selectedDevice
                                     ? window.isDeviceDetached(deviceManager.selectedDevice.id)
                                     : false
                        onOpenStandaloneRequested: (device) => window.openStandaloneForDevice(device)
                    }
                }
            }

        }
    }

    CreateDeviceDialog {
        id: createDeviceDialog
        manager: deviceManager
    }

    ClearDeviceDataDialog {
        id: clearDataDialog
        manager: deviceManager
    }

    Component {
        id: standaloneWindowComponent
        StandaloneDeviceWindow { }
    }
}
