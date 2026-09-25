import QtQuick
import QtQuick.Shapes
import QtWebEngine
import Hesh 1.0

Item {
    id: root

    property var device: null
    // Optional DeviceManager, used by the stopped state to start the device
    // without leaving the frame.
    property var manager: null
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
    // A device accent overrides the application accent for this preview. The
    // device model stores "no accent" as an empty name and never reads
    // application preferences, so the fallback is resolved here.
    readonly property color deviceAccent: root.device !== null && root.device.hasAccent
                                          ? root.device.accent : Theme.accent
    // Chromium force-dark for this device. It is a renderer setting applied at
    // paint time, so it does not appear in computed styles — a light-styled page
    // really does render dark. Pages that ship their own dark styling keep it;
    // force-dark only fills in pages that ignore the scheme.
    readonly property bool forceDarkContent: root.device !== null
                                             && root.device.contentTheme === "dark"

    // Set when a load reports no progress for a while. A connection that
    // black-holes never fails, so the loading state has to say it is stuck.
    property bool slowLoad: false
    // A finished load keeps the overlay up for one beat so the progress bar
    // visibly completes instead of vanishing mid-fill.
    property bool loadCompleted: false
    readonly property bool overlayVisible: root.device !== null
                                           && (root.frameState !== "ready" || root.loadCompleted)
    // The device screen is a four-state machine. The state overlay below
    // always covers the WebEngineView unless the state is "ready", so a
    // stopped, failed, or still-loading preview can never render black.
    readonly property string frameState: {
        if (!root.device) return "idle"
        if (root.device.status !== "Running") return "stopped"
        if (root.pageFailed) return "error"
        if (root.pageLoaded && !root.pageLoading) return "ready"
        return "loading"
    }
    // Width of the device screen in the device's own visual space. It is
    // exactly what the state overlay gets, because the screen inset and the
    // frame scale cancel out in both hosts.
    readonly property real screenVisualWidth: root.device
                                              ? root.device.viewportWidth * root.presentationScale
                                              : 0
    // State content shrinks with a small preview. Without this the fixed
    // column width overflows a scaled-down screen and the clipped progress
    // bar reads as a bar that never finishes loading.
    readonly property real stateContentWidth: Math.max(24, Math.min(288, root.screenVisualWidth - 40))
    readonly property real progressValue: root.loadCompleted ? 100
                                          : Math.max(0, Math.min(100, webView.loadProgress))
    readonly property bool progressVisible: root.loadCompleted
                                            || (root.frameState === "loading"
                                                && webView.loadProgress > 0 && webView.loadProgress < 100)
    readonly property color stateColor: root.frameState === "error" ? Theme.error
                                       : root.frameState === "stopped" ? Theme.textFaint
                                       : root.deviceAccent
    // Every state shows the same slot in the same order: glyph, kicker, title,
    // detail, target URL, progress, raw code, actions. Empty strings collapse.
    readonly property var stateText: {
        if (root.frameState === "stopped") {
            return {
                kicker: "DEVICE STOPPED",
                title: "This device is not running",
                detail: "Start it to load the preview again.",
                url: root.device ? root.device.url : "",
                code: "",
            }
        }
        if (root.frameState === "error") {
            var info = root.classifyLoadError(root.pageError)
            return {
                kicker: info.kicker,
                title: info.title,
                detail: info.detail,
                url: root.device ? root.device.url : "",
                code: root.pageError,
            }
        }
        if (root.frameState === "loading") {
            return {
                kicker: "LOADING PREVIEW",
                title: "",
                detail: root.slowLoad ? "Still waiting on the server…" : "",
                url: root.device ? root.device.url : "",
                code: "",
            }
        }
        return { kicker: "", title: "", detail: "", url: "", code: "" }
    }

    onFrameStateChanged: {
        root.slowLoad = false
        if (root.frameState === "ready") {
            root.loadCompleted = true
            completionTimer.restart()
        } else {
            completionTimer.stop()
            root.loadCompleted = false
        }
    }

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

    // Standalone hosts inspect the page from their own DevTools window.
    readonly property alias pageView: webView
    // DevTools has its own preference store. Chromium's process theme and
    // WebEngineSettings.forceDarkMode do not reliably select this setting.
    // Modern DevTools is built from ES modules and no longer exposes a global
    // settings object, and the legacy host preference is ignored at startup.
    // Import the frontend's settings module by absolute URL (a relative import
    // fails from an injected script) and set its theme; it applies live.
    readonly property string devToolsDarkThemeScript:
        "import('devtools://devtools/bundled/core/common/common.js').then(C => {" +
        "  const s = C.Settings.Settings.instance();" +
        "  let t;" +
        "  try { t = s.moduleSetting('ui-theme'); }" +
        "  catch (_) { t = s.createSetting('ui-theme', 'systemPreferred'); }" +
        "  if (t.get() !== 'dark') t.set('dark');" +
        "}).catch(() => {})"

    function applyDevToolsDarkTheme() {
        if (!root.showDevTools || root.devToolsThemeApplied
                || devToolsView.loading || devToolsView.url.toString() === "") {
            return
        }

        devToolsView.runJavaScript(root.devToolsDarkThemeScript)
        // No result callback: Qt WebEngine delivers it through the QML engine
        // and can do so after the view is torn down, which segfaults in
        // QJSEngine::create. The script is idempotent, so the retry timer runs
        // it a bounded number of times instead of waiting for an answer.
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
            if (root.devToolsThemeAttempts >= 12) {
                root.devToolsThemeApplied = true
                stop()
            }
        }
    }

    Timer {
        id: reloadTimer
        interval: 650
        repeat: false
        onTriggered: {
            // Only clear the failure when the retry can actually run. Without
            // the profile there is no browser at all, so leaving the error
            // state up beats flipping back to a fake loading state.
            if (webView && root.profileReady) {
                root.pageFailed = false
                root.pageError = ""
                root.reloadPage(false)
            }
        }
    }

    // A black-holed connection never reaches LoadFailedStatus, so the loading
    // state has to admit it is waiting rather than look like a hang.
    Timer {
        id: slowLoadTimer
        interval: 4000
        repeat: false
        running: root.frameState === "loading"
        onTriggered: root.slowLoad = true
    }

    // Long enough for the progress fill animation to reach 100%, short enough
    // that revealing a rendered page still feels immediate.
    Timer {
        id: completionTimer
        interval: 190
        repeat: false
        onTriggered: root.loadCompleted = false
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
        // A stopped device has no page to load: its URL binding is pinned to
        // about:blank, and blank navigations are ignored below. Without this
        // guard the frame would enter "loading" and stay there forever.
        if (root.device.status !== "Running") return

        reloadTimer.stop()
        root.pageLoaded = false
        root.pageLoading = true
        root.pageFailed = false
        root.pageError = ""
        webView.lifecycleState = WebEngineView.LifecycleState.Active

        // A renderer that died or was discarded while the app sat idle ignores
        // reload(); navigating again spawns a fresh one.
        if (webView.renderProcessPid === 0 || webView.url.toString() === "about:blank")
            root.navigateFresh()
        else if (bypassCache && typeof webView.reloadAndBypassCache === "function")
            webView.reloadAndBypassCache()
        else
            webView.reload()
        root.reloadRetried = false
        reloadWatchdog.restart()
    }

    // Re-installing the url binding makes WebEngineView load it again, even
    // when the value is unchanged, and keeps the stopped-device pinning.
    function navigateFresh() {
        webView.url = Qt.binding(function() {
            return root.profileReady && root.device && root.device.status === "Running"
                    ? root.device.url : "about:blank"
        })
    }

    // reload() can be silently dropped by a stale WebContents. If Chromium
    // never reports the load starting, pageLoading stays latched and blocks
    // every later surface recovery, so retry once by navigating, then give up
    // visibly with the Retry button instead of spinning forever.
    property bool reloadRetried: false
    Timer {
        id: reloadWatchdog
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.pageLoading || root.pageLoaded || !root.device) return
            if (webView.loading && webView.loadProgress > 0) return
            if (!root.reloadRetried) {
                root.reloadRetried = true
                webView.stop()
                webView.lifecycleState = WebEngineView.LifecycleState.Active
                root.navigateFresh()
                restart()
            } else {
                root.pageLoading = false
                root.pageFailed = true
                root.pageError = "Reload did not start"
            }
        }
    }

    // Turns a raw Chromium/Qt WebEngine load failure into copy a device
    // developer can act on. The raw net:: code stays visible in the frame as
    // secondary detail; this only decides the words around it.
    function classifyLoadError(raw) {
        var code = String(raw || "")
        var text = code.toLowerCase()

        if (text.indexOf("renderer crashed") >= 0)
            return { kicker: "PREVIEW CRASHED", title: "The preview process stopped", detail: "Hesh is restarting it automatically." }
        if (text.indexOf("webengine profile") >= 0)
            return { kicker: "PREVIEW UNAVAILABLE", title: "The device browser is busy", detail: "Another window still holds this device's browser data. Close it, then retry." }
        if (text.indexOf("err_internet_disconnected") >= 0)
            return { kicker: "CAN'T CONNECT", title: "No network connection", detail: "This machine appears to be offline. Check the connection and try again." }
        if (text.indexOf("err_name_not_resolved") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Host not found", detail: "Hesh could not resolve that host name. Check the URL or your DNS." }
        if (text.indexOf("err_connection_refused") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Connection refused", detail: "Nothing is listening at that address. Is the server running?" }
        if (text.indexOf("timed_out") >= 0 || text.indexOf("err_timed_out") >= 0)
            return { kicker: "CAN'T CONNECT", title: "The server timed out", detail: "That address did not respond in time." }
        if (text.indexOf("err_connection_reset") >= 0 || text.indexOf("err_connection_closed") >= 0)
            return { kicker: "CAN'T CONNECT", title: "The connection dropped", detail: "The server closed the connection while the page was loading." }
        if (text.indexOf("err_empty_response") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Empty response", detail: "The server accepted the connection but sent no data." }
        if (text.indexOf("err_cert") >= 0 || text.indexOf("err_ssl") >= 0 || text.indexOf("err_bad_ssl") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Certificate rejected", detail: "Hesh refused an insecure connection to this server." }
        if (text.indexOf("err_http_response_code_failure") >= 0)
            return { kicker: "CAN'T CONNECT", title: "The server returned an error", detail: "The page answered with an HTTP error status." }
        if (text.indexOf("err_invalid_url") >= 0 || text.indexOf("err_unknown_url_scheme") >= 0 || text.indexOf("err_disallowed_url_scheme") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Invalid address", detail: "Hesh cannot open that URL. Check the scheme and the host." }
        if (text.indexOf("err_aborted") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Load cancelled", detail: "The load stopped before the page finished." }
        if (text.indexOf("err_blocked") >= 0 || text.indexOf("err_unsafe") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Request blocked", detail: "The request was blocked before it left this machine." }
        if (text.indexOf("err_file_not_found") >= 0)
            return { kicker: "CAN'T CONNECT", title: "File not found", detail: "That file is not on disk." }
        if (text.indexOf("err_network") >= 0 || text.indexOf("err_address_unreachable") >= 0)
            return { kicker: "CAN'T CONNECT", title: "Network unreachable", detail: "That address cannot be reached from this machine right now." }

        return { kicker: "CAN'T CONNECT", title: "Unable to load preview", detail: "Hesh could not load this page. Check that the URL is running, then retry." }
    }

    function goBack() { webView.goBack() }
    function goForward() { webView.goForward() }
    function ensureActive() {
        if (webView) webView.lifecycleState = WebEngineView.LifecycleState.Active
    }

    function recoverSurface() {
        if (!webView || !root.profileReady || !root.device) return

        webView.lifecycleState = WebEngineView.LifecycleState.Active
        // A reload is already producing a new surface. Avoid injecting the
        // repaint JavaScript into the same WebContents during navigation.
        if (root.pageLoading) return

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

    Connections {
        target: root.device

        function onContentThemeChanged() {
            // Force dark is a renderer setting that only takes effect for the
            // next paint of a loaded document, so a change is applied by
            // reloading rather than leaving the old rendering on screen.
            if (root.device && root.device.status === "Running") root.reloadPage(false)
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
            var p = BrowserProfiles.profileFor(root.device)
            if (p && root.device.userAgent) p.httpUserAgent = root.device.userAgent
            root.syncDevicePixelRatio()
        }
    }

    onProfileDprChanged: {
        if (root.profileReady) root.syncDevicePixelRatio()
    }

    // Every device owns one long-lived browser profile (BrowserProfiles), so
    // localStorage, IndexedDB, cookies and cache stay isolated per device and
    // every host of the device shares them. Creation should not fail; if it
    // does, retry briefly before reporting it.
    property int profileAttempts: 0

    function bindProfile() {
        if (root.profileReady) return true
        root.profileAttempts++
        // Assign after construction; assigning instance() through a binding
        // during WebEngineView creation can crash Qt WebEngine on Wayland.
        var profile = BrowserProfiles.profileFor(root.device)
        if (!profile) {
            if (root.profileAttempts < 40) {
                profileRetryTimer.restart()
            } else {
                console.warn("Hesh could not create a WebEngine profile for device",
                             root.device ? root.device.id : "<none>")
                root.pageFailed = true
                root.pageError = "WebEngine profile unavailable"
            }
            return false
        }
        if (root.device && root.device.userAgent) {
            profile.httpUserAgent = root.device.userAgent
        }
        webView.profile = profile
        root.pageFailed = false
        root.pageError = ""
        root.profileReady = true
        // On Wayland the first frame can be black until the view is
        // explicitly activated; force Active once the profile is bound.
        if (webView) webView.lifecycleState = WebEngineView.LifecycleState.Active
        return true
    }

    Timer {
        id: profileRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.bindProfile()
    }

    // The Retry button: without a profile there is nothing to reload yet.
    function retry() {
        if (root.profileReady) {
            root.reloadPage(false)
        } else {
            root.profileAttempts = 0
            root.pageFailed = false
            root.pageError = ""
            root.bindProfile()
        }
    }

    Component.onCompleted: root.bindProfile()

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

            // Preview state overlay. Deliberately opaque and unscaled: it
            // covers the WebEngineView until the page has rendered, so a
            // stopped or failed preview can never show a black surface, and
            // the state stays legible in small standalone windows.
            Rectangle {
                anchors.fill: parent
                color: "#0d1014"
                z: 1
                visible: root.overlayVisible

                Column {
                    anchors.centerIn: parent
                    width: root.stateContentWidth
                    spacing: 11

                    // Fixed-height glyph slot: spinner, error mark, or stopped
                    // device outline, so the text below never jumps. It
                    // collapses once the load is done, leaving the completed
                    // bar centered for the hold.
                    Item {
                        width: parent.width
                        height: root.loadCompleted ? 0 : 44

                        Item {
                            id: stateSpinner
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            visible: root.frameState === "loading"

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    strokeColor: Theme.border
                                    strokeWidth: 2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 13
                                        centerY: 13
                                        radiusX: 11
                                        radiusY: 11
                                        startAngle: 0
                                        sweepAngle: 360
                                    }
                                }

                                ShapePath {
                                    strokeColor: root.deviceAccent
                                    strokeWidth: 2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 13
                                        centerY: 13
                                        radiusX: 11
                                        radiusY: 11
                                        startAngle: 0
                                        sweepAngle: 96
                                    }
                                }
                            }

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 950
                                loops: Animation.Infinite
                                running: stateSpinner.visible
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: root.frameState === "error"
                            width: 42
                            height: 42
                            radius: 12
                            color: Theme.errorSoft
                            border.width: 1
                            border.color: Theme.errorStrong

                            Text {
                                anchors.centerIn: parent
                                text: "!"
                                color: Theme.error
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                        }

                        Item {
                            anchors.centerIn: parent
                            visible: root.frameState === "stopped"
                            width: 24
                            height: 38

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.textFaint
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 7
                                height: 2
                                radius: 1
                                color: Theme.textFaint
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 4
                                height: 4
                                radius: 2
                                color: Theme.textFaint
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: text.length > 0
                        text: root.stateText.kicker
                        color: root.stateColor
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.7
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                        text: root.stateText.title
                        color: Theme.text
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.25
                        visible: text.length > 0
                        text: root.stateText.detail
                        color: Theme.textMuted
                        font.pixelSize: 11
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: text.length > 0
                        text: root.stateText.url
                        color: Theme.textFaint
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Shorter than the text column and never wider than
                        // the screen, so the fill can never be clipped.
                        width: Math.min(180, parent.width)
                        height: 3
                        radius: 1.5
                        color: Theme.border
                        visible: root.progressVisible

                        Rectangle {
                            width: parent.width * root.progressValue / 100
                            height: parent.height
                            radius: parent.radius
                            color: root.deviceAccent

                            Behavior on width {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: text.length > 0
                        text: root.stateText.code
                        color: Theme.textFaint
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        visible: root.frameState === "error"
                                 || (root.frameState === "stopped" && !!root.manager)

                        AppButton {
                            visible: root.frameState === "error"
                            text: "Retry"
                            compact: true
                            onClicked: root.retry()
                        }

                        AppButton {
                            visible: root.frameState === "stopped" && !!root.manager
                            text: "Start Device"
                            compact: true
                            onClicked: if (root.manager && root.device) root.manager.startDevice(root.device.id)
                        }
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
                settings.forceDarkMode: root.forceDarkContent
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
                        root.pageError = loadRequest.errorString
                        console.info("Hesh WebDevice could not load", loadRequest.url, loadRequest.errorString)
                    }
                }
                onRenderProcessTerminated: function(terminationStatus, exitCode) {
                    console.warn("Hesh WebEngine render process terminated", terminationStatus, exitCode, webView.url)
                    root.pageLoading = false
                    root.pageLoaded = false
                    root.pageFailed = true
                    root.pageError = "Renderer crashed (status " + terminationStatus + ")"
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
