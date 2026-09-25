import QtQuick
import QtQuick.Window
import QtWebEngine
import Hesh 1.0

pragma ComponentBehavior: Bound

// A real top-level window is deliberately created without a transient parent.
// This lets a Wayland compositor treat each device as an independent surface.
Window {
    id: root

    property var device: null
    property var manager: null
    property string deviceId: ""
    // Latched off while the main window tears this host down, and while a
    // clear-data wipe is pending.
    property bool browserSurfaceReleased: false
    readonly property bool browserSurfaceActive: browserLoader.active
    property bool suppressCloseSignal: false
    // DevTools opens as its own top-level window so Hyprland can tile it next
    // to the device instead of resizing the device's viewport.
    property bool devToolsOpen: false
    // Window dimensions are device-independent pixels. Use the compositor's
    // available work area (which excludes reserved bars/panels) and never
    // enlarge the logical viewport; upscaling the WebEngine surface is what
    // makes portrait previews look soft on fractional-scale displays.
    readonly property real viewportWidth: root.device ? Math.max(1, Number(root.device.viewportWidth)) : 412
    readonly property real viewportHeight: root.device ? Math.max(1, Number(root.device.viewportHeight)) : 915
    readonly property real availableScreenWidth: Screen.desktopAvailableWidth > 0
                                                 ? Screen.desktopAvailableWidth : 1200
    readonly property real availableScreenHeight: Screen.desktopAvailableHeight > 0
                                                  ? Screen.desktopAvailableHeight : 675
    readonly property real workAreaVerticalMargin: 64
    readonly property real initialPresentationScale: root.device
                                                     ? Math.min(1.0,
                                                                Math.max(1, root.availableScreenWidth - 32) / root.viewportWidth,
                                                                Math.max(1, root.availableScreenHeight - root.workAreaVerticalMargin) / root.viewportHeight)
                                                     : 1.0

    signal closedByUser(string id)
    signal deviceUnavailable(string id)
    signal focusChanged(string id, bool focused)
    signal mainWindowRequested(string id)

    visible: false
    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: null
    color: Theme.window
    title: root.device ? root.device.name + " — Hesh" : "Hesh"
    width: Math.max(1, Math.round(root.viewportWidth * root.initialPresentationScale))
    height: Math.max(1, Math.round(root.viewportHeight * root.initialPresentationScale))
    minimumWidth: 1
    minimumHeight: 1

    onDeviceChanged: {
        if (root.device) root.deviceId = root.device.id
    }

    onActiveChanged: {
        root.focusChanged(root.deviceId, root.active)
        if (root.active && browserLoader.item) {
            Qt.callLater(function() {
                if (root.active && browserLoader.item)
                    browserLoader.item.recoverSurface()
            })
        }
    }

    function focusWindow() {
        if (!root.visible) {
            root.show()
        }
        root.raise()
        root.requestActivate()
        // Wayland can create the surface black until the WebEngineView
        // is forced back to Active after the window is mapped.
        if (browserLoader.item) {
            var frame = browserLoader.item
            if (frame) {
                if (frame.ensureActive) frame.ensureActive()
                if (frame.pageFailed) frame.reloadPage()
            }
        }
    }

    onVisibleChanged: {
        if (root.visible && browserLoader.item) {
            // Give the compositor a frame to map the surface before
            // forcing Active; otherwise the first paint stays #0d1014.
            Qt.callLater(function() {
                if (!root.visible || !browserLoader.item) return
                var f = browserLoader.item
                if (f && f.recoverSurface) f.recoverSurface()
                // If the view is stuck on the dark placeholder (black
                // screenshot) without loading or error, nudge it.
                if (f && !f.pageLoaded && !f.pageLoading && !f.pageFailed) f.reloadPage()
            })
        }
    }

    // An unfocused standalone surface can stay black until the pointer moves
    // over it: Chromium only submits a fresh frame when something asks it to.
    // Ask on every event that can expose the window without focusing it
    // (workspace switch, tiling resize, output change, a load finishing in the
    // background), and ask twice, since the first pass can land before
    // Hyprland has mapped the new buffer.
    function scheduleSurfaceRecovery() {
        surfaceRecoveryTimer.passes = 0
        surfaceRecoveryTimer.interval = 60
        surfaceRecoveryTimer.restart()
    }

    Timer {
        id: surfaceRecoveryTimer
        property int passes: 0
        repeat: false
        onTriggered: {
            var f = browserLoader.item
            if (!root.visible || !f || !f.recoverSurface) return
            f.recoverSurface()
            if (++passes < 2) {
                interval = 400
                restart()
            }
        }
    }

    onVisibilityChanged: root.scheduleSurfaceRecovery()
    onScreenChanged: root.scheduleSurfaceRecovery()
    onWidthChanged: root.scheduleSurfaceRecovery()
    onHeightChanged: root.scheduleSurfaceRecovery()

    Connections {
        target: browserLoader.item
        ignoreUnknownSignals: true
        function onPageLoadedChanged() {
            if (browserLoader.item && browserLoader.item.pageLoaded) root.scheduleSurfaceRecovery()
        }
    }

    // A standalone device has no DeviceWorkspace, so provide the same browser
    // shortcuts here. Ctrl+Shift+R bypasses the profile disk cache.
    Shortcut {
        sequence: "Ctrl+R"
        context: Qt.ApplicationShortcut
        enabled: root.visible && browserLoader.item !== null
        onActivated: browserLoader.item.reloadPage(false)
    }

    Shortcut {
        sequence: "Ctrl+Shift+R"
        context: Qt.ApplicationShortcut
        enabled: root.visible && browserLoader.item !== null
        onActivated: browserLoader.item.reloadPage(true)
    }

    // Main.qml calls this before restoring the embedded host. Keeping the
    // browser Loader explicit makes the destroy-before-restore ordering clear.
    function releaseBrowserSurface() {
        root.browserSurfaceReleased = true
    }

    function closeForDeviceRemoval() {
        releaseBrowserSurface()
        root.suppressCloseSignal = true
        root.close()
    }

    onClosing: function(closeEvent) {
        root.devToolsOpen = false
        releaseBrowserSurface()
        if (!root.suppressCloseSignal) root.closedByUser(root.deviceId)
    }

    Connections {
        target: root.device
        ignoreUnknownSignals: true
        function onDestroyed() {
            root.deviceUnavailable(root.deviceId)
        }
    }

    // Clearing this device's data destroys its WebEngineProfile before the
    // storage directories are removed. Drop the browser surface for the wipe and
    // rebuild it afterwards so the profile and the page session are fresh.
    Connections {
        target: root.device

        function onDataClearing() {
            root.browserSurfaceReleased = true
        }

        function onDataCleared() {
            Qt.callLater(function() {
                if (root.device) root.browserSurfaceReleased = false
            })
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        color: Theme.window

        Loader {
            id: browserLoader
            anchors.centerIn: parent
            active: root.device !== null && !root.browserSurfaceReleased
            sourceComponent: DeviceFrame {
                device: root.device
                manager: root.manager
                availableWidth: root.width
                availableHeight: root.height
                bezel: 0
                screenRadius: 0
                showChrome: false
                allowUpscale: false
                presentationPadding: 0
                showDevTools: false
            }
        }

        MouseArea {
            // Only right-click is handled here; ordinary page clicks and
            // scrolling continue to go directly to WebEngineView.
            anchors.fill: parent
            z: 4
            acceptedButtons: Qt.RightButton
            onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    standaloneMenu.openAt(mouse.x, mouse.y)
                }
            }
        }

        StandaloneContextMenu {
            id: standaloneMenu
            parent: surface
            z: 10
            device: root.device
            canGoBack: browserLoader.item ? browserLoader.item.canGoBack : false
            canGoForward: browserLoader.item ? browserLoader.item.canGoForward : false
            devToolsOpen: root.devToolsOpen
            onDevToolsRequested: root.devToolsOpen = !root.devToolsOpen
            onReloadRequested: if (browserLoader.item) browserLoader.item.reloadPage(false)
            onBackRequested: if (browserLoader.item) browserLoader.item.goBack()
            onForwardRequested: if (browserLoader.item) browserLoader.item.goForward()
            onOpenBrowserRequested: (url) => Qt.openUrlExternally(url)
            onMainWindowRequested: root.mainWindowRequested(root.deviceId)
            onCloseRequested: root.close()
        }
    }

    Window {
        id: devToolsWindow
        // Only attach while shown: an invisible attached DevTools view still
        // draws Chromium's inspector overlays into the page.
        readonly property var inspected: root.devToolsOpen && browserLoader.item
                                         ? browserLoader.item.pageView : null
        visible: inspected !== null
        transientParent: null
        flags: Qt.Window
        title: (root.device ? root.device.name : "Device") + " DevTools — Hesh"
        color: Theme.panelRaised
        width: 720
        height: Math.max(480, root.height)

        onClosing: root.devToolsOpen = false

        WebEngineView {
            id: standaloneDevTools
            anchors.fill: parent
            inspectedView: devToolsWindow.inspected
            backgroundColor: Theme.panelRaised
            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    devToolsThemeTimer.attempts = 0
                    devToolsThemeTimer.restart()
                }
            }
        }

        // The DevTools frontend builds its settings store after load, so the
        // idempotent dark-theme script is repeated for a short while.
        Timer {
            id: devToolsThemeTimer
            property int attempts: 0
            interval: 150
            repeat: true
            onTriggered: {
                if (!devToolsWindow.visible || !browserLoader.item || ++attempts > 12) {
                    stop()
                    return
                }
                standaloneDevTools.runJavaScript(browserLoader.item.devToolsDarkThemeScript)
            }
        }
    }
}
