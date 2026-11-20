import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick3D
import QtQuick3D.Helpers
import Qt5Compat.GraphicalEffects
import Qt5Compat.GraphicalEffects as GE

Item {
    id: mapRoot
    anchors.fill: parent

    // ---- SPLIT / MISSION-PLAN mode --------------------------------------------------------------
    // splitT: 0 = full screen (normal), 1 = this view lives in the left third next to the mission map.
    // Everything that depends on the width is interpolated on splitT, so the transition is one smooth morph.
    property real splitT: 0.0
    readonly property bool compact: splitT > 0.5
    readonly property real designW: 1920.0 - 1280.0 * splitT          // the width the layout is designed for
    readonly property real sf: Math.min(Math.max(Math.min(width / designW, height / 1080.0), 0.75), 1.65)

    property real scrollPos: 3.0
    property int currentIndex: 3
    readonly property int maxIndex: 8
    readonly property real cardW: Math.round(width * 0.161)
    readonly property real cardH: Math.round(height * 0.175)
    readonly property real cardSpacing: Math.round(cardW * 0.07)
    readonly property real peekScale: 0.78
    readonly property real cardTopY: Math.round(height * 0.142)

    // ---- ENVIRONMENT (matched to the Neuboat reference) --------------------
    // The horizon sits at horizonFrac of the screen height. The 3D camera pitch is
    // derived from it, so the 2D sky / mountains and the 3D water always line up.
    readonly property real horizonFrac: 0.431
    readonly property real horizonY: height * horizonFrac
    readonly property real camFovV: 60.0
    readonly property real camPitchDeg: Math.atan((1.0 - 2.0 * horizonFrac) * Math.tan(camFovV * Math.PI / 360.0)) * 180.0 / Math.PI

    // =====================================================================
    // THEME:  lightMode (bool, set by Main.qml / the toggle)  ->  lm (0..1, animated)
    //   0 = night look (deep indigo sky, charcoal water)
    //   1 = Neuboat DAY look (teal-to-peach sky, pale blue-grey water, frosted-glass cards)
    // Every colour below is mixed on `lm`, so the switch is one smooth cross-fade.
    // =====================================================================
    property bool lightMode: false
    property real lm: lightMode ? 1.0 : 0.0
    property bool themeAnimated: true            // false = switch instantly (screenshots / tests)
    Behavior on lm { enabled: mapRoot.themeAnimated; NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }
    // horizon haze: dark grey (night)  ->  blue-grey of the water at the horizon (day, sampled #98a9b8)
    readonly property color hazeColor: mixc("#5a5f68", "#98a9b8")

    // sky colour of the DAY gradient at a screen position (bilinear on the same grid the sky is drawn from);
    // the cards use it as their frosted-glass fill, so they always match the sky right behind them
    readonly property var skyRGB: {
        var a = [], d = skyLight.gData;
        for (var i = 0; i < d.length; ++i) { var c = Qt.color(d[i]); a.push([c.r, c.g, c.b]); }
        return a;
    }
    function skyAt(px, py) {
        var cols = skyLight.gCols, rows = skyLight.gRows, g = skyRGB;
        var fx = Math.max(0, Math.min(cols - 1, px / Math.max(1, width) * cols - 0.5));
        var fy = Math.max(0, Math.min(rows - 1, py / Math.max(1, skyLight.height) * rows - 0.5));
        var x0 = Math.floor(fx), y0 = Math.floor(fy), x1 = Math.min(cols - 1, x0 + 1), y1 = Math.min(rows - 1, y0 + 1);
        var tx = fx - x0, ty = fy - y0, o = [0, 0, 0];
        for (var k = 0; k < 3; ++k) {
            var top = g[y0 * cols + x0][k] * (1 - tx) + g[y0 * cols + x1][k] * tx;
            var bot = g[y1 * cols + x0][k] * (1 - tx) + g[y1 * cols + x1][k] * tx;
            o[k] = top * (1 - ty) + bot * ty;
        }
        return Qt.rgba(o[0], o[1], o[2], 1);
    }

    NumberAnimation {
        id: carouselAnim
        target: mapRoot
        property: "scrollPos"
        duration: 300
        easing.type: Easing.OutCubic
    }

    function animateTo(t) {
        carouselAnim.stop();
        carouselAnim.to = t;
        carouselAnim.start();
    }


    // ---- Neuboat card-row layout --------------------------------------
    // Measured from the reference (card = 171 x 105 px @1061 x 600):
    //  * 3 FULL cards in the focus window  [current-1, current, current+1]
    //  * the next 2 cards on the right are NARROW (0.63 of a full card, same height)
    //  * 2 PEEK cards sit behind each end (scaled 0.78 / 0.64, dimmed, half hidden)
    //  * gap between cards = 0.07 x card width
    // Every value is in units of the full card width (cardW) and is interpolated
    // linearly on  rel = index - scrollPos,  so cards grow / shrink while sliding.
    // table index = rel + 4   (rel -4 .. +6)
    readonly property var layX: [-1.66, -1.63, -1.42, -1.07, 0.0, 1.07, 1.955, 2.655, 2.83, 3.08, 3.10]
    readonly property var layW: [ 1.00,  1.00,  1.00,  1.00, 1.0, 1.00, 0.63,  0.63,  1.00, 1.00, 1.00]
    readonly property var layS: [ 0.64,  0.64,  0.78,  1.00, 1.0, 1.00, 1.00,  1.00,  0.78, 0.64, 0.64]
    readonly property var layO: [ 0.00,  0.55,  0.72,  1.00, 1.0, 1.00, 1.00,  1.00,  0.72, 0.55, 0.00]
    readonly property var layZ: [ 2,     3,     4,     10,   12,  10,   8,     8,     4,    3,    2   ]
    readonly property real rowShift: -0.62      // centre card sits 0.62 cards left of screen centre (as in the reference)

    // ---- compact pager: 3 pages x 3 cards (weather page first, as in the Neuboat split view) -----------
    property real pagePos: 0.0
    property int pageIndex: 0
    readonly property var cPage: [1, 1, 0, 2, 2, 0, 0, 2, 1]       // card index -> page
    readonly property var cSlot: [0, 1, 0, 0, 1, 1, 2, 2, 2]       // card index -> slot in the page
    readonly property var cSlotW: [0.39, 0.25, 0.25]                // slot width  (fraction of the pane width)
    readonly property real cMargin: 0.04
    readonly property real cGap: 0.016
    function cSlotLeft(sl) {
        var x = cMargin;
        for (var i = 0; i < sl; ++i) x += cSlotW[i] + cGap;
        return x * width;
    }
    function cCardX(k)  { return cSlotLeft(cSlot[k]) + cSlotW[cSlot[k]] * width / 2 + (cPage[k] - pagePos) * width; }
    function cCardW(k)  { return cSlotW[cSlot[k]] * width; }
    function cCardO(k)  { return Math.max(0.0, 1.0 - Math.abs(cPage[k] - pagePos) * 1.7); }
    NumberAnimation { id: pageAnim; target: mapRoot; property: "pagePos"; duration: 300; easing.type: Easing.OutCubic }
    function goPage(p) {
        pageIndex = Math.max(0, Math.min(2, p));
        pageAnim.stop(); pageAnim.to = pageIndex; pageAnim.start();
    }

    function lay(tbl, k, s) {
        var r = Math.max(-4.0, Math.min(6.0, k - s));
        var f = Math.floor(r);
        if (f >= 6) f = 5;
        var t = r - f;
        var a = tbl[f + 4];
        var b = tbl[f + 5];
        return a + (b - a) * t;
    }

    function mixv(a, b) { return a + (b - a) * splitT; }
    function getCardX(k, s) {
        var n = width / 2.0 + (rowShift + lay(layX, k, s)) * cardW;
        return splitT < 0.001 ? n : mixv(n, cCardX(k));
    }
    function getCardWidth(k, s)   { var n = cardW * lay(layW, k, s); return splitT < 0.001 ? n : mixv(n, cCardW(k)); }
    function getCardScale(k, s)   { var n = lay(layS, k, s); return splitT < 0.001 ? n : mixv(n, 1.0); }
    function getCardOpacity(k, s) { var n = lay(layO, k, s); return splitT < 0.001 ? n : mixv(n, cCardO(k)); }
    function getCardZ(k, s)       { var n = Math.round(lay(layZ, k, s)); return splitT < 0.5 ? n : 10; }

    // =====================================================================
    // ENVIRONMENT BACKDROP  (drawn behind the transparent 3D view)
    // violet zenith -> slate -> grey haze at the horizon, pixel-mosaic sky,
    // layered hazy mountains.
    // =====================================================================
    Item {
        id: envBackdrop
        anchors.fill: parent

        Rectangle {
            id: skyRect
            x: 0
            y: 0
            width: parent.width
            height: mapRoot.horizonY + Math.round(10 * mapRoot.sf)
            readonly property real k: mapRoot.horizonY / height
            gradient: Gradient {
                GradientStop { position: 0.00 * skyRect.k; color: "#160f20" }
                GradientStop { position: 0.13 * skyRect.k; color: "#161122" }
                GradientStop { position: 0.25 * skyRect.k; color: "#1a1729" }
                GradientStop { position: 0.32 * skyRect.k; color: "#1a1b2d" }
                GradientStop { position: 0.39 * skyRect.k; color: "#252735" }
                GradientStop { position: 0.52 * skyRect.k; color: "#272d39" }
                GradientStop { position: 0.65 * skyRect.k; color: "#292e3a" }
                GradientStop { position: 0.71 * skyRect.k; color: "#2b3140" }
                GradientStop { position: 0.77 * skyRect.k; color: "#373e4b" }
                GradientStop { position: 0.84 * skyRect.k; color: "#454e57" }
                GradientStop { position: 0.90 * skyRect.k; color: "#565c64" }
                GradientStop { position: 0.97 * skyRect.k; color: "#5f6468" }
                GradientStop { position: 1.00 * skyRect.k; color: "#5d6065" }
                GradientStop { position: 1.00;             color: "#5d6065" }
            }
        }


        // ---- LIGHT SKY: a 9 x 30 colour grid measured from the Neuboat day screenshot,
        // scaled up with linear filtering = a smooth 2D gradient (teal zenith, peach-white band,
        // pink haze at the horizon, cooler on the left / warmer on the right, darker corners).
        Item {
            id: skyLight
            x: 0
            y: 0
            width: skyRect.width
            height: skyRect.height
            opacity: mapRoot.lm
            visible: opacity > 0.002
            readonly property int gCols: 9
            readonly property int gRows: 30
            readonly property var gData: [
            "#556770", "#617d8b", "#61879c", "#648a9f", "#6f95a7", "#7e9ead", "#88a4af", "#85959c", "#757d7f",
            "#5b6e78", "#678698", "#668ba0", "#698fa5", "#7499ab", "#83a2b0", "#90a9b3", "#90a2a9", "#7e8588",
            "#60737d", "#6e8b9e", "#6a8fa5", "#6c93a8", "#7b9dae", "#88a6b4", "#96aeb8", "#99a9b0", "#868c8f",
            "#60727b", "#718fa3", "#7095aa", "#7095aa", "#7699ae", "#a3b7be", "#a3b7be", "#a2b1b7", "#8f9294",
            "#64767f", "#7798ac", "#759aae", "#759aae", "#7f9eb5", "#a9bcc3", "#a9bcc3", "#acb7bd", "#96989a",
            "#6a7b84", "#7f9fb3", "#7d9eb2", "#7d9eb2", "#81a1b5", "#b2c2c9", "#b2c2c9", "#b4bec2", "#9e9f9f",
            "#6e8089", "#83a4b7", "#81a2b6", "#81a2b6", "#85a7b9", "#bbc6cd", "#bbc6cd", "#bcc3c7", "#a5a4a5",
            "#74858f", "#89a7ba", "#87a8bb", "#87a8bb", "#8babbe", "#c2cbd2", "#c2cbd2", "#c5c9cc", "#adabab",
            "#7e919e", "#8ba8b9", "#8bacbf", "#8eaec0", "#99b7c4", "#aec2cc", "#c5cdd4", "#cacdd0", "#b3b0af",
            "#8496a2", "#8faaba", "#8daec0", "#8fb0c1", "#9bb8c6", "#b1c4ce", "#c6cfd5", "#cdcdce", "#bab6b5",
            "#889aa7", "#93acbb", "#93b3c5", "#94b4c6", "#a0bbca", "#b4c7cf", "#b4c7cf", "#d0cfcf", "#bebab8",
            "#8fa0ac", "#97afbf", "#95b6c6", "#95b6c7", "#a5bfcd", "#b8cad3", "#b8cad3", "#d2d1cf", "#c1bdba",
            "#95a5b0", "#99b1c0", "#9abacb", "#96bbca", "#aac2cf", "#bfccd6", "#bfccd6", "#d0d0d0", "#c5c1bd",
            "#9aa9b3", "#9bb3c2", "#9ebdce", "#a0becf", "#b0c8d4", "#c2d0d8", "#c2d0d8", "#cecfd0", "#c8c4c1",
            "#a0aeb8", "#9fb6c4", "#a3c1d0", "#a6c3d1", "#b7ccd6", "#c9d3db", "#c9d3db", "#d1d1d1", "#cbc8c4",
            "#a8b5be", "#a4bac8", "#aac6d3", "#a9c6d2", "#bcd0d9", "#ced6dd", "#ced6dd", "#d3d3d3", "#cfccc8",
            "#adb9c0", "#a8bdca", "#b1c9d7", "#b1cad6", "#c1d2dc", "#d0d7de", "#d0d7de", "#d4d5d5", "#d2cecb",
            "#b1bbc3", "#adc0cc", "#b9cfda", "#b9cfd9", "#cad7df", "#d5dbe0", "#d5dbe0", "#d5d7d6", "#d4d1ce",
            "#b7c0c6", "#b0c2cd", "#c3d4de", "#c0d3de", "#d0dae2", "#dcdee2", "#dcdee2", "#d6d8d6", "#d7d3d0",
            "#bec2c7", "#bac7d1", "#dadbe0", "#dadce1", "#d4dce3", "#dfe0e3", "#dfe0e3", "#dadcdb", "#d9d6d2",
            "#bdc0c8", "#cdcfd5", "#d5dae1", "#d5dae1", "#dfe1e3", "#e0e2e1", "#e0e2e1", "#e6e4df", "#ddd9d4",
            "#bfc2ca", "#d3d2d8", "#e3e3e5", "#e4e2e4", "#e3e3e3", "#e3e1e2", "#e3e1e2", "#e8e6e1", "#dedbd6",
            "#c6c4cb", "#d4d4db", "#dedee3", "#e1e1e4", "#eae6e4", "#f0e8e6", "#f0eae7", "#e8e7e2", "#dddbd6",
            "#c3c2c9", "#dad9de", "#dbdce2", "#e2e0e3", "#ece5e3", "#f0e8e6", "#f0e9e6", "#ece9e5", "#dddbd6",
            "#bec0c9", "#d4d3da", "#dcdbe0", "#e4e0e2", "#ece3e2", "#efe6e4", "#efe7e5", "#ece8e3", "#dcd9d3",
            "#c2c4cb", "#cfd2db", "#d5d7df", "#dddce1", "#e8e0e0", "#efe3e2", "#efe5e3", "#ece4e1", "#ded7d2",
            "#bbbec7", "#ced1da", "#d0d4dd", "#d8d7df", "#dfdbe0", "#e5dee0", "#ebdfdf", "#ebe0de", "#ddd2cf",
            "#bebec6", "#cbced7", "#ced1db", "#d5d4dd", "#ddd8de", "#e5dcde", "#e8dcdd", "#e7dcdb", "#d9cecc",
            "#bebdc4", "#cecdd4", "#d1d0d8", "#d8d2da", "#dfd5da", "#e4d8db", "#e8dada", "#e7dad9", "#d7cacb",
            "#b0b7c0", "#c2c6d1", "#c9ccd6", "#d5d0d7", "#dcd3d9", "#dfd5d9", "#e2d6d8", "#e1d6d8", "#d2c8cb"
            ]
            Item {
                id: skyLightTex
                width: skyLight.gCols
                height: skyLight.gRows
                Repeater {
                    model: skyLight.gCols * skyLight.gRows
                    delegate: Rectangle {
                        x: index % skyLight.gCols
                        y: Math.floor(index / skyLight.gCols)
                        width: 1
                        height: 1
                        color: skyLight.gData[index]
                    }
                }
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: skyLightTex
                hideSource: true
                live: true
                smooth: true
                textureSize: Qt.size(skyLight.gCols, skyLight.gRows)
                wrapMode: ShaderEffectSource.ClampToEdge
            }
        }

        // fallback water tone (the 3D water plane covers it; this only guards seams)
        Rectangle {
            opacity: 1.0 - mapRoot.lm
            x: 0
            y: mapRoot.horizonY
            width: parent.width
            height: parent.height - mapRoot.horizonY
            gradient: Gradient {
                GradientStop { position: 0.00; color: "#555a62" }
                GradientStop { position: 0.06; color: "#5a5f66" }
                GradientStop { position: 0.11; color: "#535961" }
                GradientStop { position: 0.15; color: "#474d56" }
                GradientStop { position: 0.22; color: "#3a414c" }
                GradientStop { position: 0.30; color: "#2f3440" }
                GradientStop { position: 0.38; color: "#282d3a" }
                GradientStop { position: 0.48; color: "#242633" }
                GradientStop { position: 0.58; color: "#1f1f2b" }
                GradientStop { position: 0.68; color: "#1c1c26" }
                GradientStop { position: 0.77; color: "#1a1923" }
                GradientStop { position: 1.00; color: "#17161f" }
            }
        }

        Rectangle {
            x: 0
            y: mapRoot.horizonY
            width: parent.width
            height: parent.height - mapRoot.horizonY
            opacity: mapRoot.lm
            gradient: Gradient {
                GradientStop { position: 0.00; color: "#92a5b5" }
                GradientStop { position: 0.14; color: "#a4b7c2" }
                GradientStop { position: 0.30; color: "#aec2c9" }
                GradientStop { position: 1.00; color: "#a6bcc2" }
            }
        }

        // ---- pixel-mosaic sky (top ~21 %), fades out downwards ------------
        Item {
            id: skyMosaic
            x: 0
            y: 0
            width: parent.width
            height: parent.height * 0.21
            readonly property real cell: Math.max(8, Math.round(width / 66.0))
            readonly property int cols: Math.ceil(width / cell) + 1
            readonly property int rows: Math.ceil(height / cell) + 1
            // deterministic pseudo-random 0..1 (same mosaic every launch)
            function rnd(i, j) {
                var s = Math.sin(i * 127.1 + j * 311.7) * 43758.5453;
                return s - Math.floor(s);
            }
            Repeater {
                model: skyMosaic.cols * skyMosaic.rows
                delegate: Rectangle {
                    readonly property int ci: index % skyMosaic.cols
                    readonly property int cj: Math.floor(index / skyMosaic.cols)
                    readonly property real r: skyMosaic.rnd(ci + 3, cj + 7)
                    readonly property real fade: Math.max(0.0, 1.0 - (cj * skyMosaic.cell) / skyMosaic.height)
                    visible: r >= 0.40 && fade > 0.0
                    x: ci * skyMosaic.cell + 1
                    y: cj * skyMosaic.cell + 1
                    width: skyMosaic.cell - 2
                    height: skyMosaic.cell - 2
                    color: Qt.rgba((120 + 135 * mapRoot.lm) / 255, (125 + 130 * mapRoot.lm) / 255, (190 + 65 * mapRoot.lm) / 255,
                                   (0.034 - 0.017 * mapRoot.lm) * fade * (0.55 + 0.9 * r))
                }
            }
        }

        // ---- distant mountains: three hazy layers, base melts into the horizon ----
        // pts = [x as fraction of width, height as fraction of screen height]
        component Ridge: Shape {
            id: ridgeShape
            property var pts: []
            property color tint: "#969fa0"
            property real aTop: 0.1
            property real aBot: 0.05
            property real peak: 0.07
            property real hs: 1.0      // vertical scale of the ridge heights
            readonly property real dayFade: 1.0 - 0.90 * mapRoot.lm            // ridges nearly dissolve in the day look
            readonly property color tintNow: mapRoot.mixc(tint, "#b9bfcf")
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            preferredRendererType: Shape.GeometryRenderer

            function smooth() {
                var W = width, H = height, hy = mapRoot.horizonY, out = [];
                var P = pts;
                if (!P || P.length < 3) return out;
                out.push(Qt.point(P[0][0] * W, hy + 8));
                out.push(Qt.point(P[0][0] * W, hy - P[0][1] * H * hs));
                var sx = P[0][0] * W, sy = hy - P[0][1] * H * hs;
                for (var i = 1; i < P.length - 1; ++i) {
                    var cx = P[i][0] * W, cy = hy - P[i][1] * H * hs;
                    var mx = (P[i][0] + P[i + 1][0]) * 0.5 * W;
                    var my = hy - (P[i][1] + P[i + 1][1]) * 0.5 * H * hs;
                    for (var t = 1; t <= 8; ++t) {
                        var u = t / 8.0, v = 1.0 - u;
                        out.push(Qt.point(v * v * sx + 2 * v * u * cx + u * u * mx,
                                          v * v * sy + 2 * v * u * cy + u * u * my));
                    }
                    sx = mx; sy = my;
                }
                var last = P[P.length - 1];
                out.push(Qt.point(last[0] * W, hy - last[1] * H * hs));
                out.push(Qt.point(last[0] * W, hy + 8));
                return out;
            }

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: Qt.rgba(ridgeShape.tintNow.r, ridgeShape.tintNow.g, ridgeShape.tintNow.b, (ridgeShape.aTop + ridgeShape.aBot) * 0.5 * ridgeShape.dayFade)
                PathPolyline { path: ridgeShape.smooth() }
            }
        }

        Ridge {
            tint: "#7d868c"; aTop: 0.12; aBot: 0.06; peak: 0.075
            pts: [[0.00,0.062],[0.03,0.050],[0.07,0.020],[0.11,0.004],[0.30,0.006],[0.35,0.037],[0.39,0.056],
                  [0.425,0.072],[0.47,0.054],[0.50,0.041],[0.52,0.034],[0.60,0.025],[0.70,0.010],[0.83,0.020],
                  [0.88,0.037],[0.915,0.0455],[0.95,0.049],[0.98,0.0455],[1.00,0.040]]
        }
        Ridge {
            tint: "#7d868c"; aTop: 0.15; aBot: 0.07; peak: 0.05
            pts: [[0.095,0.000],[0.13,0.021],[0.15,0.032],[0.175,0.039],[0.20,0.030],[0.225,0.021],[0.25,0.009],
                  [0.265,0.000],[0.50,0.000],[0.53,0.019],[0.56,0.035],[0.59,0.0455],[0.62,0.0495],[0.65,0.040],
                  [0.69,0.032],[0.72,0.024],[0.745,0.019],[0.78,0.021],[0.80,0.026],[0.825,0.024],[0.85,0.026],
                  [0.88,0.037],[0.915,0.0455],[0.95,0.049],[1.00,0.040]]
        }
        Ridge {
            tint: "#2c323a"; aTop: 0.17; aBot: 0.17; peak: 0.04; hs: 0.50
            pts: [[0.00,0.062],[0.03,0.050],[0.07,0.020],[0.11,0.004],[0.30,0.006],[0.35,0.037],[0.39,0.056],
                  [0.425,0.072],[0.47,0.054],[0.50,0.041],[0.52,0.034],[0.60,0.025],[0.70,0.010],[0.83,0.020],
                  [0.88,0.037],[0.915,0.0455],[0.95,0.049],[0.98,0.0455],[1.00,0.040]]
        }
        Ridge {
            tint: "#2c323a"; aTop: 0.17; aBot: 0.17; peak: 0.03; hs: 0.50
            pts: [[0.095,0.000],[0.13,0.021],[0.15,0.032],[0.175,0.039],[0.20,0.030],[0.225,0.021],[0.25,0.009],
                  [0.265,0.000],[0.50,0.000],[0.53,0.019],[0.56,0.035],[0.59,0.0455],[0.62,0.0495],[0.65,0.040],
                  [0.69,0.032],[0.72,0.024],[0.745,0.019],[0.78,0.021],[0.80,0.026],[0.825,0.024],[0.85,0.026],
                  [0.88,0.037],[0.915,0.0455],[0.95,0.049],[1.00,0.040]]
        }
        Ridge {
            tint: "#282c34"; aTop: 0.30; aBot: 0.05; peak: 0.009
            pts: [[0.33,0.000],[0.345,0.0035],[0.38,0.007],[0.435,0.008],[0.48,0.0035],[0.50,0.000]]
        }
    }

    // Neuboat-style traffic contact: smooth white motor yacht with dark glass.
    // assets/meshes/contactYacht_mesh.mesh   slots: 0 hull + superstructure, 1 glass, 2 deck / trim
    component ContactYachtModel: Model {
        source: "assets/meshes/contactYacht_mesh.mesh"
        castsShadows: true
        receivesShadows: false
        materials: [
            PrincipledMaterial {
                lighting: PrincipledMaterial.FragmentLighting
                baseColor: "#F6F8FB"
                metalness: 0.0
                roughness: 0.34
                specularAmount: 0.7
                cullMode: Material.NoCulling
            },
            PrincipledMaterial {
                lighting: PrincipledMaterial.FragmentLighting
                baseColor: "#0B111B"
                metalness: 0.65
                roughness: 0.07
                specularAmount: 1.0
                cullMode: Material.NoCulling
            },
            PrincipledMaterial {
                lighting: PrincipledMaterial.FragmentLighting
                baseColor: "#B9BEC8"
                metalness: 0.0
                roughness: 0.55
                cullMode: Material.NoCulling
            }
        ]
    }

    // ---- colours of the 3D navigation path (night -> day through lm) --------------------------
    // reference (Neuboat) night values: blue #3473B8, green #00AE89, corridor = light grey-blue veil.
    // The numbers below are the texture inputs that come out as exactly those colours on screen.
    function navBlue(a)  { return mixc(Qt.rgba(0.19, 0.44, 0.73, a), Qt.rgba(0.30, 0.42, 0.63, a * 0.85)); }
    function navGreen()  { return mixc(Qt.rgba(0.00, 0.70, 0.55, 0.97), Qt.rgba(0.30, 0.68, 0.58, 0.95)); }
    function navCorr(a)  { return mixc(Qt.rgba(0.60, 0.65, 0.76, a), Qt.rgba(0.36, 0.42, 0.50, a * 0.55)); }

    View3D {
        id: tacticalScene3D
        anchors.fill: parent
        camera: mapCamera

        environment: SceneEnvironment {
            // transparent: the sky, haze and mountains are the 2D backdrop behind this view
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            // the reflection / ambient probe switches with the theme (regenerated once per switch)
            lightProbe: Texture {
                textureData: ProceduralSkyTextureData {
                    skyTopColor: mapRoot.lightMode ? "#a9b9c2" : "#1b1d2e"
                    skyHorizonColor: mapRoot.lightMode ? "#e9e1e1" : "#5d6065"
                    groundHorizonColor: mapRoot.lightMode ? "#c3cacc" : "#5d6065"
                    groundBottomColor: mapRoot.lightMode ? "#a5aeb1" : "#1c1a28"
                    skyEnergy: mapRoot.lightMode ? 0.9 : 1.0
                    groundEnergy: mapRoot.lightMode ? 0.55 : 0.7
                    sunEnergy: 0.0
                }
            }
            // depth fog = the horizon gradient: dark indigo water near the camera -> grey haze at the horizon
            fog: Fog {
                enabled: true
                color: mapRoot.hazeColor
                depthEnabled: true
                depthNear: 22
                depthFar: 360
                depthCurve: 0.75
            }
        }

        PerspectiveCamera {
            id: mapCamera
            position: Qt.vector3d(0, 18, 58)
            // pitch comes from horizonFrac so the 3D horizon lands exactly on the 2D one
            eulerRotation.x: -mapRoot.camPitchDeg
            fieldOfView: mapRoot.camFovV
            clipNear: 1
            clipFar: 5000
        }

        DirectionalLight {
            id: mainSunLight
            eulerRotation.x: -35
            eulerRotation.y: 35
            color: "#FFFFFF"
            ambientColor: mapRoot.mixc("#2a3040", "#707c86")
            brightness: 1.1 - 0.15 * mapRoot.lm
            castsShadow: true
            shadowMapQuality: Light.ShadowMapQualityHigh
            shadowFilter: 6.0
            shadowFactor: 40
            shadowBias: 0.005
        }

        Model {
            id: waterPlane
            source: "#Rectangle"
            scale: Qt.vector3d(8000, 8000, 1)
            eulerRotation.x: -90
            y: 0
            receivesShadows: true
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.FragmentLighting
                baseColor: mapRoot.mixc("#1b1c2c", "#aebdbc")
                metalness: 0.0
                roughness: 0.85 + 0.10 * mapRoot.lm
                specularAmount: 0.15 - 0.10 * mapRoot.lm
                cullMode: Material.NoCulling
            }
        }

        // ---- NAVIGATION PATH (Neuboat style) --------------------------------
        // grey corridor around the boat, shiny blue lane AHEAD (fades with distance),
        // green lane BEHIND (distance already covered). All three are flat 3D strips on
        // the water, so they keep perspective and sit under the boat.
        Model {
            id: navCorridor
            source: "#Rectangle"
            y: 0.35
            z: -190                                   // spans z +60 ... -440
            scale: Qt.vector3d(0.112, 5.0, 1.0)       // 11.2 wide x 500 long
            eulerRotation.x: -90
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.NoLighting
                baseColor: "#FFFFFF"
                alphaMode: PrincipledMaterial.Blend
                cullMode: Material.NoCulling
                baseColorMap: Texture {
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                    sourceItem: Rectangle {
                        width: 8; height: 512
                        gradient: Gradient {
                            // flat grey-blue band, lightens the water by ~+18 right in front of the camera, ~+8 beside the boat,
                            // nothing at the far end (measured on the Neuboat reference)
                            GradientStop { position: 0.00; color: mapRoot.navCorr(0.00) }
                            GradientStop { position: 0.38; color: mapRoot.navCorr(0.00) }
                            GradientStop { position: 0.685; color: mapRoot.navCorr(0.02) }
                            GradientStop { position: 0.889; color: mapRoot.navCorr(0.067) }
                            GradientStop { position: 0.932; color: mapRoot.navCorr(0.15) }
                            GradientStop { position: 1.00; color: mapRoot.navCorr(0.17) }
                        }
                    }
                }
            }
        }

        Model {
            id: navPathAhead
            source: "#Rectangle"
            y: 0.45
            z: -208                                   // spans z +4 ... -420
            scale: Qt.vector3d(0.076, 4.24, 1.0)      // 7.6 wide (= boat beam) x 424 long
            eulerRotation.x: -90
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.NoLighting
                baseColor: "#FFFFFF"
                alphaMode: PrincipledMaterial.Blend
                cullMode: Material.NoCulling
                baseColorMap: Texture {
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                    sourceItem: Rectangle {
                        width: 8; height: 512
                        gradient: Gradient {
                            // flat matte blue (#3473B8 on the reference) that is solid next to the bow and
                            // melts into the haze ~2.5x further out; profile measured on the Neuboat reference
                            GradientStop { position: 0.00;  color: mapRoot.navBlue(0.00) }
                            GradientStop { position: 0.731; color: mapRoot.navBlue(0.00) }
                            GradientStop { position: 0.811; color: mapRoot.navBlue(0.09) }
                            GradientStop { position: 0.864; color: mapRoot.navBlue(0.32) }
                            GradientStop { position: 0.902; color: mapRoot.navBlue(0.69) }
                            GradientStop { position: 0.931; color: mapRoot.navBlue(1.00) }
                            GradientStop { position: 1.00;  color: mapRoot.navBlue(1.00) }
                        }
                    }
                }
            }
        }

        Model {
            id: navPathBehind
            source: "#Rectangle"
            y: 0.45
            z: 31                                     // spans z +14 ... +48
            scale: Qt.vector3d(0.076, 0.34, 1.0)      // 7.6 wide x 34 long
            eulerRotation.x: -90
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.NoLighting
                baseColor: "#FFFFFF"
                alphaMode: PrincipledMaterial.Blend
                cullMode: Material.NoCulling
                baseColorMap: Texture {
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                    sourceItem: Rectangle {
                        width: 8; height: 64
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: mapRoot.navGreen() }
                            GradientStop { position: 1.0; color: mapRoot.navGreen() }
                        }
                    }
                }
            }
        }

        // ---- soft shadow under the own boat (visible by day only) ----------------
        Model {
            id: ownBoatShadow
            source: "#Rectangle"
            position: Qt.vector3d(0.9, 0.09, 10.4)
            eulerRotation.x: -90
            scale: Qt.vector3d(0.13, 0.19, 1.0)
            opacity: mapRoot.lm
            visible: mapRoot.lm > 0.01
            castsShadows: false
            receivesShadows: false
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.NoLighting
                baseColor: "#FFFFFF"
                alphaMode: PrincipledMaterial.Blend
                cullMode: Material.NoCulling
                baseColorMap: Texture {
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                    sourceItem: Item {
                        width: 128
                        height: 128
                        // concentric translucent discs = a soft round shadow (no shader needed)
                        Repeater {
                            model: 18
                            delegate: Rectangle {
                                anchors.centerIn: parent
                                width: 128 * (1.0 - index * 0.052)
                                height: width
                                radius: width / 2
                                color: Qt.rgba(0.10, 0.14, 0.17, 0.034)
                            }
                        }
                    }
                }
            }
        }

        // ---- OWN VESSEL: TANDAV stealth USV ----------------------------------
        // assets/meshes/tandavStealth_mesh.mesh   (balsam export of tandavStealth.obj)
        //   material slots: 0 wrapped cap, 1 hull, 2 mast, 3 CI4 sticker, 4 TANDAV sticker
        // The hull is modelled bow = -Z.  If your photos show it facing the other way in the
        // scene, set ownBoatFlip to true (rotates the model 180 deg about the vertical axis).
        Node {
            id: ownVesselNode
            property bool ownBoatFlip: false
            position: Qt.vector3d(0, 0.05, 9.3)
            scale: Qt.vector3d(4.3, 4.3, 4.3)
            eulerRotation.x: (typeof vesselState !== "undefined" && vesselState) ? vesselState.pitch : 0
            eulerRotation.y: ((typeof vesselState !== "undefined" && vesselState) ? ((vesselState.heading - (vesselState.targetHeading || vesselState.heading)) * 0.5) : 0) + (ownBoatFlip ? 180 : 0)
            eulerRotation.z: (typeof vesselState !== "undefined" && vesselState) ? vesselState.roll : 0

            Model {
                id: tandavHull
                source: "assets/meshes/tandavStealth_mesh.mesh"
                castsShadows: true
                receivesShadows: false
                materials: [
                    // 0  glossy black wrapped cap (deck facets, skirt)
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: mapRoot.mixc("#FFFFFF", "#C4C4C4")
                        baseColorMap: Texture {
                            source: "assets/textures/tandav_wrap.png"
                            tilingModeHorizontal: Texture.Repeat
                            tilingModeVertical: Texture.Repeat
                            generateMipmaps: true
                            mipFilter: Texture.Linear
                        }
                        metalness: 0.90
                        roughness: 0.10
                        specularAmount: 1.0
                        cullMode: Material.NoCulling
                    },
                    // 1  dark navy hull body
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#0D1830"
                        metalness: 0.20
                        roughness: 0.42
                        cullMode: Material.NoCulling
                    },
                    // 2  mast + collar
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#0A0B0F"
                        metalness: 0.35
                        roughness: 0.38
                        cullMode: Material.NoCulling
                    },
                    // 3  CI4 sticker
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#FFFFFF"
                        baseColorMap: Texture { source: "assets/textures/ci4_decal.png"; generateMipmaps: true; mipFilter: Texture.Linear }
                        alphaMode: PrincipledMaterial.Blend
                        metalness: 0.0
                        roughness: 0.30
                        cullMode: Material.NoCulling
                    },
                    // 4  TANDAV sticker
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#FFFFFF"
                        baseColorMap: Texture { source: "assets/textures/tandav_decal.png"; generateMipmaps: true; mipFilter: Texture.Linear }
                        alphaMode: PrincipledMaterial.Blend
                        metalness: 0.0
                        roughness: 0.30
                        cullMode: Material.NoCulling
                    },
                    // 5  satin metallic edge band of the cap
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#4A5163"
                        metalness: 1.0
                        roughness: 0.28
                        cullMode: Material.NoCulling
                    }
                ]
            }
        }

        Node {
            id: threatContactsGroup

            Node {
                id: threatNode1
                position: Qt.vector3d(-26, 0.2, -20)
                eulerRotation.y: 40
                scale: Qt.vector3d(1.85, 1.85, 1.85)
                ContactYachtModel { }
            }

            Node {
                id: threatNode2
                position: Qt.vector3d(36, 0.2, -35)
                eulerRotation.y: -75
                scale: Qt.vector3d(1.9, 1.9, 1.9)
                ContactYachtModel { }
            }

            Node {
                id: threatNode3
                position: Qt.vector3d(-38, 0.2, -70)
                eulerRotation.y: 25
                scale: Qt.vector3d(1.4, 1.4, 1.4)
                ContactYachtModel { }
            }

            Node {
                id: threatNode4
                position: Qt.vector3d(26, 0.2, -65)
                eulerRotation.y: -20
                scale: Qt.vector3d(1.3, 1.3, 1.3)
                ContactYachtModel { }
            }

            Node {
                id: threatNode5
                position: Qt.vector3d(-8, 0.2, -100)
                eulerRotation.y: 10
                scale: Qt.vector3d(1.0, 1.0, 1.0)
                ContactYachtModel { }
            }
        }
    }

    // =====================================================================
    // ENVIRONMENT OVERLAY  (above the 3D view): edge vignette + horizon compass strip
    // =====================================================================
    // =====================================================================
    // MISSION-SPLIT HORIZON GLOW  (violet on the left -> teal on the right, sampled from the Neuboat split view)
    // a horizontal colour gradient, masked by a vertical alpha ramp that peaks at the horizon.
    // Only exists while the mission map is open (splitT > 0), so the normal screen costs nothing.
    // =====================================================================
    Item {
        id: splitGlow
        anchors.fill: parent
        z: 1
        visible: mapRoot.splitT > 0.01
        opacity: Math.min(1.0, mapRoot.splitT * 1.4) * (1.0 - 0.45 * mapRoot.lm)

        // 32 thin strips: each has the violet -> teal colour gradient, the alpha grows towards the horizon.
        // (no offscreen mask pass, so it costs almost nothing on the Jetson)
        Repeater {
            model: 32
            delegate: Rectangle {
                readonly property real t: (index + 0.5) / 32.0
                readonly property real a: 0.94 * Math.pow(t, 1.9)
                readonly property real span: mapRoot.height * 0.27 + Math.round(10 * mapRoot.sf)
                x: 0
                width: splitGlow.width
                readonly property real y0: Math.round(mapRoot.horizonY - mapRoot.height * 0.27)
                y: y0 + Math.round(index * span / 32.0)
                height: Math.round((index + 1) * span / 32.0) - Math.round(index * span / 32.0)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: Qt.rgba(0.416, 0.322, 0.635, a) }
                    GradientStop { position: 0.38; color: Qt.rgba(0.361, 0.310, 0.588, a) }
                    GradientStop { position: 0.52; color: Qt.rgba(0.310, 0.541, 0.588, a) }
                    GradientStop { position: 1.00; color: Qt.rgba(0.373, 0.631, 0.651, a) }
                }
            }
        }
        // soft teal bloom just below the horizon line (the water in the reference picks up the glow)
        Rectangle {
            x: 0
            width: parent.width
            y: mapRoot.horizonY
            height: mapRoot.height * 0.10
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2a63c3c3" }
                GradientStop { position: 1.0; color: "#0063c3c3" }
            }
        }
    }

    Item {
        id: envOverlay
        anchors.fill: parent
        z: 2

        // DAY vignette (water only; the sky grid already carries its own dark corners):
        // an elliptical radial falloff, warm-grey (70,70,72), alpha 0 inside r = 0.84 -> 0.62 in the corners
        Item {
            x: 0
            y: mapRoot.horizonY
            width: parent.width
            height: parent.height - mapRoot.horizonY
            clip: true
            opacity: mapRoot.lm
            visible: opacity > 0.002
            GE.RadialGradient {
                x: 0
                y: -mapRoot.horizonY
                width: mapRoot.width
                height: mapRoot.height
                horizontalRadius: mapRoot.width * 0.5 * 1.32
                verticalRadius: mapRoot.height * 0.5 * 1.32
                gradient: Gradient {
                    GradientStop { position: 0.00; color: Qt.rgba(0.275, 0.275, 0.282, 0.0) }
                    GradientStop { position: 0.63; color: Qt.rgba(0.275, 0.275, 0.282, 0.0) }
                    GradientStop { position: 0.76; color: Qt.rgba(0.275, 0.275, 0.282, 0.19) }
                    GradientStop { position: 0.89; color: Qt.rgba(0.275, 0.275, 0.282, 0.43) }
                    GradientStop { position: 1.00; color: Qt.rgba(0.275, 0.275, 0.282, 0.62) }
                }
            }
        }

        // DAY horizon glow: the reference water is warmer / greyer on the right (reflected peach sky)
        // and a touch cooler on the left. Two soft elliptical washes, water only.
        Item {
            x: 0
            y: mapRoot.horizonY
            width: parent.width
            height: parent.height - mapRoot.horizonY
            clip: true
            opacity: mapRoot.lm
            visible: opacity > 0.002
            GE.RadialGradient {
                width: mapRoot.width * 1.07
                height: mapRoot.height * 1.04
                x: mapRoot.width - width / 2
                y: 44 * mapRoot.height / 1080 - height / 2
                horizontalRadius: width / 2
                verticalRadius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.00; color: Qt.rgba(0.867, 0.80, 0.76, 0.50) }
                    GradientStop { position: 1.00; color: Qt.rgba(0.867, 0.80, 0.76, 0.0) }
                }
            }
            GE.RadialGradient {
                width: mapRoot.width * 0.68
                height: mapRoot.height * 0.28
                x: -width / 2
                y: 17 * mapRoot.height / 1080 - height / 2
                horizontalRadius: width / 2
                verticalRadius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.00; color: Qt.rgba(0.46, 0.56, 0.64, 0.35) }
                    GradientStop { position: 1.00; color: Qt.rgba(0.46, 0.56, 0.64, 0.0) }
                }
            }
        }

        // soft side vignette below the horizon (night look)
        Rectangle {
            opacity: 1.0 - mapRoot.lm
            x: 0
            y: mapRoot.horizonY
            width: parent.width * 0.20
            height: parent.height - mapRoot.horizonY
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.16) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }
        Rectangle {
            opacity: 1.0 - mapRoot.lm
            x: parent.width * 0.80
            y: mapRoot.horizonY
            width: parent.width * 0.20
            height: parent.height - mapRoot.horizonY
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.16) }
            }
        }

        // horizon compass strip (heading-driven): a short tick every 10 degrees hanging
        // from the horizon line, a labelled mark at every 45 degrees, tall thin line for N
        Item {
            id: horizonCompass
            anchors.fill: parent

            readonly property real hdg: (typeof vesselState !== "undefined" && vesselState && vesselState.heading !== undefined) ? vesselState.heading : 0
            readonly property real u: mapRoot.width / mapRoot.designW
            readonly property real ppd: 16.0 * u
            readonly property real hy: Math.round(mapRoot.horizonY)
            readonly property var names: ({ "0": "N", "45": "NE", "90": "E", "135": "SE", "180": "S", "225": "SW", "270": "W", "315": "NW" })

            Rectangle {
                x: 0
                y: horizonCompass.hy - 1
                width: parent.width
                height: 2
                color: mapRoot.mixc(Qt.rgba(1, 1, 1, 0.17), Qt.rgba(0.35, 0.42, 0.50, 0.62))
            }

            // 10-degree ticks
            Repeater {
                model: Math.ceil(mapRoot.width / (10 * horizonCompass.ppd)) + 3
                delegate: Rectangle {
                    readonly property real bearing: (Math.floor(horizonCompass.hdg / 10.0) + index - Math.floor(Math.ceil(mapRoot.width / (10 * horizonCompass.ppd)) / 2 + 1)) * 10
                    x: horizonCompass.width / 2 + (bearing - horizonCompass.hdg) * horizonCompass.ppd - width / 2
                    y: horizonCompass.hy - 1
                    width: Math.max(1, Math.round(1.8 * horizonCompass.u))
                    height: Math.round(11 * horizonCompass.u)
                    color: mapRoot.mixc(Qt.rgba(1, 1, 1, 0.78), Qt.rgba(0.30, 0.36, 0.40, 0.88))
                }
            }

            // 45-degree labels
            Repeater {
                model: 9
                delegate: Item {
                    readonly property real bearing: (Math.floor(horizonCompass.hdg / 45.0) + index - 4) * 45
                    readonly property int deg: ((Math.round(bearing) % 360) + 360) % 360
                    readonly property bool north: deg === 0
                    readonly property real tx: horizonCompass.width / 2 + (bearing - horizonCompass.hdg) * horizonCompass.ppd

                    Rectangle {
                        visible: parent.north
                        x: parent.tx - width / 2
                        y: horizonCompass.hy - height
                        width: Math.max(1, Math.round(1.6 * horizonCompass.u))
                        height: Math.round(29 * horizonCompass.u)
                        color: mapRoot.mixc(Qt.rgba(1, 1, 1, 0.42), Qt.rgba(0.35, 0.35, 0.40, 0.50))
                    }
                    Text {
                        text: horizonCompass.names[String(parent.deg)] !== undefined ? horizonCompass.names[String(parent.deg)] : ""
                        color: mapRoot.mixc(Qt.rgba(0.80, 0.82, 0.86, parent.north ? 0.80 : 0.50),
                                            parent.north ? Qt.rgba(0.17, 0.17, 0.20, 0.88) : Qt.rgba(0.33, 0.35, 0.41, 0.70))
                        font.pixelSize: Math.round((parent.north ? 21 : 15) * horizonCompass.u)
                        x: parent.tx - width / 2
                        y: parent.north ? horizonCompass.hy - Math.round(29 * horizonCompass.u) - height - Math.round(1 * horizonCompass.u)
                                        : horizonCompass.hy - Math.round(22 * horizonCompass.u) - height / 2
                    }
                }
            }
        }
    }

    Item {
        id: threat1Badge
        property var screenPos: tacticalScene3D.mapFrom3DScene(threatNode1.scenePosition)
        x: screenPos ? Math.round(screenPos.x - width / 2) : -1000
        y: screenPos ? Math.round(screenPos.y - height - 16 * sf) : -1000
        visible: screenPos && screenPos.z > 0 && y > (carouselLayer.y + carouselLayer.height)
        z: 8
        width: threat1Content.implicitWidth + Math.round(16 * sf)
        height: Math.round(26 * sf)

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: mapRoot.mixc(Qt.rgba(0.06, 0.08, 0.12, 0.88), Qt.rgba(0.243, 0.318, 0.396, 0.82))
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.12 + 0.06 * mapRoot.lm)
            border.width: 1
        }

        RowLayout {
            id: threat1Content
            anchors.centerIn: parent
            spacing: Math.round(6 * sf)

            Text {
                text: "03 kt"
                color: "#00E5FF"
                font.pixelSize: Math.round(11 * sf)
                font.bold: true
                font.family: "Segoe UI, Inter, sans-serif"
            }

            Text {
                text: "20 kt"
                color: Qt.rgba(0.75, 0.82, 0.95, 0.70)
                font.pixelSize: Math.round(11 * sf)
                font.bold: true
                font.family: "Segoe UI, Inter, sans-serif"
            }

            Rectangle {
                width: Math.round(8 * sf)
                height: Math.round(8 * sf)
                radius: 2
                color: "#ef4444"
            }
        }
    }

    Item {
        id: threat2Badge
        property var screenPos: tacticalScene3D.mapFrom3DScene(threatNode2.scenePosition)
        x: screenPos ? Math.round(screenPos.x - width / 2) : -1000
        y: screenPos ? Math.round(screenPos.y - height - 16 * sf) : -1000
        visible: screenPos && screenPos.z > 0 && y > (carouselLayer.y + carouselLayer.height)
        z: 8
        width: Math.round(24 * sf)
        height: Math.round(24 * sf)

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: mapRoot.mixc(Qt.rgba(0.06, 0.08, 0.12, 0.88), Qt.rgba(0.243, 0.318, 0.396, 0.82))
            border.color: Qt.rgba(0.10, 0.85, 0.50, 0.45)
            border.width: 1

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(8 * sf)
                height: Math.round(8 * sf)
                radius: 2
                color: "#10b981"
            }
        }
    }

    Item {
        id: carouselLayer
        anchors.top: parent.top
        anchors.topMargin: mapRoot.cardTopY
        anchors.left: parent.left
        anchors.right: parent.right
        height: mapRoot.cardH + Math.round(26 * sf)
        z: 10
        clip: false

        Item {
            id: carouselViewport
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: mapRoot.cardH
            clip: false

            Repeater {
                model: [
                    accountCardComp,
                    fuelCardComp,
                    weatherCardComp,
                    rollCardComp,
                    pitchCardComp,
                    depthCardComp,
                    windCardComp,
                    waypointCardComp,
                    speedCardComp
                ]

                delegate: Item {
                    id: mapCardWrapper
                    width: mapRoot.getCardWidth(index, mapRoot.scrollPos)
                    height: mapRoot.cardH
                    x: mapRoot.getCardX(index, mapRoot.scrollPos) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    z: mapRoot.getCardZ(index, mapRoot.scrollPos)
                    scale: mapRoot.getCardScale(index, mapRoot.scrollPos)
                    opacity: mapRoot.getCardOpacity(index, mapRoot.scrollPos)
                    visible: opacity > 0.01
                    transformOrigin: Item.Center

                    Loader {
                        anchors.fill: parent
                        sourceComponent: modelData
                        z: 1
                        onLoaded: {
                            if (item && typeof item.isActive !== "undefined") {
                                item.isActive = Qt.binding(function() { return mapRoot.compact ? (mapRoot.cPage[index] === mapRoot.pageIndex) : (index === mapRoot.currentIndex); });
                            }
                            if (item && typeof item.bgTop !== "undefined") {
                                item.bgTop = Qt.binding(function() { return mapRoot.skyAt(mapCardWrapper.x + mapCardWrapper.width / 2, mapRoot.cardTopY + mapRoot.cardH * 0.10); });
                                item.bgBottom = Qt.binding(function() { return mapRoot.skyAt(mapCardWrapper.x + mapCardWrapper.width / 2, mapRoot.cardTopY + mapRoot.cardH * 0.95); });
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                property bool dragActive: false
                property real startMouseX: 0
                property real startScrollPos: 0

                onPressed: (mouse) => {
                    dragActive = true;
                    startMouseX = mouse.x;
                    startScrollPos = mapRoot.compact ? mapRoot.pagePos : mapRoot.scrollPos;
                    carouselAnim.stop();
                    pageAnim.stop();
                }

                onPositionChanged: (mouse) => {
                    if (dragActive) {
                        var dx = mouse.x - startMouseX;
                        if (mapRoot.compact) {
                            var rp = startScrollPos - dx / Math.max(1, mapRoot.width * 0.9);
                            if (rp < 0) rp *= 0.28; else if (rp > 2) rp = 2 + (rp - 2) * 0.28;
                            mapRoot.pagePos = rp;
                            return;
                        }
                        var step = mapRoot.cardW * 1.07;
                        var raw = startScrollPos - dx / step;
                        if (raw < 0) raw = raw * 0.28;
                        else if (raw > mapRoot.maxIndex) raw = mapRoot.maxIndex + (raw - mapRoot.maxIndex) * 0.28;
                        mapRoot.scrollPos = raw;
                    }
                }

                onReleased: (mouse) => {
                    if (dragActive) {
                        dragActive = false;
                        var dx = mouse.x - startMouseX;
                        var thr = Math.round(38 * sf);
                        if (mapRoot.compact) {
                            mapRoot.goPage(dx < -thr ? mapRoot.pageIndex + 1 : dx > thr ? mapRoot.pageIndex - 1 : mapRoot.pageIndex);
                            return;
                        }
                        var target = mapRoot.currentIndex;
                        if (dx < -thr) target = Math.min(mapRoot.maxIndex, mapRoot.currentIndex + 1);
                        else if (dx > thr) target = Math.max(0, mapRoot.currentIndex - 1);
                        mapRoot.currentIndex = target;
                        mapRoot.animateTo(target);
                    }
                }

                onCanceled: {
                    dragActive = false;
                    if (mapRoot.compact) { mapRoot.goPage(mapRoot.pageIndex); return; }
                    mapRoot.animateTo(mapRoot.currentIndex);
                }

                onWheel: (wheel) => {
                    if (mapRoot.compact) { mapRoot.goPage(mapRoot.pageIndex + ((wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) ? 1 : -1)); return; }
                    if (wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) {
                        mapRoot.currentIndex = Math.min(mapRoot.maxIndex, mapRoot.currentIndex + 1);
                        mapRoot.animateTo(mapRoot.currentIndex);
                    } else {
                        mapRoot.currentIndex = Math.max(0, mapRoot.currentIndex - 1);
                        mapRoot.animateTo(mapRoot.currentIndex);
                    }
                }
            }
        }

        Row {
            anchors.top: carouselViewport.bottom
            anchors.topMargin: Math.round(8 * sf)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(5 * sf)

            Repeater {
                model: mapRoot.compact ? 3 : mapRoot.maxIndex + 1
                delegate: Rectangle {
                    readonly property int cur: mapRoot.compact ? mapRoot.pageIndex : mapRoot.currentIndex
                    width: (index === cur) ? Math.round(18 * sf) : Math.round(5 * sf)
                    height: Math.round(4 * sf)
                    radius: height / 2
                    color: (index === cur) ? mapRoot.mixc("#00E5FF", "#1C62B5")
                                                           : mapRoot.mixc(Qt.rgba(0.68, 0.78, 0.90, 0.28), Qt.rgba(0.28, 0.36, 0.44, 0.30))
                    Behavior on width { NumberAnimation { duration: 180 } }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (mapRoot.compact) { mapRoot.goPage(index); return; }
                            mapRoot.currentIndex = index;
                            mapRoot.animateTo(index);
                        }
                    }
                }
            }
        }
    }

    Item {
        id: leftHudBadge
        anchors.left: parent.left
        anchors.leftMargin: Math.round(28 * sf)
        anchors.bottom: speedPillBar.top
        anchors.bottomMargin: Math.round(16 * sf)
        z: 10

        Rectangle {
            height: Math.round(36 * sf)
            radius: Math.round(8 * sf)
            color: mapRoot.mixc(Qt.rgba(0.06, 0.08, 0.12, 0.82), Qt.rgba(0.243, 0.318, 0.396, 0.82))
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.07 + 0.11 * mapRoot.lm)
            border.width: 1
            implicitWidth: leftBadgeContent.implicitWidth + Math.round(20 * sf)

            RowLayout {
                id: leftBadgeContent
                anchors.centerIn: parent
                spacing: Math.round(8 * sf)

                Text {
                    text: (typeof vesselState !== "undefined" && vesselState) ? vesselState.speed.toFixed(0) + " kt" : "12 kt"
                    color: "#00E5FF"
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }

                Rectangle {
                    width: 1
                    height: Math.round(14 * sf)
                    color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
                }

                Text {
                    text: (typeof vesselState !== "undefined" && vesselState && vesselState.targetSpeed > 0) ? vesselState.targetSpeed.toFixed(0) + " kt" : "14 kt"
                    color: Qt.rgba(0.72, 0.82, 0.95, 0.60)
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }

                Rectangle {
                    width: Math.round(10 * sf)
                    height: Math.round(10 * sf)
                    radius: 3
                    color: "#ef4444"
                }
            }
        }
    }

    Item {
        id: speedPillBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(76 * sf)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(236 * sf)
        height: Math.round(42 * sf)
        z: 10

        RectangularGlow {
            anchors.fill: speedPillRect
            anchors.margins: -6
            glowRadius: 12
            spread: 0.0
            opacity: 1.0 - mapRoot.lm
            color: Qt.rgba(0.0, 0.88, 1.0, 0.12)
            cornerRadius: speedPillRect.radius + glowRadius
        }

        Rectangle {
            id: speedPillRect
            anchors.fill: parent
            radius: Math.round(10 * sf)
            color: mapRoot.mixc(Qt.rgba(0.07, 0.09, 0.13, 0.90), Qt.rgba(0.80, 0.90, 0.94, 0.10))
            border.color: mapRoot.mixc(Qt.rgba(1.0, 1.0, 1.0, 0.09), Qt.rgba(0.02, 0.34, 0.68, 1.0))
            border.width: lm > 0.5 ? 2 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(16 * sf)
                anchors.rightMargin: Math.round(16 * sf)
                spacing: Math.round(14 * sf)

                Text {
                    text: "^"
                    color: mapRoot.mixc("#00E5FF", "#25282D")
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                telemetry.sendTargetSpeed(vesselState.targetSpeed + 1.0);
                            }
                        }
                    }
                }

                Text {
                    text: (typeof vesselState !== "undefined" && vesselState) ? (vesselState.targetSpeed > 0 ? Math.round(vesselState.targetSpeed) : Math.round(vesselState.speed * 2)) : "14"
                    color: mapRoot.mixc("#eef3fb", "#0C0C10")
                    font.pixelSize: Math.round(18 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: "v"
                    color: mapRoot.mixc("#00E5FF", "#25282D")
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                telemetry.sendTargetSpeed(Math.max(0.0, vesselState.targetSpeed - 1.0));
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: Math.round(18 * sf)
                    color: mapRoot.mixc(Qt.rgba(0.68, 0.78, 0.90, 0.22), Qt.rgba(0.2, 0.25, 0.3, 0.30))
                }

                Text {
                    text: "||"
                    color: mapRoot.mixc("#c8d8ec", "#25282D")
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                }

                Text {
                    text: "■"
                    color: mapRoot.mixc("#ef4444", "#25282D")
                    font.pixelSize: Math.round(13 * sf)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry) {
                                telemetry.sendEmergencyStop();
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // TELEMETRY CARDS (Neuboat style): Account, Fuel, Weather, Roll, Pitch,
    // Depth, Wind, Waypoint, Speed.  Values read from vesselState where the
    // field exists, otherwise they fall back to the static demo value.
    // ---------------------------------------------------------------------
    Component {
        id: accountCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: ac
            title: "Account"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.70
            valueSize: 36
            readonly property real pct: (typeof vesselState !== "undefined" && vesselState && vesselState.accountHealth !== undefined) ? vesselState.accountHealth : 82
            cardValue: pct.toFixed(0)
            cardUnit: "%"
            cardSubtext: "327 hours logged"

            TelemetryCard.TickArc {
                lm: mapRoot.lm
                anchors.fill: parent
                cx: width / 2; cy: height * 0.70; r: height * 0.255
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.010)
                segStart: 135
                segSweep: 270 * Math.max(0, Math.min(100, ac.pct)) / 100
                segWidth: Math.max(2, height * 0.020)
                capLen: height * 0.06
            }
        }
    }

    Component {
        id: fuelCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: fc
            title: "Fuel"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.50
            valueSize: 46
            readonly property real pct: (typeof vesselState !== "undefined" && vesselState && vesselState.fuelLevel !== undefined) ? vesselState.fuelLevel : 30
            readonly property real avail: (typeof vesselState !== "undefined" && vesselState && vesselState.fuelAvailable !== undefined) ? vesselState.fuelAvailable : 16
            cardValue: pct.toFixed(0)
            cardUnit: "%"

            TelemetryCard.TickArc {
                lm: mapRoot.lm
                id: fuelArc
                anchors.fill: parent
                cx: width / 2; cy: height * 0.50; r: height * 0.30
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.008)
                segStart: 135
                segSweep: 270 * Math.max(0, Math.min(100, fc.pct)) / 100
                segWidth: Math.max(2, height * 0.018)
                capLen: height * 0.06
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.80
                textFormat: Text.StyledText
                text: "Available: <font color=\"" + fc.cTitle + "\"><b>" + fc.avail.toFixed(0) + " gal</b></font>"
                color: fc.cSoft
                font.pixelSize: Math.round(10.5 * fc.u)
                font.weight: Font.Light
                font.family: fc.fontText
            }
            Text {
                text: "E"
                x: fuelArc.cx - fuelArc.r * 0.707 - width / 2
                y: fuelArc.cy + fuelArc.r * 0.707 - height * 0.2
                color: fc.cFaint
                font.pixelSize: Math.round(9.5 * fc.u)
                font.family: fc.fontText
            }
            Text {
                text: "F"
                x: fuelArc.cx + fuelArc.r * 0.707 - width / 2
                y: fuelArc.cy + fuelArc.r * 0.707 - height * 0.2
                color: fc.cFaint
                font.pixelSize: Math.round(9.5 * fc.u)
                font.family: fc.fontText
            }
        }
    }

    Component {
        id: weatherCardComp
        TelemetryCard {
            lm: mapRoot.lm
            title: "Tampa, FL"
            titleMoon: true
            cardValue: "6"
            cardUnit: "°F"
            cardSubtext: "Mostly Cloudy\nRain: 30%\nVisibility: 9 nm"

            // big cloud, flush with the right + bottom edge (clipped by the card corners)
            Image {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.60
                height: parent.height * 0.70
                source: Qt.resolvedUrl("assets/weather_cloud.png")
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignRight
                verticalAlignment: Image.AlignBottom
                smooth: true
                mipmap: true
                // day look: the smoky night cloud is lifted to a bright white cloud
                layer.enabled: mapRoot.lm > 0.001
                layer.effect: MultiEffect { brightness: 0.34 * mapRoot.lm; contrast: 0.08 * mapRoot.lm }
            }
        }
    }

    Component {
        id: rollCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: rc
            title: "Roll"
            readonly property real ang: (typeof vesselState !== "undefined" && vesselState) ? vesselState.roll : 15
            cardValue: Math.abs(ang).toFixed(0)
            cardUnit: "°"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState)
                         ? ("The boat is tilted\n" + Math.abs(ang).toFixed(0) + "° " + (ang >= 0 ? "stbd" : "port"))
                         : "The boat is tilted\n15° upward"

            // dashed protractor arc over the boat + thin blue span from top-centre toward the heel side
            TelemetryCard.TickArc {
                lm: mapRoot.lm
                anchors.fill: parent
                cx: width * 0.64; cy: height * 0.72; r: width * 0.31
                trackStart: 183; trackSweep: 174
                trackWidth: height * 0.050
                segStart: 270
                segSweep: (rc.ang >= 0 ? 1 : -1) * Math.min(80, Math.max(8, Math.abs(rc.ang) * 4))
                segWidth: Math.max(2, height * 0.014)
                capLen: height * 0.075
            }
            Text {
                text: "Left"
                x: parent.width * 0.64 - parent.width * 0.31 * 0.70 - width / 2
                y: parent.height * 0.72 - height / 2
                color: rc.cLabel
                font.pixelSize: Math.round(9 * rc.u)
                font.weight: Font.Light
                font.family: rc.fontText
            }
            Text {
                text: "Right"
                x: parent.width * 0.64 + parent.width * 0.31 * 0.70 - width / 2
                y: parent.height * 0.72 - height / 2
                color: rc.cLabel
                font.pixelSize: Math.round(9 * rc.u)
                font.weight: Font.Light
                font.family: rc.fontText
            }
            Image {
                width: parent.width * 0.34
                height: parent.height * 0.52
                x: parent.width * 0.64 - width / 2
                y: parent.height * 0.67 - height / 2
                source: Qt.resolvedUrl("assets/roll_yacht_render.png")
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                rotation: rc.ang
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            }
        }
    }

    Component {
        id: pitchCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: pc
            title: "Pitch"
            readonly property real ang: (typeof vesselState !== "undefined" && vesselState) ? vesselState.pitch : 7
            cardValue: Math.abs(ang).toFixed(0)
            cardUnit: "°"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState)
                         ? ("The boat is tilted\n" + Math.abs(ang).toFixed(0) + "° " + (ang >= 0 ? "bow up" : "bow down"))
                         : "The boat is tilted\n7° bow up"

            // dashed arc rising from the bow + blue bracket that opens toward the pitch direction
            TelemetryCard.TickArc {
                lm: mapRoot.lm
                anchors.fill: parent
                cx: width * 0.77; cy: height * 0.73; r: width * 0.35
                trackStart: 190; trackSweep: 85
                trackWidth: height * 0.050
                segStart: 180
                segSweep: (pc.ang >= 0 ? 1 : -1) * Math.min(70, Math.max(8, Math.abs(pc.ang) * 3))
                segWidth: Math.max(2, height * 0.014)
                capLen: height * 0.075
            }
            Image {
                width: parent.width * 0.56
                height: parent.height * 0.44
                x: parent.width * 0.79 - width / 2
                y: parent.height * 0.74 - height / 2
                source: Qt.resolvedUrl("assets/pitch_yacht_render.png")
                fillMode: Image.PreserveAspectFit
                mirror: true                       // bow points left, like the reference
                smooth: true
                mipmap: true
                rotation: pc.ang
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            }
        }
    }

    Component {
        id: depthCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: dc
            title: "Depth"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.715
            cardValue: (typeof vesselState !== "undefined" && vesselState) ? (vesselState.depth * 3.28084).toFixed(0) : "27"
            cardUnit: "ft"
            cardSubtext: "Located in deep water"

            Item {
                id: depthGfx
                anchors.fill: parent
                readonly property real railTop: height * 0.42
                readonly property real railBot: height * 0.90
                readonly property real stemLen: height * 0.13
                readonly property color blue: dc.accentBlue

                // dim dashed rails across the card
                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: dc.cRail
                        strokeWidth: depthGfx.height * 0.024
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2.4, 2.8]
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        startX: depthGfx.width * 0.07; startY: depthGfx.railTop
                        PathLine { x: depthGfx.width * 0.93; y: depthGfx.railTop }
                    }
                    ShapePath {
                        strokeColor: dc.cRail
                        strokeWidth: depthGfx.height * 0.024
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2.4, 2.8]
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        startX: depthGfx.width * 0.07; startY: depthGfx.railBot
                        PathLine { x: depthGfx.width * 0.93; y: depthGfx.railBot }
                    }
                }
                // blue centre bars with soft ends
                Repeater {
                    model: [depthGfx.railTop, depthGfx.railBot]
                    delegate: Rectangle {
                        width: depthGfx.width * 0.30
                        height: Math.max(3, depthGfx.height * 0.028)
                        x: (depthGfx.width - width) / 2
                        y: modelData - height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.00; color: Qt.rgba(depthGfx.blue.r, depthGfx.blue.g, depthGfx.blue.b, 0.0) }
                            GradientStop { position: 0.22; color: depthGfx.blue }
                            GradientStop { position: 0.78; color: depthGfx.blue }
                            GradientStop { position: 1.00; color: Qt.rgba(depthGfx.blue.r, depthGfx.blue.g, depthGfx.blue.b, 0.0) }
                        }
                    }
                }
                // stems that form the two "T"s
                Rectangle {
                    width: Math.max(2, depthGfx.height * 0.010); height: depthGfx.stemLen
                    x: (depthGfx.width - width) / 2; y: depthGfx.railTop
                    color: depthGfx.blue
                }
                Rectangle {
                    width: Math.max(2, depthGfx.height * 0.010); height: depthGfx.stemLen
                    x: (depthGfx.width - width) / 2; y: depthGfx.railBot - height
                    color: depthGfx.blue
                }
            }
        }
    }

    Component {
        id: windCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: wc
            title: "Wind"
            centerDesign: true
            readonly property real windFrom: 113        // bearing the wind comes from
            readonly property real windKmh: 13
            readonly property var names16: ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
            cardSubtext: "Speed: " + windKmh.toFixed(0) + "km/h\nDirection: " + windFrom.toFixed(0) + "° " + names16[Math.round(windFrom / 22.5) % 16]

            TelemetryCard.CompassDial {
                lm: mapRoot.lm
                width: parent.height * 0.50
                height: width
                x: (parent.width - width) / 2
                y: parent.height * 0.69 - height / 2
                windFrom: wc.windFrom
                heading: (typeof vesselState !== "undefined" && vesselState && vesselState.heading !== undefined) ? vesselState.heading : 45
            }
        }
    }

    Component {
        id: waypointCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: nc
            title: "Waypoint"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.58
            valueSize: 34
            readonly property real dist: (typeof vesselState !== "undefined" && vesselState && vesselState.wpDistanceNm !== undefined) ? vesselState.wpDistanceNm : 2.25
            cardValue: dist.toFixed(2)
            cardUnit: "NM"

            TelemetryCard.TickArc {
                lm: mapRoot.lm
                id: wpArc
                anchors.fill: parent
                cx: width / 2; cy: height * 0.58; r: height * 0.335
                trackStart: 0; trackSweep: 360
                dashed: false
                trackWidth: Math.max(1, height * 0.010)
                trackColor: nc.cWpTrack
                segStart: 120
                segSweep: 300
                segWidth: Math.max(2, height * 0.026)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: wpArc.cy - wpArc.r * 0.62 - height / 2
                text: "To WP-02"
                color: nc.cFaint
                font.pixelSize: Math.round(9.5 * nc.u)
                font.weight: Font.Light
                font.family: nc.fontText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: wpArc.cy + wpArc.r * 0.62 - height / 2
                text: "Distance"
                color: nc.cFaint
                font.pixelSize: Math.round(9.5 * nc.u)
                font.weight: Font.Light
                font.family: nc.fontText
            }
        }
    }

    Component {
        id: speedCardComp
        TelemetryCard {
            lm: mapRoot.lm
            id: sc
            title: "Speed (SOG)"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.64
            valueSize: 38
            readonly property real kts: (typeof vesselState !== "undefined" && vesselState) ? vesselState.speed : 12
            cardValue: kts.toFixed(1)
            cardUnit: "kts"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState) ? ("HDG: " + Math.round(vesselState.heading) + "° | RPM: " + vesselState.rpm) : "Stationary"

            TelemetryCard.TickArc {
                lm: mapRoot.lm
                anchors.fill: parent
                cx: width / 2; cy: height * 0.64; r: height * 0.30
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.008)
                segStart: 135
                segSweep: 270 * Math.max(0.02, Math.min(1, sc.kts / 30))
                segWidth: Math.max(2, height * 0.018)
                capLen: height * 0.06
            }
        }
    }
}