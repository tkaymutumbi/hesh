import QtQuick
import Hesh 1.0

// A web surface must never sit black. Sample a tiny grab of the view on a
// short timer and, when it is solid black, ask the owner to wake it. The wake
// is escalated if the first one does not take.
Item {
    id: root

    property Item target: null
    property bool running: false
    property int interval: 1500
    property int strikes: 0
    signal wake(int strikes)

    width: 0
    height: 0

    Timer {
        interval: root.interval
        repeat: true
        running: root.running && root.target !== null
        onTriggered: {
            if (!root.target || root.target.width < 4 || root.target.height < 4) return
            root.target.grabToImage(function(result) {
                if (!result) return
                if (SurfaceProbe.isBlack(result.image)) {
                    root.strikes++
                    console.log("Hesh: black surface detected, waking (" + root.strikes + ")")
                    root.wake(root.strikes)
                } else {
                    root.strikes = 0
                }
            }, Qt.size(12, 12))
        }
    }
}
