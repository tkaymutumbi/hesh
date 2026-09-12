import QtQuick
import Hesh 1.0

// Settings icon, drawn from primitives like the empty-state device glyph rather
// than typed as a character: a font's gear can render as a colour emoji, and an
// icon-font dependency would be a heavier contract than these three sliders.
Item {
    id: root

    property color color: Theme.textMuted

    implicitWidth: 18
    implicitHeight: 18

    Repeater {
        // Knob offset per track, so the three rows read as sliders rather than
        // as a stack of identical lines.
        model: [3, 9, 6]

        delegate: Item {
            id: track

            required property int modelData
            required property int index

            x: 0
            y: 4 + index * 5 - 1
            width: root.width
            height: 2

            Rectangle {
                anchors.fill: parent
                radius: 1
                color: root.color
            }

            Rectangle {
                x: track.modelData
                y: -(height - track.height) / 2
                width: 5
                height: 6
                radius: 2
                color: root.color
            }
        }
    }
}
