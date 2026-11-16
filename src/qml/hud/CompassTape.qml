import QtQuick

Item {
    id: root
    width: 450
    height: 55

    property real heading: vesselState ? vesselState.heading : 0.0

    Rectangle {
        anchors.fill: parent
        color: "#0a101d"
        border.color: "#1e293b"
        border.width: 1
        radius: 4
        clip: true

        Item {
            id: tape
            height: parent.height
            width: 360 * 6
            x: (root.width / 2) - ((root.heading >= 0 ? root.heading : 360 + root.heading) * 6)

            Repeater {
                model: 72
                delegate: Item {
                    property int deg: index * 5
                    x: deg * 6
                    width: 30
                    height: parent.height

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: deg % 10 === 0 ? 2 : 1
                        height: deg % 30 === 0 ? 14 : (deg % 10 === 0 ? 9 : 5)
                        color: deg % 30 === 0 ? "#00f0ff" : "#64748b"
                    }

                    Text {
                        visible: deg % 30 === 0
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (deg === 0 || deg === 360) return "N";
                            if (deg === 90) return "E";
                            if (deg === 180) return "S";
                            if (deg === 270) return "W";
                            return deg.toString();
                        }
                        color: (deg === 0 || deg === 90 || deg === 180 || deg === 270) ? "#00f0ff" : "#94a3b8"
                        font.pixelSize: (deg === 0 || deg === 90 || deg === 180 || deg === 270) ? 12 : 10
                        font.bold: true
                        font.family: "Monospace"
                    }
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 3
            height: parent.height - 12
            color: "#f59e0b"
        }

        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 10
            height: 6
            color: "#f59e0b"
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: 60
            height: 18
            color: "#0f172a"
            border.color: "#00f0ff"
            border.width: 1
            radius: 2

            Text {
                anchors.centerIn: parent
                text: Math.round(root.heading).toString().padStart(3, '0') + "°"
                color: "#00f0ff"
                font.pixelSize: 11
                font.bold: true
                font.family: "Monospace"
            }
        }
    }
}
