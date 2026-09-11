import QtQuick
import QtQuick.Shapes
import QtWebEngine
import Hesh 1.0

Item {
    id: root

    property var device: null
    property real availableWidth: 620
    property real availableHeight: 560
    property int bezel: 12
    property int screenRadius: 14
    // Embedded previews keep the device bezel and fit down to the workspace.
    // Standalone hosts turn the chrome off and may scale in either direction
    // while preserving the browser's logical viewport dimensions.
    property bool showChrome: true
    property bool allowUpscale: false
    property real presentationPadding: root.showChrome ? 32 : 0
    // Clamped to WebEngine's supported zoom range (0.25–5.0) to avoid
    // bilinear fallback when the workspace is tiny.
    property real minimumPresentationScale: root.allowUpscale ? 0.25 : 0.25
    property real maximumPresentationScale: root.allowUpscale ? 5.0 : 1.0
    property bool pageLoaded: false
    property bool pageLoading: false
    property bool pageFailed: false
    property string pageError: ""
    property bool profileReady: false
    property bool showDevTools: false
    property int devToolsWidth: 420
    property bool devToolsThemeApplied: false
    property int devToolsThemeAttempts: 0
    // Briefly changed when a Wayland surface is exposed again. A tiny zoom
    // transition makes Chromium submit a fresh frame without reloading the
    // page or losing form/application state.
    property real renderWakeNudge: 0
    // Effective chrome metrics scaled with presentation to keep border
    // proportions correct when we render without Item.scale transform.
    property real effectiveBezel: root.bezel * root.presentationScale
    property real effectiveRadius: root.screenRadius * root.presentationScale
    property real profileDpr: root.device ? root.device.devicePixelRatio : 1.0

    function syncDevicePixelRatio() {
        if (!root.profileReady || !root.device || webView.url.toString() === "about:blank")
            return
        var dpr = root.profileDpr
        if (dpr <= 0) return
        var vw = root.device.viewportWidth
        // Emulate devicePixelRatio for CSS media queries, srcset and JS.
        // Runs after load; complements native backing-store which already
        // uses the window's Screen.devicePixelRatio with PassThrough rounding.
        webView.runJavaScript(
            "(() => { try {"
            + " const dpr = " + dpr + ";"
            + " try { Object.defineProperty(window, 'devicePixelRatio', { get: () => dpr, configurable: true }); } catch(e) {}"
            + " let m = document.querySelector('meta[name=viewport]');"
            + " if (!m) { m = document.createElement('meta'); m.name='viewport'; if (document.head) document.head.appendChild(m); }"
            + " let c = m.getAttribute('content') || '';"
            + " if (!c.includes('width=')) c = (c ? c + ', ' : '') + 'width=" + vw + "';"
            + " if (!c.includes('initial-scale')) c += (c ? ', ' : '') + 'initial-scale=1';"
            + " m.setAttribute('content', c);"
            + " try { document.documentElement.style.setProperty('--hesh-dpr', String(dpr)); } catch(e) {}"
            + " return true; } catch(e){ return false; } })()")
    }

    function applyDevToolsDarkTheme() {
        if (!root.showDevTools || root.devToolsThemeApplied
                || devToolsView.loading || devToolsView.url.toString() === "") {
            return
        }

        // DevTools has its own preference store. Chromium's process theme and
        // WebEngineSettings.forceDarkMode do not reliably select this setting.
        devToolsView.runJavaScript(
            "(() => {" +
            "  try {" +
            "    const settings = globalThis.Common?.settings ?? " +
            "      globalThis.Common?.Settings?.Settings?.instance?.();" +
            "    if (!settings) return false;" +
            "    let theme;" +
            "    try { theme = settings.moduleSetting('uiTheme'); } catch (_) {}" +
            "    theme ||= settings.createSetting('uiTheme', 'systemPreferred');" +
            "    if (theme.get() !== 'dark') theme.set('dark');" +
            "    return theme.get() === 'dark';" +
            "  } catch (_) { return false; }" +
            "})()",
            function(applied) {
                root.devToolsThemeApplied = applied === true
            })
    }

    onShowDevToolsChanged: {
        if (root.showDevTools) {
            root.devToolsThemeApplied = false
            root.devToolsThemeAttempts = 0
            devToolsThemeTimer.restart()
        } else {
            devToolsThemeTimer.stop()
            // Detaching DevTools removes Chromium's viewport-size overlay
            // from the inspected page. Repaint once so a label already on
            // screen disappears immediately.
            Qt.callLater(root.recoverSurface)
        }
    }

    Timer {
        id: devToolsThemeTimer
        interval: 150
        repeat: true
        running: root.showDevTools && !root.devToolsThemeApplied
        onTriggered: {
            root.devToolsThemeAttempts++
            root.applyDevToolsDarkTheme()
            if (root.devToolsThemeApplied || root.devToolsThemeAttempts >= 40) stop()
        }
    }

    Timer {
        id: reloadTimer
        interval: 650
        repeat: false
        onTriggered: {
            if (webView) {
                root.pageFailed = false
                root.pageError = ""
                root.reloadPage(false)
            }
        }
    }

    Timer {
        id: renderWakeTimer
        interval: 80
        repeat: false
        onTriggered: root.renderWakeNudge = 0
    }

    // The WebEngineView is now sized directly to its visual size and its
    // zoomFactor is set to presentationScale. This keeps CSS viewport
    // (visual / zoom) at the profile's logical size while rendering at the
    // exact display size – no Item.scale bilinear filtering.
    property real presentationScale: root.device
                                       ? Math.min(root.maximumPresentationScale,
                                                  Math.max(root.minimumPresentationScale, (root.availableWidth
                                                           - root.presentationPadding
                                                           - (root.showDevTools ? root.devToolsWidth + 16 : 0))
                                                           / (root.device.viewportWidth + root.bezel * 2)),
                                                  Math.max(root.minimumPresentationScale, (root.availableHeight
                                                           - root.presentationPadding)
                                                           / (root.device.viewportHeight + root.bezel * 2)))
                                       : 1.0
    readonly property int presentationPercent: Math.round(root.presentationScale * 100)
    readonly property string presentationMode: root.allowUpscale ? "Scale" : "Fit"
    readonly property bool canGoBack: webView.canGoBack
    readonly property bool canGoForward: webView.canGoForward

    // Always wake the WebEngine surface before navigation. A WebEngineView
    // can retain an old imported Wayland buffer after being covered or moved;
    // reloading a non-active surface leaves that buffer black.
    function reloadPage(bypassCache) {
        if (!webView || !root.profileReady || !root.device) return

        reloadTimer.stop()
        root.pageLoaded = false
        root.pageLoading = true
        root.pageFailed = false
        root.pageError = ""
        webView.lifecycleState = WebEngineView.LifecycleState.Active

        if (bypassCache && typeof webView.reloadAndBypassCache === "function")
            webView.reloadAndBypassCache()
        else
            webView.reload()
    }
    function goBack() { webView.goBack() }
    function goForward() { webView.goForward() }
    function ensureActive() {
        if (webView) webView.lifecycleState = WebEngineView.LifecycleState.Active
    }

    function recoverSurface() {
        if (!webView || !root.profileReady || !root.device) return

        webView.lifecycleState = WebEngineView.LifecycleState.Active

        var currentUrl = webView.url.toString()
        if (currentUrl === "" || currentUrl === "about:blank") {
            if (root.device.status === "Running") root.reloadPage(false)
            return
        }

        if (root.pageFailed || webView.renderProcessPid === 0) {
            reloadTimer.restart()
            return
        }

        // Force a new Chromium/Qt Quick texture submission. The JavaScript
        // nudge repaints the document; the fractional zoom change also repairs
        // a stale imported GPU buffer on Wayland.
        root.renderWakeNudge = root.renderWakeNudge === 0 ? 0.001 : -root.renderWakeNudge
        renderWakeTimer.restart()
        webView.runJavaScript(
            "requestAnimationFrame(() => {" +
            " window.dispatchEvent(new Event('resize'));" +
            " document.documentElement.getBoundingClientRect();" +
            "});")
    }

    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active && root.visible)
                Qt.callLater(root.recoverSurface)
        }
    }

    width: root.device
           ? (root.device.viewportWidth + root.bezel * 2) * root.presentationScale
             + (root.showDevTools ? root.devToolsWidth + 16 : 0)
           : 0
    height: root.device
            ? (root.device.viewportHeight + root.bezel * 2) * root.presentationScale
            : 0

    onDeviceChanged: {
        root.pageLoaded = false
        root.pageLoading = false
        root.pageFailed = false
        root.pageError = ""
        if (root.profileReady && root.device) {
            var p = deviceProfile.instance()
            if (p && root.device.userAgent) p.httpUserAgent = root.device.userAgent
            root.syncDevicePixelRatio()
        }
    }

    onProfileDprChanged: {
        if (root.profileReady) root.syncDevicePixelRatio()
    }

    // Every device gets its own browser profile. This keeps localStorage,
    // IndexedDB, cookies and cache isolated and available after a reload.
    WebEngineProfilePrototype {
        id: deviceProfile
        storageName: root.device ? "hesh-device-" + root.device.id : "hesh-device-preview"
        // The device owns the storage layout, so the profile and the
        // clear-data operation can never disagree about the directories.
        persistentStoragePath: root.device ? root.device.persistentStoragePath : ""
        cachePath: root.device ? root.device.cachePath : ""
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }

    Component.onCompleted: {
        // Assign after construction; assigning instance() through a binding
        // during WebEngineView creation can crash Qt WebEngine on Wayland.
        var profile = deviceProfile.instance()
        if (!profile) {
            // The prototype refuses to build a profile while another live
            // profile still owns the same data path. Keep the placeholder
            // instead of attaching a null profile to the view.
            console.warn("Hesh could not create a WebEngine profile for device",
                         root.device ? root.device.id : "<none>")
            return
        }
        if (root.device && root.device.userAgent) {
            profile.httpUserAgent = root.device.userAgent
        }
        webView.profile = profile
        root.profileReady = true
        // On Wayland the first frame can be black until the view is
        // explicitly activated; force Active once the profile is bound.
        if (webView) webView.lifecycleState = WebEngineView.LifecycleState.Active
    }

    Component.onDestruction: {
        // Stop any pending load so the shared profile isn't kept busy
        // while the Loader's deferred destroy is still pending. This
        // prevents "black on switch" when a new DeviceFrame reuses the
        // same storageName before the old WebContents is torn down.
        if (webView) {
            webView.stop()
            webView.lifecycleState = WebEngineView.LifecycleState.Discarded
        }
    }

    Rectangle {
        id: frame
        width: root.device ? (root.device.viewportWidth + root.bezel * 2) * root.presentationScale : 0
        height: root.device ? (root.device.viewportHeight + root.bezel * 2) * root.presentationScale : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.showDevTools ? 0 : (root.width - width - (root.showDevTools ? root.devToolsWidth + 16 : 0)) / 2
        // No scale transform – geometry is directly sized for crisp raster.
        antialiasing: true
        radius: root.showChrome ? root.effectiveRadius : 0
        color: root.showChrome ? Theme.panelRaised : "transparent"
        border.width: root.showChrome ? 1 : 0
        border.color: root.showChrome ? Theme.borderStrong : "transparent"
        clip: true

        Text {
            anchors.top: parent.top
            anchors.topMargin: 1 * root.presentationScale
            anchors.horizontalCenter: parent.horizontalCenter
            height: Math.max(1, root.effectiveBezel - 2 * root.presentationScale)
            verticalAlignment: Text.AlignVCenter
            text: root.device ? root.device.profileName : ""
            visible: root.showChrome && root.presentationScale > 0.45
            color: Theme.textFaint
            font.pixelSize: Math.max(7, Math.round(9 * Math.min(1.0, root.presentationScale)))
            font.weight: Font.Medium
        }

        Rectangle {
            id: contentSurface
            anchors.fill: parent
            anchors.margins: root.effectiveBezel
            // Top margin leaves room for profile label when chrome is shown
            anchors.topMargin: root.showChrome ? root.effectiveBezel + (root.presentationScale > 0.45 ? Math.max(8, 10 * root.presentationScale) : 0) : root.effectiveBezel
            radius: root.showChrome ? Math.max(0, root.effectiveRadius - root.effectiveBezel * 0.5) : 0
            color: "#0d1014"
            border.width: 0
            clip: true

            Rectangle {
                anchors.fill: parent
                color: "#0d1014"
                z: 1
                visible: !root.pageLoaded

                Column {
                    anchors.centerIn: parent
                    spacing: 9

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "WEB DEVICE"
                        color: Theme.accent
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.7
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.pageFailed ? "Unable to load preview" : (root.pageLoading ? "Loading preview…" : (root.device ? root.device.url : ""))
                        color: Theme.textMuted
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.pageFailed
                        text: root.pageError
                        color: Theme.error
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }

                    AppButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.pageFailed
                        text: "Retry"
                        compact: true
                        onClicked: webView.reload()
                    }
                }
            }

            WebEngineView {
                id: webView
                anchors.fill: parent
                z: 0
                url: root.profileReady && root.device && root.device.status === "Running"
                     ? root.device.url : "about:blank"
                // Render directly at visual size: zoom = presentationScale
                // keeps CSS viewport = visual / zoom = profile logical size
                // while backing store = visual * Screen.devicePixelRatio is
                // native and not bilinear-filtered. Clamped to WebEngine limits.
                zoomFactor: Math.max(0.25, Math.min(5.0,
                                                   (root.presentationScale > 0 ? root.presentationScale : 1.0)
                                                   + root.renderWakeNudge))
                backgroundColor: "#0d1014"
                settings.accelerated2dCanvasEnabled: true
                settings.webGLEnabled: true
                settings.fullScreenSupportEnabled: false
                settings.javascriptEnabled: true
                settings.localContentCanAccessRemoteUrls: true
                lifecycleState: WebEngineView.LifecycleState.Active
                // Keep rendering active even when briefly detached during
                // Loader recreation or Wayland output changes.
                onVisibleChanged: if (visible) Qt.callLater(root.recoverSurface)
                onLifecycleStateChanged: {
                    if (root.visible && lifecycleState !== WebEngineView.LifecycleState.Active)
                        lifecycleState = WebEngineView.LifecycleState.Active
                }
                // Ensure high-DPI pixmaps and playback are crisp
                onLoadProgressChanged: {
                    // Ignore the initial about:blank probe; it renders as a
                    // solid backgroundColor (#0d1014) which looks "black" if we
                    // hide the placeholder overlay too early (see screenshot).
                    if (webView.url.toString() === "about:blank") return
                    // loadingChanged can arrive late for development servers.
                    // Reveal the page as soon as Chromium has rendered it.
                    if (loadProgress >= 100) {
                        root.pageLoading = false
                        root.pageLoaded = true
                        root.pageFailed = false
                        root.syncDevicePixelRatio()
                    }
                }
                onLoadingChanged: function(loadRequest) {
                    // Swallow about:blank transitions – they are internal
                    // to profileReady gating and should not flip the
                    // placeholder overlay (otherwise you see a black rect).
                    var isBlank = loadRequest.url.toString() === "about:blank"
                    if (isBlank && loadRequest.status !== WebEngineView.LoadFailedStatus) return
                    if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                        // Don't show loading for about:blank
                        if (isBlank) return
                        root.pageLoading = true
                        root.pageLoaded = false
                        root.pageFailed = false
                        root.pageError = ""
                    } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                        if (isBlank) return
                        root.pageLoading = false
                        root.pageLoaded = true
                        root.pageFailed = false
                        root.syncDevicePixelRatio()
                    } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                        // about:blank never fails visibly; real URL failures do
                        if (isBlank) return
                        root.pageLoading = false
                        root.pageLoaded = false
                        root.pageFailed = true
                        root.pageError = loadRequest.errorString || "Check that the URL is running."
                        console.info("Hesh WebDevice could not load", loadRequest.url, loadRequest.errorString)
                    }
                }
                onRenderProcessTerminated: function(terminationStatus, exitCode) {
                    console.warn("Hesh WebEngine render process terminated", terminationStatus, exitCode, webView.url)
                    root.pageLoading = false
                    root.pageLoaded = false
                    root.pageFailed = true
                    root.pageError = "Renderer crashed (status " + terminationStatus + "). Retrying…"
                    // Active lifecycle is required to restart the renderer;
                    // Discarded/Frozen would stay black.
                    lifecycleState = WebEngineView.LifecycleState.Active
                    reloadTimer.restart()
                }
            }

            // Corner masks scaled with presentation
            Shape {
                width: root.effectiveRadius
                height: root.effectiveRadius
                visible: root.showChrome && root.effectiveRadius > 0.5
                anchors.left: parent.left
                anchors.top: parent.top
                z: 2

                ShapePath {
                    fillColor: Theme.panelRaised
                    strokeColor: "transparent"
                    startX: 0
                    startY: 0
                    PathLine { x: root.effectiveRadius; y: 0 }
                    PathCubic {
                        control1X: root.effectiveRadius * 0.4477
                        control1Y: 0
                        control2X: 0
                        control2Y: root.effectiveRadius * 0.4477
                        x: 0
                        y: root.effectiveRadius
                    }
                    PathLine { x: 0; y: 0 }
                }
            }

            Shape {
                width: root.effectiveRadius
                height: root.effectiveRadius
                visible: root.showChrome && root.effectiveRadius > 0.5
                anchors.right: parent.right
                anchors.top: parent.top
                z: 2

                ShapePath {
                    fillColor: Theme.panelRaised
                    strokeColor: "transparent"
                    startX: 0
                    startY: 0
                    PathLine { x: root.effectiveRadius; y: 0 }
                    PathLine { x: root.effectiveRadius; y: root.effectiveRadius }
                    PathCubic {
                        control1X: root.effectiveRadius
                        control1Y: root.effectiveRadius * 0.4477
                        control2X: root.effectiveRadius * 0.5523
                        control2Y: 0
                        x: 0
                        y: 0
                    }
                }
            }

            Shape {
                width: root.effectiveRadius
                height: root.effectiveRadius
                visible: root.showChrome && root.effectiveRadius > 0.5
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                z: 2

                ShapePath {
                    fillColor: Theme.panelRaised
                    strokeColor: "transparent"
                    startX: 0
                    startY: 0
                    PathLine { x: 0; y: root.effectiveRadius }
                    PathLine { x: root.effectiveRadius; y: root.effectiveRadius }
                    PathCubic {
                        control1X: root.effectiveRadius * 0.4477
                        control1Y: root.effectiveRadius
                        control2X: 0
                        control2Y: root.effectiveRadius * 0.5523
                        x: 0
                        y: 0
                    }
                }
            }

            Shape {
                width: root.effectiveRadius
                height: root.effectiveRadius
                visible: root.showChrome && root.effectiveRadius > 0.5
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                z: 2

                ShapePath {
                    fillColor: Theme.panelRaised
                    strokeColor: "transparent"
                    startX: 0
                    startY: root.effectiveRadius
                    PathLine { x: root.effectiveRadius; y: root.effectiveRadius }
                    PathLine { x: root.effectiveRadius; y: 0 }
                    PathCubic {
                        control1X: root.effectiveRadius * 0.5523
                        control1Y: root.effectiveRadius
                        control2X: root.effectiveRadius
                        control2Y: root.effectiveRadius * 0.4477
                        x: 0
                        y: root.effectiveRadius
                    }
                }
            }
        }
    }

    Rectangle {
        id: devToolsPanel
        visible: root.showDevTools
        x: root.device ? (root.device.viewportWidth + root.bezel * 2) * root.presentationScale + 16 : 0
        y: 0
        width: root.devToolsWidth
        height: root.height
        color: Theme.panelRaised
        border.width: 1
        border.color: Theme.borderStrong
        radius: root.screenRadius
        clip: true

        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 14
            height: 34
            verticalAlignment: Text.AlignVCenter
            text: "DEVTOOLS"
            color: Theme.textMuted
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
        }

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.rightMargin: 5
            iconText: "×"
            tooltip: "Close DevTools"
            onClicked: root.showDevTools = false
        }

        WebEngineView {
            id: devToolsView
            anchors.top: parent.top
            anchors.topMargin: 34
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Qt warns that leaving an invisible DevTools view attached can
            // expose debug information (including the "width × height" resize
            // overlay) in the inspected page.
            inspectedView: root.showDevTools ? webView : null
            backgroundColor: Theme.panelRaised
            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                    root.devToolsThemeApplied = false
                    root.devToolsThemeAttempts = 0
                } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    devToolsThemeTimer.restart()
                    root.applyDevToolsDarkTheme()
                }
            }
        }
    }
}
