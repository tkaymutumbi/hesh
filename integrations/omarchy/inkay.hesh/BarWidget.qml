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
    property bool launching: false
    readonly property bool starting: launching && !connected
    readonly property var panelObject: panelLoader.item
    // Panel-coordination hooks the bar uses to swap popups: the bar closes the
    // previously open one through these when another icon is clicked.
    readonly property bool popoutSwitchClosing: panelObject ? panelObject.popoutSwitchClosing === true : false
    function closeForPopoutSwitch() {
      if (panelObject && typeof panelObject.closeForPopoutSwitch === "function") panelObject.closeForPopoutSwitch()
      else if (panelObject) panelObject.close()
    }
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
    function powerOn() {
        if (launching || connected) return
        error = ""
        launching = true
        launchTimeout.restart()
        backend.running = true
        poll.restart()
    }
    function powerOff() {
        error = ""
        connected = false
        devices = []
        launching = false
        killer.running = true
    }
    function parse(output) {
        var text = String(output).trim()
        if (text.length === 0) return {ok: true}
        try { return JSON.parse(text) }
        catch (e) { return {ok: false, error: "Could not read Hesh response"} }
    }
    Process {
        id: backend
        // setsid -f detaches Hesh from the shell so it survives bar/shell restarts
        command: ["setsid", "-f", root.executable, "--background"]
        onExited: root.refresh()
    }
    Timer { id: launchTimeout; interval: 10000; onTriggered: root.launching = false }
    Process {
        id: killer
        command: ["pkill", "-x", "hesh"]
        onExited: root.refresh()
    }
    Process {
        id: query
        command: [root.executable, "--control", '{"action":"list"}']
        stdout: StdioCollector { id: queryOut; waitForEnd: true }
        onExited: function(code) {
            var reply = root.parse(queryOut.text)
            root.connected = code === 0 && reply.ok === true
            if (root.connected) root.launching = false
            if (root.connected) {
                var next = reply.devices || []
                if (JSON.stringify(next) !== JSON.stringify(root.devices)) root.devices = next
            }
            else {
                if (root.devices.length) root.devices = []
                root.error = ""
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
    Component.onCompleted: refresh()
    Timer { id: poll; interval: root.starting ? 700 : (root.opened ? 2000 : 10000); running: true; repeat: true; onTriggered: root.refresh() }
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
        function on(): void { root.powerOn() }
        function off(): void { root.powerOff() }
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
        Text {
            anchors.centerIn: parent
            text: "H"
            color: button.foreground
            font.pixelSize: 16
            font.bold: true
            opacity: root.connected ? 1 : 0.4
        }
        Rectangle {
            visible: root.connected
            width: 5; height: 5; radius: 3
            color: Color.accent
            anchors { right: parent.right; top: parent.top; rightMargin: 1; topMargin: 3 }
        }
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        tooltipText: root.connected ? "Hesh · " + root.devices.length + " devices — click for controls" : (root.starting ? "Hesh · starting…" : "Hesh · off — click to turn on")
        horizontalMargin: 8.5
        verticalPadding: 6
        onPressed: function(btn) { if (btn === Qt.LeftButton) root.toggle() }
    }
}
