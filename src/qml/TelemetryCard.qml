import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string primaryValue: ""
    property string unit: ""
    property string valueColor: "#ffffff"
    property bool isActive: false
    default property alias content: customContent.data

    RectangularGlow {
        anchors.fill: glassCard
        anchors.margins: -4
        glowRadius: 16
        spread: 0.0
        color: root.isActive ? Qt.rgba(0.0, 0.90, 1.0, 0.22) : Qt.rgba(0.0, 0.0, 0.0, 0.65)
        cornerRadius: glassCard.radius + glowRadius
        z: 0
    }

    Rectangle {
        id: glassCard
        anchors.fill: parent
        z: 1
        radius: 12
        color: root.isActive ? Qt.rgba(0.08, 0.12, 0.18, 0.50) : Qt.rgba(0.05, 0.07, 0.10, 0.35)
        border.width: 1
        border.color: root.isActive ? Qt.rgba(0.0, 0.90, 1.0, 0.40) : Qt.rgba(1.0, 1.0, 1.0, 0.15)
        clip: true


        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1.0, 1.0, 1.0, 0.25)
            radius: parent.radius
            z: 10
        }

        Item {
            anchors.fill: parent
            anchors.margins: 16
            z: 2

            RowLayout {
                id: headerRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right

                Text {
                    text: root.title
                    color: Qt.rgba(0.78, 0.86, 0.96, 0.80)
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 0.4
                    font.family: "Segoe UI, Inter, sans-serif"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "•••"
                    color: Qt.rgba(0.55, 0.65, 0.80, 0.35)
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignRight
                }
            }

            RowLayout {
                anchors.top: headerRow.bottom
                anchors.topMargin: 10
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    RowLayout {
                        spacing: 3

                        Text {
                            text: root.primaryValue
                            color: root.valueColor
                            font.pixelSize: 42
                            font.bold: true
                            font.family: "Segoe UI, Inter, sans-serif"
                        }

                        Text {
                            text: root.unit
                            color: Qt.rgba(0.72, 0.82, 0.95, 0.65)
                            font.pixelSize: 17
                            font.bold: true
                            Layout.alignment: Qt.AlignBaseline
                        }
                    }

                    Text {
                        text: root.subtitle
                        color: Qt.rgba(0.55, 0.65, 0.80, 0.70)
                        font.pixelSize: 11
                        font.family: "Segoe UI, Inter, sans-serif"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                Item {
                    id: customContent
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 128
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                }
            }
        }
    }
}
