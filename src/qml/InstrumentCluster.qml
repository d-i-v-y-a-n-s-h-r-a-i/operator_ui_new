import QtQuick
import QtQuick.Shapes

// =====================================================================================================
//  InstrumentCluster.qml  -  the boat's instrument cluster, drawn natively on the operator screen.
//
//  The video of the real cluster is no longer streamed. The boat reads its own cluster 24/7 and sends TEXT;
//  this item turns that text into a live cluster (RPM LED bar, speed, fuel, coolant, gear, drive mode, trip,
//  engine hours, battery, alerts).
//
//  FEED IT (any one of these):
//     cluster.json = '{"speedKmh":24,"rpm":3378,...}'        // JSON text straight from the boat (parsed here)
//     cluster.feed = ({ speedKmh: 24, rpm: 3378, ... })      // an object / QVariantMap
//     nothing         -> falls back to vesselState (speed [kn], rpm, fuelLevel, coolantTemp, mode, leakDetected)
//
//  ALWAYS include an increasing  "seq"  (or a timestamp) in every message: an identical string does not
//  trigger QML, so a parked boat would otherwise look "stale".
//
//  JSON keys (all optional - a missing key falls back to vesselState, then to "--"):
//     seq                    number    message counter (any changing value) - keeps the link "LIVE"
//     speedKmh | speedKn     number    boat speed
//     rpm, rpmMax            number    engine rpm, redline scale (default 6500)
//     gear                   "F" | "N" | "R"
//     driveMode              "SPORT" | "ECO" | "CRUISE" | "DOCK" ...   (shown as "SPORT MODE")
//     control                "AUTO" | "TELEOP"                       (small badge left of the speed)
//     tripKm, tripLabel      number, "A" | "B"
//     engineHours            number
//     battV                  number (volts)
//     fuelPct                0..100
//     coolantC               number (deg C)
//     alerts                 ["LOW OIL PRESSURE", ...]              (any text; cycles when several)
//
//  DATA AGE: every json/data update stamps the receive time. Older than 1.5 s = "STALE" (amber),
//  older than 4 s = values blank out and "NO DATA FROM VESSEL" is shown. If you do not use json/data,
//  bind dataAgeMs yourself (e.g. dataAgeMs: vesselState.clusterAgeMs).
//
//  Tap the speed = switch km/h <-> kn.     Theme: pass lm (0 night .. 1 day).
// =====================================================================================================
Item {
    id: ic

    // ---------------------------------------------------------------- inputs
    property real lm: 0.0
    property string json: ""
    property var feed: ({})
    property int dataAgeMs: 0
    property string speedUnit: "kmh"                  // "kmh" | "kn"

    implicitWidth: 360
    implicitHeight: 202
    readonly property real u: width / 360.0
    readonly property string fontFam: "Inter, Segoe UI, sans-serif"

    // ---------------------------------------------------------------- theme
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }
    readonly property color accent: mixc("#00f0ff", "#4a9cf0")
    readonly property color cAmber: "#ffb020"
    readonly property color cRed: "#ff4d4d"
    readonly property color cGreen: "#34d399"
    readonly property color cDim: Qt.rgba(0.80, 0.87, 0.96, 0.55)
    readonly property color cOff: Qt.rgba(0.80, 0.87, 0.96, 0.085)

    // ---------------------------------------------------------------- data in
    readonly property var vs: (typeof vesselState !== "undefined") ? vesselState : null
    property double lastRx: 0
    property double nowMs: Date.now()
    onJsonChanged: {
        if (json === "") return;
        try {
            var o = JSON.parse(json);
            if (o && typeof o === "object") { ic.feed = o; }
        } catch (e) { }
    }
    onFeedChanged: { if (feed && Object.keys(feed).length > 0) lastRx = Date.now(); }
    Timer { interval: 500; repeat: true; running: ic.lastRx > 0; onTriggered: ic.nowMs = Date.now() }
    readonly property int age: ic.lastRx > 0 ? Math.max(0, ic.nowMs - ic.lastRx) : ic.dataAgeMs
    readonly property bool lost: age >= 4000
    readonly property bool stale: age >= 1500 && !lost

    function num(key, fb, def) {
        var v = feed ? feed[key] : undefined;
        if (v !== undefined && v !== null && v !== "" && !isNaN(Number(v))) return Number(v);
        if (fb !== undefined && fb !== null && fb !== "" && !isNaN(Number(fb))) return Number(fb);
        return def;
    }
    function str(key, fb, def) {
        var v = feed ? feed[key] : undefined;
        if (v !== undefined && v !== null && String(v) !== "") return String(v);
        if (fb !== undefined && fb !== null && String(fb) !== "") return String(fb);
        return def;
    }

    readonly property real speedKn: {
        var kn = num("speedKn", undefined, NaN);
        if (!isNaN(kn)) return kn;
        var kmh = num("speedKmh", undefined, NaN);
        if (!isNaN(kmh)) return kmh / 1.852;
        return num("speed", vs ? vs.speed : undefined, 0);
    }
    readonly property real rpmVal: Math.max(0, num("rpm", vs ? vs.rpm : undefined, 0))
    readonly property real rpmMax: Math.max(1000, num("rpmMax", undefined, 6500))
    readonly property real fuelPct: num("fuelPct", vs ? vs.fuelLevel : undefined, NaN)
    readonly property real coolantC: num("coolantC", vs ? vs.coolantTemp : undefined, NaN)
    readonly property real battV: num("battV", undefined, NaN)
    readonly property real tripKm: num("tripKm", undefined, NaN)
    readonly property real engineHours: num("engineHours", undefined, NaN)
    readonly property string tripLabel: str("tripLabel", "", "A")
    readonly property string gear: str("gear", "", speedKn < 0.3 ? "N" : "F").toUpperCase()
    readonly property string control: str("control", vs ? vs.mode : "", "AUTO").toUpperCase()

    readonly property string modeRaw: str("driveMode", "", "").toUpperCase()
    readonly property string modeText: modeRaw !== "" ? (modeRaw.indexOf("MODE") >= 0 ? modeRaw : modeRaw + " MODE")
                                                      : (control === "TELEOP" ? "MANUAL MODE" : "AUTONOMOUS")
    readonly property color modeColor: {
        if (modeRaw.indexOf("SPORT") >= 0) return "#ff8a2a";
        if (modeRaw.indexOf("ECO") >= 0) return cGreen;
        if (modeRaw.indexOf("DOCK") >= 0 || modeRaw.indexOf("IDLE") >= 0) return "#9fb4cc";
        if (modeRaw === "" && control === "TELEOP") return cAmber;
        return accent;
    }

    // alerts from the boat + local sanity limits
    readonly property var alertList: {
        var a = [];
        var src = feed ? feed.alerts : null;
        if (src && src.length) for (var i = 0; i < src.length; ++i) a.push(String(src[i]).toUpperCase());
        if (!isNaN(coolantC) && coolantC >= 95) a.push("HIGH COOLANT TEMP");
        if (!isNaN(fuelPct) && fuelPct >= 0 && fuelPct <= 15) a.push("LOW FUEL");
        if (!isNaN(battV) && battV > 0 && battV < 11.8) a.push("LOW BATTERY");
        if (vs && vs.leakDetected) a.push("BILGE INGRESS");
        return a;
    }
    property int alertIdx: 0
    Timer { interval: 2200; repeat: true; running: ic.alertList.length > 1; onTriggered: ic.alertIdx = (ic.alertIdx + 1) % ic.alertList.length }
    readonly property string alertText: alertList.length > 0 ? alertList[alertIdx % alertList.length] : ""

    // smoothed values for display
    property real dRpm: lost ? 0 : rpmVal
    Behavior on dRpm { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    property real dSpeedKn: lost ? 0 : speedKn
    Behavior on dSpeedKn { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
    property real dFuel: isNaN(fuelPct) ? 0 : fuelPct
    Behavior on dFuel { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    property real dTemp: isNaN(coolantC) ? 0 : coolantC
    Behavior on dTemp { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    readonly property real rpmFrac: Math.min(1, dRpm / rpmMax)
    readonly property bool useKmh: speedUnit === "kmh"
    readonly property string speedStr: {
        var v = useKmh ? dSpeedKn * 1.852 : dSpeedKn;
        if (useKmh) { var n = Math.min(999, Math.round(v)); return (n < 100 ? " " : "") + (n < 10 ? " " : "") + String(n); }
        var s = Math.min(99.9, v).toFixed(1);
        return (s.length < 4 ? " " : "") + s;
    }
    function fmt(v, d) { return isNaN(v) || lost ? "--" : v.toFixed(d); }

    // ================================================================= card
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 14 * ic.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: ic.mixc("#18222f", "#2c2f35") }
            GradientStop { position: 1.0; color: ic.mixc("#0c1119", "#1c1e22") }
        }
        border.color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
        border.width: 1
        clip: true

        // soft light behind the speed
        Rectangle {
            x: 70 * ic.u; y: 40 * ic.u; width: 220 * ic.u; height: 130 * ic.u; radius: 65 * ic.u
            opacity: 0.55
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(ic.modeColor.r, ic.modeColor.g, ic.modeColor.b, 0.0) }
                GradientStop { position: 0.5; color: Qt.rgba(ic.modeColor.r, ic.modeColor.g, ic.modeColor.b, 0.075) }
                GradientStop { position: 1.0; color: Qt.rgba(ic.modeColor.r, ic.modeColor.g, ic.modeColor.b, 0.0) }
            }
        }

        // ------------------------------------------------------------- header
        Rectangle {
            id: header
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 26 * ic.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1f2939" }
                GradientStop { position: 1.0; color: "#141b27" }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

            Rectangle {
                id: dot
                x: 12 * ic.u; anchors.verticalCenter: parent.verticalCenter
                width: 7 * ic.u; height: width; radius: width / 2
                color: ic.lost ? ic.cRed : (ic.stale ? ic.cAmber : ic.cGreen)
                SequentialAnimation on opacity {
                    running: !ic.lost && !ic.stale; loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Text {
                x: 26 * ic.u; anchors.verticalCenter: parent.verticalCenter
                text: "INSTRUMENT CLUSTER"
                color: Qt.rgba(0.85, 0.90, 0.98, 0.88)
                font.pixelSize: Math.round(10 * ic.u); font.bold: true; font.letterSpacing: 1.1 * ic.u
                font.family: ic.fontFam
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 12 * ic.u; anchors.verticalCenter: parent.verticalCenter
                text: ic.lost ? "NO DATA" : (ic.stale ? ("STALE " + (ic.age / 1000).toFixed(1) + " s") : "LIVE")
                color: ic.lost ? ic.cRed : (ic.stale ? ic.cAmber : Qt.rgba(0.62, 0.95, 0.80, 0.90))
                font.pixelSize: Math.round(9.5 * ic.u); font.bold: true; font.letterSpacing: 1.0 * ic.u
                font.family: ic.fontFam
            }
        }

        // all live values: dimmed when the feed is lost
        Item {
            id: body
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: header.bottom; anchors.bottom: parent.bottom
            opacity: ic.lost ? 0.30 : (ic.stale ? 0.75 : 1.0)
            Behavior on opacity { NumberAnimation { duration: 250 } }

            // ----------------------------------------------------- RPM LED bar
            Item {
                id: rpmBar
                x: 16 * ic.u; y: 9 * ic.u; width: 328 * ic.u; height: 11 * ic.u
                readonly property int n: 40
                readonly property real gap: 2 * ic.u
                readonly property real segW: (width - gap * (n - 1)) / n
                Repeater {
                    model: rpmBar.n
                    Rectangle {
                        required property int index
                        x: index * (rpmBar.segW + rpmBar.gap); width: rpmBar.segW; height: rpmBar.height
                        radius: 1.6 * ic.u
                        readonly property bool lit: (index + 0.5) / rpmBar.n <= ic.rpmFrac
                        color: !lit ? ic.cOff : (index >= 35 ? ic.cRed : (index >= 28 ? ic.cAmber : ic.accent))
                        opacity: lit ? (0.62 + 0.38 * (index / rpmBar.n)) : 1.0
                    }
                }
            }
            Text {
                x: 16 * ic.u; y: 23 * ic.u
                text: "RPM"; color: ic.cDim
                font.pixelSize: Math.round(9 * ic.u); font.bold: true; font.letterSpacing: 1.2 * ic.u; font.family: ic.fontFam
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16 * ic.u; y: 21 * ic.u
                text: ic.lost ? "----" : String(Math.round(ic.dRpm))
                color: ic.rpmFrac > 0.86 ? ic.cRed : (ic.rpmFrac > 0.70 ? ic.cAmber : "#eef3fb")
                font.pixelSize: Math.round(12.5 * ic.u); font.bold: true; font.family: ic.fontFam
            }

            // ----------------------------------------------------- FUEL (left)
            Item {
                id: fuelCol
                x: 16 * ic.u; y: 44 * ic.u; width: 56 * ic.u; height: 82 * ic.u
                Text {
                    text: "FUEL"; color: ic.cDim
                    font.pixelSize: Math.round(9 * ic.u); font.bold: true; font.letterSpacing: 1.0 * ic.u; font.family: ic.fontFam
                }
                Text {
                    anchors.right: parent.right
                    text: ic.fmt(ic.fuelPct, 0) + (isNaN(ic.fuelPct) || ic.lost ? "" : "%")
                    color: (!isNaN(ic.fuelPct) && ic.fuelPct <= 15) ? ic.cRed : ((!isNaN(ic.fuelPct) && ic.fuelPct <= 25) ? ic.cAmber : "#eef3fb")
                    font.pixelSize: Math.round(11 * ic.u); font.bold: true; font.family: ic.fontFam
                }
                Column {
                    y: 15 * ic.u
                    spacing: 1.6 * ic.u
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            readonly property int level: 7 - index                         // 7 = top = full
                            readonly property bool lit: ic.dFuel / 100 * 8 > level + 0.15
                            width: 20 * ic.u; height: 6.4 * ic.u; radius: 1.6 * ic.u
                            color: !lit ? ic.cOff : (ic.dFuel <= 15 ? ic.cRed : (ic.dFuel <= 25 ? ic.cAmber : ic.accent))
                        }
                    }
                }
                Text { x: 26 * ic.u; y: 14 * ic.u; text: "F"; color: ic.cDim; font.pixelSize: Math.round(10 * ic.u); font.bold: true; font.family: ic.fontFam }
                Text { x: 26 * ic.u; y: 70 * ic.u; text: "E"; color: ic.cDim; font.pixelSize: Math.round(10 * ic.u); font.bold: true; font.family: ic.fontFam }
            }

            // ----------------------------------------------------- COOLANT (right)
            Item {
                id: tempCol
                x: 282 * ic.u; y: 44 * ic.u; width: 62 * ic.u; height: 82 * ic.u
                Text {
                    text: "TEMP"; color: ic.cDim
                    font.pixelSize: Math.round(9 * ic.u); font.bold: true; font.letterSpacing: 1.0 * ic.u; font.family: ic.fontFam
                }
                Text {
                    anchors.right: parent.right
                    text: ic.fmt(ic.coolantC, 0) + (isNaN(ic.coolantC) || ic.lost ? "" : "°C")
                    color: (!isNaN(ic.coolantC) && ic.coolantC >= 95) ? ic.cRed : ((!isNaN(ic.coolantC) && ic.coolantC >= 85) ? ic.cAmber : "#eef3fb")
                    font.pixelSize: Math.round(10.5 * ic.u); font.bold: true; font.family: ic.fontFam
                }
                Column {
                    y: 15 * ic.u; anchors.right: parent.right
                    spacing: 1.6 * ic.u
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            readonly property int level: 7 - index
                            readonly property bool lit: (ic.dTemp - 30) / 80 * 8 > level + 0.15       // 30 C .. 110 C
                            width: 20 * ic.u; height: 6.4 * ic.u; radius: 1.6 * ic.u
                            color: !lit ? ic.cOff : (level >= 7 ? ic.cRed : (level >= 6 ? ic.cAmber : ic.cGreen))
                        }
                    }
                }
                Text { anchors.right: parent.right; anchors.rightMargin: 26 * ic.u; y: 14 * ic.u; text: "H"; color: ic.cDim; font.pixelSize: Math.round(10 * ic.u); font.bold: true; font.family: ic.fontFam }
                Text { anchors.right: parent.right; anchors.rightMargin: 26 * ic.u; y: 70 * ic.u; text: "C"; color: ic.cDim; font.pixelSize: Math.round(10 * ic.u); font.bold: true; font.family: ic.fontFam }
            }

            // ----------------------------------------------------- SPEED (centre)
            Item {
                id: speedBox
                x: 90 * ic.u; y: 34 * ic.u; width: 180 * ic.u; height: 82 * ic.u

                readonly property real dw: 40 * ic.u
                readonly property real dotW: 16 * ic.u
                // total width of the digit cells so the number stays centred and nothing jitters
                readonly property real totalW: ic.useKmh ? 3 * dw : (3 * dw + dotW)

                Row {
                    id: digits
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    Repeater {
                        model: ic.lost ? (ic.useKmh ? ["-", "-", "-"] : [" ", "-", ".", "-"]) : ic.speedStr.split("")
                        Item {
                            required property string modelData
                            readonly property bool isDot: modelData === "."
                            width: isDot ? speedBox.dotW : speedBox.dw
                            height: 72 * ic.u
                            // unlit "88" segments behind the digits (cluster look, also keeps the layout still)
                            Text {
                                anchors.centerIn: parent
                                text: parent.isDot ? "." : "8"
                                color: ic.cOff
                                font.pixelSize: Math.round(66 * ic.u); font.bold: true; font.italic: true; font.family: ic.fontFam
                            }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData === " " ? "" : parent.modelData
                                color: "#f4f8fd"
                                font.pixelSize: Math.round(66 * ic.u); font.bold: true; font.italic: true; font.family: ic.fontFam
                            }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 66 * ic.u
                    text: ic.useKmh ? "KM/H" : "KNOTS"
                    color: ic.accent
                    font.pixelSize: Math.round(10.5 * ic.u); font.bold: true; font.letterSpacing: 2.2 * ic.u; font.family: ic.fontFam
                }
                MouseArea { anchors.fill: parent; onClicked: ic.speedUnit = ic.useKmh ? "kn" : "kmh" }
            }

            // ----------------------------------------------------- control badge (left) and gear badge (right) of the speed
            Rectangle {
                x: 82 * ic.u; y: 48 * ic.u; width: 32 * ic.u; height: 18 * ic.u; radius: 5 * ic.u
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: ic.control === "TELEOP" ? ic.cAmber : Qt.rgba(ic.accent.r, ic.accent.g, ic.accent.b, 0.70)
                Text {
                    anchors.centerIn: parent
                    text: ic.control === "TELEOP" ? "MAN" : "AUTO"
                    color: ic.control === "TELEOP" ? ic.cAmber : ic.accent
                    font.pixelSize: Math.round(9.5 * ic.u); font.bold: true; font.letterSpacing: 0.8 * ic.u; font.family: ic.fontFam
                }
            }
            Rectangle {
                x: 246 * ic.u; y: 44 * ic.u; width: 28 * ic.u; height: 28 * ic.u; radius: 7 * ic.u
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1.2
                border.color: ic.gear === "R" ? ic.cAmber : (ic.gear === "N" ? Qt.rgba(0.80, 0.87, 0.96, 0.45) : Qt.rgba(ic.accent.r, ic.accent.g, ic.accent.b, 0.85))
                Text {
                    anchors.centerIn: parent
                    text: ic.lost ? "-" : ic.gear
                    color: ic.gear === "R" ? ic.cAmber : (ic.gear === "N" ? "#c9d6e6" : ic.accent)
                    font.pixelSize: Math.round(17 * ic.u); font.bold: true; font.family: ic.fontFam
                }
            }
            Text {
                x: 246 * ic.u; width: 28 * ic.u; y: 74 * ic.u
                horizontalAlignment: Text.AlignHCenter
                text: "GEAR"; color: ic.cDim
                font.pixelSize: Math.round(9 * ic.u); font.bold: true; font.letterSpacing: 0.8 * ic.u; font.family: ic.fontFam
            }

            // ----------------------------------------------------- drive mode  /  alert
            Item {
                id: modeRow
                y: 116 * ic.u; width: parent.width; height: 24 * ic.u
                readonly property bool alerting: ic.alertText !== "" && !ic.lost
                readonly property color tone: alerting ? ic.cRed : ic.modeColor

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 16 * ic.u; width: (parent.width / 2 - 16 * ic.u) - (modeLabel.width / 2 + 18 * ic.u); height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(modeRow.tone.r, modeRow.tone.g, modeRow.tone.b, 0.0) }
                        GradientStop { position: 1.0; color: Qt.rgba(modeRow.tone.r, modeRow.tone.g, modeRow.tone.b, 0.75) }
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width / 2 + modeLabel.width / 2 + 18 * ic.u; width: (parent.width / 2 - 16 * ic.u) - (modeLabel.width / 2 + 18 * ic.u); height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(modeRow.tone.r, modeRow.tone.g, modeRow.tone.b, 0.75) }
                        GradientStop { position: 1.0; color: Qt.rgba(modeRow.tone.r, modeRow.tone.g, modeRow.tone.b, 0.0) }
                    }
                }
                Row {
                    id: modeLabel
                    anchors.centerIn: parent
                    spacing: 7 * ic.u
                    // warning triangle (only while an alert is shown)
                    Shape {
                        visible: modeRow.alerting
                        width: 16 * ic.u; height: 14 * ic.u
                        anchors.verticalCenter: parent.verticalCenter
                        preferredRendererType: Shape.GeometryRenderer
                        ShapePath {
                            fillColor: ic.cRed; strokeColor: "transparent"
                            PathSvg { path: "M" + (8 * ic.u) + " 0 L" + (16 * ic.u) + " " + (14 * ic.u) + " L0 " + (14 * ic.u) + " Z" }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 3.5 * ic.u; text: "!"; color: "#1a0b0b"
                               font.pixelSize: Math.round(9.5 * ic.u); font.bold: true; font.family: ic.fontFam }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modeRow.alerting ? ic.alertText : ic.modeText
                        color: modeRow.tone
                        font.pixelSize: Math.round((modeRow.alerting ? 13 : 16) * ic.u)
                        font.bold: true; font.italic: !modeRow.alerting
                        font.letterSpacing: (modeRow.alerting ? 1.0 : 2.2) * ic.u; font.family: ic.fontFam
                        SequentialAnimation on opacity {
                            running: modeRow.alerting; loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 450 }
                            NumberAnimation { to: 1.0; duration: 450 }
                        }
                        onTextChanged: opacity = 1.0
                    }
                }
            }

            // ----------------------------------------------------- bottom strip: trip / engine hours / battery
            Rectangle {
                id: infoStrip
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 34 * ic.u
                color: Qt.rgba(0, 0, 0, 0.30)
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

                Repeater {
                    model: [
                        { label: "TRIP " + ic.tripLabel,
                          value: ic.fmt(ic.useKmh ? ic.tripKm : ic.tripKm * 0.539957, 1) + (isNaN(ic.tripKm) || ic.lost ? "" : (ic.useKmh ? " km" : " NM")),
                          tone: "#eef3fb" },
                        { label: "ENGINE HRS",
                          value: ic.fmt(ic.engineHours, 1) + (isNaN(ic.engineHours) || ic.lost ? "" : " h"),
                          tone: "#eef3fb" },
                        { label: "BATTERY",
                          value: ic.fmt(ic.battV, 1) + (isNaN(ic.battV) || ic.lost ? "" : " V"),
                          tone: (!isNaN(ic.battV) && ic.battV < 11.8) ? ic.cRed : ((!isNaN(ic.battV) && ic.battV < 12.2) ? ic.cAmber : "#eef3fb") }
                    ]
                    Item {
                        required property int index
                        required property var modelData
                        x: index * (infoStrip.width / 3); width: infoStrip.width / 3; height: infoStrip.height
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 5 * ic.u
                            text: modelData.label; color: ic.cDim
                            font.pixelSize: Math.round(9 * ic.u); font.bold: true; font.letterSpacing: 1.0 * ic.u; font.family: ic.fontFam
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 16 * ic.u
                            text: modelData.value; color: modelData.tone
                            font.pixelSize: Math.round(13.5 * ic.u); font.bold: true; font.family: ic.fontFam
                        }
                        Rectangle {
                            visible: index > 0
                            x: 0; anchors.verticalCenter: parent.verticalCenter
                            width: 1; height: 20 * ic.u; color: Qt.rgba(1, 1, 1, 0.10)
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------- feed lost
        Item {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: header.bottom; anchors.bottom: parent.bottom
            visible: ic.lost
            Rectangle {
                anchors.centerIn: parent
                width: 214 * ic.u; height: 48 * ic.u; radius: 10 * ic.u
                color: Qt.rgba(0.05, 0.07, 0.10, 0.88)
                border.color: Qt.rgba(1.0, 0.69, 0.13, 0.55); border.width: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 9 * ic.u
                    text: "NO DATA FROM VESSEL"; color: ic.cAmber
                    font.pixelSize: Math.round(13 * ic.u); font.bold: true; font.letterSpacing: 1.2 * ic.u; font.family: ic.fontFam
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 28 * ic.u
                    text: "last update " + (ic.lastRx > 0 ? (ic.age / 1000).toFixed(0) + " s ago" : "never")
                    color: ic.cDim
                    font.pixelSize: Math.round(10 * ic.u); font.family: ic.fontFam
                }
            }
        }
    }
}
