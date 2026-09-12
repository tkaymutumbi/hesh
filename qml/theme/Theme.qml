pragma Singleton

import QtQuick

// A plain palette. Everything here is a live binding for its consumers, so the
// accent trio carries default values instead of being readonly: Main.qml pushes
// the stored accent in, and every binding that reads Theme.accent follows.
QtObject {
    readonly property color window: "#111317"
    readonly property color panel: "#181b20"
    readonly property color panelRaised: "#1e2229"
    readonly property color panelSoft: "#20242c"
    readonly property color input: "#12151a"
    readonly property color border: "#2a3039"
    readonly property color borderStrong: "#3a424e"
    readonly property color text: "#edf0f5"
    readonly property color textMuted: "#929aa8"
    readonly property color textFaint: "#626b79"
    property color accent: "#a4a7ff"
    property color accentStrong: "#8589f0"
    property color accentSoft: "#292c4a"
    // Border of an accentSoft surface. It used to be hardcoded at the two call
    // sites, which only worked while the accent was the indigo default.
    property color accentBorder: "#454a75"
    readonly property color success: "#66d6a3"
    readonly property color warning: "#efbd75"
    readonly property color error: "#ee7d86"
    readonly property color errorStrong: "#d1646d"
    readonly property color errorSoft: "#3a2328"
    readonly property int radiusSmall: 7
    readonly property int radiusMedium: 10
    readonly property int spacing: 12
}
