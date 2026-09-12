import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hesh 1.0

// Application settings. Every control writes straight through to the
// `Preferences` singleton — there is no OK/Cancel, because the palette and the
// preview knobs have to be seen while they are being changed. The stored values
// are announced through the singleton's change signals, so the rest of the UI
// follows without this dialog holding any state of its own.
Popup {
    id: root

    property var manager
    property int section: 0

    readonly property var sections: [
        { title: "Devices", hint: "New device defaults" },
        { title: "Preview", hint: "How devices render" },
        { title: "Appearance", hint: "Accent colour" },
        { title: "Storage", hint: "Device browser data" },
        { title: "Advanced", hint: "Chromium and diagnostics" }
    ]

    function indexOfProfile(name) {
        const profiles = root.manager ? root.manager.availableProfiles : []
        for (let i = 0; i < profiles.length; ++i) {
            if (profiles[i].name === name) return i
        }
        return 0
    }

    // Fields are re-seeded every time the dialog opens: a TextField that takes
    // user input drops the binding that filled it, so the stored value has to be
    // pushed in again rather than relied on.
    function reset() {
        nameField.text = Preferences.newDeviceName
        urlField.text = Preferences.newDeviceUrl
        profileCombo.currentIndex = indexOfProfile(Preferences.newDeviceProfile)
        flagsField.text = Preferences.extraChromiumFlags
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    width: Math.min(760, (Overlay.overlay ? Overlay.overlay.width : 760) - 40)
    height: Math.min(560, (Overlay.overlay ? Overlay.overlay.height : 560) - 40)
    padding: 0

    onOpened: reset()
    onClosed: reset()

    Overlay.modal: Rectangle { color: "#99080a0e" }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: Theme.panel
        border.width: 1
        border.color: Theme.borderStrong

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 12
            anchors.rightMargin: 12
            iconText: "×"
            tooltip: "Close"
            onClicked: root.close()
        }
    }

    // One row in the section rail.
    component NavRow: Rectangle {
        id: navRow

        property string label: ""
        property bool selected: false
        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        radius: Theme.radiusSmall
        color: navRow.selected ? Theme.accentSoft
                               : navMouse.containsMouse ? Theme.panelRaised : "transparent"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            text: navRow.label
            color: navRow.selected ? Theme.text : Theme.textMuted
            font.pixelSize: 12
            font.weight: navRow.selected ? Font.Medium : Font.Normal
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navRow.activated()
        }
    }

    // A settings row: label and explanation on the left, control on the right.
    component ToggleRow: RowLayout {
        id: toggleRow

        property string label: ""
        property string description: ""
        property bool checked: false
        signal toggled()

        Layout.fillWidth: true
        Layout.topMargin: 16
        spacing: 18

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: toggleRow.label
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: toggleRow.description
                visible: toggleRow.description.length > 0
                color: Theme.textMuted
                font.pixelSize: 11
                lineHeight: 1.2
                wrapMode: Text.WordWrap
            }
        }

        SettingSwitch {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            checked: toggleRow.checked
            onToggled: toggleRow.toggled()
        }
    }

    component SectionTitle: Text {
        Layout.fillWidth: true
        color: Theme.text
        font.pixelSize: 17
        font.weight: Font.Medium
    }

    component SectionHint: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        color: Theme.textMuted
        font.pixelSize: 12
        lineHeight: 1.2
        wrapMode: Text.WordWrap
    }

    component FieldLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 18
        color: Theme.textMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    component FieldNote: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        color: Theme.textFaint
        font.pixelSize: 11
        lineHeight: 1.3
        wrapMode: Text.WordWrap
    }

    // A path or flag list: no spaces to wrap on, so it breaks anywhere.
    component ValueNote: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        textFormat: Text.PlainText
        color: Theme.textMuted
        font.pixelSize: 11
        lineHeight: 1.3
        wrapMode: Text.WrapAnywhere
    }

    component SettingField: TextField {
        id: settingField

        Layout.fillWidth: true
        Layout.topMargin: 8
        implicitHeight: 38
        color: Theme.text
        font.pixelSize: 12
        selectByMouse: true
        leftPadding: 12
        rightPadding: 12
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.input
            border.width: 1
            border.color: settingField.activeFocus ? Theme.accentStrong : Theme.border
        }
    }

    contentItem: Item {
        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: rail
                Layout.fillHeight: true
                Layout.preferredWidth: 186
                color: Theme.window
                border.width: 1
                border.color: Theme.border
                topLeftRadius: Theme.radiusMedium
                bottomLeftRadius: Theme.radiusMedium

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 24
                    anchors.bottomMargin: 18
                    spacing: 2

                    Text {
                        Layout.leftMargin: 20
                        Layout.bottomMargin: 14
                        text: "SETTINGS"
                        color: Theme.textFaint
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.4
                    }

                    Repeater {
                        model: root.sections

                        delegate: NavRow {
                            required property var modelData
                            required property int index

                            label: modelData.title
                            selected: root.section === index
                            onActivated: root.section = index
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 16
                        text: "Hesh " + Preferences.appVersion
                        color: Theme.textFaint
                        font.pixelSize: 10
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Flickable {
                    id: sectionFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: sectionColumn.implicitHeight + 56
                    clip: true

                    ColumnLayout {
                        id: sectionColumn
                        width: Math.max(0, sectionFlick.width - 56)
                        x: 28
                        y: 28
                        spacing: 0

                        // Devices ---------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.section === 0

                            SectionTitle { text: "New device defaults" }
                            SectionHint {
                                text: "What the Create Device dialog starts from. Existing devices "
                                      + "keep their own profile and URL."
                            }

                            FieldLabel { text: "Name" }
                            SettingField {
                                id: nameField
                                onTextEdited: Preferences.newDeviceName = text
                            }

                            FieldLabel { text: "URL" }
                            SettingField {
                                id: urlField
                                inputMethodHints: Qt.ImhUrlCharactersOnly
                                onTextEdited: Preferences.newDeviceUrl = text
                            }

                            FieldLabel { text: "Profile" }
                            ComboBox {
                                id: profileCombo
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                implicitHeight: 38
                                model: root.manager ? root.manager.availableProfiles : []
                                textRole: "name"
                                valueRole: "name"
                                leftPadding: 12
                                rightPadding: 32
                                contentItem: Text {
                                    text: profileCombo.displayText
                                    color: Theme.text
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.input
                                    border.width: 1
                                    border.color: profileCombo.activeFocus ? Theme.accentStrong : Theme.border
                                }
                                popup: Popup {
                                    y: profileCombo.height + 4
                                    width: profileCombo.width
                                    padding: 4
                                    contentItem: ListView {
                                        implicitHeight: Math.min(contentHeight, 250)
                                        model: profileCombo.popup.visible ? profileCombo.delegateModel : null
                                        clip: true
                                    }
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: Theme.panelRaised
                                        border.width: 1
                                        border.color: Theme.borderStrong
                                    }
                                }
                                onActivated: Preferences.newDeviceProfile = currentText
                            }

                            FieldNote {
                                text: "A profile that is not in the catalog falls back to the "
                                      + "first entry when the device is created."
                            }
                        }

                        // Preview ---------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.section === 1

                            SectionTitle { text: "Preview" }
                            SectionHint {
                                text: "How embedded device previews are presented. Standalone "
                                      + "windows always keep their own 1:1 sizing."
                            }

                            ToggleRow {
                                label: "Show DevTools when a device opens"
                                description: "The device toolbar keeps its own DevTools toggle."
                                checked: Preferences.showDevToolsOnOpen
                                onToggled: Preferences.showDevToolsOnOpen = !Preferences.showDevToolsOnOpen
                            }

                            ToggleRow {
                                label: "Open new devices in a standalone window"
                                description: "Window placement and open state stay session-only: "
                                             + "reopening Hesh does not restore windows."
                                checked: Preferences.openInStandalone
                                onToggled: Preferences.openInStandalone = !Preferences.openInStandalone
                            }

                            ToggleRow {
                                label: "Allow upscaling the embedded preview"
                                description: "Previews normally scale down only. Upscaling zooms the "
                                             + "browser surface past 1:1, which softens text and "
                                             + "risks colour banding."
                                checked: Preferences.allowUpscale
                                onToggled: Preferences.allowUpscale = !Preferences.allowUpscale
                            }

                            ToggleRow {
                                label: "Show viewport metrics"
                                description: "Viewport, device pixel ratio, fit mode, and zoom level "
                                             + "in the device toolbar."
                                checked: Preferences.showMetrics
                                onToggled: Preferences.showMetrics = !Preferences.showMetrics
                            }
                        }

                        // Appearance ------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.section === 2

                            SectionTitle { text: "Accent" }
                            SectionHint {
                                text: "The accent tints interactive controls, the selected device, "
                                      + "and the preview's loading and progress states."
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                spacing: 10

                                AccentPicker {
                                    current: Preferences.accentName
                                    onPicked: (name) => Preferences.accentName = name
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Preferences.accentName
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }
                            }

                            FieldNote {
                                text: "Presets keep the hover, pressed, and surface shades coherent "
                                      + "with the base accent. Text and panel colours stay fixed. "
                                      + "A single device can override this from its right-click menu."
                            }
                        }

                        // Storage ---------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.section === 3

                            SectionTitle { text: "Device browser data" }
                            SectionHint {
                                text: "Each device keeps its own cookies, local storage, IndexedDB, "
                                      + "and cache. Clearing a device removes them and reloads it "
                                      + "with a fresh session."
                            }

                            FieldLabel { text: "Data directory" }
                            ValueNote { text: Preferences.dataRootPath }
                            FieldLabel { text: "Cache directory" }
                            ValueNote { text: Preferences.cacheRootPath }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 24
                                spacing: 9

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const count = root.manager ? root.manager.deviceCount : 0
                                        return count === 1 ? "1 device stores data here"
                                                           : count + " devices store data here"
                                    }
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }

                                AppButton {
                                    text: "Open Data Folder"
                                    secondary: true
                                    compact: true
                                    onClicked: Preferences.openDataFolder()
                                }

                                AppButton {
                                    text: "Clear All Device Data"
                                    destructive: true
                                    compact: true
                                    enabled: root.manager ? root.manager.deviceCount > 0 : false
                                    onClicked: clearAllDialog.open()
                                }
                            }
                        }

                        // Advanced --------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.section === 4

                            SectionTitle { text: "Chromium" }
                            SectionHint {
                                text: "Extra flags for the embedded browser. The rendering guards "
                                      + "Hesh needs for persistent device surfaces are always "
                                      + "appended."
                            }

                            FieldLabel { text: "Extra flags" }
                            SettingField {
                                id: flagsField
                                placeholderText: "e.g. --enable-features=WebUIDarkMode"
                                placeholderTextColor: Theme.textFaint
                                onTextEdited: Preferences.extraChromiumFlags = text
                            }
                            FieldNote {
                                text: "Chromium reads its command line once, so a change applies to "
                                      + "the next launch. Flags set in QTWEBENGINE_CHROMIUM_FLAGS "
                                      + "for one launch take precedence."
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 16
                                spacing: 10
                                visible: Preferences.restartRequired

                                Rectangle {
                                    implicitWidth: restartLabel.implicitWidth + 20
                                    implicitHeight: 28
                                    radius: Theme.radiusSmall
                                    color: Theme.errorSoft
                                    border.width: 1
                                    border.color: Theme.warning

                                    Text {
                                        id: restartLabel
                                        anchors.centerIn: parent
                                        text: "Restart required"
                                        color: Theme.warning
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                AppButton {
                                    text: "Relaunch Hesh"
                                    compact: true
                                    onClicked: Preferences.relaunch()
                                }

                                Item { Layout.fillWidth: true }
                            }

                            FieldLabel { text: "Flags this process is running with" }
                            ValueNote {
                                text: Preferences.effectiveChromiumFlags.length > 0
                                      ? Preferences.effectiveChromiumFlags
                                      : "No flags set"
                            }

                            FieldLabel { text: "Diagnostics" }
                            FieldNote {
                                text: "Hesh " + Preferences.appVersion
                                      + "  ·  Qt " + Preferences.qtVersion
                                      + "  ·  Chromium " + Preferences.chromiumVersion
                                      + "  ·  HiDPI rounding " + Preferences.highDpiPolicy
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: Theme.panelRaised
                    bottomRightRadius: Theme.radiusMedium

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        spacing: 9

                        Text {
                            Layout.fillWidth: true
                            text: "Restoring defaults keeps your devices and their browser data."
                            color: Theme.textFaint
                            elide: Text.ElideRight
                            font.pixelSize: 11
                        }

                        AppButton {
                            text: "Restore Defaults"
                            secondary: true
                            compact: true
                            onClicked: Preferences.resetToDefaults()
                        }

                        AppButton {
                            text: "Close"
                            compact: true
                            onClicked: root.close()
                        }
                    }
                }
            }
        }
    }

    ClearDeviceDataDialog {
        id: clearAllDialog
        manager: root.manager
        allDevices: true
    }
}
