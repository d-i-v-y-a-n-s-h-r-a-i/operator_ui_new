import QtQuick
import QtQuick.Shapes

// ============================================================================================================
//  DriveRays  -  "which way am I driving" pop-up (replaces the old arrow-key tiles at the bottom right)
//
//  * TANDAV top view in the middle, six ray zones around it (BOW, BOW STBD, STERN STBD, STERN, STERN PORT, BOW PORT)
//  * it is HIDDEN until a drive key is pressed (Up / Down / Left / Right / Space) and fades out again
//    hideMs (10 s) after the LAST key activity.  A key that is still held keeps it open.
//  * colours:  forward = cyan/blue   reverse = amber   brake (Space) = red   steering only = soft blue
//
//  Data in:  `keys` = { Up, Down, Left, Right, Space : bool }  -  exactly what loraBridge.keys already provides.
//            Default binding is loraBridge.keys; set `keys` yourself (or call poke()) for tests / other sources.
// ============================================================================================================
Item {
    id: root

    property real sf: 1.0
    property real lm: 0.0                          // 0 night .. 1 day
    property color accent: "#00f0ff"
    property int hideMs: 10000                     // auto-hide after the last key activity
    property bool pinned: false                    // true = never hide (for design / debugging)
    property var bridge: (typeof loraBridge !== "undefined") ? loraBridge : null
    property var keys: bridge ? bridge.keys : ({})

    // ---- derived drive state -------------------------------------------------------------------------
    readonly property bool kUp: !!(keys && keys.Up)
    readonly property bool kDown: !!(keys && keys.Down)
    readonly property bool kLeft: !!(keys && keys.Left)
    readonly property bool kRight: !!(keys && keys.Right)
    readonly property bool kSpace: !!(keys && keys.Space)
    readonly property bool anyKey: kUp || kDown || kLeft || kRight || kSpace

    readonly property bool brake: kSpace
    readonly property bool fwd: kUp && !kDown && !brake
    readonly property bool rev: kDown && !kUp && !brake
    readonly property bool steerL: kLeft && !kRight
    readonly property bool steerR: kRight && !kLeft
    readonly property bool thrust: fwd || rev
    readonly property bool steerOnly: !brake && !thrust && (steerL || steerR)
    readonly property bool animate: shown && (thrust || steerOnly)

    // zone targets 0..1  (bow, bowStbd, sternStbd, stern, sternPort, bowPort)
    readonly property real tBow:       brake ? 1 : (fwd ? (steerL || steerR ? 0.45 : 1) : 0)
    readonly property real tBowStbd:   brake ? 1 : (fwd && steerR ? 1 : (steerOnly && steerR ? 0.8 : 0))
    readonly property real tBowPort:   brake ? 1 : (fwd && steerL ? 1 : (steerOnly && steerL ? 0.8 : 0))
    readonly property real tStern:     brake ? 1 : (rev ? (steerL || steerR ? 0.45 : 1) : 0)
    readonly property real tSternStbd: brake ? 1 : (rev && steerR ? 1 : 0)
    readonly property real tSternPort: brake ? 1 : (rev && steerL ? 1 : 0)

    readonly property color cFwd: "#27d3ff"
    readonly property color cRev: "#fbbf24"
    readonly property color cBrake: "#ff5468"
    readonly property color cSteer: "#6aa8ff"
    readonly property color stateColor: brake ? cBrake : (fwd ? cFwd : (rev ? cRev : (steerOnly ? cSteer : mixc("#8d9db2", "#5d6b7d"))))
    readonly property string stateText: {
        if (brake) return "BRAKE";
        var s = fwd ? "FWD" : (rev ? "REV" : "");
        var d = steerR ? "STBD" : (steerL ? "PORT" : "");
        if (s && d) return s + "  ·  " + d;
        if (s) return s;
        if (d) return "STEER  ·  " + d;
        return "IDLE";
    }

    // ---- show / hide ---------------------------------------------------------------------------------
    property bool shown: false
    property real lingerT: 1.0                     // 1 -> 0 over hideMs once every key is released
    visible: opacity > 0.01
    opacity: (shown || pinned) ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // read the key object itself (not anyKey): the derived bindings may not have re-evaluated yet when this runs
    function holding() { return !!(keys && (keys.Up || keys.Down || keys.Left || keys.Right || keys.Space)); }
    function poke() {                              // any key activity: show now and restart the 10 s countdown
        shown = true;
        linger.stop();
        lingerT = 1.0;
        if (!holding()) linger.start();            // a key that is still held keeps the card open
    }
    property bool armed: false                     // ignore the initial binding evaluation, start hidden
    Component.onCompleted: armed = true
    onKeysChanged: if (armed) poke()

    NumberAnimation {
        id: linger
        target: root; property: "lingerT"; from: 1.0; to: 0.0
        duration: root.hideMs
        onFinished: root.shown = false
    }

    // wave that runs outwards through the arcs while the boat is being driven
    property real phase: 0.0
    NumberAnimation on phase {
        from: 0.0; to: 1.0; duration: 1100; loops: Animation.Infinite
        running: root.animate && root.visible
    }

    // ---- helpers -------------------------------------------------------------------------------------
    function px(v) { return Math.round(v * sf); }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }

    // ---- geometry (design px, scaled with sf) --------------------------------------------------------
    readonly property real cardW: px(232)
    readonly property real cardH: px(260)
    readonly property real headH: px(34)
    readonly property real cx: cardW / 2
    readonly property real cy: headH + (cardH - headH - px(8)) / 2
    readonly property real r1: px(70)
    readonly property real r2: px(85)
    readonly property real r3: px(100)
    readonly property real rGlow: px(106)

    implicitWidth: cardW
    implicitHeight: cardH
    width: cardW
    height: cardH
    transformOrigin: Item.BottomRight
    scale: (shown || pinned) ? 1.0 : 0.94

    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // ---- card ----------------------------------------------------------------------------------------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.px(20)
        color: root.mixc(Qt.rgba(0.055, 0.075, 0.105, 0.90), Qt.rgba(0.965, 0.975, 0.99, 0.93))
        border.width: 1
        border.color: root.mixc(Qt.rgba(1, 1, 1, 0.10), Qt.rgba(0.1, 0.18, 0.3, 0.14))
    }

    // ---- header: label + state --------------------------------------------------------------------
    Row {
        x: root.px(16); y: root.px(10); height: root.px(18); spacing: root.px(7)
        Rectangle {
            width: root.px(7); height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
            color: root.stateColor
            SequentialAnimation on opacity {
                running: root.anyKey && root.visible; loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 450 }
                NumberAnimation { to: 1.0; duration: 450 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "DRIVE"
            font.pixelSize: root.px(10); font.bold: true; font.letterSpacing: root.px(2)
            font.family: "Segoe UI, Inter, sans-serif"
            color: root.mixc("#8d9db2", "#5d6b7d")
        }
    }
    Rectangle {
        id: stateChip
        anchors.right: parent.right; anchors.rightMargin: root.px(14)
        y: root.px(8); height: root.px(22); radius: height / 2
        width: chipText.implicitWidth + root.px(22)
        color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, root.anyKey ? 0.16 : 0.0)
        border.width: 1
        border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, root.anyKey ? 0.55 : 0.0)
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: root.stateText
            font.pixelSize: root.px(10); font.bold: true; font.letterSpacing: root.px(1.2)
            font.family: "Segoe UI, Inter, sans-serif"
            color: root.stateColor
            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }

    // ---- the six ray zones ---------------------------------------------------------------------------
    component Zone: Item {
        id: zn
        property real centerDeg: -90                // 0 = 3 o'clock, clockwise (y points down), -90 = straight up (bow)
        property real target: 0                     // 0..1 asked by the key state
        property real lvl: 0                        // smoothed
        property color zc: root.stateColor
        property bool wave: true
        property real spanDeg: 38
        anchors.fill: parent
        Behavior on lvl { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        onTargetChanged: lvl = target
        Component.onCompleted: lvl = target
        readonly property real a0: centerDeg - spanDeg / 2
        readonly property real rad0: a0 * Math.PI / 180
        readonly property real rad1: (a0 + spanDeg) * Math.PI / 180

        // brightness of arc i (0 inner .. 2 outer): a pulse that travels outwards; brake / steering-only = steady
        function arcBright(i) {
            if (!zn.wave || !root.animate) return 1.0;
            var p = root.phase * 3.6 - i;                  // 3.6 -> the pulse has left the outer arc before the loop restarts
            var d = Math.abs(p - 0.5);
            return 0.30 + 0.70 * Math.max(0, 1.0 - d / 1.1);
        }
        readonly property color idleCol: root.mixc(Qt.rgba(1, 1, 1, 0.11), Qt.rgba(0.06, 0.12, 0.22, 0.14))

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer
            layer.enabled: true
            layer.samples: 4

            // pie shaped glow, strongest around the middle arc, fading to the outside
            ShapePath {
                strokeWidth: 0
                fillGradient: RadialGradient {
                    centerX: root.cx; centerY: root.cy; centerRadius: root.rGlow
                    focalX: root.cx; focalY: root.cy
                    GradientStop { position: 0.58; color: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, 0.0) }
                    GradientStop { position: 0.80; color: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, 0.34 * zn.lvl) }
                    GradientStop { position: 0.94; color: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, 0.42 * zn.lvl) }
                    GradientStop { position: 1.00; color: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, 0.0) }
                }
                startX: root.cx; startY: root.cy
                PathAngleArc {
                    centerX: root.cx; centerY: root.cy; radiusX: root.rGlow; radiusY: root.rGlow
                    startAngle: zn.a0; sweepAngle: zn.spanDeg
                }
            }
            // idle outlines (always there, so the six zones are readable even while nothing is lit)
            ShapePath {
                strokeColor: zn.idleCol; strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r1; radiusY: root.r1; startAngle: zn.a0 + 3; sweepAngle: zn.spanDeg - 6 }
            }
            ShapePath {
                strokeColor: zn.idleCol; strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r2; radiusY: root.r2; startAngle: zn.a0 + 2; sweepAngle: zn.spanDeg - 4 }
            }
            ShapePath {
                strokeColor: zn.idleCol; strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r3; radiusY: root.r3; startAngle: zn.a0; sweepAngle: zn.spanDeg }
            }
            // lit arcs
            ShapePath {
                strokeColor: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, zn.lvl * zn.arcBright(0))
                strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r1; radiusY: root.r1; startAngle: zn.a0 + 3; sweepAngle: zn.spanDeg - 6 }
            }
            ShapePath {
                strokeColor: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, zn.lvl * zn.arcBright(1))
                strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r2; radiusY: root.r2; startAngle: zn.a0 + 2; sweepAngle: zn.spanDeg - 4 }
            }
            ShapePath {
                strokeColor: Qt.rgba(zn.zc.r, zn.zc.g, zn.zc.b, zn.lvl * zn.arcBright(2))
                strokeWidth: root.px(6); capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r3; radiusY: root.r3; startAngle: zn.a0; sweepAngle: zn.spanDeg }
            }
        }
    }

    Zone { centerDeg: -90;  target: root.tBow;       wave: !root.brake && !root.steerOnly }
    Zone { centerDeg: -45;  target: root.tBowStbd;   wave: !root.brake && !root.steerOnly }
    Zone { centerDeg: 45;   target: root.tSternStbd; wave: !root.brake && !root.steerOnly }
    Zone { centerDeg: 90;   target: root.tStern;     wave: !root.brake && !root.steerOnly }
    Zone { centerDeg: 135;  target: root.tSternPort; wave: !root.brake && !root.steerOnly }
    Zone { centerDeg: -135; target: root.tBowPort;   wave: !root.brake && !root.steerOnly }

    // brake: a slow red pulse over the whole ring, so it can never be mistaken for a thrust state
    Rectangle {
        id: brakeRing
        anchors.fill: parent; radius: card.radius
        color: "transparent"
        border.width: root.px(2)
        border.color: root.cBrake
        opacity: 0.0
        SequentialAnimation on opacity {
            running: root.brake && root.visible; loops: Animation.Infinite
            NumberAnimation { to: 0.75; duration: 380; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.15; duration: 380; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) brakeRing.opacity = 0.0
        }
    }

    // port / starboard hints in the free side gaps
    Text {
        x: root.px(12); y: root.cy - height / 2; text: "PORT"
        font.pixelSize: root.px(8); font.bold: true; font.letterSpacing: root.px(1.4); font.family: "Segoe UI, Inter, sans-serif"
        color: root.mixc("#8d9db2", "#5d6b7d"); opacity: 0.55
    }
    Text {
        x: root.cardW - width - root.px(12); y: root.cy - height / 2; text: "STBD"
        font.pixelSize: root.px(8); font.bold: true; font.letterSpacing: root.px(1.4); font.family: "Segoe UI, Inter, sans-serif"
        color: root.mixc("#8d9db2", "#5d6b7d"); opacity: 0.55
    }

    // ---- TANDAV, top view (hull outline traced from the 3D model's top render) ------------------------
    Item {
        id: boat
        readonly property real hullH: root.px(108)
        readonly property real k: hullH / 691.0
        width: 313 * k; height: 691 * k
        x: root.cx - width / 2
        y: root.cy - height / 2

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            // soft shadow / rim so the black hull still reads on the dark card
            ShapePath {
                strokeWidth: root.px(6); strokeColor: root.mixc(Qt.rgba(0, 0, 0, 0.35), Qt.rgba(0.1, 0.2, 0.35, 0.10))
                fillColor: "transparent"; joinStyle: ShapePath.RoundJoin
                PathPolyline { path: boat.hull }
            }
            ShapePath {
                strokeWidth: 1.2; strokeColor: root.mixc("#56677f", "#8493a8"); joinStyle: ShapePath.RoundJoin
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: boat.width; y2: 0
                    GradientStop { position: 0.0; color: root.mixc("#222b3a", "#2a3445") }
                    GradientStop { position: 0.5; color: root.mixc("#141a24", "#1a2230") }
                    GradientStop { position: 1.0; color: root.mixc("#0c1017", "#121822") }
                }
                PathPolyline { path: boat.hull }
            }
        }
        // bow highlight line + camera dome + TANDAV side marks + C4 mark
        Rectangle {
            x: boat.width * 0.5 - width / 2; y: boat.height * 0.10
            width: 1; height: boat.height * 0.26
            color: root.mixc(Qt.rgba(1, 1, 1, 0.16), Qt.rgba(1, 1, 1, 0.20))
        }
        Rectangle {                                                   // dome
            width: boat.width * 0.15; height: width; radius: width / 2
            x: boat.width * 0.52 - width / 2; y: boat.height * 0.47 - height / 2
            color: "#05070a"
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
        }
        Rectangle { x: boat.width * 0.12; y: boat.height * 0.505; width: Math.max(1, boat.width * 0.035); height: boat.height * 0.27; color: "#d8323c"; opacity: 0.85 }
        Rectangle { x: boat.width * 0.85; y: boat.height * 0.505; width: Math.max(1, boat.width * 0.035); height: boat.height * 0.27; color: "#d8323c"; opacity: 0.85 }
        Text {                                                        // C4 mark
            x: boat.width * 0.5 - width / 2 + root.px(1)
            y: boat.height * 0.71
            text: "C4"
            rotation: 0
            font.pixelSize: Math.max(6, boat.width * 0.27); font.bold: true; font.family: "Segoe UI, Inter, sans-serif"
            color: Qt.rgba(1, 1, 1, 0.82)
        }
        readonly property var hull: [
            Qt.point(166 * k, 0), Qt.point(313 * k, 335 * k), Qt.point(310 * k, 557 * k), Qt.point(284 * k, 640 * k),
            Qt.point(240 * k, 690 * k), Qt.point(63 * k, 686 * k), Qt.point(22 * k, 634 * k), Qt.point(0, 551 * k),
            Qt.point(6 * k, 329 * k), Qt.point(166 * k, 0)
        ]
    }

    // ---- auto-hide countdown -------------------------------------------------------------------------
    Rectangle {
        id: lingerBar
        anchors.bottom: parent.bottom; anchors.bottomMargin: root.px(9)
        x: root.px(22); height: root.px(2); radius: 1
        width: (root.cardW - root.px(44)) * root.lingerT
        color: root.mixc(Qt.rgba(1, 1, 1, 0.22), Qt.rgba(0.1, 0.2, 0.35, 0.25))
        visible: !root.anyKey && !root.pinned
    }
}
