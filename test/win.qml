import QtQuick
import QtQuick.Window
Window {
    id: w; width: 1920; height: 1080; visible: true
    property real lmv: 0.0
    property alias panel: panel
    color: lmv < 0.5 ? "#171d28" : "#cfd8e3"
    ConnectionsPanel { id: panel; objectName: "panel"; anchors.fill: parent; open: true; tab: 1; sf: 1.0; lm: w.lmv; accent: "#00f0ff" }
}
