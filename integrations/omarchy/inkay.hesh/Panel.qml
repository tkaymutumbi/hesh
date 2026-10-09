import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "inkay.hesh"
    ipcTarget: "inkay.hesh"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property bool creating: false
    property string editingId: ""
    property string renamingId: ""
    // Two-step confirm for destructive actions: "<id>:<kind>" while armed.
    property string armed: ""
    function arm(id, kind) { armed = id + ":" + kind; armTimer.restart() }
    Timer { id: armTimer; interval: 3000; onTriggered: root.armed = "" }
    readonly property var barIdentity: hostWidget || root
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color accent: Color.accent
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
    readonly property color cardFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
    readonly property color cardBorder: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property int corner: Style.cornerRadius > 0 ? 10 : 0
    readonly property bool on: hostWidget ? hostWidget.connected : false
    readonly property bool starting: hostWidget ? hostWidget.starting : false
    readonly property bool busy: hostWidget ? hostWidget.busy : false
    function open() { controller.show(); if (hostWidget) hostWidget.refresh() }
    function toggle() { opened ? close() : open() }
    function run(action, id, extra) {
        var request = extra || {}
        request.action = action
        if (id) request.id = id
        hostWidget.run(request)
    }

    // New-device form state. "web" or "phone".
    property string kind: "web"
    property var phones: []
    property var pairing: []
    property string phoneMessage: ""
    property bool phoneOk: false
    function parseReply(text) { try { return JSON.parse(String(text)) } catch (e) { return {ok: false, error: "No answer from Hesh"} } }
    function scanPhones() { if (hostWidget && !phonesProc.running) phonesProc.running = true }
    onCreatingChanged: if (creating) { phoneMessage = ""; scanPhones() }
    onKindChanged: if (kind === "phone") scanPhones()
    Process {
        id: phonesProc
        command: [root.hostWidget ? root.hostWidget.executable : "", "--control", '{"action":"phones"}']
        stdout: StdioCollector { id: phonesOut; waitForEnd: true }
        onExited: {
            var r = root.parseReply(phonesOut.text)
            root.phones = r.phones || []
            root.pairing = r.pairing || []
            if (root.pairing.length > 0 && pairAddress.text.length === 0) pairAddress.text = root.pairing[0].address
        }
    }
    Process {
        id: pairProc
        stdout: StdioCollector { id: pairOut; waitForEnd: true }
        onExited: {
            var r = root.parseReply(pairOut.text)
            root.phoneOk = r.ok === true
            root.phoneMessage = r.ok ? "Paired. Connect from the Wireless debugging screen, then refresh." : (r.error || "Pairing failed")
            if (r.ok) { pairCode.text = "" }
            root.scanPhones()
        }
    }
    function pairNow() {
        root.phoneMessage = "Pairing…"; root.phoneOk = true
        pairProc.command = [hostWidget.executable, "--control", JSON.stringify({action: "pair", address: pairAddress.text.trim(), code: pairCode.text.trim()})]
        pairProc.running = true
    }

    // Themed drop-down used by the new-device form.
    component Select: Controls.ComboBox {
        id: sel
        font.family: root.fontFamily
        font.pixelSize: 11
        implicitHeight: 30
        leftPadding: 10
        rightPadding: 26
        contentItem: Text {
            text: sel.displayText
            color: root.foreground
            font: sel.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            x: sel.width - width - 10
            y: (sel.height - height) / 2
            text: "▾"
            color: root.dim
            font.pixelSize: 11
        }
        background: Rectangle {
            radius: root.corner > 0 ? 8 : 0
            color: root.cardFill
            border.width: 1
            border.color: sel.activeFocus || sel.popup.visible ? root.accent : root.cardBorder
        }
        delegate: Controls.ItemDelegate {
            width: sel.width
            height: 28
            contentItem: Text { text: modelData; color: root.foreground; font: sel.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            background: Rectangle { color: hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent" }
        }
        popup: Controls.Popup {
            y: sel.height + 2
            width: sel.width
            padding: 3
            implicitHeight: Math.min(contentItem.implicitHeight + 6, 200)
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: sel.popup.visible ? sel.delegateModel : null
            }
            background: Rectangle {
                radius: root.corner > 0 ? 8 : 0
                color: Qt.darker(Color.background, 1.1)
                border.width: 1
                border.color: root.cardBorder
            }
        }
    }

    // Two-way switch between the kinds of device that can be created.
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string value: ""
        signal picked(string v)
        implicitHeight: 30
        radius: root.corner > 0 ? 8 : 0
        color: root.cardFill
        border.width: 1
        border.color: root.cardBorder
        Row {
            anchors.fill: parent
            anchors.margins: 2
            Repeater {
                model: seg.options
                Rectangle {
                    required property var modelData
                    width: seg.width / seg.options.length - 1
                    height: parent.height
                    radius: root.corner > 0 ? 6 : 0
                    color: seg.value === modelData.id ? root.accent : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: seg.value === modelData.id
                        color: seg.value === modelData.id ? Color.background : root.foreground
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(modelData.id) }
                }
            }
        }
    }

    // Flat, theme-aware button. kind: "ghost" | "primary" | "danger"
    component Btn: Rectangle {
        id: b
        property string text: ""
        property string kind: "ghost"
        property string tip: ""
        property bool reload: false
        signal clicked()
        readonly property color tone: kind === "danger" ? Color.urgent : root.accent
        implicitHeight: 28
        implicitWidth: Math.max(28, label.implicitWidth + 20)
        radius: root.corner > 0 ? 8 : 0
        opacity: enabled ? 1 : 0.4
        color: kind === "primary"
            ? (area.pressed ? Qt.darker(tone, 1.2) : tone)
            : Qt.rgba(tone.r, tone.g, tone.b, area.containsMouse && enabled ? (kind === "danger" ? 0.22 : 0.16) : (kind === "danger" ? 0.10 : 0.0))
        border.width: kind === "primary" ? 0 : 1
        border.color: kind === "danger" ? Qt.rgba(tone.r, tone.g, tone.b, 0.45)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, area.containsMouse ? 0.28 : 0.14)
        Behavior on color { ColorAnimation { duration: 110 } }
        Canvas {
            id: reloadIcon
            visible: b.reload
            anchors.centerIn: parent
            width: 14; height: 14
            readonly property color ink: root.foreground
            onInkChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                c.strokeStyle = ink; c.fillStyle = ink; c.lineWidth = 1.6; c.lineCap = "round"
                var cx = 7, cy = 7, r = 4.6, a0 = -0.6, a1 = 4.9
                c.beginPath(); c.arc(cx, cy, r, a0, a1, false); c.stroke()
                var ex = cx + r * Math.cos(a1), ey = cy + r * Math.sin(a1)
                var t = a1 + Math.PI / 2
                c.beginPath()
                c.moveTo(ex + 3.2 * Math.cos(t + 0.0) , ey + 3.2 * Math.sin(t))
                c.lineTo(ex + 2.4 * Math.cos(t + 2.4), ey + 2.4 * Math.sin(t + 2.4))
                c.lineTo(ex + 2.4 * Math.cos(t - 2.4), ey + 2.4 * Math.sin(t - 2.4))
                c.closePath(); c.fill()
            }
        }
        Text {
            id: label
            visible: !b.reload
            anchors.centerIn: parent
            text: b.text
            font.family: root.fontFamily
            font.pixelSize: 11
            font.bold: b.kind === "primary"
            color: b.kind === "primary" ? Color.background : (b.kind === "danger" ? b.tone : root.foreground)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: b.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
        Controls.ToolTip {
            visible: area.containsMouse && b.tip.length > 0
            delay: 350
            y: b.height + 6
            text: b.tip
            padding: 0
            contentItem: Text {
                text: b.tip
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 11
                leftPadding: 10; rightPadding: 10; topPadding: 5; bottomPadding: 5
            }
            background: Rectangle {
                radius: root.corner > 0 ? 7 : 0
                color: Qt.darker(Color.background, 1.15)
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
            }
        }
    }
    component Field: Controls.TextField {
        font.family: root.fontFamily
        font.pixelSize: 11
        implicitHeight: 30
        selectByMouse: true
        color: root.foreground
        placeholderTextColor: root.dim
        leftPadding: 10
        rightPadding: 10
        background: Rectangle {
            radius: root.corner > 0 ? 8 : 0
            color: root.cardFill
            border.width: 1
            border.color: parent.activeFocus ? root.accent : root.cardBorder
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        padding: 14
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(380)
        contentHeight: panel.fittedContentHeight(body.implicitHeight, 520)
        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(dir) { root.switchPanel(dir) }
        }
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "H"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                    Layout.preferredWidth: 24
                    horizontalAlignment: Text.AlignHCenter
                    opacity: root.on ? 1 : 0.45
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: "Hesh"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 16; font.bold: true }
                    RowLayout {
                        spacing: 5
                        Rectangle { width: 6; height: 6; radius: 3; color: root.on ? root.accent : root.dim }
                        Text {
                            text: root.on ? (hostWidget.devices.length + " device" + (hostWidget.devices.length === 1 ? "" : "s")) : (root.starting ? "starting…" : "off")
                            color: root.dim; font.family: root.fontFamily; font.pixelSize: 11
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Btn { visible: root.on; reload: true; tip: "Refresh devices"; onClicked: root.hostWidget.refresh() }
                Btn { visible: root.on; text: root.creating ? "×" : "+"; tip: root.creating ? "Cancel" : "New device"; onClicked: root.creating = !root.creating }
                Btn { visible: root.on; text: "Open app ↗"; kind: "primary"; onClicked: { root.run("show"); root.close() } }
                Btn { visible: root.on; text: "⏻"; kind: "danger"; tip: "Shut down Hesh"; onClicked: { root.creating = false; root.editingId = ""; root.hostWidget.powerOff() } }
            }

            Text {
                visible: text.length > 0
                text: root.hostWidget ? root.hostWidget.error : ""
                color: Color.urgent; font.family: root.fontFamily; font.pixelSize: 11
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }

            // Off state
            Rectangle {
                visible: !root.on
                Layout.fillWidth: true
                implicitHeight: offCol.implicitHeight + 40
                radius: root.corner
                color: root.cardFill
                border.width: 1
                border.color: root.cardBorder
                ColumnLayout {
                    id: offCol
                    anchors.centerIn: parent
                    width: parent.width - 40
                    spacing: 10
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 64; height: 64; radius: 32
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, powerArea.containsMouse ? 0.24 : 0.12)
                        border.width: 2
                        border.color: root.starting ? root.dim : root.accent
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "⏻"; font.pixelSize: 28
                            color: root.starting ? root.dim : root.accent
                            RotationAnimator on rotation { running: root.starting; from: 0; to: 360; duration: 1400; loops: Animation.Infinite }
                        }
                        MouseArea {
                            id: powerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.starting
                            onClicked: root.hostWidget.powerOn()
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.starting ? "Starting Hesh…" : "Hesh is off"
                        color: root.foreground; font.family: root.fontFamily; font.pixelSize: 14; font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Turn it on to run the app in the background and control your devices from here."
                        color: root.dim; font.family: root.fontFamily; font.pixelSize: 11
                    }
                    Btn {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.starting ? "Starting…" : "Turn on"
                        kind: "primary"
                        enabled: !root.starting
                        implicitWidth: 120
                        onClicked: root.hostWidget.powerOn()
                    }
                }
            }

            // Device list
            Controls.ScrollView {
                id: deviceScroll
                visible: root.on && !root.creating
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(deviceList.implicitHeight, 420)
                contentWidth: availableWidth
                clip: true
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOff
                Column {
                    id: deviceList
                    width: deviceScroll.availableWidth
                    spacing: 8
                    Repeater {
                        model: root.on ? root.hostWidget.devices : []
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool running: modelData.status !== "Stopped"
                            width: deviceList.width
                            implicitHeight: details.implicitHeight + 24
                            radius: root.corner
                            color: root.cardFill
                            border.width: 1
                            border.color: running ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : root.cardBorder
                            ColumnLayout {
                                id: details
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { width: 8; height: 8; radius: 4; color: card.running ? root.accent : root.dim }
                                    Text { text: card.modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Rectangle {
                                        implicitWidth: prof.implicitWidth + 14
                                        implicitHeight: 20
                                        radius: root.corner > 0 ? 10 : 0
                                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                                        Text { id: prof; anchors.centerIn: parent; text: card.modelData.profile; color: root.dim; font.family: root.fontFamily; font.pixelSize: 10 }
                                    }
                                    Btn { text: "󰏫"; tip: "Rename"; implicitHeight: 24; implicitWidth: 26
                                        onClicked: { root.editingId = ""; root.renamingId = root.renamingId === card.modelData.id ? "" : card.modelData.id } }
                                    Btn {
                                        readonly property bool on: root.armed === card.modelData.id + ":clear"
                                        text: on ? "Clear?" : "󰃢"; kind: on ? "danger" : "ghost"; tip: on ? "Click again to confirm" : "Clear data"
                                        implicitHeight: 24; implicitWidth: on ? 52 : 26; enabled: !root.busy
                                        onClicked: { if (on) { root.armed = ""; root.run("clear", card.modelData.id) } else root.arm(card.modelData.id, "clear") }
                                    }
                                    Btn {
                                        readonly property bool on: root.armed === card.modelData.id + ":delete"
                                        text: on ? "Delete?" : "󰆴"; kind: "danger"; tip: on ? "Click again to confirm" : "Delete device"
                                        implicitHeight: 24; implicitWidth: on ? 58 : 26; enabled: !root.busy
                                        onClicked: { if (on) { root.armed = ""; root.run("delete", card.modelData.id) } else root.arm(card.modelData.id, "delete") }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Btn {
                                        text: card.running ? "■ Stop" : "▶ Start"
                                        kind: card.running ? "ghost" : "primary"
                                        enabled: !root.busy
                                        onClicked: root.run(card.running ? "stop" : "start", card.modelData.id)
                                    }
                                    Btn { text: "Preview ↗"; enabled: !root.busy && card.running; onClicked: root.run("preview", card.modelData.id) }
                                    Btn { reload: true; tip: "Reload preview"; enabled: !root.busy && card.running; onClicked: root.run("reload", card.modelData.id) }
                                    Item { Layout.fillWidth: true }
                                    Btn { text: "URL"; tip: "Change URL"; onClicked: { root.renamingId = ""; root.editingId = root.editingId === card.modelData.id ? "" : card.modelData.id } }
                                }
                                RowLayout {
                                    visible: root.renamingId === card.modelData.id
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Field { id: deviceRename; Layout.fillWidth: true; text: card.modelData.name; placeholderText: "Device name"
                                        onAccepted: if (text.trim().length) { root.run("rename", card.modelData.id, {name: text}); root.renamingId = "" } }
                                    Btn { text: "Save"; kind: "primary"; enabled: !root.busy && deviceRename.text.trim().length > 0
                                        onClicked: { root.run("rename", card.modelData.id, {name: deviceRename.text}); root.renamingId = "" } }
                                }
                                RowLayout {
                                    visible: root.editingId === card.modelData.id
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Field { id: deviceUrl; Layout.fillWidth: true; text: card.modelData.url; onAccepted: root.run("url", card.modelData.id, {url: text}) }
                                    Btn { text: "Go"; kind: "primary"; enabled: !root.busy; onClicked: root.run("url", card.modelData.id, {url: deviceUrl.text}) }
                                }
                            }
                        }
                    }
                    Text { visible: root.on && root.hostWidget.devices.length === 0; text: "No devices yet. Use + to create one."; color: root.dim; font.family: root.fontFamily; font.pixelSize: 11 }
                }
            }

            // New device
            Rectangle {
                visible: root.on && root.creating
                Layout.fillWidth: true
                implicitHeight: createCol.implicitHeight + 28
                radius: root.corner
                color: root.cardFill
                border.width: 1
                border.color: root.cardBorder
                ColumnLayout {
                    id: createCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 10

                    Segmented {
                        Layout.fillWidth: true
                        options: [{id: "web", label: "Web page"}, {id: "phone", label: "My phone"}]
                        value: root.kind
                        onPicked: function(v) { root.kind = v }
                    }

                    Field { id: deviceName; Layout.fillWidth: true; placeholderText: root.kind === "phone" ? "Name, e.g. My phone" : "Device name" }

                    // Web page
                    ColumnLayout {
                        visible: root.kind === "web"
                        Layout.fillWidth: true
                        spacing: 10
                        Select { id: profile; Layout.fillWidth: true; model: ["Pixel 7", "Pixel 8", "iPhone 14", "Galaxy S24", "iPad", "Desktop", "Custom"] }
                        Field { id: newUrl; Layout.fillWidth: true; placeholderText: "http://localhost:3000" }
                        Btn {
                            Layout.alignment: Qt.AlignRight
                            text: "Create"
                            kind: "primary"
                            enabled: !root.busy && deviceName.text.trim().length > 0 && newUrl.text.trim().length > 0
                            onClicked: { root.run("create", "", {name: deviceName.text, profile: profile.currentText, url: newUrl.text}); deviceName.text = ""; newUrl.text = ""; root.creating = false }
                        }
                    }

                    // Phone
                    ColumnLayout {
                        visible: root.kind === "phone"
                        Layout.fillWidth: true
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Select {
                                id: phoneSelect
                                Layout.fillWidth: true
                                model: root.phones.length > 0 ? root.phones.map(function(p) { return p.model + "  ·  " + p.serial.substring(0, 22) }) : ["No phone connected yet"]
                            }
                            Btn { reload: true; tip: "Look for phones"; onClicked: root.scanPhones() }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            text: root.pairing.length > 0
                                ? "A phone is showing a pairing code. Type it below."
                                : "Not listed? On the phone open Developer options, Wireless debugging, Pair device with pairing code."
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field { id: pairAddress; Layout.fillWidth: true; placeholderText: "Pairing address  192.168.1.20:37099" }
                            Field { id: pairCode; Layout.preferredWidth: 78; placeholderText: "Code"; maximumLength: 6; inputMethodHints: Qt.ImhDigitsOnly }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: root.phoneMessage
                                wrapMode: Text.WordWrap
                                color: root.phoneOk ? root.accent : Color.urgent
                                font.family: root.fontFamily
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: root.phoneMessage.length === 0 }
                            Btn {
                                text: "Pair"
                                enabled: !pairProc.running && pairAddress.text.trim().length > 0 && pairCode.text.trim().length === 6
                                onClicked: root.pairNow()
                            }
                            Btn {
                                text: "Add phone"
                                kind: "primary"
                                enabled: !root.busy && root.phones.length > 0
                                onClicked: {
                                    var chosen = root.phones[phoneSelect.currentIndex]
                                    root.run("create", "", {type: "android", name: deviceName.text.trim() || chosen.model, profile: "Pixel 7", serial: chosen.serial})
                                    deviceName.text = ""; root.creating = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
