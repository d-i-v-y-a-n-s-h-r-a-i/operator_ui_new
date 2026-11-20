import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// TANDAV HUD telemetry tile, matched to the Neuboat reference.
//  * near-opaque dark navy glass, 1px light border + dark outer ring
//  * light-weight white value, bold title, light subtext with BOLD values ("Rain: 30%")
//  * graphics live in a full-card layer that is clipped to the rounded corners,
//    so clouds / boats can bleed off the card edge exactly like the reference
//  * reusable gauge parts: TelemetryCard.TickArc, TelemetryCard.CompassDial, TelemetryCard.GlowArc
// LIGHT MODE: `lm` (0 = dark, 1 = light, animated by the owner) cross-fades every colour of the
// card, the gauge parts and the text.  Cards read `lm` from the owner (mapRoot.lm / appWindow.lm).
// Everything is sized from `u` (card size / 280x150 design size), so the same file
// renders correctly in the 355x210 map carousel and the 611x205 HUD carousel.
Item {
    id: rootCard
    width: 280
    height: 150

    // ------------------------------------------------------------------
    // PUBLIC API (all existing names kept)
    // ------------------------------------------------------------------
    property string title: ""
    property string primaryValue: ""
    property alias cardValue: rootCard.primaryValue
    property string unit: ""
    property alias cardUnit: rootCard.unit
    property string subtitle: ""
    property alias cardSubtext: rootCard.subtitle
    // 0 = dark theme, 1 = light theme (Neuboat day look). Driven by the owner, animated there.
    property real lm: 0.0
    property color valueColor: rootCard.cValue
    // sky colour behind the card (light theme frosted fill); the owner binds these to its sky gradient
    property color bgTop: "#a9bfca"
    property color bgBottom: "#d4dade"
    property bool isActive: false
    property bool showTextColumn: true
    property real valueSize: 58            // big-number size in design px (at 280x150)

    // Layout, chosen automatically (override in a card if needed):
    //   titleAtBottom : Roll / Pitch style. Value on top, bold title + subtext at the bottom.
    //                   (automatic when the unit is a bare degree sign)
    //   subtitleAtTop : Depth / Wind style. Bold title with the caption right under it, at the top.
    //                   (automatic for a valueless card, or a one-line subtext)
    // Otherwise (Weather style): title on top, value, then bold first subtext line + light lines.
    property bool titleAtBottom: unit === "°"
    property bool subtitleAtTop: primaryValue === "" || (!titleAtBottom && subtitle !== "" && subtitle.indexOf("\n") < 0)

    property bool valueCentered: false     // value (and its unit) centred in the card, e.g. Depth / Fuel
    property real valueCenterY: 0.70       // vertical centre of the value, fraction of card height
    property bool centerDesign: false      // true: graphics box is centred, false: stuck to the right edge
    property bool titleMoon: false         // little half-moon icon in front of the title (Weather)

    // children land in the clipped graphics box (see designBox)
    default property alias content: designBox.data
    property alias designArea: designBox
    property alias customContent: graphicArea     // legacy, unused by the new cards
    property alias graphicColumn: graphicArea

    // ------------------------------------------------------------------
    // SCALE + METRICS
    // ------------------------------------------------------------------
    // text / graphics scale follows the card HEIGHT (narrow cards keep the same type size as full ones)
    readonly property real u: Math.max(0.4, height / 150.0)
    // 1 = full-width card, 0 = narrow card (carousel side cards): graphics that need width fade out
    readonly property real wideMix: Math.max(0, Math.min(1, (width / Math.max(1, height) - 1.15) / 0.35))
    readonly property real padX: Math.round(13 * u)
    readonly property real padBottom: Math.round(12 * u)
    readonly property real cornerR: Math.round(12 * u)
    readonly property real innerW: width - 2 * padX
    readonly property string fontText: "Inter, Helvetica Neue, Segoe UI, Roboto, sans-serif"
    readonly property string fontNum: "Helvetica Neue, Inter, Segoe UI, Roboto, sans-serif"

    // ---- THEME (dark -> light), every colour mixes on `lm` ----------------
    function mixc(a, b) {
        return Qt.rgba(a.r + (b.r - a.r) * lm, a.g + (b.g - a.g) * lm,
                       a.b + (b.b - a.b) * lm, a.a + (b.a - a.a) * lm);
    }
    readonly property color accentBlue: mixc(Qt.color("#2C88DA"), Qt.color("#1C62B5"))   // arcs, needles, depth bars
    readonly property color cTitle:  mixc(Qt.rgba(1, 1, 1, 1),         Qt.rgba(0.106, 0.114, 0.149, 1))   // bold titles, bold values  #1B1D26
    readonly property color cValue:  mixc(Qt.rgba(1, 1, 1, 1),         Qt.rgba(0.086, 0.094, 0.110, 1))   // big light-weight number  #16181C
    readonly property color cUnit:   mixc(Qt.rgba(1, 1, 1, 0.92),      Qt.rgba(0.086, 0.094, 0.110, 0.92))
    readonly property color cSoft:   mixc(Qt.rgba(1, 1, 1, 0.78),      Qt.rgba(0.375, 0.415, 0.450, 0.88)) // light captions  ~#606A73 (grey, like the reference)
    readonly property color cFaint:  mixc(Qt.rgba(1, 1, 1, 0.55),      Qt.rgba(0.375, 0.415, 0.450, 0.70)) // E / F / To WP / Distance
    readonly property color cLabel:  mixc(Qt.rgba(1, 1, 1, 0.28),      Qt.rgba(0.420, 0.480, 0.530, 0.70)) // Left / Right
    readonly property color cDash:   mixc(Qt.rgba(0.62, 0.66, 0.78, 0.20), Qt.rgba(0.71, 0.74, 0.76, 0.88))  // dashed protractor arcs
    readonly property color cRing:   mixc(Qt.rgba(0.62, 0.66, 0.78, 0.22), Qt.rgba(0.30, 0.38, 0.46, 0.26))  // solid gauge tracks
    readonly property color cRail:   mixc(Qt.rgba(0.62, 0.66, 0.78, 0.22), Qt.rgba(0.56, 0.61, 0.67, 0.85))  // depth rails
    readonly property color cWpTrack: mixc(Qt.rgba(0.17, 0.53, 0.85, 0.22), Qt.rgba(0.11, 0.38, 0.71, 0.24))
    readonly property color cDots:   mixc(Qt.rgba(1, 1, 1, 0.92),      Qt.rgba(1, 1, 1, 0.96))
    readonly property color cIcon:   mixc(Qt.rgba(1, 1, 1, 0.90),      Qt.rgba(0.23, 0.28, 0.33, 0.92))

    readonly property var subLines: subtitle === "" ? [] : subtitle.split("\n")
    // bold line above the light subtext block (bottom block only)
    readonly property string boldLine: titleAtBottom ? title
                                       : ((!subtitleAtTop && subLines.length > 1) ? subLines[0] : "")
    readonly property string lightText: titleAtBottom ? subtitle
                                        : ((boldLine !== "") ? subLines.slice(1).join("\n") : (subtitleAtTop ? "" : subtitle))

    // "Rain: 30%" -> label light, value bold (like the reference)
    function rich(str) {
        if (!str) return "";
        var bold = "" + rootCard.cTitle;
        var esc = function(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); };
        return str.split("\n").map(function(line) {
            return line.split(" | ").map(function(seg) {
                var i = seg.indexOf(": ");
                if (i > 0 && i <= 16)
                    return esc(seg.substring(0, i)) + ": <font color=\"" + bold + "\"><b>" + esc(seg.substring(i + 2)) + "</b></font>";
                return esc(seg);
            }).join(" | ");
        }).join("<br/>");
    }

    // 0 -> 1 when the card becomes the centre card (animated, drives glass + shadow)
    property real activeMix: isActive ? 1.0 : 0.0
    Behavior on activeMix { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    // ------------------------------------------------------------------
    // REUSABLE: dashed arc track + thin blue segment with end caps
    //   cx / cy / r in pixels of the item it fills (use anchors.fill: parent).
    //   Angles: 0 = 3 o'clock, 90 = 6 o'clock, 270 = 12 o'clock (clockwise).
    // ------------------------------------------------------------------
    component TickArc: Item {
        id: ta
        property real cx: width / 2
        property real cy: height / 2
        property real r: Math.min(width, height) / 2
        property real trackStart: 180
        property real trackSweep: 0              // 0 = no track
        property bool dashed: true
        property real trackWidth: 6
        property real lm: 0.0                    // theme mix (cards pass lm: <card>.lm)
        function mx(a, b) {
            return Qt.rgba(a.r + (b.r - a.r) * lm, a.g + (b.g - a.g) * lm, a.b + (b.b - a.b) * lm, a.a + (b.a - a.a) * lm);
        }
        property color trackColor: dashed ? mx(Qt.rgba(0.62, 0.66, 0.78, 0.20), Qt.rgba(0.71, 0.74, 0.76, 0.88))
                                          : mx(Qt.rgba(0.62, 0.66, 0.78, 0.22), Qt.rgba(0.30, 0.38, 0.46, 0.26))
        property real segStart: 0
        property real segSweep: 0                // 0 = no blue segment
        property real segWidth: 3
        property color segColor: mx(Qt.color("#2C88DA"), Qt.color("#1C62B5"))
        property real capLen: 0                  // length of the perpendicular end caps (0 = none)

        function pt(a, rr) {
            var t = a * Math.PI / 180.0;
            return Qt.point(cx + rr * Math.cos(t), cy + rr * Math.sin(t));
        }
        readonly property point c1a: pt(segStart, r - capLen / 2)
        readonly property point c1b: pt(segStart, r + capLen / 2)
        readonly property point c2a: pt(segStart + segSweep, r - capLen / 2)
        readonly property point c2b: pt(segStart + segSweep, r + capLen / 2)

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: ta.trackSweep !== 0 ? ta.trackColor : "transparent"
                strokeWidth: ta.trackWidth
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ta.dashed ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: [2.0, 1.7]
                PathAngleArc {
                    centerX: ta.cx; centerY: ta.cy
                    radiusX: ta.r; radiusY: ta.r
                    startAngle: ta.trackStart
                    sweepAngle: ta.trackSweep
                }
            }

            ShapePath {
                strokeColor: ta.segSweep !== 0 ? ta.segColor : "transparent"
                strokeWidth: ta.segWidth
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: ta.cx; centerY: ta.cy
                    radiusX: ta.r; radiusY: ta.r
                    startAngle: ta.segStart
                    sweepAngle: ta.segSweep
                }
                PathMove { x: ta.c1a.x; y: ta.c1a.y }
                PathLine { x: ta.c1b.x; y: ta.c1b.y }
                PathMove { x: ta.c2a.x; y: ta.c2a.y }
                PathLine { x: ta.c2b.x; y: ta.c2b.y }
            }
        }
    }

    // ------------------------------------------------------------------
    // REUSABLE: wind compass (thin ring, cardinal ticks + letters, wind needle, heading arrow)
    // ------------------------------------------------------------------
    component CompassDial: Item {
        id: cd
        property real windFrom: 113          // bearing the wind blows FROM (deg, clockwise from N)
        property real heading: 45            // vessel heading (deg)
        readonly property real s: Math.min(width, height)
        property real lm: 0.0
        function mx(a, b) {
            return Qt.rgba(a.r + (b.r - a.r) * lm, a.g + (b.g - a.g) * lm, a.b + (b.b - a.b) * lm, a.a + (b.a - a.a) * lm);
        }
        readonly property color ringColor:   mx(Qt.rgba(0.62, 0.66, 0.78, 0.50), Qt.rgba(0.26, 0.28, 0.31, 0.78))
        readonly property color letterColor: mx(Qt.rgba(0.17, 0.53, 0.85, 0.85), Qt.rgba(0.11, 0.38, 0.71, 0.95))
        readonly property color tickColor:   mx(Qt.rgba(0.80, 0.84, 0.92, 0.65), Qt.rgba(0.22, 0.24, 0.28, 0.85))
        readonly property color dotColor:    mx(Qt.rgba(0.62, 0.66, 0.78, 0.30), Qt.rgba(0.30, 0.33, 0.38, 0.45))
        readonly property color tailColor:   mx(Qt.rgba(0.62, 0.66, 0.74, 0.70), Qt.rgba(0.36, 0.40, 0.46, 0.80))
        readonly property color armColor:    mx(Qt.color("#F2F5FA"), Qt.color("#2A2D33"))
        readonly property color arrowColor:  mx(Qt.color("#2C88DA"), Qt.color("#1C62B5"))

        // thin outer ring
        Rectangle {
            anchors.centerIn: parent
            width: cd.s; height: cd.s
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, Math.round(cd.s * 0.012))
            border.color: cd.ringColor
        }
        // fine ticks just inside the ring (dotted look)
        TickArc {
            anchors.centerIn: parent
            width: cd.s; height: cd.s
            r: cd.s * 0.5 - cd.s * 0.045
            trackSweep: 360
            trackWidth: cd.s * 0.04
            trackColor: cd.dotColor
        }

        // N / E / S / W ticks crossing the ring
        Repeater {
            model: 4
            delegate: Item {
                anchors.centerIn: parent
                width: 1; height: 1
                rotation: index * 90
                Rectangle {
                    x: -Math.max(1, cd.s * 0.016) / 2
                    y: -cd.s / 2 - cd.s * 0.045
                    width: Math.max(1, cd.s * 0.016)
                    height: cd.s * 0.12
                    color: cd.tickColor
                }
            }
        }

        // letters
        Text { text: "N"; color: cd.letterColor; font.pixelSize: cd.s * 0.11; font.weight: Font.DemiBold
               anchors.horizontalCenter: parent.horizontalCenter; y: parent.height / 2 - cd.s * 0.5 + cd.s * 0.12 }
        Text { text: "S"; color: cd.letterColor; font.pixelSize: cd.s * 0.11; font.weight: Font.DemiBold
               anchors.horizontalCenter: parent.horizontalCenter; y: parent.height / 2 + cd.s * 0.5 - cd.s * 0.12 - height }
        Text { text: "W"; color: cd.letterColor; font.pixelSize: cd.s * 0.11; font.weight: Font.DemiBold
               anchors.verticalCenter: parent.verticalCenter; x: parent.width / 2 - cd.s * 0.5 + cd.s * 0.12 }
        Text { text: "E"; color: cd.letterColor; font.pixelSize: cd.s * 0.11; font.weight: Font.DemiBold
               anchors.verticalCenter: parent.verticalCenter; x: parent.width / 2 + cd.s * 0.5 - cd.s * 0.12 - width }

        // wind needle: grey tail toward the bearing the wind comes from, white arm on the far side
        Item {
            anchors.centerIn: parent
            width: 1; height: 1
            rotation: cd.windFrom - 90
            Rectangle {      // tail (toward wind origin)
                x: 0; y: -height / 2
                width: cd.s * 0.40; height: Math.max(2, cd.s * 0.028)
                radius: height / 2
                color: cd.tailColor
            }
            Rectangle {      // white arm (opposite side)
                x: -width; y: -height / 2
                width: cd.s * 0.36; height: Math.max(2, cd.s * 0.045)
                radius: height / 2
                color: cd.armColor
            }
        }

        // vessel heading arrow
        Shape {
            anchors.centerIn: parent
            width: cd.s * 0.30; height: cd.s * 0.30
            rotation: cd.heading
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: "transparent"
                fillColor: cd.arrowColor
                startX: cd.s * 0.30 * 0.50; startY: 0
                PathLine { x: cd.s * 0.30 * 0.80; y: cd.s * 0.30 * 0.95 }
                PathLine { x: cd.s * 0.30 * 0.50; y: cd.s * 0.30 * 0.72 }
                PathLine { x: cd.s * 0.30 * 0.20; y: cd.s * 0.30 * 0.95 }
                PathLine { x: cd.s * 0.30 * 0.50; y: 0 }
            }
        }
    }

    // ------------------------------------------------------------------
    // LEGACY GLOWING ARC  ->  TelemetryCard.GlowArc { }  (kept so nothing else breaks)
    // ------------------------------------------------------------------
    component GlowArc: Item {
        id: arc
        property real startAngle: 135
        property real sweepAngle: 90
        property real trackStart: 135
        property real trackSweep: 0
        property real lineWidth: 8
        property color arcColor: "#0066FF"
        property color trackColor: Qt.rgba(0.0, 0.40, 1.0, 0.22)
        property real glow: 0.9
        readonly property real radius: Math.max(1, Math.min(width, height) / 2 - lineWidth / 2 - 1)

        Shape {
            id: trackShape
            anchors.fill: parent
            visible: arc.trackSweep > 0
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: arc.trackColor
                strokeWidth: arc.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: arc.width / 2; centerY: arc.height / 2
                    radiusX: arc.radius; radiusY: arc.radius
                    startAngle: arc.trackStart
                    sweepAngle: arc.trackSweep
                }
            }
        }

        Shape {
            id: arcShape
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: arc.arcColor
                strokeWidth: arc.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: arc.width / 2; centerY: arc.height / 2
                    radiusX: arc.radius; radiusY: arc.radius
                    startAngle: arc.startAngle
                    sweepAngle: arc.sweepAngle
                }
            }
        }

        MultiEffect {
            anchors.fill: arcShape
            source: arcShape
            autoPaddingEnabled: true
            shadowEnabled: arc.glow > 0
            shadowColor: arc.arcColor
            shadowBlur: 1.0
            shadowOpacity: arc.glow
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
    }

    // ------------------------------------------------------------------
    // 1. DROP SHADOW  (sibling of the glass, so it never touches the content)
    // ------------------------------------------------------------------
    Rectangle {
        id: shadowRect
        anchors.fill: parent
        radius: rootCard.cornerR
        color: "#000000"
    }

    ShaderEffectSource {
        id: shadowSrc
        sourceItem: shadowRect
        hideSource: true
        live: false
    }

    MultiEffect {
        anchors.fill: shadowRect
        source: shadowSrc
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: rootCard.mixc(Qt.rgba(0, 0, 0, 1), Qt.rgba(0.17, 0.25, 0.32, 1))
        shadowBlur: 1.0
        shadowHorizontalOffset: 0
        shadowVerticalOffset: ((7 + 8 * rootCard.activeMix) * (1 - rootCard.lm) + (4 + 4 * rootCard.activeMix) * rootCard.lm) * rootCard.u
        shadowOpacity: (0.50 + 0.30 * rootCard.activeMix) * (1 - rootCard.lm) + (0.20 + 0.10 * rootCard.activeMix) * rootCard.lm
        shadowScale: 1.0 + 0.02 * rootCard.activeMix
        maskEnabled: true
        maskSource: shadowSrc
        maskInverted: true
    }

    // ------------------------------------------------------------------
    // 2. GLASS BODY: deep navy, almost opaque, thin light border
    // ------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: rootCard.cornerR + 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0.0 + 0.20 * rootCard.lm, 0.0 + 0.30 * rootCard.lm, 0.0 + 0.36 * rootCard.lm,
                              0.55 * (1 - rootCard.lm) + 0.07 * rootCard.lm)
    }

    Rectangle {
        id: glass
        anchors.fill: parent
        radius: rootCard.cornerR
        gradient: Gradient {
            // dark: deep navy, almost opaque.
            // light: frosted glass = the sky colour that sits behind the card (bgTop / bgBottom are fed by the
            // owner from the sky gradient), a few % darker toward the bottom. It hides the cards stacked
            // behind it, exactly like the blurred glass of the Neuboat day look.
            GradientStop {
                position: 0.0
                color: Qt.rgba((0.043 + 0.012 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgTop.r * 0.992 * rootCard.lm,
                               (0.059 + 0.014 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgTop.g * 0.992 * rootCard.lm,
                               (0.098 + 0.020 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgTop.b * 0.992 * rootCard.lm,
                               0.94 * (1 - rootCard.lm) + 0.97 * rootCard.lm)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba((0.082 + 0.012 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgBottom.r * 0.962 * rootCard.lm,
                               (0.090 + 0.014 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgBottom.g * 0.962 * rootCard.lm,
                               (0.137 + 0.020 * rootCard.activeMix) * (1 - rootCard.lm) + rootCard.bgBottom.b * 0.962 * rootCard.lm,
                               0.94 * (1 - rootCard.lm) + 0.97 * rootCard.lm)
            }
        }
        border.width: 1
        border.color: Qt.rgba(1.0, 1.0, 1.0, (0.17 + 0.12 * rootCard.activeMix) * (1 - rootCard.lm) + (0.26 + 0.10 * rootCard.activeMix) * rootCard.lm)
    }

    // ------------------------------------------------------------------
    // 3. GRAPHICS LAYER: full card, clipped to the rounded corners (things may bleed off the edge)
    // ------------------------------------------------------------------
    Item {
        id: bleedLayer
        anchors.fill: parent
        z: 2
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bleedMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // design box: 1.69 : 1 (the proportions of the reference card), glued to the right edge
        // (or centred), so graphics keep their shape on wide cards too
        Item {
            id: designBox
            width: Math.min(rootCard.width, rootCard.height * 1.69)
            height: rootCard.height
            x: rootCard.centerDesign ? (rootCard.width - width) / 2 : rootCard.width - width
            opacity: rootCard.centerDesign ? 1.0 : rootCard.wideMix
        }
    }
    Item {
        id: bleedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: rootCard.cornerR; color: "#000000" }
    }

    // legacy inset area (not used by the new cards)
    Item {
        id: graphicArea
        anchors.right: parent.right
        anchors.rightMargin: Math.round(11 * rootCard.u)
        anchors.top: parent.top
        anchors.topMargin: Math.round(30 * rootCard.u)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(8.4 * rootCard.u)
        width: (rootCard.width - 40 * rootCard.u) * 0.45
        z: 2
    }

    // ------------------------------------------------------------------
    // 4. "..." DOTS (top right, bright white)
    // ------------------------------------------------------------------
    Row {
        id: dots
        anchors.right: parent.right
        anchors.rightMargin: rootCard.padX
        y: Math.round(rootCard.height * 0.13 - height / 2)
        spacing: Math.max(2, Math.round(3.2 * rootCard.u))
        z: 5
        Repeater {
            model: 3
            delegate: Rectangle {
                width: Math.max(2, Math.round(3 * rootCard.u))
                height: width
                radius: width / 2
                color: rootCard.cDots
            }
        }
    }

    // ------------------------------------------------------------------
    // 5. TEXT: title block (top), value, bottom block
    // ------------------------------------------------------------------
    Item {
        id: textCol
        visible: rootCard.showTextColumn
        anchors.fill: parent
        z: 3

        // half-moon icon (Weather)
        Shape {
            id: moonIcon
            visible: rootCard.titleMoon
            x: rootCard.padX
            y: Math.round(rootCard.height * 0.175 - height / 2)
            width: Math.round(11 * rootCard.u); height: width
            layer.enabled: visible
            layer.samples: 4
            ShapePath {
                strokeColor: rootCard.cIcon
                strokeWidth: Math.max(1, rootCard.u)
                fillColor: rootCard.cIcon
                PathAngleArc {
                    centerX: moonIcon.width / 2; centerY: moonIcon.height / 2
                    radiusX: moonIcon.width / 2 - 1; radiusY: moonIcon.height / 2 - 1
                    startAngle: 90; sweepAngle: 180
                }
            }
            ShapePath {
                strokeColor: rootCard.cIcon
                strokeWidth: Math.max(1, rootCard.u)
                fillColor: "transparent"
                PathAngleArc {
                    centerX: moonIcon.width / 2; centerY: moonIcon.height / 2
                    radiusX: moonIcon.width / 2 - 1; radiusY: moonIcon.height / 2 - 1
                    startAngle: 0; sweepAngle: 360
                }
            }
        }

        // ---- top block: bold title (+ caption under it for Depth / Wind style)
        Column {
            id: topBlock
            visible: !rootCard.titleAtBottom && (rootCard.title !== "" || (rootCard.subtitleAtTop && rootCard.subtitle !== ""))
            x: rootCard.padX + (rootCard.titleMoon ? Math.round(16 * rootCard.u) : 0)
            y: Math.round(rootCard.height * 0.175 - titleText.height / 2)
            width: rootCard.innerW * (0.60 + 0.34 * (1 - rootCard.wideMix))
            spacing: Math.round(2 * rootCard.u)

            Text {
                id: titleText
                visible: text !== ""
                width: parent.width
                text: rootCard.title
                color: rootCard.cTitle
                font.pixelSize: Math.round(12 * rootCard.u)
                font.weight: Font.DemiBold
                font.family: rootCard.fontText
                elide: Text.ElideRight
            }

            Text {
                id: topCaption
                visible: rootCard.subtitleAtTop && text !== ""
                x: -(rootCard.titleMoon ? Math.round(16 * rootCard.u) : 0)
                width: parent.width
                textFormat: Text.StyledText
                text: rootCard.subtitleAtTop ? rootCard.rich(rootCard.subtitle) : ""
                color: rootCard.cSoft
                font.pixelSize: Math.round(10 * rootCard.u)
                font.weight: Font.Light
                font.family: rootCard.fontText
                lineHeight: 1.18
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        // ---- big light-weight value + baseline-locked unit
        Item {
            id: valueRow
            visible: rootCard.primaryValue !== ""
            readonly property bool degreeInline: rootCard.unit === "°"
            readonly property real unitExtra: unitVal.visible
                ? unitVal.implicitWidth + unitVal.gap + (degMark.visible ? degMark.implicitWidth * 0.5 : 0) : 0
            readonly property real maxW: rootCard.valueCentered ? rootCard.innerW * 0.86 : rootCard.innerW * (0.58 + 0.34 * (1 - rootCard.wideMix))

            width: mainVal.contentWidth + unitExtra
            height: mainVal.height
            x: rootCard.valueCentered ? Math.round((rootCard.width - width) / 2) : rootCard.padX
            y: (rootCard.valueCentered || rootCard.subtitleAtTop)
               ? Math.round(rootCard.height * rootCard.valueCenterY - height / 2)
               : Math.round(rootCard.height * 0.18)

            Text {
                id: mainVal
                anchors.left: parent.left
                anchors.top: parent.top
                // width is reserved for the unit, so the number can never run into it
                width: Math.max(1, valueRow.maxW - valueRow.unitExtra)
                // a bare degree sign is part of the number (15°), same size, like the reference
                text: rootCard.primaryValue + (valueRow.degreeInline ? "°" : "")
                color: rootCard.valueColor
                font.pixelSize: Math.round(rootCard.valueSize * rootCard.u)
                font.weight: Font.Light
                font.family: rootCard.fontNum
                font.letterSpacing: -0.8 * rootCard.u
                wrapMode: Text.NoWrap
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.round(22 * rootCard.u)
            }

            // "°F" style units: degree mark near the cap line, the letter on the baseline
            Text {
                id: degMark
                visible: unitVal.raised && rootCard.primaryValue !== ""
                text: "°"
                color: rootCard.cUnit
                font.pixelSize: unitVal.font.pixelSize
                font.weight: Font.Normal
                font.family: rootCard.fontNum
                anchors.baseline: mainVal.baseline
                anchors.baselineOffset: -0.72 * Math.max(0, mainVal.fontInfo.pixelSize - font.pixelSize) + 0.18 * 0.72 * mainVal.fontInfo.pixelSize
                anchors.left: mainVal.left
                anchors.leftMargin: mainVal.contentWidth + unitVal.gap
            }

            Text {
                id: unitVal
                readonly property real gap: Math.round(3 * rootCard.u)
                readonly property bool raised: rootCard.unit.length > 1 && rootCard.unit.charAt(0) === "°"
                visible: rootCard.unit !== "" && rootCard.primaryValue !== "" && !valueRow.degreeInline
                text: raised ? rootCard.unit.slice(1) : rootCard.unit
                color: rootCard.cUnit
                font.pixelSize: Math.round(rootCard.valueSize * (raised ? 0.34 : 0.42) * rootCard.u)
                font.weight: Font.Normal
                font.family: rootCard.fontNum
                // STRICT BASELINE LOCK to the big number (ft, kts, F ...)
                anchors.baseline: mainVal.baseline
                anchors.baselineOffset: raised ? -0.08 * mainVal.fontInfo.pixelSize : 0
                anchors.left: mainVal.left
                anchors.leftMargin: mainVal.contentWidth + gap + (raised ? degMark.implicitWidth * 0.5 : 0)
            }
        }

        // ---- bottom block: bold line + light lines (values in bold)
        Column {
            id: bottomBlock
            visible: boldText.text !== "" || lightLines.text !== ""
            x: rootCard.padX
            anchors.bottom: parent.bottom
            anchors.bottomMargin: rootCard.padBottom
            width: rootCard.innerW * (0.56 + 0.38 * (1 - rootCard.wideMix))
            spacing: Math.round(2 * rootCard.u)

            Text {
                id: boldText
                visible: text !== ""
                width: parent.width
                text: rootCard.boldLine
                color: rootCard.cTitle
                font.pixelSize: Math.round(12 * rootCard.u)
                font.weight: Font.DemiBold
                font.family: rootCard.fontText
                elide: Text.ElideRight
            }

            Text {
                id: lightLines
                visible: text !== ""
                width: parent.width
                textFormat: Text.StyledText
                text: rootCard.rich(rootCard.lightText)
                color: rootCard.cSoft
                font.pixelSize: Math.round(10.5 * rootCard.u)
                font.weight: Font.Light
                font.family: rootCard.fontText
                lineHeight: 1.2
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }
}
