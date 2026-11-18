import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Hesh 1.0

pragma ComponentBehavior: Bound

// OAuth windows retain their opener and share this device's persistent profile.
// While open, MCP targets the topmost popup; closing it restores its parent.
Window {
    id: root
    property var device: null
    property var manager: null
    readonly property var pageView: popupFrame.pageView
    visible: false
    transientParent: null
    title: (device ? device.name : "Browser") + " — Sign-in"
    color: Theme.window
    width: Math.min(640, Screen.desktopAvailableWidth - 32)
    height: Math.min(720, Screen.desktopAvailableHeight - 64)
    minimumWidth: Math.min(320, Screen.desktopAvailableWidth - 32)
    minimumHeight: Math.min(300, Screen.desktopAvailableHeight - 64)
    DeviceFrame {
        id: popupFrame
        anchors.fill: parent
        device: root.device
        manager: root.manager
        availableWidth: root.width
        availableHeight: root.height
        responsiveViewport: true
        isPopup: true
        navigateOnCreate: false
        bezel: 0
        screenRadius: 0
        showChrome: false
        presentationPadding: 0
    }
    Connections { target: root.pageView; function onWindowCloseRequested() { root.close() } }
    Connections { target: root.device; function onDataClearing() { root.close() } }
    Connections {
        target: Automation
        function onLoginRequired(id) {
            if (root.device && root.device.id === id) { root.show(); root.raise(); root.requestActivate() }
        }
    }
    LoginHandoff { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; deviceId: root.device ? root.device.id : "" }
    SurfaceKeepAlive { running: root.visible }
}
