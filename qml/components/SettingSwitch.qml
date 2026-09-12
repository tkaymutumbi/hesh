import QtQuick
import Hesh 1.0

// A settings toggle. QtQuick Controls' Switch would need its indicator and
// handle restyled anyway, so the track and knob are drawn directly: two states,
// one animation, no control background to fight.
Item {
    id: root

    property bool checked: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 22

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.panelSoft
        border.width: 1
        border.color: root.checked ? Theme.accentStrong : Theme.borderStrong

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    Rectangle {
        id: knob
        width: 14
        height: 14
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 4 : 4
        color: root.checked ? Theme.window : Theme.textMuted

        Behavior on x {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled()
    }

    opacity: root.enabled ? 1.0 : 0.45
}
