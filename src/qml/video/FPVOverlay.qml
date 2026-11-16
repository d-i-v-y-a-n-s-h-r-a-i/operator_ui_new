import QtQuick
import QtQuick.Controls
import QtMultimedia

Item {
    id: root
    width: 640
    height: 360

    Rectangle {
        anchors.fill: parent
        color: "#050811"
        clip: true

        MediaPlayer {
            id: player
            source: video ? video.sourceUrl : ""
        }

        VideoOutput {
            anchors.fill: parent
        }

        Item {
            id: crosshair
            anchors.centerIn: parent
            width: 160
            height: 160

            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: 5
                color: "transparent"
                border.color: "#00f0ff"
                border.width: 1.5
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: 55
                height: 1.5
                color: "#00f0ff"
                opacity: 0.8
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: 55
                height: 1.5
                color: "#00f0ff"
                opacity: 0.8
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: 1.5
                height: 55
                color: "#00f0ff"
                opacity: 0.8
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 1.5
                height: 55
                color: "#00f0ff"
                opacity: 0.8
            }
        }

        Repeater {
            model: vesselState ? vesselState.threats : []
            delegate: Item {
                x: (modelData.x || 0) * root.width
                y: (modelData.y || 0) * root.height
                width: (modelData.w || 0.1) * root.width
                height: (modelData.h || 0.1) * root.height

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 0, 0, 0.12)
                    border.color: (modelData.colregs === "GIVE_WAY") ? "#ef4444" : "#f59e0b"
                    border.width: 1.5
                    radius: 2
                }

                Rectangle {
                    anchors.bottom: parent.top
                    anchors.left: parent.left
                    height: 16
                    width: threatLabel.implicitWidth + 8
                    color: (modelData.colregs === "GIVE_WAY") ? "#ef4444" : "#f59e0b"
                    radius: 2

                    Text {
                        id: threatLabel
                        anchors.centerIn: parent
                        text: (modelData.class || "TARGET") + " " + (modelData.range_m ? Math.round(modelData.range_m) + "m" : "")
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "Monospace"
                    }
                }
            }
        }

        Row {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 10
            spacing: 8

            Rectangle {
                width: 50
                height: 20
                color: "#ef4444"
                radius: 3
                Text {
                    anchors.centerIn: parent
                    text: "LIVE"
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 10
                    font.family: "Monospace"
                }
            }

            Rectangle {
                width: 70
                height: 20
                color: "#0f172a"
                border.color: "#334155"
                border.width: 1
                radius: 3
                Text {
                    anchors.centerIn: parent
                    text: (video ? video.fps : 30) + " FPS"
                    color: "#10b981"
                    font.bold: true
                    font.pixelSize: 10
                    font.family: "Monospace"
                }
            }

            Rectangle {
                width: 90
                height: 20
                color: "#0f172a"
                border.color: "#334155"
                border.width: 1
                radius: 3
                Text {
                    anchors.centerIn: parent
                    text: (video ? video.bitrateKbps : 4500) + " kbps"
                    color: "#94a3b8"
                    font.pixelSize: 10
                    font.family: "Monospace"
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 110
            height: 22
            color: (vesselState && vesselState.armed) ? "#ef4444" : "#1e293b"
            radius: 3

            Text {
                anchors.centerIn: parent
                text: (vesselState && vesselState.armed) ? "ARMED — LIVE" : "DISARMED"
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 11
                font.family: "Monospace"
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            color: "#0a101d"
            opacity: 0.85

            Row {
                anchors.centerIn: parent
                spacing: 24

                Text {
                    text: "SPD: " + (vesselState ? vesselState.speed.toFixed(1) : "0.0") + " kts"
                    color: "#00f0ff"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "Monospace"
                }

                Text {
                    text: "HDG: " + (vesselState ? vesselState.heading.toFixed(0) : "0") + "°"
                    color: "#00f0ff"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "Monospace"
                }

                Text {
                    text: "DEPTH: " + (vesselState ? vesselState.depth.toFixed(1) : "0.0") + " m"
                    color: "#00f0ff"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "Monospace"
                }

                Text {
                    text: "BAT: " + (vesselState ? vesselState.batteryPercentage : 0) + "% (" + (vesselState ? vesselState.batteryVoltage.toFixed(1) : "0.0") + "V)"
                    color: (vesselState && vesselState.batteryPercentage < 20) ? "#ef4444" : "#10b981"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "Monospace"
                }
            }
        }
    }
}
