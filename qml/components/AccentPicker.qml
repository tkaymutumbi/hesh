import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// Accent swatches. The catalog and the derived shades live in C++, so the app
// accent picker and the per-device picker cannot disagree about what a preset
// looks like. Sizes are configurable because the settings dialog has room for
// large swatches while the device context menu does not.
RowLayout {
    id: root

    property var palette: Preferences.accentPresets
    property string current: ""
    property int swatchWidth: 46
    property int swatchHeight: 30
    property int swatchSpacing: 10
    signal picked(string name)

    spacing: root.swatchSpacing

    Repeater {
        model: root.palette

        delegate: Rectangle {
            required property var modelData

            Layout.preferredWidth: root.swatchWidth
            Layout.preferredHeight: root.swatchHeight
            radius: Theme.radiusSmall
            color: modelData.accent
            border.width: 2
            border.color: root.current === modelData.name ? Theme.text : "transparent"

            ToolTip {
                text: modelData.name
                visible: swatchMouse.containsMouse
                delay: 400
            }

            MouseArea {
                id: swatchMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(modelData.name)
            }
        }
    }
}
