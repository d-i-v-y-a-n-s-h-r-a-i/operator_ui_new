import QtQuick

// ============================================================================================================
//  LoraControlHud.qml  -  on-screen side of the manual-control link (keyboard + touch).
//
//  Needs the Python context property `loraBridge` (backend/lora_bridge.py).  Without it the item hides itself, so the
//  same Main.qml still runs in the C++ build.
//
//    pill      NO USB / USB - NO LORA / LORA LINKED   (tap = connect / disconnect the ESP32 serial port)
//    rays      DriveRays pop-up (see DriveRays.qml): TANDAV top view + front / back / side rays.  Appears when a drive
//              key (Up / Down / Left / Right / Space) is pressed, hides itself 10 s after the last key.
//              It sits to the LEFT of the 1-4 buttons, bottom aligned = where the old arrow tiles used to be.
//    1-4       Engine / Mode / VTS up / VTS down - flash cyan when sent, green on STM32 ACK, amber when rejected
//    bars      real throttle / steering / brake pot feedback while telemetry is fresh
//
//  Nothing here blocks the keyboard: key capture lives in Python (works whatever item has focus).
// ============================================================================================================
Item {
    id: root

    property real sf: 1.0
    property real lm: 0.0                          // 0 night .. 1 day
    property color accent: "#00f0ff"
    property bool showPill: false                  // false = hide the "LORA LINKED" status pill
    property bool showKeys: true                   // false = only the status pill
    property bool showRays: true                   // the new DriveRays pop-up
    property bool showKeyTiles: false              // true = bring the old arrow / SPACE tiles back (touch-screen driving)
    property int raysHideMs: 10000                 // DriveRays auto-hide after the last key activity
    property var bridge: (typeof loraBridge !== "undefined") ? loraBridge : null

    readonly property bool have: bridge !== null
    readonly property string st: have ? bridge.status : "disconnected"
    readonly property bool usb: st !== "disconnected"
    readonly property bool linked: st === "lora"
    property var keyState: have ? bridge.keys : ({})
    property var solState: have ? bridge.solenoidStates : ({})

    visible: have
    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function px(v) { return Math.round(v * sf); }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }
    readonly property color cOk: "#34d399"
    readonly property color cWarn: "#fbbf24"
    readonly property color cFail: "#ff5468"
    readonly property color tText: mixc("#e9f0f8", "#1d2733")
    readonly property color tMuted: mixc("#8d9db2", "#5d6b7d")
    readonly property color pillColor: linked ? cOk : usb ? cWarn : cFail
    readonly property string pillText: linked ? "LORA LINKED" : usb ? "USB  -  NO LORA" : "NO USB  -  TAP TO CONNECT"

    // ---- drive rays pop-up: overlay (does not take part in the layout), left of the 1-4 buttons, bottom aligned
    DriveRays {
        id: driveRays
        visible: root.showRays && opacity > 0.01
        enabled: false                              // never steals touches / clicks from what is behind it
        sf: root.sf; lm: root.lm; accent: root.accent
        hideMs: root.raysHideMs
        bridge: root.bridge
        x: root.showKeyTiles ? -(width + root.px(14) + root.px(46) * 3 + root.px(22)) : -(width + root.px(14))
        y: root.height - height
        z: 5
    }

    Column {
        id: col
        spacing: root.px(8)

        // ------------------------------------------------------------------------------------------ status pill
        Rectangle {
            id: pill
            visible: root.showPill
            height: root.showPill ? root.px(28) : 0
            radius: height / 2
            width: pillRow.implicitWidth + root.px(26)
            color: Qt.rgba(root.mixc("#0b121b", "#f3f6fa").r, root.mixc("#0b121b", "#f3f6fa").g, root.mixc("#0b121b", "#f3f6fa").b, 0.82)
            border.width: 1
            border.color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.7)
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: root.px(8)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.px(9); height: width; radius: width / 2; color: root.pillColor
                    SequentialAnimation on opacity {
                        running: root.linked; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pillText + (root.have && root.usb && bridge.portName.length ? "   " + bridge.portName : "")
                    color: root.tText; font.pixelSize: root.px(11); font.bold: true; font.letterSpacing: 1.2
                    font.family: "Segoe UI, Inter, sans-serif"
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (!root.have) return; if (root.usb) bridge.disconnectPort(); else bridge.connectAuto(); }
            }
        }

        // ------------------------------------------------------------------------------------------ keys + buttons
        Column {
            visible: root.showKeys && root.usb
            spacing: root.px(6)

            component KeyTile: Rectangle {
                id: tile
                property string label: ""
                property string sub: ""
                property string keyName: ""                       // motor key name for bridge.setKey
                property real tw: root.px(46)
                readonly property bool down: root.keyState[keyName] === true
                width: tw; height: root.px(40); radius: root.px(9)
                color: down ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                            : Qt.rgba(root.mixc("#101823", "#ffffff").r, root.mixc("#101823", "#ffffff").g, root.mixc("#101823", "#ffffff").b, 0.78)
                border.width: 1
                border.color: down ? root.accent : Qt.rgba(0.68, 0.78, 0.90, root.linked ? 0.34 : 0.16)
                scale: down ? 0.94 : 1.0
                opacity: root.linked ? 1.0 : 0.55
                Behavior on scale { NumberAnimation { duration: 70 } }
                Behavior on color { ColorAnimation { duration: 90 } }
                Column {
                    anchors.centerIn: parent
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.label; font.bold: true
                           font.pixelSize: root.px(tile.label.length > 2 ? 11 : 17); font.family: "Segoe UI, Inter, sans-serif"
                           color: tile.down ? "#04121a" : root.tText }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.sub; visible: tile.sub.length > 0
                           font.pixelSize: root.px(8); font.letterSpacing: 0.6; font.family: "Segoe UI, Inter, sans-serif"
                           color: tile.down ? "#04121a" : root.tMuted }
                }
                MouseArea {                                        // touch screen: press and hold = key held
                    anchors.fill: parent
                    enabled: tile.keyName.length > 0 && root.have
                    onPressed: bridge.setKey(tile.keyName, true)
                    onReleased: bridge.setKey(tile.keyName, false)
                    onCanceled: bridge.setKey(tile.keyName, false)
                }
            }

            Row {
                spacing: root.px(14)
                Column {                                           // OLD arrow cluster - hidden by default, replaced by DriveRays
                    visible: root.showKeyTiles
                    spacing: root.px(4)
                    Item { width: root.px(46) * 3 + root.px(8); height: root.px(40)
                           KeyTile { x: root.px(46) + root.px(4); label: "↑"; sub: "THR +"; keyName: "Up" } }
                    Row {
                        spacing: root.px(4)
                        KeyTile { label: "←"; sub: "LEFT"; keyName: "Left" }
                        KeyTile { label: "↓"; sub: "THR −"; keyName: "Down" }
                        KeyTile { label: "→"; sub: "RIGHT"; keyName: "Right" }
                    }
                    KeyTile { tw: root.px(46) * 3 + root.px(8); label: "SPACE"; sub: "BRAKE"; keyName: "Space" }
                }
                Column {                                           // 1-4 + pot feedback
                    spacing: root.px(8)
                    Grid {
                        columns: 2; spacing: root.px(4)
                        Repeater {
                            model: [ { k: "1", ch: "E", n: "ENGINE" }, { k: "2", ch: "M", n: "MODE" },
                                     { k: "3", ch: "VU", n: "VTS UP" }, { k: "4", ch: "VD", n: "VTS DN" } ]
                            Rectangle {
                                id: sol
                                readonly property string s: root.solState[modelData.ch] || "idle"
                                readonly property color sc: s === "ok" ? root.cOk : s === "rejected" || s === "timeout" ? root.cWarn
                                                          : s === "pending" ? root.accent : "transparent"
                                width: root.px(70); height: root.px(40); radius: root.px(9)
                                color: s === "idle" ? Qt.rgba(root.mixc("#101823", "#ffffff").r, root.mixc("#101823", "#ffffff").g, root.mixc("#101823", "#ffffff").b, 0.78)
                                                    : Qt.rgba(sc.r, sc.g, sc.b, 0.28)
                                border.width: 1
                                border.color: s === "idle" ? Qt.rgba(0.68, 0.78, 0.90, root.linked ? 0.34 : 0.16) : sc
                                opacity: root.linked ? 1.0 : 0.45
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    anchors.centerIn: parent; spacing: root.px(6)
                                    Text { text: modelData.k; font.bold: true; font.pixelSize: root.px(17); color: root.tText; font.family: "Segoe UI, Inter, sans-serif" }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: sol.s === "ok" ? "✓" : sol.s === "rejected" ? "✗" : sol.s === "pending" ? "…" : modelData.n
                                           font.pixelSize: root.px(sol.s === "idle" ? 8 : 13); font.letterSpacing: 0.5; color: sol.s === "idle" ? root.tMuted : sol.sc
                                           font.family: "Segoe UI, Inter, sans-serif" }
                                }
                                MouseArea { anchors.fill: parent; enabled: root.have; onClicked: bridge.fireSolenoid(modelData.ch) }
                            }
                        }
                    }
                    Column {                                       // real pot feedback
                        spacing: root.px(3)
                        visible: root.have && bridge.feedbackFresh
                        Repeater {
                            model: [ { n: "THR", c: "#ff5468", mid: false }, { n: "STR", c: "#fbbf24", mid: true },
                                     { n: "BRK", c: "#38bdf8", mid: false } ]
                            Row {
                                spacing: root.px(5)
                                readonly property real raw: !root.have ? 0 : (index === 0 ? bridge.throttlePct
                                                          : index === 1 ? bridge.steeringPct : bridge.brakePct)
                                readonly property real v: Math.max(0, Math.min(100, raw))
                                Text { width: root.px(24); text: modelData.n; font.pixelSize: root.px(8); color: root.tMuted; font.letterSpacing: 0.6
                                       font.family: "Segoe UI, Inter, sans-serif"; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle {
                                    width: root.px(80); height: root.px(5); radius: height / 2; color: Qt.rgba(1, 1, 1, 0.10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        height: parent.height; radius: height / 2; color: modelData.c
                                        x: modelData.mid ? parent.width * Math.min(0.5, parent.parent.v / 100) : 0
                                        width: modelData.mid ? parent.width * Math.abs(parent.parent.v - 50) / 100 : parent.width * parent.parent.v / 100
                                    }
                                }
                                Text { width: root.px(28); text: Math.round(parent.v) + "%"; font.pixelSize: root.px(9); color: root.tText
                                       horizontalAlignment: Text.AlignRight; font.family: "Segoe UI, Inter, sans-serif"; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }
        }
    }
}
