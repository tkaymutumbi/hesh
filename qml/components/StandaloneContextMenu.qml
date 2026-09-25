import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// A compact, Hesh-styled menu for the standalone surface. It intentionally
// exposes browser navigation without allowing the page's native Chromium
// menu to replace the app's visual language.
Popup {
    id: root

    property var device: null
    property bool canGoBack: false
    property bool canGoForward: false
    property bool devToolsOpen: false

    signal reloadRequested()
    signal devToolsRequested()
    signal backRequested()
    signal forwardRequested()
    signal openBrowserRequested(string url)
    signal mainWindowRequested()
    signal closeRequested()

    width: 190
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.panelRaised
        border.width: 1
        border.color: Theme.borderStrong
        radius: Theme.radiusSmall
    }

    function openAt(localX, localY) {
        x = Math.max(8, Math.min(localX, parent.width - width - 8))
        y = Math.max(8, Math.min(localY, parent.height - height - 8))
        open()
    }

    function itemColor(mouse, enabled) {
        if (!enabled) return "transparent"
        return mouse.containsMouse ? Theme.panelSoft : "transparent"
    }

    contentItem: ColumnLayout {
        spacing: 2

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 7
            Layout.rightMargin: 7
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.device ? root.device.name : "Web device"
                color: Theme.text
                elide: Text.ElideRight
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Text {
                Layout.fillWidth: true
                text: root.device ? root.device.url : ""
                color: Theme.textFaint
                elide: Text.ElideMiddle
                font.pixelSize: 10
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: root.itemColor(reloadMouse, true)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Reload"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: reloadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    // Release the popup's pointer grab before reloading its
                    // WebEngineView. Reloading while this menu still owns the
                    // click can race the standalone surface's focus recovery.
                    Qt.callLater(function() { root.reloadRequested() })
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: root.itemColor(devToolsMouse, true)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: root.devToolsOpen ? "Hide DevTools" : "DevTools"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: devToolsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    Qt.callLater(function() { root.devToolsRequested() })
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: root.itemColor(backMouse, root.canGoBack)
            opacity: root.canGoBack ? 1.0 : 0.45

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Back"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                enabled: root.canGoBack
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.backRequested()
                    root.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: root.itemColor(forwardMouse, root.canGoForward)
            opacity: root.canGoForward ? 1.0 : 0.45

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Forward"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: forwardMouse
                anchors.fill: parent
                enabled: root.canGoForward
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.forwardRequested()
                    root.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: browserMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Open in Browser"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: browserMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.openBrowserRequested(root.device ? root.device.url : "")
                    root.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: mainWindowMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Main Window"
                color: Theme.text
                font.pixelSize: 12
            }

            MouseArea {
                id: mainWindowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.mainWindowRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 5
            color: closeMouse.containsMouse ? Theme.panelSoft : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "Close Window"
                color: Theme.error
                font.pixelSize: 12
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.close()
                    root.closeRequested()
                }
            }
        }
    }
}
