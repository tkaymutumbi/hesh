import QtQuick
import QtQuick.Layouts
import Hesh 1.0

Item {
    id: root

    signal createRequested()

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 14

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: 18
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accentBorder

            Rectangle {
                width: 25
                height: 40
                anchors.centerIn: parent
                radius: 5
                color: "transparent"
                border.width: 2
                border.color: Theme.accent

                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 4
                    width: 8
                    height: 2
                    radius: 1
                    color: Theme.accent
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 4
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.accent
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "No devices yet"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Create a device to start testing\nyour application."
            color: Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.25
            font.pixelSize: 13
        }

        Item { Layout.preferredHeight: 2 }

        AppButton {
            Layout.alignment: Qt.AlignHCenter
            text: "+  Create Device"
            onClicked: root.createRequested()
        }
    }
}
