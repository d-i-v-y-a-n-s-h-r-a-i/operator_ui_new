
import QtQuick
import QtQuick.Window
Window {
    id: w; width: 900; height: 520; visible: true; color: "#0b121b"
    LoraControlHud { id: hud; x: 24; y: 20; sf: 1.3; accent: "#00f0ff" }
    TextInput { id: ti; objectName: "ti"; x: 600; y: 20; width: 200; height: 30; color: "white"; text: "" }
}
