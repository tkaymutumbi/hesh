import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Hesh 1.0

pragma ComponentBehavior: Bound

Window {
    id: root
    property var manager: null
    property string deviceId: ""
    property string selectedSite: ""
    property string pending: ""
    property string message: ""
    readonly property var device: manager && deviceId ? manager.deviceById(deviceId) : null
    signal launchRequested(string id, string url)
    visible: false
    transientParent: null
    title: "Hesh applications"
    color: Theme.window
    width: Math.min(560, Screen.desktopAvailableWidth - 32)
    height: Math.min(620, Screen.desktopAvailableHeight - 64)
    minimumWidth: Math.min(360, Screen.desktopAvailableWidth - 32)
    minimumHeight: Math.min(360, Screen.desktopAvailableHeight - 64)

    function openFor(id) {
        deviceId = id || ""
        selectedSite = ""
        pending = ""
        message = ""
        appName.text = ""
        appUrl.text = Automation.pageUrl(deviceId) || (device ? device.url : "")
        show(); raise(); requestActivate()
    }
    function send(command) {
        if (pending) return
        pending = "site-ui-" + Date.now()
        Automation.request(pending, command)
    }
    Connections {
        target: Automation
        function onFinished(token, reply) {
            if (token !== root.pending) return
            root.pending = ""
            root.message = reply.ok ? "Saved." : reply.error
            if (reply.ok) { root.selectedSite = ""; appName.text = ""; appUrl.text = "" }
        }
    }
    Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; onActivated: root.close() }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Applications"; color: Theme.text; font.pixelSize: 22; font.weight: Font.DemiBold }
            IconButton { iconText: "×"; tooltip: "Close"; onClicked: root.close() }
        }
        Text {
            Layout.fillWidth: true
            text: root.device ? "Open saved websites in " + root.device.name : "Choose a web device in Hesh to launch a website."
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: Automation.savedSites
            ScrollBar.vertical: ScrollBar {}
            Text { anchors.centerIn: parent; visible: list.count === 0; text: "Save your first website below"; color: Theme.textMuted; font.pixelSize: 13 }
            delegate: Rectangle {
                id: entry
                required property var modelData
                width: list.width
                height: 76
                radius: Theme.radiusSmall
                color: root.selectedSite === modelData.id ? Theme.accentSoft : Theme.panelRaised
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: entry.modelData.name; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: entry.modelData.url; color: Theme.textMuted; font.pixelSize: 11; elide: Text.ElideMiddle }
                    }
                    IconButton {
                        iconText: "✎"; tooltip: "Edit application"
                        onClicked: { root.selectedSite = entry.modelData.id; appName.text = entry.modelData.name; appUrl.text = entry.modelData.url }
                    }
                    AppButton {
                        text: "Open"; compact: true
                        enabled: root.device && root.device.type === "web"
                        onClicked: { root.launchRequested(root.deviceId, entry.modelData.url); root.close() }
                    }
                }
            }
        }
        Text { text: root.selectedSite ? "Edit application" : "Save a website"; color: Theme.text; font.pixelSize: 14 }
        TextField {
            id: appName
            Layout.fillWidth: true
            placeholderText: "Name, e.g. Google Analytics"
            color: Theme.text
            placeholderTextColor: Theme.textFaint
            selectByMouse: true
            background: Rectangle { color: Theme.input; radius: 6; border.color: appName.activeFocus ? Theme.accent : Theme.border }
        }
        TextField {
            id: appUrl
            Layout.fillWidth: true
            placeholderText: "https://analytics.google.com"
            color: Theme.text
            placeholderTextColor: Theme.textFaint
            selectByMouse: true
            background: Rectangle { color: Theme.input; radius: 6; border.color: appUrl.activeFocus ? Theme.accent : Theme.border }
        }
        Text { Layout.fillWidth: true; visible: root.message.length > 0; text: root.message; color: Theme.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap }
        RowLayout {
            Layout.fillWidth: true
            AppButton {
                text: root.selectedSite ? "Save changes" : "Save application"
                Layout.fillWidth: true
                enabled: !root.pending && appName.text.trim().length > 0 && appUrl.text.trim().length > 0
                onClicked: root.send({action: "site_save", siteId: root.selectedSite, name: appName.text, url: appUrl.text})
            }
            AppButton {
                text: "Delete"; secondary: true; destructive: true
                visible: !!root.selectedSite
                enabled: !root.pending
                onClicked: root.send({action: "site_delete", siteId: root.selectedSite})
            }
            IconButton {
                iconText: "+"; tooltip: "New application"; visible: !!root.selectedSite
                onClicked: { root.selectedSite = ""; appName.text = ""; appUrl.text = "" }
            }
        }
    }
}
