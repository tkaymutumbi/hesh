import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
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
    readonly property var barIdentity: hostWidget || root
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    function open() { controller.show(); if (hostWidget) hostWidget.refresh() }
    function toggle() { opened ? close() : open() }
    function run(action, id, extra) {
        var request = extra || {}
        request.action = action
        if (id) request.id = id
        hostWidget.run(request)
    }
    component SmallButton: Controls.Button {
        font.pixelSize: 11
        leftPadding: 7
        rightPadding: 7
        topPadding: 3
        bottomPadding: 3
        implicitHeight: 25
    }
    component SmallField: Controls.TextField {
        font.pixelSize: 11
        implicitHeight: 28
        selectByMouse: true
        leftPadding: 8
        rightPadding: 8
        topPadding: 4
        bottomPadding: 4
    }
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        padding: 12
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(360)
        contentHeight: panel.fittedContentHeight(body.implicitHeight, 450)
        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(dir) { root.switchPanel(dir) }
        }
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Hesh"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
                SmallButton { text: "↻"; onClicked: root.hostWidget.refresh(); Controls.ToolTip.visible: hovered; Controls.ToolTip.text: "Refresh devices" }
                SmallButton { text: "+"; onClicked: root.creating = !root.creating; Controls.ToolTip.visible: hovered; Controls.ToolTip.text: "New device" }
                SmallButton { text: "App ↗"; onClicked: { root.run("show"); root.close() } }
            }
            Text {
                visible: text.length > 0
                text: root.hostWidget ? root.hostWidget.error : ""
                color: "#ff8b8b"; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Controls.ScrollView {
                id: deviceScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(deviceList.implicitHeight, 255)
                contentWidth: availableWidth
                clip: true
                Column {
                    id: deviceList
                    width: deviceScroll.availableWidth
                    spacing: 5
                    Repeater {
                        model: root.hostWidget ? root.hostWidget.devices : []
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            width: deviceList.width
                            implicitHeight: details.implicitHeight + 14
                            radius: 6
                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                            ColumnLayout {
                                id: details
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle { width: 5; height: 5; radius: 3; color: card.modelData.status === "Running" ? "#99c794" : "#858585" }
                                    Text { text: card.modelData.name; color: root.foreground; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Text { text: card.modelData.profile; color: root.foreground; opacity: 0.55; font.pixelSize: 10 }
                                }
                                RowLayout {
                                    spacing: 2
                                    SmallButton { text: "Preview ↗"; enabled: !root.hostWidget.busy; onClicked: root.run("preview", card.modelData.id) }
                                    SmallButton { text: "↻"; enabled: !root.hostWidget.busy; onClicked: root.run("reload", card.modelData.id); Controls.ToolTip.visible: hovered; Controls.ToolTip.text: "Reload preview" }
                                    SmallButton { text: card.modelData.status === "Stopped" ? "Start" : "Stop"; enabled: !root.hostWidget.busy; onClicked: root.run(card.modelData.status === "Stopped" ? "start" : "stop", card.modelData.id) }
                                    Item { Layout.fillWidth: true }
                                    SmallButton { text: "URL"; onClicked: root.editingId = root.editingId === card.modelData.id ? "" : card.modelData.id }
                                }
                                RowLayout {
                                    visible: root.editingId === card.modelData.id
                                    Layout.fillWidth: true
                                    SmallField { id: deviceUrl; Layout.fillWidth: true; text: card.modelData.url; onAccepted: root.run("url", card.modelData.id, {url: text}) }
                                    SmallButton { text: "Go"; enabled: !root.hostWidget.busy; onClicked: root.run("url", card.modelData.id, {url: deviceUrl.text}) }
                                }
                            }
                        }
                    }
                    Text { visible: root.hostWidget && root.hostWidget.connected && root.hostWidget.devices.length === 0; text: "No devices. Use + to create one."; color: root.foreground; font.pixelSize: 11 }
                }
            }
            ColumnLayout {
                visible: root.creating
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    SmallField { id: deviceName; Layout.fillWidth: true; placeholderText: "Device name" }
                    Controls.ComboBox { id: profile; font.pixelSize: 11; implicitHeight: 28; implicitWidth: 105; model: ["Pixel 7", "Pixel 8", "iPhone 14", "Galaxy S24", "iPad", "Desktop", "Custom"] }
                }
                RowLayout {
                    SmallField { id: newUrl; Layout.fillWidth: true; placeholderText: "http://localhost:3000" }
                    SmallButton {
                        text: "Create"
                        enabled: root.hostWidget && root.hostWidget.connected && !root.hostWidget.busy && deviceName.text.trim().length > 0 && newUrl.text.trim().length > 0
                        onClicked: root.run("create", "", {name: deviceName.text, profile: profile.currentText, url: newUrl.text})
                    }
                }
            }
        }
    }
}
