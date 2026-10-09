import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Overlay for Hesh AI control. It exists only while the agent has an active
// session (hesh_session start .. done) or is paused, and only around the Hesh
// window the agent is working in, on the workspace that is currently showing.
// Switching workspace or focus dismisses it until the session ends.
// The glow is drawn outside the window edge. A small circle sits on the window's
// side edge and opens a box with the agent's controls; everything else is
// click-through, so no page content is ever covered.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string executable: Quickshell.env("HOME") + "/.local/bin/hesh"
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hesh-agent.json"
  readonly property color amber: "#efbd75"

  property bool active: false
  // Set when the user changes workspace, focus or window placement during an
  // agent session: the overlay then stays hidden for the rest of that session
  // so it never follows the user around or draws over what they are doing. It
  // only changes how the overlay looks; agent control is unaffected.
  property bool dismissed: false
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
    : (activity.length > 0 ? activity : (task.length > 0 ? task : "Working"))

  function apply(text) {
    var data = {}
    try { data = JSON.parse(String(text)) } catch (e) { data = {} }
    active = data.active === true
    if (!active) dismissed = false
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
    if (!active || dismissed) { targets = []; return }
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
    var mine = clients.filter(function(c) { return (c["class"] === "hesh" || c["class"] === "scrcpy") && c.mapped && !c.hidden && visible(c) })
    var suffix = " \u2014 Hesh"
    var standalone = mine.filter(function(c) {
      return c.title.endsWith(suffix) && c.title.indexOf("DevTools") < 0
        && (deviceName === "" || c.title === deviceName + suffix)
    })
    var chosen = standalone.length > 0 ? standalone : mine.filter(function(c) { return c.title === "Hesh" })
    var out = chosen.slice(0, 4).map(function(c) {
      var m = monitors.filter(function(mm) { return mm.id === c.monitor })[0]
      return {x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1], monitor: m.name, top: m.reserved[1], sw: Math.round(m.width / m.scale)}
    })
    if (JSON.stringify(out) !== JSON.stringify(targets)) targets = out
  }

  // Hide at once when the workspace or focus changes instead of waiting for
  // the next poll, which would leave the overlay up for a moment on the
  // workspace being left. The poll then brings it back if it should show.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "workspace" || n === "workspacev2" || n === "focusedmon" || n === "focusedmonv2"
          || n === "activespecial" || n === "activespecialv2" || n === "movewindow" || n === "movewindowv2"
          || n === "closewindow") {
        if (root.active) root.dismissed = true
        if (root.targets.length > 0) root.targets = []
      }
    }
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
      // Room beside the window for the circle and its box.
      readonly property int side: 262
      readonly property int bubble: 36
      // The box goes on the right unless that would leave the screen.
      readonly property bool onRight: t ? (t.x + t.w + pad + side <= t.sw) : true
      property bool open: false
      screen: t ? (Quickshell.screens.filter(function(s) { return s.name === t.monitor })[0] || Quickshell.screens[0]) : Quickshell.screens[0]
      visible: root.active && t !== null
      color: "transparent"
      anchors { top: true; left: true }
      margins.left: t ? Math.max(0, t.x - pad - (onRight ? 0 : side)) : 0
      margins.top: t ? Math.max(t.top, t.y - pad) : 0
      implicitWidth: t ? t.w + pad * 2 + side : 1
      implicitHeight: t ? t.h + pad * 2 : 1
      exclusionMode: ExclusionMode.Ignore
      focusable: false
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "hesh-agent"
      // Only the circle (and the box while it is open) takes the pointer. The
      // parent region must not be empty-but-full: give it the circle and add the
      // box as a child, falling back to the circle when the box is closed.
      mask: Region {
        item: bubbleItem
        Region { item: win.open ? box : bubbleItem }
      }
      onVisibleChanged: if (!visible) open = false

      // Window rect inside this layer surface.
      readonly property real wx: onRight ? pad : side + pad
      readonly property real wy: t ? t.y - margins.top : pad

      Item {
        id: frame
        x: win.wx - win.pad
        y: win.wy - win.pad
        width: win.t ? win.t.w + win.pad * 2 : 0
        height: win.t ? win.t.h + win.pad * 2 : 0

        SequentialAnimation on opacity {
          running: win.visible && !root.paused
          loops: Animation.Infinite
          NumberAnimation { to: 0.7; duration: 1200; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
          onStopped: frame.opacity = 1
        }
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
          Rectangle { id: ringMask; anchors.fill: parent; visible: false; color: "transparent"; radius: 15; border.width: 3; border.color: "black" }
          OpacityMask { id: crisp; anchors.fill: parent; source: spectrum; maskSource: ringMask; visible: false }
          FastBlur { anchors.fill: parent; source: crisp; radius: 18; opacity: 0.95; transparentBorder: true }
          FastBlur { anchors.fill: parent; source: crisp; radius: 6; transparentBorder: true }
          OpacityMask { anchors.fill: parent; source: spectrum; maskSource: ringMask }
        }
        Repeater {
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

      // The circle: sits on the window's outer side edge, a third of the way down.
      Rectangle {
        id: bubbleItem
        width: win.bubble
        height: win.bubble
        radius: width / 2
        x: win.onRight ? win.wx + (win.t ? win.t.w : 0) - width / 2 : win.wx - width / 2
        y: win.wy + Math.min(Math.max(40, (win.t ? win.t.h : 0) * 0.3), Math.max(40, (win.t ? win.t.h : 0) - 80))
        color: Color.background
        border.width: 2
        border.color: root.stateColor
        scale: bubbleArea.containsMouse ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }

        // Working: a pulsing dot. Paused: a pause glyph.
        Rectangle {
          visible: !root.paused
          anchors.centerIn: parent
          width: 12; height: 12; radius: 6
          color: root.stateColor
          SequentialAnimation on opacity {
            running: !root.paused && win.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700 }
            NumberAnimation { to: 1.0; duration: 700 }
            onStopped: parent.opacity = 1
          }
        }
        Row {
          visible: root.paused
          anchors.centerIn: parent
          spacing: 3
          Rectangle { width: 4; height: 13; radius: 1; color: root.stateColor }
          Rectangle { width: 4; height: 13; radius: 1; color: root.stateColor }
        }
        MouseArea {
          id: bubbleArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: win.open = !win.open
        }
      }

      // The box that pops out beside the circle.
      Rectangle {
        id: box
        visible: win.open
        width: 224
        height: boxColumn.implicitHeight + 24
        radius: 14
        color: Color.background
        border.width: 1
        border.color: root.stateColor
        x: win.onRight ? bubbleItem.x + bubbleItem.width + 10 : bubbleItem.x - 10 - width
        y: Math.min(bubbleItem.y, Math.max(0, win.height - height))

        Column {
          id: boxColumn
          x: 14; y: 12
          width: parent.width - 28
          spacing: 10

          Row {
            spacing: 8
            Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: root.stateColor }
            Text {
              text: root.client.length > 0 ? root.client : "AI control"
              color: Color.foreground
              font.pixelSize: 12
              font.bold: true
              font.family: "monospace"
              elide: Text.ElideRight
              width: boxColumn.width - 16
            }
          }
          Text {
            width: boxColumn.width
            text: root.line
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.65)
            font.pixelSize: 11
            font.family: "monospace"
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
          Row {
            spacing: 8
            Rectangle {
              width: 98; height: 28; radius: 14
              color: root.paused ? root.stateColor : "transparent"
              border.width: 1
              border.color: root.stateColor
              Text {
                anchors.centerIn: parent
                text: root.paused ? "Resume" : "Pause"
                color: root.paused ? Color.background : root.stateColor
                font.pixelSize: 12
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.send(root.paused ? "agent_resume" : "agent_pause")
              }
            }
            Rectangle {
              width: 98; height: 28; radius: 14
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.3)
              Text {
                anchors.centerIn: parent
                text: "End session"
                color: Color.foreground
                font.pixelSize: 12
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { win.open = false; root.send("agent_done") }
              }
            }
          }
        }
      }
    }
  }
}
