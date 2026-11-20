import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// ============================================================================================================
//  ConnectionsPanel.qml  -  "SYSTEM CONNECTIONS": every link of the boat in one pop-up, with a live health check.
//
//  Opened by the gear button in the bottom dock (Main.qml: settingsViewOpen).  Data comes from the Python
//  object `linkMonitor` (link_monitor.py).  Without it the panel shows clearly-marked DEMO data, so the look
//  can be tuned on a dev PC.
//
//  Each check the monitor sends is a map:
//      id      unique string                      group   one of the groupDefs below
//      name    "Telemetry downlink"               detail  one line, e.g. "UDP :9001 - 20 pkt/s - age 0.04 s"
//      status  ok | warn | fail | checking | na   chip    optional text for the status chip (LIVE, SIM, ...)
//      metric  optional short value at the right  note    optional longer text, shown when the row is tapped
//      tile    true = small tile (devices on the marine LAN), false = full row
// ============================================================================================================
Item {
    id: root

    property bool open: false
    property real sf: 1.0
    property real lm: 0.0                          // 0 night .. 1 day  (same number as appWindow.lm)
    property color accent: "#00f0ff"
    property var monitor: null                     // linkMonitor, or null -> demo data
    property var serial: (typeof loraBridge !== "undefined") ? loraBridge : null     // lora_bridge.py (SERIAL TERMINAL tab)
    property int tab: 0                            // 0 = CONNECTIONS (health checks), 1 = SERIAL TERMINAL
    signal closeRequested()

    // While the terminal tab is on screen, Up / Down / Space / 1-4 must never reach the boat (somebody is only scrolling the log)
    Binding { target: root.serial; property: "motorEnabled"; value: false; when: root.serial !== null && root.open && root.tab === 1 }

    opacity: open ? 1.0 : 0.0                      // closed = fully invisible and no longer takes clicks
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    readonly property bool demo: monitor === null
    readonly property bool busy: demo ? demoBusy : (monitor && monitor.running === true)
    property bool demoBusy: false
    property int tick: 0                           // bumps on every data refresh (bindings that read the models depend on it)
    property string updatedText: "-"

    function px(v) { return Math.round(v * sf); }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }

    // ---------------------------------------------------------------- palette
    readonly property color cOk: "#34d399"
    readonly property color cWarn: "#fbbf24"
    readonly property color cFail: "#ff5468"
    readonly property color cNa: "#7a8797"
    readonly property color tText: "#e9f0f8"
    readonly property color tMuted: "#8d9db2"
    readonly property color line: Qt.rgba(0.68, 0.78, 0.90, 0.16)

    function statusColor(s) {
        return s === "ok" ? cOk : s === "warn" ? cWarn : s === "fail" ? cFail : s === "checking" ? accent : cNa;
    }
    function statusRank(s) { return s === "fail" ? 4 : s === "warn" ? 3 : s === "checking" ? 2 : s === "ok" ? 1 : 0; }
    function chipText(s, c) {
        if (c && c.length) return c;
        return s === "ok" ? "OK" : s === "warn" ? "WARN" : s === "fail" ? "FAULT" : s === "checking" ? "CHECKING" : "N/A";
    }

    // ---------------------------------------------------------------- groups (static layout, 3 columns)
    readonly property var groupDefs: [
        { gid: "vessel",  title: "VESSEL LINKS",    sub: "GCS and boat",              col: 0 },
        { gid: "video",   title: "VIDEO",           sub: "FPV camera stream",         col: 0 },
        { gid: "onboard", title: "ONBOARD SYSTEMS", sub: "Jetson, CAN bus, sensors",  col: 1 },
        { gid: "nav",     title: "NAVIGATION",      sub: "GNSS position source",      col: 1 },
        { gid: "maps",    title: "OFFLINE MAPS",    sub: "mission map packs",         col: 2 },
        { gid: "lan",     title: "MARINE LAN",      sub: "192.168.1.0/24 devices",    col: 2 }
    ]
    ListModel { id: m_vessel }
    ListModel { id: m_video }
    ListModel { id: m_onboard }
    ListModel { id: m_nav }
    ListModel { id: m_maps }
    ListModel { id: m_lan }
    function modelFor(gid) {
        return gid === "vessel" ? m_vessel : gid === "video" ? m_video : gid === "onboard" ? m_onboard
             : gid === "nav" ? m_nav : gid === "maps" ? m_maps : m_lan;
    }
    function allModels() { return [m_vessel, m_video, m_onboard, m_nav, m_maps, m_lan]; }

    function s(v, d) { return (v === undefined || v === null) ? d : String(v); }

    // push a list of checks into the models (rows keep their identity -> no flicker, expanded state survives)
    function applyChecks(list) {
        if (!list) return;
        for (var i = 0; i < list.length; ++i) {
            var c = list[i];
            var m = modelFor(c.group);
            var row = {
                cid: s(c.id, ""), name: s(c.name, ""), detail: s(c.detail, ""), status: s(c.status, "na"),
                chip: s(c.chip, ""), metric: s(c.metric, ""), note: s(c.note, ""), tile: c.tile === true
            };
            var idx = -1;
            for (var k = 0; k < m.count; ++k) { if (m.get(k).cid === row.cid) { idx = k; break; } }
            if (idx < 0) { row.expanded = false; m.append(row); }
            else {
                var cur = m.get(idx);
                if (cur.name !== row.name) m.setProperty(idx, "name", row.name);
                if (cur.detail !== row.detail) m.setProperty(idx, "detail", row.detail);
                if (cur.status !== row.status) m.setProperty(idx, "status", row.status);
                if (cur.chip !== row.chip) m.setProperty(idx, "chip", row.chip);
                if (cur.metric !== row.metric) m.setProperty(idx, "metric", row.metric);
                if (cur.note !== row.note) m.setProperty(idx, "note", row.note);
            }
        }
        updatedText = Qt.formatTime(new Date(), "hh:mm:ss");
        tick++;
    }

    function counts() {
        var r = { ok: 0, warn: 0, fail: 0, checking: 0, na: 0, total: 0, firstFail: "", firstFailChip: "", firstWarn: "" };
        var ms = allModels();
        for (var a = 0; a < ms.length; ++a)
            for (var i = 0; i < ms[a].count; ++i) {
                var it = ms[a].get(i);
                r[it.status] = (r[it.status] || 0) + 1; r.total++;
                if (it.status === "fail" && r.firstFail === "") { r.firstFail = it.name + ": " + it.detail; r.firstFailChip = it.chip; }
                if (it.status === "warn" && r.firstWarn === "") r.firstWarn = it.name + ": " + it.detail;
            }
        return r;
    }
    function groupWorst(gid) {
        var m = modelFor(gid), w = "na", n = 0, okc = 0;
        for (var i = 0; i < m.count; ++i) {
            var st = m.get(i).status;
            if (statusRank(st) > statusRank(w)) w = st;
            n++; if (st === "ok") okc++;
        }
        return { worst: w, n: n, ok: okc };
    }

    readonly property var sum: { root.tick; return counts(); }
    readonly property string bannerState: sum.total === 0 ? "na" : sum.fail > 0 ? "fail" : sum.warn > 0 ? "warn" : sum.checking > 0 ? "checking" : sum.ok > 0 ? "ok" : "na"
    readonly property string bannerTitle: {
        if (sum.total === 0) return "NO DATA YET";
        if (sum.fail > 0) return sum.firstFailChip === "SIM" ? "NOT LIVE  -  VALUES ON SCREEN ARE SIMULATED" : (sum.fail === 1 ? "1 FAULT NEEDS ATTENTION" : sum.fail + " FAULTS NEED ATTENTION");
        if (sum.warn > 0) return sum.warn + (sum.warn === 1 ? " WARNING" : " WARNINGS");
        if (sum.checking > 0) return "CHECKING LINKS...";
        return "ALL LINKS HEALTHY";
    }
    readonly property string bannerSub: sum.fail > 0 ? sum.firstFail : sum.warn > 0 ? sum.firstWarn : (sum.ok + " of " + sum.total + " checks passed" + (sum.na > 0 ? "  -  " + sum.na + " not testable" : ""))

    // ---------------------------------------------------------------- data source
    Connections {
        target: root.monitor
        ignoreUnknownSignals: true
        function onChecksChanged() { if (root.monitor) root.applyChecks(root.monitor.checks); }
    }
    onMonitorChanged: if (monitor) applyChecks(monitor.checks)
    onOpenChanged: {
        if (monitor) {
            if (typeof monitor.setPanelOpen === "function") monitor.setPanelOpen(open);
            if (open) { applyChecks(monitor.checks); if (typeof monitor.runAll === "function") monitor.runAll(); }
        } else if (open) {
            if (m_vessel.count === 0) applyChecks(demoChecks());
            runDemo();
        }
    }
    Component.onCompleted: { if (!monitor) applyChecks(demoChecks()); else applyChecks(monitor.checks); }

    function runAll() {
        if (monitor) { if (typeof monitor.runAll === "function") monitor.runAll(); }
        else runDemo();
    }

    // ---------------------------------------------------------------- demo data (dev PC without backend)
    function demoChecks() {
        function c(id, g, name, detail, status, chip, metric, note, tile) {
            return { id: id, group: g, name: name, detail: detail, status: status, chip: chip || "", metric: metric || "", note: note || "", tile: tile === true };
        }
        return [
            c("tlm", "vessel", "Telemetry downlink", "UDP :9001  -  20 pkt/s  -  age 0.04 s  -  loss 0.0 %", "ok", "LIVE", "20 Hz", "Binary 77-byte frames (magic TNDV). Live while a packet arrived in the last second; otherwise the UI shows simulated values."),
            c("uplink", "vessel", "Command uplink", "UDP to 192.168.1.200:9000  -  no ack channel", "ok", "", "", "UDP has no acknowledgement. This only checks that the target is the same host the boat's telemetry comes from."),
            c("lora", "vessel", "LoRa 433 MHz (via STM32)", "link quality 99 %  -  mode AUTO  -  boat side timeout 10 s", "ok", "", "99 %", "The GCS has no LoRa radio. The STM32 reports its LoRa link quality inside telemetry. Heartbeat lost after 5 s, SAFE STOP after 10 s (boat side)."),
            c("autonomy", "vessel", "Jetson to STM32 guidance", "AUTONOMY_STATUS 1.0 Hz  -  age 0.3 s", "ok", "", "", ""),
            c("video", "video", "FPV video stream", "H.265 RTP UDP :5000  -  30 fps  -  1920x1080", "ok", "LIVE", "30 fps", "Frame rate measured on the video sink inside the UI."),
            c("jetson", "onboard", "Jetson autonomy node", "192.168.1.200  -  ping 2 ms", "ok", "", "2 ms", ""),
            c("can_eng", "onboard", "Engine ECU (CAN 0x200)", "RPM 3400  -  coolant 68 C  -  age 0.1 s", "ok", "", "", ""),
            c("can_bat", "onboard", "Battery BMS (CAN 0x300)", "13.8 V  -  age 0.4 s", "warn", "STALE", "", "Frame older than 2 s."),
            c("leak", "onboard", "Hull leak sensor", "bilge dry", "ok", "DRY", "", ""),
            c("gnss", "nav", "GNSS position", "3D fix  -  gpsd  -  12.45175 N  76.55234 E", "ok", "3D", "", ""),
            c("gpsd", "nav", "gpsd daemon", "127.0.0.1:2947  -  connect 1 ms", "ok", "", "1 ms", ""),
            c("gnss_dev", "nav", "GNSS receiver port", "/dev/ttyACM0 present", "ok", "", "", ""),
            c("mappack", "maps", "Offline map pack", "krs_region (z0-14)", "ok", "", "", ""),
            c("mapcov", "maps", "Coverage at vessel position", "inside pack  -  detail to z14", "ok", "", "", ""),
            c("nic", "lan", "GCS network adapter", "192.168.1.50 on eth0", "ok", "", "", ""),
            c("d_cam1", "lan", "Main IP camera", "192.168.1.205  -  RTSP 554  -  4 ms", "ok", "", "4 ms", "", true),
            c("d_cam2", "lan", "Wide-angle camera", "192.168.1.167  -  RTSP 554", "fail", "FAULT", "", "", true),
            c("d_sonar", "lan", "Oculus sonar", "192.168.1.201  -  ping 3 ms", "ok", "", "3 ms", "", true),
            c("d_bms", "lan", "Battery BMS", "192.168.1.208  -  ping 2 ms", "ok", "", "2 ms", "", true),
            c("d_gnss", "lan", "GNSS receiver", "192.168.1.215  -  ping 2 ms", "ok", "", "2 ms", "", true),
            c("d_mcu", "lan", "Hardware controller", "192.168.1.20  -  ping 2 ms", "ok", "", "2 ms", "", true),
            c("d_metal", "lan", "Metal detector", "192.168.1.62  -  no reply", "na", "", "", "", true),
            c("d_dec", "lan", "Video decoder", "192.168.1.27  -  ping 3 ms", "ok", "", "3 ms", "", true)
        ];
    }
    function runDemo() {
        demoBusy = true;
        var ms = allModels();
        for (var a = 0; a < ms.length; ++a) for (var i = 0; i < ms[a].count; ++i) ms[a].setProperty(i, "status", "checking");
        tick++;
        demoTimer.restart();
    }
    Timer { id: demoTimer; interval: 1100; onTriggered: { root.demoBusy = false; root.applyChecks(root.demoChecks()); } }
    // auto refresh of the real checks while the panel is open is done by the backend (setPanelOpen)

    // ================================================================ visuals
    // scrim (also swallows clicks and closes the panel)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.03, 0.06, 0.66)
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.closeRequested() }
    }

    Rectangle {
        id: card
        width: Math.min(root.width - root.px(48), root.px(1660))
        height: Math.min(root.height - root.px(36), root.px(900))
        anchors.centerIn: parent
        radius: root.px(20)
        scale: root.open ? 1.0 : 0.965
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.mixc("#151c28", "#1a1a19") }
            GradientStop { position: 1.0; color: root.mixc("#0c1119", "#0e0e0d") }
        }
        border.color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
        border.width: 1
        clip: true
        MouseArea { anchors.fill: parent }          // clicks inside the card must not reach the scrim

        // ------------------------------------------------------------ header
        Item {
            id: head
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: root.px(28); anchors.rightMargin: root.px(24)
            height: root.px(82)

            Row {                                        // signal-bars icon
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(3)
                Repeater {
                    model: 4
                    Rectangle {
                        width: root.px(5); height: root.px(8 + index * 6); radius: 1.5
                        anchors.bottom: parent.bottom
                        color: root.accent
                        opacity: 0.45 + index * 0.18
                    }
                }
            }
            Column {
                anchors.left: icon.right; anchors.leftMargin: root.px(16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(3)
                Text {
                    text: "SYSTEM CONNECTIONS"
                    color: root.tText; font.pixelSize: root.px(20); font.bold: true; font.letterSpacing: 2.2
                    font.family: "Segoe UI, Inter, sans-serif"
                }
                Row {
                    spacing: root.px(10)
                    Text {
                        text: "Updated " + root.updatedText + "   -   auto refresh while open"
                        color: root.tMuted; font.pixelSize: root.px(12)
                        font.family: "Segoe UI, Inter, sans-serif"
                    }
                    Rectangle {
                        visible: root.demo
                        width: demoTxt.implicitWidth + root.px(14); height: root.px(18); radius: height / 2
                        color: Qt.rgba(root.cWarn.r, root.cWarn.g, root.cWarn.b, 0.16)
                        border.color: Qt.rgba(root.cWarn.r, root.cWarn.g, root.cWarn.b, 0.7); border.width: 1
                        Text { id: demoTxt; anchors.centerIn: parent; text: "DEMO DATA  -  no backend connected"; color: root.cWarn; font.pixelSize: root.px(10); font.bold: true; font.letterSpacing: 0.8; font.family: "Segoe UI, Inter, sans-serif" }
                    }
                }
            }

            // tabs
            Row {
                id: tabs
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(4)
                Repeater {
                    model: [ { t: "CONNECTIONS" }, { t: "SERIAL TERMINAL" } ]
                    Rectangle {
                        readonly property bool on: root.tab === index
                        width: tabTxt.implicitWidth + root.px(36); height: root.px(36); radius: height / 2
                        color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        border.width: 1; border.color: on ? root.accent : root.line
                        Text { id: tabTxt; anchors.centerIn: parent; text: modelData.t; color: on ? root.accent : root.tMuted
                               font.pixelSize: root.px(11); font.bold: true; font.letterSpacing: 1.4; font.family: "Segoe UI, Inter, sans-serif" }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                    }
                }
            }

            // right side: counters, run button, close
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(14)

                Repeater {
                    model: root.tab === 0 ? [ { k: "ok", t: "OK" }, { k: "warn", t: "WARN" }, { k: "fail", t: "FAULT" } ] : []
                    Rectangle {
                        readonly property int n: { root.tick; return root.sum[modelData.k] || 0; }
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.px(78); height: root.px(34); radius: height / 2
                        color: Qt.rgba(root.statusColor(modelData.k).r, root.statusColor(modelData.k).g, root.statusColor(modelData.k).b, n > 0 ? 0.13 : 0.05)
                        border.color: Qt.rgba(root.statusColor(modelData.k).r, root.statusColor(modelData.k).g, root.statusColor(modelData.k).b, n > 0 ? 0.55 : 0.18)
                        border.width: 1
                        Row {
                            anchors.centerIn: parent; spacing: root.px(7)
                            Text { text: n; color: n > 0 ? root.statusColor(modelData.k) : root.tMuted; font.pixelSize: root.px(15); font.bold: true; font.family: "Segoe UI, Inter, sans-serif" }
                            Text { text: modelData.t; color: n > 0 ? root.statusColor(modelData.k) : root.tMuted; font.pixelSize: root.px(10); font.bold: true; font.letterSpacing: 1; anchors.baseline: parent.children[0].baseline; font.family: "Segoe UI, Inter, sans-serif" }
                        }
                    }
                }

                Rectangle {                                          // RUN ALL CHECKS
                    id: runBtn
                    visible: root.tab === 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.px(188); height: root.px(38); radius: height / 2
                    color: runMouse.pressed ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, runMouse.containsMouse ? 0.22 : 0.14)
                    border.color: root.accent; border.width: 1.2
                    Row {
                        anchors.centerIn: parent; spacing: root.px(9)
                        Item {
                            width: root.px(15); height: root.px(15); anchors.verticalCenter: parent.verticalCenter
                            Shape {
                                anchors.fill: parent
                                layer.enabled: false
                                ShapePath {
                                    strokeColor: root.accent; strokeWidth: root.px(2); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: root.px(7.5); centerY: root.px(7.5); radiusX: root.px(5.8); radiusY: root.px(5.8); startAngle: 20; sweepAngle: 290 }
                                }
                            }
                            RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.busy }
                        }
                        Text {
                            text: root.busy ? "CHECKING..." : "RUN ALL CHECKS"
                            color: root.accent; font.pixelSize: root.px(12); font.bold: true; font.letterSpacing: 1.3
                            font.family: "Segoe UI, Inter, sans-serif"
                        }
                    }
                    MouseArea { id: runMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!root.busy) root.runAll() }
                }

                Rectangle {                                          // close
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.px(38); height: root.px(38); radius: width / 2
                    color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(0.68, 0.78, 0.90, closeMouse.containsMouse ? 0.5 : 0.22); border.width: 1
                    Rectangle { anchors.centerIn: parent; width: root.px(15); height: 1.6; rotation: 45; color: root.tText; radius: 1 }
                    Rectangle { anchors.centerIn: parent; width: root.px(15); height: 1.6; rotation: -45; color: root.tText; radius: 1 }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
                }
            }
        }

        Rectangle { id: headLine; anchors.top: head.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: root.line }

        // ------------------------------------------------------------ SERIAL TERMINAL tab
        SerialTerminal {
            id: terminalTab
            visible: root.tab === 1
            active: root.open && root.tab === 1
            anchors.top: headLine.bottom; anchors.topMargin: root.px(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: root.px(20)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.px(28); anchors.rightMargin: root.px(28)
            sf: root.sf; lm: 0.0; accent: root.accent          // the card stays dark in day mode too -> terminal always uses the dark palette
            serial: root.serial
        }

        // ------------------------------------------------------------ banner (overall verdict)
        Rectangle {
            id: banner
            visible: root.tab === 0
            anchors.top: headLine.bottom; anchors.topMargin: root.px(16)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.px(28); anchors.rightMargin: root.px(28)
            height: root.px(58); radius: root.px(12)
            readonly property color bc: root.statusColor(root.bannerState)
            color: Qt.rgba(bc.r, bc.g, bc.b, 0.10)
            border.color: Qt.rgba(bc.r, bc.g, bc.b, 0.45); border.width: 1
            Behavior on color { ColorAnimation { duration: 250 } }

            Rectangle { x: 0; y: root.px(10); width: root.px(4); height: parent.height - root.px(20); radius: 2; color: banner.bc }
            Rectangle {                                                   // pulsing beacon
                id: beacon
                x: root.px(24); anchors.verticalCenter: parent.verticalCenter
                width: root.px(14); height: width; radius: width / 2; color: banner.bc
                Rectangle {
                    anchors.centerIn: parent; width: parent.width; height: width; radius: width / 2
                    color: "transparent"; border.color: banner.bc; border.width: 1.5
                    SequentialAnimation on scale { loops: Animation.Infinite; running: root.open
                        NumberAnimation { from: 1.0; to: 2.4; duration: 1300; easing.type: Easing.OutQuad } }
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: root.open
                        NumberAnimation { from: 0.8; to: 0.0; duration: 1300; easing.type: Easing.OutQuad } }
                }
            }
            Column {
                anchors.left: beacon.right; anchors.leftMargin: root.px(18)
                anchors.right: parent.right; anchors.rightMargin: root.px(18)
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(2)
                Text {
                    text: root.bannerTitle
                    color: banner.bc; font.pixelSize: root.px(15); font.bold: true; font.letterSpacing: 1.4
                    font.family: "Segoe UI, Inter, sans-serif"
                }
                Text {
                    width: parent.width
                    text: root.bannerSub
                    color: root.tMuted; font.pixelSize: root.px(12); elide: Text.ElideRight
                    font.family: "Segoe UI, Inter, sans-serif"
                }
            }
        }

        // ------------------------------------------------------------ body: 3 columns of group cards
        Flickable {
            id: flick
            visible: root.tab === 0
            anchors.top: banner.bottom; anchors.topMargin: root.px(16)
            anchors.bottom: foot.top; anchors.bottomMargin: root.px(8)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.px(28); anchors.rightMargin: root.px(28)
            contentWidth: width
            contentHeight: Math.max(c0.height, c1.height, c2.height) + root.px(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            readonly property real gap: root.px(16)
            readonly property real colW: (width - 2 * gap) / 3

            Column { id: c0; x: 0;                        width: flick.colW; spacing: flick.gap
                Repeater { model: root.groupDefs.filter(function(g) { return g.col === 0; }); GroupCard { g: modelData; width: flick.colW } } }
            Column { id: c1; x: flick.colW + flick.gap;   width: flick.colW; spacing: flick.gap
                Repeater { model: root.groupDefs.filter(function(g) { return g.col === 1; }); GroupCard { g: modelData; width: flick.colW } } }
            Column { id: c2; x: 2 * (flick.colW + flick.gap); width: flick.colW; spacing: flick.gap
                Repeater { model: root.groupDefs.filter(function(g) { return g.col === 2; }); GroupCard { g: modelData; width: flick.colW } } }
        }

        // ------------------------------------------------------------ footer legend
        Item {
            id: foot
            visible: root.tab === 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: root.px(28); anchors.rightMargin: root.px(28)
            height: root.px(38)
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: root.line }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(20)
                Repeater {
                    model: [ { k: "ok", t: "healthy" }, { k: "warn", t: "degraded / stale" }, { k: "fail", t: "down / not live" }, { k: "na", t: "cannot be tested from here" } ]
                    Row {
                        spacing: root.px(7)
                        Rectangle { width: root.px(9); height: width; radius: width / 2; color: root.statusColor(modelData.k); anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.t; color: root.tMuted; font.pixelSize: root.px(11); font.family: "Segoe UI, Inter, sans-serif" }
                    }
                }
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: "Tap a row for details   -   Esc closes"
                color: root.tMuted; font.pixelSize: root.px(11); font.family: "Segoe UI, Inter, sans-serif"
            }
        }
    }

    // ================================================================ one group card
    component GroupCard: Rectangle {
        id: grp
        property var g
        readonly property var gm: root.modelFor(g.gid)
        readonly property var info: { root.tick; return root.groupWorst(g.gid); }
        radius: root.px(14)
        height: gHead.height + gBody.height + root.px(14)
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.mixc("#1a222f", "#202020") }
            GradientStop { position: 1.0; color: root.mixc("#121822", "#161615") }
        }
        border.color: Qt.rgba(0.68, 0.78, 0.90, 0.14); border.width: 1

        Item {
            id: gHead
            width: parent.width; height: root.px(52)
            Rectangle {
                id: gDot
                x: root.px(18); anchors.verticalCenter: parent.verticalCenter
                width: root.px(10); height: width; radius: width / 2
                color: root.statusColor(grp.info.worst)
            }
            Column {
                anchors.left: gDot.right; anchors.leftMargin: root.px(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text { text: grp.g.title; color: root.tText; font.pixelSize: root.px(13); font.bold: true; font.letterSpacing: 1.8; font.family: "Segoe UI, Inter, sans-serif" }
                Text { text: grp.g.sub; color: root.tMuted; font.pixelSize: root.px(10.5); font.family: "Segoe UI, Inter, sans-serif" }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: root.px(18); anchors.verticalCenter: parent.verticalCenter
                text: grp.info.n > 0 ? (grp.info.ok + " / " + grp.info.n) : ""
                color: root.statusColor(grp.info.worst); font.pixelSize: root.px(12); font.bold: true; font.family: "Segoe UI, Inter, sans-serif"
            }
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: root.px(14); anchors.rightMargin: root.px(14); height: 1; color: root.line }
        }

        Column {
            id: gBody
            anchors.top: gHead.bottom
            width: parent.width
            // full rows
            Column {
                width: parent.width
                Repeater {
                    model: grp.gm
                    delegate: CheckRow { visible: !model.tile; width: grp.width }
                }
            }
            // small device tiles, two per line
            Flow {
                id: tiles
                x: root.px(10); width: parent.width - root.px(20)
                spacing: root.px(8)
                topPadding: root.px(8); bottomPadding: root.px(4)
                readonly property real tw: (width - spacing) / 2
                Repeater {
                    model: grp.gm
                    delegate: DeviceTile { visible: model.tile; width: tiles.tw }
                }
            }
        }
    }

    // ================================================================ a full row
    component CheckRow: Item {
        id: row
        readonly property color sc: root.statusColor(model.status)
        height: rowTop.height + (model.expanded && model.note !== "" ? noteText.implicitHeight + root.px(14) : 0)
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        clip: true

        Rectangle { anchors.fill: parent; color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.035) : "transparent" }
        Item {
            id: rowTop
            width: parent.width; height: root.px(56)

            Item {                                                         // status dot (rings while checking)
                id: dotBox
                x: root.px(18); anchors.verticalCenter: parent.verticalCenter
                width: root.px(12); height: width
                Rectangle { anchors.fill: parent; radius: width / 2; color: row.sc }
                Rectangle {
                    anchors.centerIn: parent; width: parent.width; height: width; radius: width / 2
                    color: "transparent"; border.color: row.sc; border.width: 1.4
                    visible: model.status === "checking"
                    SequentialAnimation on scale { loops: Animation.Infinite; running: model.status === "checking" && root.open
                        NumberAnimation { from: 1.0; to: 2.3; duration: 800; easing.type: Easing.OutQuad } }
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: model.status === "checking" && root.open
                        NumberAnimation { from: 0.9; to: 0.0; duration: 800; easing.type: Easing.OutQuad } }
                }
            }

            Column {
                anchors.left: dotBox.right; anchors.leftMargin: root.px(14)
                anchors.right: chip.left; anchors.rightMargin: root.px(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(2)
                Text {
                    width: parent.width; text: model.name; elide: Text.ElideRight
                    color: root.tText; font.pixelSize: root.px(13.5); font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }
                Text {
                    width: parent.width; text: model.detail; elide: Text.ElideRight
                    color: model.status === "fail" ? Qt.lighter(root.cFail, 1.15) : root.tMuted
                    font.pixelSize: root.px(11.5)
                    font.family: "Segoe UI, Inter, sans-serif"
                }
            }

            Rectangle {
                id: chip
                anchors.right: parent.right; anchors.rightMargin: root.px(16); anchors.verticalCenter: parent.verticalCenter
                width: Math.max(root.px(58), chipTxt.implicitWidth + root.px(18)); height: root.px(24); radius: height / 2
                color: Qt.rgba(row.sc.r, row.sc.g, row.sc.b, 0.14)
                border.color: Qt.rgba(row.sc.r, row.sc.g, row.sc.b, 0.55); border.width: 1
                Text {
                    id: chipTxt; anchors.centerIn: parent
                    text: root.chipText(model.status, model.chip)
                    color: row.sc; font.pixelSize: root.px(10); font.bold: true; font.letterSpacing: 0.9
                    font.family: "Segoe UI, Inter, sans-serif"
                }
            }
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: root.px(18); anchors.rightMargin: root.px(18); height: 1; color: Qt.rgba(0.68, 0.78, 0.90, 0.07) }
        }

        Text {
            id: noteText
            anchors.top: rowTop.bottom; anchors.topMargin: root.px(2)
            anchors.left: parent.left; anchors.leftMargin: root.px(44)
            anchors.right: parent.right; anchors.rightMargin: root.px(18)
            text: model.note
            wrapMode: Text.WordWrap
            color: root.mixc("#aebccd", "#aebccd"); font.pixelSize: root.px(11.5); lineHeight: 1.15
            font.family: "Segoe UI, Inter, sans-serif"
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: model.note !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (model.note !== "") model.expanded = !model.expanded
        }
    }

    // ================================================================ a device tile (marine LAN)
    component DeviceTile: Rectangle {
        id: tile
        readonly property color sc: root.statusColor(model.status)
        height: visible ? root.px(52) : 0
        radius: root.px(10)
        color: Qt.rgba(sc.r, sc.g, sc.b, model.status === "na" ? 0.04 : 0.08)
        border.color: Qt.rgba(sc.r, sc.g, sc.b, model.status === "na" ? 0.18 : 0.40); border.width: 1

        Rectangle {
            id: tdot
            x: root.px(11); anchors.verticalCenter: parent.verticalCenter
            width: root.px(9); height: width; radius: width / 2; color: tile.sc
            SequentialAnimation on opacity { loops: Animation.Infinite; running: model.status === "checking" && root.open
                NumberAnimation { from: 1.0; to: 0.25; duration: 450 } NumberAnimation { from: 0.25; to: 1.0; duration: 450 } }
        }
        Column {
            anchors.left: tdot.right; anchors.leftMargin: root.px(9)
            anchors.right: parent.right; anchors.rightMargin: root.px(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { width: parent.width; text: model.name; elide: Text.ElideRight; color: root.tText; font.pixelSize: root.px(12); font.bold: true; font.family: "Segoe UI, Inter, sans-serif" }
            Text { width: parent.width; text: model.detail; elide: Text.ElideRight; color: model.status === "fail" ? Qt.lighter(root.cFail, 1.15) : root.tMuted; font.pixelSize: root.px(10); font.family: "Segoe UI, Inter, sans-serif" }
        }
    }
}
