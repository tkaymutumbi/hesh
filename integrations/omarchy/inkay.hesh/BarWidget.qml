import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "inkay.hesh"
    readonly property string executable: Quickshell.env("HOME") + "/.local/bin/hesh"
    property var devices: []
    property string error: ""
    property bool connected: false
    readonly property bool busy: action.running
    readonly property var panelObject: panelLoader.item
    readonly property bool opened: panelObject ? panelObject.opened : false
    function injectPanel() {
        if (!panelObject) return
        panelObject.bar = root.bar
        panelObject.settings = root.settings
        panelObject.anchorItem = button
        panelObject.hostWidget = root
    }
    function open() { injectPanel(); if (panelObject) panelObject.open(); refresh() }
    function close() { if (panelObject) panelObject.close() }
    function toggle() { opened ? close() : open() }
    function refresh() { if (!query.running && !action.running) query.running = true }
    function run(request) {
        if (action.running) return
        error = ""
        action.command = [executable, "--control", JSON.stringify(request)]
        action.running = true
    }
    function parse(output) {
        try { return JSON.parse(String(output).trim()) }
        catch (e) { return {ok: false, error: "Could not read Hesh response"} }
    }
    Process {
        id: backend
        command: [root.executable, "--background"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: root.refresh()
    }
    Process {
        id: query
        command: [root.executable, "--control", '{"action":"list"}']
        stdout: StdioCollector { id: queryOut; waitForEnd: true }
        onExited: function(code) {
            var reply = root.parse(queryOut.text)
            root.connected = code === 0 && reply.ok === true
            if (root.connected) {
                var next = reply.devices || []
                if (JSON.stringify(next) !== JSON.stringify(root.devices)) root.devices = next
                if (root.error === "Hesh backend is not running") root.error = ""
            }
            else {
                root.error = reply.error || "Hesh is unavailable"
                if (!backend.running) backend.running = true
            }
        }
    }
    Process {
        id: action
        stdout: StdioCollector { id: actionOut; waitForEnd: true }
        onExited: function(code) {
            var reply = root.parse(actionOut.text)
            root.error = code === 0 && reply.ok ? "" : reply.error || "Hesh command failed"
            root.refresh()
        }
    }
    Component.onCompleted: { backend.running = true; refresh() }
    Timer { interval: root.opened ? 2000 : 10000; running: true; repeat: true; onTriggered: root.refresh() }
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()
    Loader {
        id: panelLoader
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
    }
    IpcHandler {
        target: "inkay.hesh"
        function toggle(): void { root.toggle() }
        function state(): string { return JSON.stringify({connected: root.connected, devices: root.devices, error: root.error, opened: root.opened}) }
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: ""
        labelVisible: false
        hasVisualContent: true
        fixedWidth: 24
        Image {
            anchors.centerIn: parent
            width: 17
            height: 17
            source: Qt.resolvedUrl("hesh.png")
            sourceSize: Qt.size(32, 32)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        tooltipText: "Hesh · " + root.devices.length + " devices — click for controls"
        horizontalMargin: 8.5
        verticalPadding: 6
        onPressed: function(btn) { if (btn === Qt.LeftButton) root.toggle() }
    }
}
