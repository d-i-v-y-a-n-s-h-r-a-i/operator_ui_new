import QtQuick

// ============================================================================================================
//  SerialTerminal.qml  -  Arduino-IDE style serial monitor, built into the SYSTEM CONNECTIONS pop-up.
//
//  Talks to the Python object `loraBridge` (backend/lora_bridge.py).  With it the ESP32 stays connected by itself
//  (the port you pick is pinned and re-opened automatically) - the Arduino IDE is not needed any more.
//
//    toolbar   port list (ALL ports)  |  baud  |  CONNECT / DISCONNECT  |  RESET ESP32
//    status    link state, bytes, rate, age of the last byte, errors (e.g. "COM3 is in use by Arduino IDE")
//    terminal  every raw line: time, direction (< from ESP32, > to ESP32), text or hex;  filters, pause, clear, copy
//    input     type a line, choose the line ending, SEND  (Up / Down = history)
//    values    LIVE RAW VALUES: every KEY=VALUE pair that arrives (T=, B=, S=, HDG=, SPD=, LAT=, ...) with age
//
//  Without `serial` (dev PC, C++ build) it shows a clearly marked demo feed so the look can still be tuned.
// ============================================================================================================
Item {
    id: t

    property real sf: 1.0
    property real lm: 0.0
    property color accent: "#00f0ff"
    property var serial: null
    property bool active: false

    readonly property bool have: serial !== null
    readonly property bool demo: !have
    readonly property string st: have ? serial.status : (demoConnected ? "lora" : "disconnected")
    readonly property bool connected: st !== "disconnected"
    property bool demoConnected: true

    function px(v) { return Math.round(v * sf); }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }

    // ------------------------------------------------------------------ palette (night -> day)
    readonly property color cOk: "#34d399"
    readonly property color cWarn: "#fbbf24"
    readonly property color cFail: "#ff5468"
    readonly property color tText: mixc("#e9f0f8", "#1d2733")
    readonly property color tMuted: mixc("#8d9db2", "#5d6b7d")
    readonly property color lineCol: mixc(Qt.rgba(0.68, 0.78, 0.90, 0.16), Qt.rgba(0.1, 0.2, 0.35, 0.16))
    readonly property color panelCol: mixc(Qt.rgba(0.04, 0.06, 0.09, 0.85), Qt.rgba(0.97, 0.98, 0.99, 0.92))
    readonly property color fieldCol: mixc(Qt.rgba(0.02, 0.03, 0.05, 0.9), Qt.rgba(1, 1, 1, 0.95))
    readonly property string monoFamily: Qt.platform.os === "windows" ? "Consolas" : (Qt.platform.os === "osx" ? "Menlo" : "DejaVu Sans Mono")

    function kindColor(kind, dir) {
        if (dir === "sys") return kind === "warning" ? cWarn : tMuted;
        if (dir === "out") return mixc("#5ee7ff", "#0a7f9c");
        if (kind === "heartbeat") return mixc("#7d8ea3", "#6b7a8c");
        if (kind === "ack") return mixc("#6ee7b7", "#0b8f66");
        if (kind === "key") return mixc("#5ee7ff", "#0a7f9c");
        if (kind === "btn") return mixc("#c4b5fd", "#6d4fd1");
        if (kind === "warning") return mixc("#ffb86b", "#b45309");
        if (kind === "partial") return mixc("#fbbf24", "#b0780a");
        return tText;
    }

    // ------------------------------------------------------------------ log model
    ListModel { id: logModel }
    readonly property int maxLines: 1500
    property int rxLines: 0
    property bool autoScroll: true
    property bool showHex: false
    property bool showTime: true
    property bool hideHb: false

    function addLine(ts, dir, text, hex, kind) {
        if (kind === "clear") { logModel.clear(); rxLines = 0; return; }
        logModel.append({ ts: ts, dir: dir, text: text, hex: hex, kind: kind });
        if (dir === "in") rxLines++;
        if (logModel.count > maxLines) logModel.remove(0, 300);
    }

    Connections {
        target: t.serial
        ignoreUnknownSignals: true
        function onTerminalLine(ts, dir, text, hex, kind) { t.addLine(ts, dir, text, hex, kind); }
        function onRawValuesChanged() { t.syncValues(t.serial.rawValues); }
        function onStatusChanged() { }
    }

    // ------------------------------------------------------------------ live values model (updated by key, delegates stay)
    ListModel { id: valModel }
    function syncValues(list) {
        if (!list) return;
        var idx = {};
        for (var i = 0; i < valModel.count; ++i) idx[valModel.get(i).k] = i;
        for (var j = 0; j < list.length; ++j) {
            var it = list[j];
            if (idx[it.k] === undefined) valModel.append({ k: it.k, v: String(it.v), src: it.src, age: it.age, hits: it.hits });
            else valModel.set(idx[it.k], { k: it.k, v: String(it.v), src: it.src, age: it.age, hits: it.hits });
        }
        if (list.length === 0 && valModel.count > 0) valModel.clear();
    }

    // ------------------------------------------------------------------ demo feed (no backend)
    property int demoN: 0
    Timer {
        interval: 700; running: t.demo && t.active; repeat: true
        onTriggered: {
            t.demoN++;
            var n = t.demoN;
            var ts = Qt.formatTime(new Date(), "hh:mm:ss") + ".000";
            if (n === 1) { t.addLine(ts, "sys", "Connected to COM3 (115200 baud, 8N1).  [DEMO - no loraBridge]", "", "info"); }
            t.addLine(ts, "in", "RX <- HB:STM:VS=1,HDG=" + (84 + n % 5) + ",SPD=" + (6 + (n % 4) * 0.5).toFixed(1) + ",FIX=3,LAT=12451754,LON=76552337,WP=2/5,CML=98,CAM=1/2,OBS=0", "", "heartbeat");
            if (n % 3 === 0) t.addLine(ts, "in", "STM_ACK:" + (276000 + n) + ":T=" + (4 + n % 7).toFixed(1) + ",B=3.5,S=" + (48 + n % 5).toFixed(1), "", "ack");
            if (n % 5 === 0) t.addLine(ts, "out", "KEYS:U1D0L0R0S0", "", "key");
            t.syncValues([
                { k: "VS", v: "1", src: "HB:STM", age: 0.2, hits: n }, { k: "HDG", v: String(84 + n % 5), src: "HB:STM", age: 0.2, hits: n },
                { k: "SPD", v: (6 + (n % 4) * 0.5).toFixed(1), src: "HB:STM", age: 0.2, hits: n }, { k: "FIX", v: "3", src: "HB:STM", age: 0.2, hits: n },
                { k: "LAT", v: "12451754", src: "HB:STM", age: 0.2, hits: n }, { k: "LON", v: "76552337", src: "HB:STM", age: 0.2, hits: n },
                { k: "T", v: (4 + n % 7).toFixed(1), src: "STM_ACK", age: (n % 3) * 0.7, hits: n }, { k: "B", v: "3.5", src: "STM_ACK", age: (n % 3) * 0.7, hits: n },
                { k: "S", v: (48 + n % 5).toFixed(1), src: "STM_ACK", age: (n % 3) * 0.7, hits: n }
            ]);
        }
    }

    // ------------------------------------------------------------------ port / baud selection
    property string selPort: ""
    property int selBaud: 115200
    readonly property var portList: have ? serial.ports : [ { name: "COM3", description: "Silicon Labs CP210x (demo)", likely: true }, { name: "COM7", description: "USB Serial Device (demo)", likely: false } ]
    readonly property var baudList: have ? serial.baudRates : [9600, 19200, 38400, 57600, 74880, 115200, 230400, 460800, 921600]

    function pickDefaultPort() {
        if (selPort !== "") {
            var ok = false;
            for (var i = 0; i < portList.length; ++i) if (portList[i].name === selPort) ok = true;
            if (ok) return;
        }
        var want = have ? (serial.portName || serial.pinnedPort) : "COM3";
        for (var k = 0; k < portList.length; ++k) if (portList[k].name === want) { selPort = want; return; }
        for (var m = 0; m < portList.length; ++m) if (portList[m].likely) { selPort = portList[m].name; return; }
        selPort = portList.length > 0 ? portList[0].name : "";
    }
    onPortListChanged: pickDefaultPort()
    onActiveChanged: if (active) { if (have) serial.refreshPorts(); pickDefaultPort(); if (have) selBaud = serial.baudRate; }
    Component.onCompleted: { pickDefaultPort(); if (have) selBaud = serial.baudRate; }
    Timer { interval: 2000; running: t.active && t.have; repeat: true; onTriggered: t.serial.refreshPorts() }

    function connectToggle() {
        if (!have) { demoConnected = !demoConnected; return; }
        if (serial.usbConnected) serial.disconnectPort();
        else if (selPort !== "") serial.connectPortBaud(selPort, selBaud);
    }
    function sendLine() {
        var s = input.text;
        if (!have) { addLine(Qt.formatTime(new Date(), "hh:mm:ss") + ".000", "out", s, "", "terminal"); }
        else if (!serial.sendText(s, endings[endIdx].id)) return;
        if (s.length > 0 && (history.length === 0 || history[history.length - 1] !== s)) history.push(s);
        histPos = history.length;
        input.text = "";
    }
    property var history: []
    property int histPos: 0
    readonly property var endings: [ { id: "nl", t: "NEWLINE" }, { id: "crlf", t: "CR + NL" }, { id: "cr", t: "CR" }, { id: "none", t: "NO ENDING" } ]
    property int endIdx: 0

    function copyAll() {
        var s = "";
        for (var i = 0; i < logModel.count; ++i) {
            var r = logModel.get(i);
            s += r.ts + (r.dir === "in" ? "  <  " : r.dir === "out" ? "  >  " : "  *  ") + r.text + "\n";
        }
        clip.text = s; clip.selectAll(); clip.copy(); clip.deselect();
        copiedFlash.restart();
    }
    TextEdit { id: clip; visible: false }
    Timer { id: copiedFlash; interval: 1200 }

    // ================================================================ visuals
    readonly property real gap: px(14)
    readonly property real rightW: Math.max(px(380), width * 0.30)

    // ---------------------------------------------------------------- left: toolbar + status + terminal + input
    Item {
        id: leftCol
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.right: valuesCol.left; anchors.rightMargin: t.gap

        // ---- toolbar
        Row {
            id: bar
            anchors.top: parent.top; anchors.left: parent.left
            spacing: t.px(10)
            height: t.px(40)
            z: 20

            Dropdown {
                id: portDd
                width: t.px(330); label: "PORT"
                valueText: t.selPort === "" ? "no ports found" : t.selPort + (function() {
                    for (var i = 0; i < t.portList.length; ++i) if (t.portList[i].name === t.selPort) return "   " + t.portList[i].description;
                    return "";
                })()
                items: t.portList.map(function(p) { return { id: p.name, text: p.name + "   " + p.description + (p.likely ? "   (ESP32 chip)" : "") }; })
                onPicked: function(id) { t.selPort = id; if (t.have && t.serial.usbConnected && id !== t.serial.portName) t.serial.connectPortBaud(id, t.selBaud); }
            }
            Dropdown {
                id: baudDd
                width: t.px(150); label: "BAUD"
                valueText: String(t.selBaud)
                items: t.baudList.map(function(b) { return { id: String(b), text: String(b) + (b === 115200 ? "   (default)" : "") }; })
                onPicked: function(id) { t.selBaud = parseInt(id); if (t.have) t.serial.baudRate = t.selBaud; }
            }
            PillButton {
                text: t.connected ? "DISCONNECT" : "CONNECT"
                tone: t.connected ? "fail" : "accent"
                width: t.px(140)
                onClicked: t.connectToggle()
            }
            PillButton {
                text: "RESET ESP32"
                tone: "warn"
                width: t.px(140)
                enabled: t.connected
                onClicked: { if (t.have) t.serial.resetEsp32(); }
            }
        }

        // ---- status strip
        Rectangle {
            id: stat
            anchors.top: bar.bottom; anchors.topMargin: t.px(10)
            anchors.left: parent.left; anchors.right: parent.right
            height: t.px(40); radius: t.px(10)
            readonly property color sc: t.st === "lora" ? t.cOk : t.st === "usb" ? t.cWarn : t.cFail
            color: Qt.rgba(sc.r, sc.g, sc.b, 0.10)
            border.width: 1; border.color: Qt.rgba(sc.r, sc.g, sc.b, 0.45)
            Rectangle { x: t.px(14); anchors.verticalCenter: parent.verticalCenter; width: t.px(10); height: width; radius: width / 2; color: stat.sc
                SequentialAnimation on opacity { running: t.st === "lora" && t.active; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 800 } NumberAnimation { to: 1.0; duration: 800 } } }
            Text {
                id: statTxt
                x: t.px(36); anchors.verticalCenter: parent.verticalCenter
                text: t.st === "lora" ? "LORA LINKED" : t.st === "usb" ? "USB CONNECTED  -  NO LORA LINK" : "NOT CONNECTED"
                color: stat.sc; font.pixelSize: t.px(12); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif"
            }
            Text {
                anchors.left: statTxt.right; anchors.leftMargin: t.px(16)
                anchors.right: parent.right; anchors.rightMargin: t.px(14)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                color: t.tMuted; font.pixelSize: t.px(11); font.family: "Segoe UI, Inter, sans-serif"
                text: {
                    if (!t.have) return "DEMO FEED - no loraBridge in this build";
                    var p = [];
                    if (t.serial.usbConnected) {
                        p.push(t.serial.portName + " @ " + t.serial.baudRate);
                        p.push("RX " + t.serial.rxBytes + " B  (" + Math.round(t.serial.rxRate) + " B/s)");
                        p.push("TX " + t.serial.txBytes + " B");
                        var a = t.serial.lastRxAge;
                        p.push(a < 0 ? "nothing received yet" : "last byte " + (a < 10 ? a.toFixed(1) : Math.round(a)) + " s ago");
                    } else if (t.serial.error.length) p.push(t.serial.error);
                    else p.push("select a port and press CONNECT");
                    if (t.serial.usbConnected && t.serial.error.length) p.push(t.serial.error);
                    return p.join("    -    ");
                }
            }
        }
        Text {   // busy / error line under the status strip, only when disconnected with an error
            id: errLine
            anchors.top: stat.bottom; anchors.topMargin: t.px(4)
            anchors.left: parent.left; anchors.right: parent.right
            visible: t.have && !t.serial.usbConnected && t.serial.error.length > 0
            height: visible ? contentHeight : 0
            wrapMode: Text.WordWrap
            text: t.have ? t.serial.error : ""
            color: t.cWarn; font.pixelSize: t.px(12); font.family: "Segoe UI, Inter, sans-serif"
        }

        // ---- terminal head (filters)
        Item {
            id: tHead
            anchors.top: errLine.bottom; anchors.topMargin: t.px(8)
            anchors.left: parent.left; anchors.right: parent.right
            height: t.px(30)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "RAW TERMINAL"; color: t.tText; font.pixelSize: t.px(12); font.bold: true; font.letterSpacing: 1.6; font.family: "Segoe UI, Inter, sans-serif" }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: t.px(8)
                Chip { text: "AUTOSCROLL"; on: t.autoScroll; onClicked: t.autoScroll = !t.autoScroll }
                Chip { text: "HEX";        on: t.showHex;    onClicked: t.showHex = !t.showHex }
                Chip { text: "TIME";       on: t.showTime;   onClicked: t.showTime = !t.showTime }
                Chip { text: "HIDE HEARTBEAT"; on: t.hideHb; onClicked: t.hideHb = !t.hideHb }
                Chip { text: copiedFlash.running ? "COPIED" : "COPY"; on: copiedFlash.running; onClicked: t.copyAll() }
                Chip { text: "CLEAR"; on: false; onClicked: { logModel.clear(); t.rxLines = 0; } }
            }
        }

        // ---- input row (bottom)
        Item {
            id: inRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: t.px(44)
            Rectangle {
                id: inBox
                anchors.left: parent.left; anchors.right: endBtn.left; anchors.rightMargin: t.px(8)
                anchors.verticalCenter: parent.verticalCenter
                height: t.px(40); radius: t.px(10)
                color: t.fieldCol
                border.width: 1; border.color: input.activeFocus ? t.accent : t.lineCol
                Text { x: t.px(14); anchors.verticalCenter: parent.verticalCenter; text: ">"; color: t.accent; font.pixelSize: t.px(15); font.bold: true; font.family: t.monoFamily }
                TextInput {
                    id: input
                    anchors.left: parent.left; anchors.leftMargin: t.px(34); anchors.right: parent.right; anchors.rightMargin: t.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    color: t.tText; font.pixelSize: t.px(14); font.family: t.monoFamily
                    clip: true; selectByMouse: true
                    enabled: t.connected
                    selectionColor: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.4)
                    onAccepted: t.sendLine()
                    Keys.onUpPressed: { if (t.history.length) { t.histPos = Math.max(0, t.histPos - 1); text = t.history[t.histPos]; } }
                    Keys.onDownPressed: { if (t.histPos < t.history.length - 1) { t.histPos++; text = t.history[t.histPos]; } else { t.histPos = t.history.length; text = ""; } }
                    Text { visible: !input.text.length; anchors.verticalCenter: parent.verticalCenter
                           text: t.connected ? "type a line to send to the ESP32 and press Enter   (Up / Down = history)" : "connect first"
                           color: t.tMuted; font.pixelSize: t.px(13); font.family: "Segoe UI, Inter, sans-serif" }
                }
            }
            PillButton {
                id: endBtn
                anchors.right: sendBtn.left; anchors.rightMargin: t.px(8); anchors.verticalCenter: parent.verticalCenter
                width: t.px(128); text: t.endings[t.endIdx].t; tone: "muted"
                onClicked: t.endIdx = (t.endIdx + 1) % t.endings.length
            }
            PillButton {
                id: sendBtn
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: t.px(100); text: "SEND"; tone: "accent"; enabled: t.connected
                onClicked: t.sendLine()
            }
        }

        // ---- terminal
        Rectangle {
            id: term
            anchors.top: tHead.bottom; anchors.topMargin: t.px(6)
            anchors.bottom: inRow.top; anchors.bottomMargin: t.px(8)
            anchors.left: parent.left; anchors.right: parent.right
            radius: t.px(12); color: t.panelCol
            border.width: 1; border.color: t.lineCol
            clip: true

            ListView {
                id: lv
                anchors.fill: parent; anchors.margins: t.px(10)
                model: logModel
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                onCountChanged: if (t.autoScroll) Qt.callLater(function() { lv.positionViewAtEnd(); })
                onMovingChanged: if (moving && !atYEnd) t.autoScroll = false
                delegate: Item {
                    width: lv.width
                    readonly property bool hidden: t.hideHb && model.kind === "heartbeat"
                    height: hidden ? 0 : Math.max(t.px(18), lineTxt.implicitHeight + t.px(2))
                    visible: !hidden
                    Text {
                        id: tsTxt
                        visible: t.showTime
                        x: 0; y: t.px(1); width: t.showTime ? t.px(98) : 0
                        text: model.ts; color: t.tMuted; opacity: 0.8
                        font.pixelSize: t.px(12); font.family: t.monoFamily
                    }
                    Text {
                        id: dirTxt
                        x: t.showTime ? t.px(100) : 0; y: t.px(1); width: t.px(18)
                        text: model.dir === "in" ? "<" : model.dir === "out" ? ">" : "*"
                        color: t.kindColor(model.kind, model.dir); font.bold: true
                        font.pixelSize: t.px(12); font.family: t.monoFamily
                    }
                    Text {
                        id: lineTxt
                        x: dirTxt.x + t.px(20); y: t.px(1)
                        width: parent.width - x
                        text: t.showHex ? model.hex : model.text
                        wrapMode: Text.WrapAnywhere
                        color: t.kindColor(model.kind, model.dir)
                        font.pixelSize: t.px(13); font.family: t.monoFamily
                        font.italic: model.dir === "sys"
                    }
                }
                Text {
                    anchors.centerIn: parent; visible: logModel.count === 0
                    text: t.connected ? "waiting for data from the ESP32 ..." : "not connected"
                    color: t.tMuted; font.pixelSize: t.px(14); font.family: "Segoe UI, Inter, sans-serif"
                }
            }
            Rectangle {      // jump to the end (shown when scrolled up)
                visible: !t.autoScroll && logModel.count > 0
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: t.px(14)
                width: t.px(120); height: t.px(30); radius: height / 2
                color: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.20); border.color: t.accent; border.width: 1
                Text { anchors.centerIn: parent; text: "LATEST"; color: t.accent; font.pixelSize: t.px(11); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
                MouseArea { anchors.fill: parent; onClicked: { t.autoScroll = true; lv.positionViewAtEnd(); } }
            }
        }
    }

    // ---------------------------------------------------------------- right: live raw values
    Rectangle {
        id: valuesCol
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: t.rightW
        radius: t.px(14); color: t.panelCol
        border.width: 1; border.color: t.lineCol

        Item {
            id: vHead
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: t.px(16); height: t.px(30)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "LIVE RAW VALUES"; color: t.tText; font.pixelSize: t.px(13); font.bold: true; font.letterSpacing: 1.6; font.family: "Segoe UI, Inter, sans-serif" }
            Chip { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "CLEAR"; on: false
                   onClicked: { valModel.clear(); if (t.have) t.serial.clearValues(); } }
        }
        Text {
            id: vSub
            anchors.top: vHead.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: t.px(16); anchors.rightMargin: t.px(16)
            wrapMode: Text.WordWrap
            text: "Every KEY=VALUE pair found in the incoming lines, exactly as received."
            color: t.tMuted; font.pixelSize: t.px(11); font.family: "Segoe UI, Inter, sans-serif"
        }
        Row {
            id: vCols
            anchors.top: vSub.bottom; anchors.topMargin: t.px(10)
            anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: t.px(16); anchors.rightMargin: t.px(16)
            height: t.px(20)
            readonly property real w: width
            Text { width: vCols.w * 0.22; text: "KEY";   color: t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
            Text { width: vCols.w * 0.34; text: "VALUE"; color: t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
            Text { width: vCols.w * 0.28; text: "FROM";  color: t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
            Text { width: vCols.w * 0.16; text: "AGE";   color: t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1.2; horizontalAlignment: Text.AlignRight; font.family: "Segoe UI, Inter, sans-serif" }
        }
        Rectangle { id: vLine; anchors.top: vCols.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: t.px(16); anchors.rightMargin: t.px(16); height: 1; color: t.lineCol }

        ListView {
            id: vlv
            anchors.top: vLine.bottom; anchors.topMargin: t.px(4)
            anchors.bottom: parent.bottom; anchors.bottomMargin: t.px(12)
            anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: t.px(16); anchors.rightMargin: t.px(16)
            model: valModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                width: vlv.width; height: t.px(27)
                readonly property real age: model.age
                readonly property color ac: age < 2.5 ? t.cOk : age < 8 ? t.cWarn : t.cFail
                Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: t.px(6)
                            color: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, age < 0.6 ? 0.18 : 0.0)
                            Behavior on color { ColorAnimation { duration: 260 } } }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: vlv.width * 0.22; text: model.k; color: t.accent; font.pixelSize: t.px(13); font.bold: true; font.family: t.monoFamily; elide: Text.ElideRight }
                    Text { width: vlv.width * 0.34; text: model.v; color: t.tText; font.pixelSize: t.px(13); font.family: t.monoFamily; elide: Text.ElideRight }
                    Text { width: vlv.width * 0.28; text: model.src; color: t.tMuted; font.pixelSize: t.px(11); font.family: t.monoFamily; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: vlv.width * 0.16; text: (age < 10 ? age.toFixed(1) : Math.round(age)) + "s"; color: ac; font.pixelSize: t.px(11); font.family: t.monoFamily; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Text {
                anchors.centerIn: parent; visible: valModel.count === 0; width: parent.width * 0.9
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: t.connected ? "no KEY=VALUE data received yet" : "connect to see live values"
                color: t.tMuted; font.pixelSize: t.px(12); font.family: "Segoe UI, Inter, sans-serif"
            }
        }
    }

    // ================================================================ small components
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool on: false
        signal clicked()
        width: chipTxt.implicitWidth + t.px(20); height: t.px(26); radius: height / 2
        color: on ? Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.20) : (cm.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
        border.width: 1; border.color: on ? t.accent : t.lineCol
        Text { id: chipTxt; anchors.centerIn: parent; text: chip.text; color: chip.on ? t.accent : t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1; font.family: "Segoe UI, Inter, sans-serif" }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    component PillButton: Rectangle {
        id: pb
        property string text: ""
        property string tone: "accent"                 // accent | warn | fail | muted
        signal clicked()
        readonly property color tc: tone === "fail" ? t.cFail : tone === "warn" ? t.cWarn : tone === "muted" ? t.tMuted : t.accent
        height: t.px(38); radius: height / 2
        opacity: enabled ? 1.0 : 0.4
        color: pm.pressed ? Qt.rgba(tc.r, tc.g, tc.b, 0.32) : Qt.rgba(tc.r, tc.g, tc.b, pm.containsMouse ? 0.22 : 0.13)
        border.width: 1.2; border.color: tc
        Text { anchors.centerIn: parent; text: pb.text; color: pb.tc; font.pixelSize: t.px(11); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; enabled: pb.enabled; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    component Dropdown: Item {
        id: dd
        property string label: ""
        property string valueText: ""
        property var items: []                         // [{id, text}]
        property bool opened: false
        signal picked(string id)
        height: t.px(40)
        Rectangle {
            anchors.fill: parent; radius: t.px(10)
            color: t.fieldCol
            border.width: 1; border.color: dd.opened ? t.accent : t.lineCol
            Text { x: t.px(12); anchors.verticalCenter: parent.verticalCenter; text: dd.label; color: t.tMuted; font.pixelSize: t.px(10); font.bold: true; font.letterSpacing: 1.2; font.family: "Segoe UI, Inter, sans-serif" }
            Text {
                x: t.px(58); anchors.verticalCenter: parent.verticalCenter; width: parent.width - t.px(86)
                text: dd.valueText; elide: Text.ElideRight; color: t.tText; font.pixelSize: t.px(12); font.family: t.monoFamily
            }
            Text { anchors.right: parent.right; anchors.rightMargin: t.px(12); anchors.verticalCenter: parent.verticalCenter; text: dd.opened ? "▴" : "▾"; color: t.tMuted; font.pixelSize: t.px(12) }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dd.opened = !dd.opened }
        }
        Rectangle {
            visible: dd.opened
            y: dd.height + t.px(4); width: Math.max(dd.width, t.px(300)); z: 100
            height: Math.min(t.px(240), ddList.contentHeight + t.px(8)); radius: t.px(10)
            color: t.mixc("#121a26", "#ffffff"); border.width: 1; border.color: t.accent
            ListView {
                id: ddList
                anchors.fill: parent; anchors.margins: t.px(4); clip: true
                model: dd.items
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    width: ddList.width; height: t.px(32); radius: t.px(7)
                    color: dm.containsMouse ? Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.18) : "transparent"
                    Text { x: t.px(10); anchors.verticalCenter: parent.verticalCenter; width: parent.width - t.px(20); elide: Text.ElideRight
                           text: modelData.text; color: t.tText; font.pixelSize: t.px(12); font.family: t.monoFamily }
                    MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: { dd.opened = false; dd.picked(modelData.id); } }
                }
                Text { anchors.centerIn: parent; visible: dd.items.length === 0; text: "nothing found"; color: t.tMuted; font.pixelSize: t.px(12) }
            }
        }
    }
}
