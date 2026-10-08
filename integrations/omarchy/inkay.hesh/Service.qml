import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Overlay for Hesh AI control. It exists only while the agent has an active
// session (hesh_session start .. done) or is paused, and only around the Hesh
// window the agent is working in, on the workspace that is currently showing.
// The glow is drawn outside the window edge and everything except the ribbon
// is click-through, so no page content is ever covered.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string executable: Quickshell.env("HOME") + "/.local/bin/hesh"
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hesh-agent.json"
  readonly property color amber: "#efbd75"

  property bool active: false
  property bool paused: false
  property string pausedBy: ""
  property string client: ""
  property string task: ""
  property string activity: ""
  property string deviceName: ""
  property var targets: []
  readonly property color stateColor: paused ? amber : Color.accent
  readonly property string line: paused
    ? (pausedBy === "agent" ? "Paused by " + client : "Paused")
    : (activity.length > 0 ? activity : (task.length > 0 ? task : (client.length > 0 ? client : "AI control")))

  function apply(text) {
    var data = {}
    try { data = JSON.parse(String(text)) } catch (e) { data = {} }
    active = data.active === true
    paused = data.paused === true
    pausedBy = data.pausedBy || ""
    client = data.client || ""
    task = data.task || ""
    activity = data.activity || ""
    deviceName = data.deviceName || ""
    poll()
  }

  function send(action) {
    control.command = [executable, "--control", JSON.stringify({action: action})]
    control.running = true
  }

  Process { id: control }

  // Finds the Hesh window(s) to frame: the standalone window of the agent's
  // device (or any Hesh standalone window when the device is unknown), else
  // the main window. Only windows on a workspace that is visible right now.
  function poll() {
    if (!active) { targets = []; return }
    if (!lookup.running) lookup.running = true
  }
  function locate(text) {
    var parts = String(text).split("@@")
    var clients = [], monitors = []
    try { clients = JSON.parse(parts[0]); monitors = JSON.parse(parts[1]) } catch (e) { return }
    var visible = function(c) {
      return monitors.some(function(m) {
        return m.id === c.monitor && (m.activeWorkspace.id === c.workspace.id
          || (m.specialWorkspace && m.specialWorkspace.id === c.workspace.id))
      })
    }
    var mine = clients.filter(function(c) { return c["class"] === "hesh" && c.mapped && !c.hidden && visible(c) })
    var suffix = " \u2014 Hesh"
    var standalone = mine.filter(function(c) {
      return c.title.endsWith(suffix) && c.title.indexOf("DevTools") < 0
        && (deviceName === "" || c.title === deviceName + suffix)
    })
    var chosen = standalone.length > 0 ? standalone : mine.filter(function(c) { return c.title === "Hesh" })
    var out = chosen.slice(0, 4).map(function(c) {
      var m = monitors.filter(function(mm) { return mm.id === c.monitor })[0]
      return {x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1], monitor: m.name, top: m.reserved[1]}
    })
    if (JSON.stringify(out) !== JSON.stringify(targets)) targets = out
  }

  Process {
    id: lookup
    command: ["sh", "-c", "hyprctl -j clients; echo @@; hyprctl -j monitors"]
    stdout: StdioCollector { onStreamFinished: root.locate(text) }
  }
  Timer { interval: 150; repeat: true; running: root.active; onTriggered: root.poll() }

  FileView {
    id: status
    path: root.statusPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.apply("")
  }

  Variants {
    model: [0, 1, 2, 3]

    PanelWindow {
      id: win
      required property int modelData
      readonly property var t: root.targets[modelData] || null
      readonly property int pad: 22
      readonly property int ribbonHeight: 28
      // Layer top: leaves room for the ribbon above the glow when the bar
      // allows it, otherwise the layer starts under the bar.
      readonly property int layerTop: t ? Math.max(t.top, t.y - pad - ribbonHeight - 6) : 0
      readonly property int topPad: t ? t.y - layerTop : 0
      screen: t ? (Quickshell.screens.filter(function(s) { return s.name === t.monitor })[0] || Quickshell.screens[0]) : Quickshell.screens[0]
      visible: root.active && t !== null
      color: "transparent"
      anchors { top: true; left: true }
      margins.left: t ? Math.max(0, t.x - pad) : 0
      margins.top: layerTop
      implicitWidth: t ? t.w + pad * 2 : 1
      implicitHeight: t ? t.h + topPad + pad : 1
      exclusionMode: ExclusionMode.Ignore
      focusable: false
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "hesh-agent"
      mask: Region { item: ribbon }

      Item {
        id: frame
        anchors.fill: parent
        anchors.topMargin: win.topPad - win.pad

        SequentialAnimation on opacity {
          running: win.visible && !root.paused
          loops: Animation.Infinite
          NumberAnimation { to: 0.7; duration: 1200; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
          onStopped: frame.opacity = 1
        }
        // Rings sit just outside the window edge: ring w spans pad-w .. pad.
        // Working: a rotating rainbow ring with a soft halo, easy to spot.
        Item {
          id: rain
          anchors.fill: parent
          anchors.margins: win.pad - 3
          visible: !root.paused
          ConicalGradient {
            id: spectrum
            anchors.fill: parent
            visible: false
            angle: 0
            NumberAnimation on angle { from: 0; to: 360; duration: 4500; loops: Animation.Infinite; running: rain.visible && win.visible }
            gradient: Gradient {
              GradientStop { position: 0.00; color: "#ff4d4d" }
              GradientStop { position: 0.17; color: "#ffb347" }
              GradientStop { position: 0.33; color: "#f7e84a" }
              GradientStop { position: 0.50; color: "#4de08a" }
              GradientStop { position: 0.67; color: "#4db8ff" }
              GradientStop { position: 0.83; color: "#b06bff" }
              GradientStop { position: 1.00; color: "#ff4d4d" }
            }
          }
          Rectangle {
            id: ringMask
            anchors.fill: parent
            visible: false
            color: "transparent"
            radius: 15
            border.width: 3
            border.color: "black"
          }
          OpacityMask { id: crisp; anchors.fill: parent; source: spectrum; maskSource: ringMask; visible: false }
          FastBlur { anchors.fill: parent; source: crisp; radius: 18; opacity: 0.95; transparentBorder: true }
          FastBlur { anchors.fill: parent; source: crisp; radius: 6; transparentBorder: true }
          OpacityMask { anchors.fill: parent; source: spectrum; maskSource: ringMask }
        }
        Repeater {
          visible: root.paused
          model: root.paused ? [ { w: 2, a: 0.95 }, { w: 6, a: 0.28 }, { w: 12, a: 0.12 }, { w: 22, a: 0.05 } ] : []
          Rectangle {
            required property var modelData
            anchors.fill: parent
            anchors.margins: win.pad - modelData.w
            color: "transparent"
            radius: 12 + modelData.w
            border.width: modelData.w
            border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, modelData.a)
          }
        }
      }

      Rectangle {
        id: ribbon
        // Above the glow when there is room, else straddling the window's top edge.
        y: win.topPad >= win.pad + win.ribbonHeight + 2 ? win.topPad - win.pad - win.ribbonHeight - 2 : Math.max(0, win.topPad - win.ribbonHeight / 2)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(row.implicitWidth + 24, parent.width - 8)
        height: win.ribbonHeight
        radius: height / 2
        color: Color.background
        border.width: 1
        border.color: root.stateColor

        Row {
          id: row
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 12
          spacing: 10
          Rectangle {
            width: 7; height: 7; radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: root.stateColor
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(60, win.width - 150))
            text: root.line
            elide: Text.ElideRight
            color: Color.foreground
            font.pixelSize: 12
            font.family: "monospace"
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.paused ? "Resume" : "Pause"
            color: root.stateColor
            font.pixelSize: 12
            font.bold: true
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.send(root.paused ? "agent_resume" : "agent_pause")
            }
          }
        }
      }
    }
  }
}
