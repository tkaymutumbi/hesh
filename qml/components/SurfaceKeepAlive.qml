import QtQuick

// An idle Wayland surface can go black until the pointer moves over it: the
// compositor stops pacing frames and the last buffer is dropped. Flipping a
// near-invisible pixel makes Qt Quick present a new frame twice a second, which
// keeps the surface alive without touching the page inside it.
Item {
    id: root

    property bool running: false

    width: 1
    height: 1
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    z: 1000
    enabled: false

    Rectangle {
        id: pixel
        anchors.fill: parent
        color: "#000000"
        opacity: 0.004
    }

    Timer {
        interval: 500
        repeat: true
        running: root.running
        onTriggered: pixel.opacity = pixel.opacity < 0.006 ? 0.008 : 0.004
    }
}
