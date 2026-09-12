import QtQuick
import QtQuick.Controls
import Hesh 1.0

Rectangle {
    id: root

    property string iconText: "·"
    property string tooltip: ""
    // Exposed so a caller that draws its own icon in this button's frame can
    // tint it on hover.
    readonly property bool hovered: mouseArea.containsMouse
    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: 7
    color: mouseArea.pressed ? Theme.panelSoft : mouseArea.containsMouse ? Theme.panelRaised : "transparent"
    opacity: root.enabled ? 1.0 : 0.45

    Text {
        anchors.centerIn: parent
        visible: root.iconText.length > 0
        text: root.iconText
        color: Theme.textMuted
        font.pixelSize: root.iconText === "×" ? 22 : 16
        font.weight: Font.Medium
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: tooltip.length > 0 && mouseArea.containsMouse
    ToolTip.text: tooltip
    ToolTip.delay: 500
}
