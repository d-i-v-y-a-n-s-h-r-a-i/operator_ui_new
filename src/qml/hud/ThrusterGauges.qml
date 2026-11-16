import QtQuick

Item {
    id: root
    width: 140
    height: 240

    property real leftThruster: vesselState ? vesselState.leftThruster : 0.0
    property real rightThruster: vesselState ? vesselState.rightThruster : 0.0

    Rectangle {
        anchors.fill: parent
        color: "#0a101d"
        border.color: "#1e293b"
        border.width: 1
        radius: 4

        Text {
            id: title
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: "PROPULSION"
            color: "#64748b"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
            font.family: "Monospace"
        }

        Row {
            anchors.top: title.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            Column {
                spacing: 4
                Text {
                    text: "PORT"
                    color: "#94a3b8"
                    font.pixelSize: 9
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Monospace"
                }

                Rectangle {
                    width: 28
                    height: 150
                    color: "#0f172a"
                    border.color: "#334155"
                    border.width: 1
                    radius: 2

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: "#64748b"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.leftThruster >= 0 ? 75 - (root.leftThruster * 75) : 75
                        height: Math.abs(root.leftThruster) * 75
                        width: parent.width - 4
                        color: root.leftThruster >= 0 ? "#10b981" : "#ef4444"
                        radius: 1
                    }
                }

                Text {
                    text: Math.round(root.leftThruster * 100) + "%"
                    color: root.leftThruster >= 0 ? "#10b981" : "#ef4444"
                    font.pixelSize: 10
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Monospace"
                }
            }

            Column {
                spacing: 4
                Text {
                    text: "STBD"
                    color: "#94a3b8"
                    font.pixelSize: 9
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Monospace"
                }

                Rectangle {
                    width: 28
                    height: 150
                    color: "#0f172a"
                    border.color: "#334155"
                    border.width: 1
                    radius: 2

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: "#64748b"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.rightThruster >= 0 ? 75 - (root.rightThruster * 75) : 75
                        height: Math.abs(root.rightThruster) * 75
                        width: parent.width - 4
                        color: root.rightThruster >= 0 ? "#10b981" : "#ef4444"
                        radius: 1
                    }
                }

                Text {
                    text: Math.round(root.rightThruster * 100) + "%"
                    color: root.rightThruster >= 0 ? "#10b981" : "#ef4444"
                    font.pixelSize: 10
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Monospace"
                }
            }
        }
    }
}
