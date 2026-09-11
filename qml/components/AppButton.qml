import QtQuick
import Hesh 1.0

Rectangle {
    id: root

    property string text: "Button"
    property bool secondary: false
    property bool destructive: false
    property bool compact: false
    signal clicked()

    implicitWidth: Math.max(compact ? 96 : 132, label.implicitWidth + (compact ? 28 : 36))
    implicitHeight: compact ? 34 : 38
    radius: Theme.radiusSmall
    color: !root.enabled
           ? Theme.panelSoft
           : mouseArea.pressed
             ? (secondary ? Theme.borderStrong : (destructive ? Theme.errorStrong : Theme.accentStrong))
             : (secondary ? Theme.panelRaised : (destructive ? Theme.error : Theme.accent))
    border.width: secondary ? 1 : 0
    border.color: Theme.borderStrong
    opacity: root.enabled ? 1.0 : 0.55

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.secondary ? Theme.text : Theme.window
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    Behavior on color {
        ColorAnimation { duration: 140 }
    }
}
