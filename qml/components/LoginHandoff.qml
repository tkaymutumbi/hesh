import QtQuick
import QtQuick.Layouts
import Hesh 1.0

Rectangle {
    id: root
    property string deviceId: ""
    visible: Automation.paused && Automation.activeDevice === root.deviceId && Automation.loginMessage.length > 0
    color: Theme.panelRaised
    height: visible ? contents.implicitHeight + 20 : 0
    border.color: Theme.accentBorder
    RowLayout {
        id: contents
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 10
        Text { Layout.fillWidth: true; text: Automation.loginMessage; color: Theme.text; font.pixelSize: 12; wrapMode: Text.WordWrap }
        AppButton { text: "Saved logins"; secondary: true; compact: true; onClicked: Automation.openLogins(root.deviceId) }
        AppButton { text: "Resume AI"; compact: true; onClicked: Automation.paused = false }
    }
}
