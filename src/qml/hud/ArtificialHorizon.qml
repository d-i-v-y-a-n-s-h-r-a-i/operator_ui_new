import QtQuick

Item {
    id: root
    width: 280
    height: 280

    property real pitch: vesselState ? vesselState.pitch : 0.0
    property real roll: vesselState ? vesselState.roll : 0.0

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#0a101d"
        border.color: "#1e293b"
        border.width: 2
        clip: true

        Item {
            id: horizonSphere
            width: parent.width * 2
            height: parent.height * 2
            anchors.centerIn: parent
            rotation: -root.roll

            Rectangle {
                id: sky
                width: parent.width
                height: parent.height / 2
                anchors.top: parent.top
                anchors.topMargin: root.pitch * 3.5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#0c2444" }
                    GradientStop { position: 1.0; color: "#194a7a" }
                }
            }

            Rectangle {
                id: ground
                width: parent.width
                height: parent.height / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -root.pitch * 3.5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#3d2814" }
                    GradientStop { position: 1.0; color: "#1c1208" }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.pitch * 3.5
                width: parent.width
                height: 2
                color: "#00f0ff"
            }

            Repeater {
                model: [-30, -20, -10, 10, 20, 30]
                delegate: Item {
                    width: parent.width
                    height: 20
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (root.pitch - modelData) * 3.5

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.abs(modelData) % 20 === 0 ? 60 : 36
                        height: 2
                        color: "#94a3b8"
                        opacity: 0.7
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 45
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.abs(modelData).toString()
                        color: "#94a3b8"
                        font.pixelSize: 9
                        font.family: "Monospace"
                    }
                }
            }
        }

        Item {
            id: fixedReticle
            anchors.centerIn: parent
            width: 120
            height: 40

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: 35
                height: 3
                color: "#f59e0b"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: 35
                height: 3
                color: "#f59e0b"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: "#f59e0b"
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: "P: " + root.pitch.toFixed(1) + "°  R: " + root.roll.toFixed(1) + "°"
            color: "#00f0ff"
            font.pixelSize: 11
            font.bold: true
            font.family: "Monospace"
        }
    }
}
