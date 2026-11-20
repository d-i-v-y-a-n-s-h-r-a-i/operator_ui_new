import QtQuick
import QtQuick.Shapes

// =====================================================================================================
//  NavPath.qml  -  augmented-reality path drawn over the live video (camera view).
//
//  A glowing perspective ribbon lies on the water and runs from the bow to the next waypoint. Animated
//  chevrons flow along it (faster when the boat is faster), distance marks sit on the right edge, the
//  next waypoint stands as a light beacon with name / distance / ETA, a red zone marks hazards
//  (with the hazard's predicted track), and small tags say what the boat is doing and where it turns.
//
//  The ribbon is drawn on the same horizon as the heading tape (horizonRot / horizonY come from Main.qml),
//  so it tilts with the video horizon.
//
//  FEED IT (any one of these, nothing is also fine):
//     navPath.json = '{"seq":812, "state":"AVOID", "msg":"Altering to port", "etaS":187,
//                      "wp":{"name":"WP 03","distM":412},
//                      "pts":[[-1,18],[-4,40],[-10,70],[-17,100], ...],
//                      "hz":[{"x":5,"z":104,"r":9,"kind":"VESSEL","label":"CARGO VESSEL","cpa":42,
//                             "track":[[14,170],[9,125],[4,80],[0,50]]}]}'
//     navPath.feed = ({ ... same keys ... })
//     nothing  -> a smooth arc to the next waypoint from  wpBearing (absolute deg) - heading, with the beacon at wpDistM.
//                 No bearing at all = straight ahead.
//
//  Coordinates (all METRES, boat frame, origin = camera/bow):   x = starboard (+) / port (-),   z = forward.
//  "pts" is the planner's local path, nearest first; the boat position (0,0) is added automatically.
//  ALWAYS send an increasing "seq" (or timestamp) so an identical message still counts as fresh.
//
//  JSON keys (all optional):
//     seq        number      message counter
//     state      "NAV" | "AVOID" | "BERTH" | "HOLD"     (tag text and colour)
//     msg        string      second line of the tag (e.g. "Altering to port - CPA 42 m")
//     pts        [[x,z],...] path to follow
//     delta      number      (instead of pts) course change in degrees, + = starboard; draws a smooth arc
//     wp         {name, distM, etaS}      next waypoint
//     etaS       number      seconds to the waypoint (else distM / speed)
//     hz         [{x,z,r,kind,label,cpa,track}]     hazards (red); r = radius in m; track = predicted path [[x,z],...]
//
//  Camera model (tune to your camera if the ribbon does not sit right on the water):
//     camHeightM   camera height above the water     focalPx   focal length in pixels (default: 70 deg HFOV)
//     halfWidthM   half width of the ribbon (boat half-beam)
//
//  Preview without boat data: press F6 in the camera view (0 live, 1 straight, 2 turn, 3 collision avoidance).
// =====================================================================================================
Item {
    id: nav

    // ----------------------------------------------------------------------------------- inputs
    property real sf: 1.0                         // UI scale (Main: scaleFactor)
    property real horizonRot: 0                   // deg, same as the heading tape
    property real horizonY: height / 2            // px, same as the heading tape
    property real heading: 0                      // deg, 0..360
    property real wpBearing: NaN                  // deg absolute, optional
    property real wpDistM: NaN                    // metres to the waypoint, optional
    property string wpName: "WP"
    property real speedMs: 0
    property bool autonomous: true
    property string json: ""
    property var feed: ({})
    property int previewScenario: 0
    property real camHeightM: 3.0
    property real focalPx: width * 0.714
    property real halfWidthM: 0.7
    property real maxRangeM: 300

    // ------------------------------------------------------------------------------------ state
    property real phase: 0
    property var rx: null                         // last parsed message
    property double lastRx: 0
    property real dataAgeMs: 0
    readonly property bool stale: rx !== null && previewScenario === 0 && dataAgeMs > 3000
    property var pX: []
    property var pZ: []
    property var pT: []                           // heading (rad) of the path at every metre
    property var haz: []
    property var wp: null                         // {x,z,name,distM,etaS}
    property string stateName: "NAV"
    property string msg: ""
    property real turnDeg: 0
    readonly property real hy0: height / 2
    readonly property real zMin: 3.5
    readonly property color cCyan: "#00f0ff"
    readonly property color cIce: "#8ff7ff"
    readonly property color cRed: "#ff3b4e"
    readonly property color cAmber: "#ffb020"
    readonly property color accent: stateName === "HOLD" ? cAmber : cCyan

    // geometry handed to the Shape
    property var gPool: []
    property var gRibbon: []
    property var gEdgeL: []
    property var gEdgeR: []
    property var gEdgeLg: []
    property var gEdgeRg: []
    property var gTicks: []
    property var gChev: []
    property var gChevGlow: []
    property var gHazFill: []
    property var gHazTrack: []
    property var gHazPillar: []
    property var gHazMark: []
    property var gRingA: []
    property var gRingB: []
    property var gPillar: []
    property var gDiamond: []
    property var tickLabels: []
    property real ringAlpha: 0.0
    property point bcnP: Qt.point(0, 0)
    property real bcnRx: 10
    property real bcnRy: 4
    property real bcnBaseY: 0
    property real bcnTopY: 0
    property real fadeNearY: height
    property bool hasWp: false
    property point wpTagP: Qt.point(0, 0)
    property point capP: Qt.point(0, 0)
    property point turnP: Qt.point(0, 0)
    property bool capOk: false
    property bool turnOk: false
    property var hazTags: []

    visible: autonomousOrManual
    readonly property bool autonomousOrManual: true
    opacity: stale ? 0.35 : (autonomous ? 1.0 : 0.6)
    Behavior on opacity { NumberAnimation { duration: 300 } }

    // ---------------------------------------------------------------------------------- helpers
    function wrap180(a) { return ((a % 360) + 540) % 360 - 180; }
    function smooth01(t) { t = Math.max(0, Math.min(1, t)); return t * t * (3 - 2 * t); }
    function proj(x, z) { var s = focalPx / z; return Qt.point(width / 2 + x * s, hy0 + camHeightM * s); }
    // The camera sees the horizon at distance dPerp from the picture centre (perpendicular to the horizon line).
    // The ground is drawn level with its horizon dPerp below the centre, then the whole picture is rolled about the centre.
    readonly property real dPerp: (horizonY - height / 2) * Math.cos(horizonRot * Math.PI / 180)
    function toScreen(p) {                         // same transform as the Shape
        var a = horizonRot * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a);
        var cx = width / 2, cy = height / 2;
        var qx = p.x - cx, qy = p.y + dPerp - cy;
        return Qt.point(cx + qx * c - qy * sn, cy + qx * sn + qy * c);
    }
    function fmtDist(m) {
        if (isNaN(m)) return "";
        if (m < 1000) return Math.round(m) + " m";
        return (m / 1852).toFixed(2) + " nm";
    }
    function fmtEta(s) {
        if (isNaN(s) || s <= 0 || s > 359999) return "";
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60);
        function p2(v) { return v < 10 ? "0" + v : "" + v; }
        return h > 0 ? (h + ":" + p2(m) + ":" + p2(sec)) : (p2(m) + ":" + p2(sec));
    }
    function stateTitle() {
        if (!autonomous) return "MANUAL CONTROL";
        if (stateName === "AVOID") return "COLLISION AVOIDANCE";
        if (stateName === "BERTH") return "AUTONOMOUS BERTHING";
        if (stateName === "HOLD") return "HOLDING POSITION";
        return "AUTONOMOUS NAVIGATION";
    }

    function scenario(k) {
        if (k === 1) return { delta: 0, wp: { name: "WP 03", distM: 420 }, state: "NAV" };
        if (k === 2) return { delta: 16, wp: { name: "WP 03", distM: 380 }, state: "NAV" };
        return {
            state: "AVOID", msg: "Cargo vessel 104 m - altering to port",
            pts: [[-1, 18], [-4, 40], [-10, 70], [-17, 100], [-21, 130], [-19, 165], [-10, 205], [0, 250], [7, 300]],
            wp: { name: "WP 03", distM: 410 },
            hz: [{ x: 5, z: 104, r: 9, kind: "VESSEL", label: "CARGO VESSEL", cpa: 12,
                   track: [[15, 175], [10, 130], [4, 82], [0, 52]] }]
        };
    }

    function ingest(o) {
        if (!o || typeof o !== "object") return;
        rx = o; lastRx = Date.now(); dataAgeMs = 0;
        scheduleRebuild();
    }
    onJsonChanged: { if (json === "") return; try { ingest(JSON.parse(json)); } catch (e) {} }
    onFeedChanged: { if (feed && Object.keys(feed).length > 0) ingest(feed); }

    // the message the geometry is built from
    function compose() {
        if (previewScenario > 0) return scenario(previewScenario);
        if (rx !== null) return rx;
        var d = isNaN(wpBearing) ? 0 : wrap180(wpBearing - heading);
        return { delta: d, wp: isNaN(wpDistM) ? null : { name: wpName, distM: wpDistM }, state: "NAV" };
    }

    // path samples every metre: X, Z, heading
    function buildSamples(src) {
        var X = [], Z = [], T = [];
        var maxS = maxRangeM + 20, n, i;
        if (src.pts && src.pts.length >= 2) {
            var pl = [[0, 0]].concat(src.pts), cum = [0];
            for (i = 1; i < pl.length; i++)
                cum.push(cum[i - 1] + Math.hypot(pl[i][0] - pl[i - 1][0], pl[i][1] - pl[i - 1][1]));
            var total = Math.min(cum[cum.length - 1], maxS), j = 1;
            n = Math.floor(total) + 1;
            for (i = 0; i < n; i++) {
                while (j < pl.length - 1 && cum[j] < i) j++;
                var seg = Math.max(0.0001, cum[j] - cum[j - 1]), u = Math.max(0, Math.min(1, (i - cum[j - 1]) / seg));
                X.push(pl[j - 1][0] + (pl[j][0] - pl[j - 1][0]) * u);
                Z.push(pl[j - 1][1] + (pl[j][1] - pl[j - 1][1]) * u);
            }
            var X2 = [], Z2 = [];                                  // light smoothing, removes planner kinks
            for (i = 0; i < n; i++) {
                var a = Math.max(0, i - 3), b = Math.min(n - 1, i + 3), sx = 0, sz = 0;
                for (var k = a; k <= b; k++) { sx += X[k]; sz += Z[k]; }
                X2.push(sx / (b - a + 1)); Z2.push(sz / (b - a + 1));
            }
            X = X2; Z = Z2;
            for (i = 0; i < n; i++) {
                var i0 = Math.max(0, i - 2), i1 = Math.min(n - 1, i + 2);
                T.push(Math.atan2(X[i1] - X[i0], Z[i1] - Z[i0]));
            }
        } else {
            var d = Math.max(-75, Math.min(75, src.delta || 0)) * Math.PI / 180;
            var Ls = Math.max(70, Math.min(170, Math.abs(d) * 180 / Math.PI * 5));
            var x = 0, z = 0;
            for (i = 0; i <= maxS; i++) {
                var th = d * smooth01(i / Ls);
                X.push(x); Z.push(z); T.push(th);
                x += Math.sin(th); z += Math.cos(th);
            }
        }
        pX = X; pZ = Z; pT = T;
    }

    function idxForZ(zv) {
        var n = pZ.length;
        for (var i = 0; i < n; i++) if (pZ[i] >= zv) return i;
        return -1;
    }

    function rebuild() {
        var src = compose();
        stateName = src.state || "NAV";
        msg = src.msg || "";
        buildSamples(src);
        var n = pX.length;
        haz = src.hz || [];

        // waypoint
        wp = null;
        if (src.wp && n > 5) {
            var dm = (src.wp.distM !== undefined) ? Number(src.wp.distM) : NaN;
            var wi = isNaN(dm) ? n - 1 : Math.min(n - 1, Math.floor(dm));
            if (src.pts && src.pts.length >= 2) wi = n - 1;
            var eta = (src.etaS !== undefined) ? Number(src.etaS) : (src.wp.etaS !== undefined ? Number(src.wp.etaS) : (speedMs > 0.3 && !isNaN(dm) ? dm / speedMs : NaN));
            wp = { x: pX[wi], z: pZ[wi], name: src.wp.name || "WP", distM: isNaN(dm) ? pZ[wi] : dm, etaS: eta, far: (!isNaN(dm) && dm > maxRangeM + 10) };
        }
        hasWp = wp !== null;

        // course change shown on the turn tag
        var ti = Math.min(n - 1, 120);
        turnDeg = n > 10 ? pT[ti] * 180 / Math.PI : 0;

        // ribbon geometry
        var w = halfWidthM, Lp = [], Rp = [], PLp = [], PRp = [];
        var first = -1, i;
        for (i = 0; i < n; i++) {
            var th = pT[i], nx = Math.cos(th), nz = -Math.sin(th), x = pX[i], z = pZ[i];
            if (z - Math.abs(nz) * w * 2.4 < 2.5) continue;
            if (first < 0) first = i;
            Lp.push(proj(x - nx * w, z - nz * w));       Rp.push(proj(x + nx * w, z + nz * w));
            PLp.push(proj(x - nx * w * 1.9, z - nz * w * 1.9)); PRp.push(proj(x + nx * w * 1.9, z + nz * w * 1.9));
        }
        function poly(A, B) { return A.concat(B.slice().reverse()); }
        function band(A, t) {
            var up = [], dn = [];
            for (var q = 0; q < A.length; q++) { up.push(Qt.point(A[q].x - t, A[q].y)); dn.push(Qt.point(A[q].x + t, A[q].y)); }
            return up.concat(dn.reverse());
        }
        gPool = poly(PLp, PRp); gRibbon = poly(Lp, Rp);
        var t1 = 2.0 * sf, t2 = 8 * sf;
        gEdgeL = band(Lp, t1); gEdgeR = band(Rp, t1); gEdgeLg = band(Lp, t2); gEdgeRg = band(Rp, t2);

        // distance marks
        var ticks = [], tl = [], marks = [25, 50, 100, 150, 200, 300];
        for (var m = 0; m < marks.length; m++) {
            var ii = idxForZ(marks[m]);
            if (ii < 0 || ii >= n - 1) continue;
            var th2 = pT[ii], nx2 = Math.cos(th2), nz2 = -Math.sin(th2);
            var A = proj(pX[ii] - nx2 * w * 1.15, pZ[ii] - nz2 * w * 1.15), B = proj(pX[ii] + nx2 * w * 1.15, pZ[ii] + nz2 * w * 1.15);
            var th3 = Math.max(1.4, 2.2 * sf);
            ticks.push([A, B, Qt.point(B.x, B.y + th3), Qt.point(A.x, A.y + th3)]);
            tl.push({ p: Qt.point(B.x + 10 * sf, B.y - 8 * sf), text: marks[m] + " m" });
        }
        gTicks = ticks; tickLabels = tl;

        // hazards: ground circle + predicted track
        var hf = [], ht = [], htags = [], hpil = [], hmark = [];
        for (var h = 0; h < haz.length; h++) {
            var hz = haz[h], r = hz.r || 6, ring = [];
            if (hz.z - r < 2.5) continue;
            for (var a2 = 0; a2 <= 28; a2++) {
                var ang = a2 / 28 * Math.PI * 2;
                ring.push(proj(hz.x + r * Math.cos(ang), Math.max(2.6, hz.z + r * Math.sin(ang))));
            }
            hf.push(ring);
            if (hz.track && hz.track.length >= 2) {
                var tw = Math.max(2.2, r * 0.42), tp = hz.track, L2 = [], R2 = [];
                for (var q = 0; q < tp.length; q++) {
                    var dx = (tp[Math.min(q + 1, tp.length - 1)][0] - tp[Math.max(q - 1, 0)][0]);
                    var dz = (tp[Math.min(q + 1, tp.length - 1)][1] - tp[Math.max(q - 1, 0)][1]);
                    var ln = Math.hypot(dx, dz) || 1, ux = dz / ln, uz = -dx / ln;     // normal
                    if (tp[q][1] - Math.abs(uz) * tw < 2.5) continue;
                    L2.push(proj(tp[q][0] - ux * tw, tp[q][1] - uz * tw)); R2.push(proj(tp[q][0] + ux * tw, tp[q][1] + uz * tw));
                }
                if (L2.length > 1) ht.push(poly(L2, R2));
            }
            var hp = proj(hz.x, hz.z), dist = Math.hypot(hz.x, hz.z), hs = focalPx / hz.z;
            var hh = Math.min(150 * sf, Math.max(38 * sf, 5 * hs)), hw = Math.max(2.5 * sf, 0.3 * hs), tri = 8 * sf;
            hpil.push([Qt.point(hp.x - hw, hp.y), Qt.point(hp.x + hw, hp.y), Qt.point(hp.x + hw * 0.3, hp.y - hh), Qt.point(hp.x - hw * 0.3, hp.y - hh)]);
            hmark.push([Qt.point(hp.x - tri, hp.y - hh - tri * 1.5), Qt.point(hp.x + tri, hp.y - hh - tri * 1.5), Qt.point(hp.x, hp.y - hh - 0.1 * tri)]);
            htags.push({ p: Qt.point(hp.x + tri + 14 * sf, hp.y - hh - tri * 0.75), top: Qt.point(hp.x + tri, hp.y - hh - tri * 0.75),
                         title: hz.label || hz.kind || "OBSTACLE",
                         sub: fmtDist(dist) + (hz.cpa !== undefined ? "  -  CPA " + Math.round(hz.cpa) + " m" : "") });
        }
        gHazFill = hf; gHazTrack = ht; hazTags = htags; gHazPillar = hpil; gHazMark = hmark;

        // beacon pieces that do not animate
        if (hasWp) {
            var wz = Math.max(wp.z, 6), P = proj(wp.x, wz), s2 = focalPx / wz;
            var hpx = Math.min(200 * sf, Math.max(48 * sf, 10 * s2)), pw = Math.max(2.5 * sf, 0.4 * s2);
            bcnBaseY = P.y; bcnTopY = P.y - hpx;
            gPillar = [[Qt.point(P.x - pw, P.y), Qt.point(P.x + pw, P.y), Qt.point(P.x + pw * 0.35, P.y - hpx), Qt.point(P.x - pw * 0.35, P.y - hpx)]];
            var d7 = 8 * sf, cy2 = P.y - hpx;
            gDiamond = [[Qt.point(P.x, cy2 - d7), Qt.point(P.x + d7, cy2), Qt.point(P.x, cy2 + d7), Qt.point(P.x - d7, cy2)]];
            wpTagP = Qt.point(P.x, cy2 - d7 - 8 * sf);
            var rx0 = Math.max(3.2 * s2, 15 * sf), ry0 = Math.max(rx0 * camHeightM / wz, 4 * sf), ringA = [];
            bcnP = P; bcnRx = rx0; bcnRy = ry0;
            for (var a3 = 0; a3 <= 36; a3++) { var g = a3 / 36 * Math.PI * 2; ringA.push(Qt.point(P.x + rx0 * Math.cos(g), P.y + ry0 * Math.sin(g))); }
            gRingA = ringA;
        } else { gPillar = []; gDiamond = []; gRingA = []; }

        // caption tag (left of the ribbon) and turn tag
        var ci = idxForZ(15);
        capOk = ci >= 0 && Lp.length > 0;
        if (capOk) {
            var cth = pT[ci], cn = proj(pX[ci] - Math.cos(cth) * w * 1.1, pZ[ci] + Math.sin(cth) * w * 1.1);
            capP = cn;
        }
        turnOk = autonomous && Math.abs(turnDeg) >= 4 && n > 40;
        if (turnOk) {
            var ki = idxForZ(32);
            if (ki >= 0) {
                var kth = pT[ki], side = turnDeg > 0 ? 1 : -1;
                turnP = proj(pX[ki] + side * (Math.cos(kth) * w * 1.7), pZ[ki] - side * Math.sin(kth) * w * 1.7);
            } else turnOk = false;
        }
        rebuildFrame();
    }

    // everything that moves with the animation phase
    function rebuildFrame() {
        var n = pX.length;
        if (n < 8) { gChev = []; gChevGlow = []; return; }
        var sp = 5.0, wc = halfWidthM * 0.70, Lc = 1.25, th = 0.55;
        var polys = [], glows = [];
        for (var s = 4.5 + phase * sp; s < n - 3; s += sp) {
            var si = Math.floor(s), fr = s - si, i1 = Math.min(n - 1, si + 1);
            var x = pX[si] + (pX[i1] - pX[si]) * fr, z = pZ[si] + (pZ[i1] - pZ[si]) * fr, t = pT[si] + (pT[i1] - pT[si]) * fr;
            var sn = Math.sin(t), cs = Math.cos(t);       // tangent (sn, cs), normal (cs, -sn)
            function mk(k) {
                var loc = [[-wc * k, -0.1 * k], [0, Lc * k], [wc * k, -0.1 * k], [wc * k, -th * k - 0.1 * k], [0, (Lc - th) * k], [-wc * k, -th * k - 0.1 * k]];
                var out = [], ok = true;
                for (var q = 0; q < loc.length; q++) {
                    var gx = x + cs * loc[q][0] + sn * loc[q][1], gz = z - sn * loc[q][0] + cs * loc[q][1];
                    if (gz < 2.2) { ok = false; break; }
                    out.push(proj(gx, gz));
                }
                return ok ? out : null;
            }
            var a = mk(1.0), b = mk(1.55);
            if (a) polys.push(a);
            if (b) glows.push(b);
        }
        gChev = polys; gChevGlow = glows;

        if (hasWp && wp) {
            var pf = (phase * 2) % 1.0, k2 = 1 + pf * 1.9, ring = [];
            for (var a3 = 0; a3 <= 36; a3++) { var g = a3 / 36 * Math.PI * 2; ring.push(Qt.point(bcnP.x + bcnRx * k2 * Math.cos(g), bcnP.y + bcnRy * k2 * Math.sin(g))); }
            gRingB = ring; ringAlpha = 0.85 * (1 - pf);
        }
    }

    Timer { id: rebuildTimer; interval: 60; onTriggered: nav.rebuild() }
    function scheduleRebuild() { if (!rebuildTimer.running) rebuildTimer.start(); }
    onWidthChanged: scheduleRebuild()
    onHeightChanged: scheduleRebuild()
    onHeadingChanged: if (rx === null && previewScenario === 0) scheduleRebuild()
    onWpBearingChanged: scheduleRebuild()
    onWpDistMChanged: scheduleRebuild()
    onWpNameChanged: scheduleRebuild()
    onPreviewScenarioChanged: scheduleRebuild()
    onAutonomousChanged: scheduleRebuild()
    onCamHeightMChanged: scheduleRebuild()
    onFocalPxChanged: scheduleRebuild()
    onHalfWidthMChanged: scheduleRebuild()
    Component.onCompleted: rebuild()

    Shortcut { sequence: "F6"; onActivated: nav.previewScenario = (nav.previewScenario + 1) % 4 }

    // chevron flow: faster when the boat is faster, never fully frozen
    property double lastT: 0
    Timer {
        interval: 33; repeat: true; running: nav.visible
        onTriggered: {
            var now = Date.now(), dt = nav.lastT > 0 ? Math.min(0.2, (now - nav.lastT) / 1000) : 0.033;
            nav.lastT = now;
            var rate = Math.max(0.3, Math.min(1.4, nav.speedMs / 8.0));      // cycles per second
            nav.phase = (nav.phase + dt * rate) % 1.0;
            if (nav.lastRx > 0) nav.dataAgeMs = now - nav.lastRx;
            nav.rebuildFrame();
        }
    }

    // ------------------------------------------------------------------------------------ gradients
    component Fade: LinearGradient {
        id: fg
        property color base: "#00f0ff"
        property real peak: 1.0
        property real mid: 0.8
        x1: 0; y1: nav.fadeNearY; x2: 0; y2: nav.hy0
        GradientStop { position: 0.00; color: Qt.rgba(fg.base.r, fg.base.g, fg.base.b, 0.0) }
        GradientStop { position: 0.09; color: Qt.rgba(fg.base.r, fg.base.g, fg.base.b, fg.peak) }
        GradientStop { position: 0.55; color: Qt.rgba(fg.base.r, fg.base.g, fg.base.b, fg.peak * fg.mid) }
        GradientStop { position: 1.00; color: Qt.rgba(fg.base.r, fg.base.g, fg.base.b, 0.0) }
    }

    // ------------------------------------------------------------------------------------ drawing
    Item {
        id: ground
        width: nav.width; height: nav.height
        transform: Rotation { origin.x: nav.width / 2; origin.y: nav.height / 2; angle: nav.horizonRot }

      Item {
        width: nav.width; height: nav.height
        y: nav.dPerp

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            // soft light pool on the water
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.accent; peak: 0.10; mid: 0.7 }
                PathPolyline { path: nav.gPool } }
            // hazard predicted track (red ribbon)
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cRed; peak: 0.55; mid: 0.75 }
                PathPolyline { path: nav.gHazTrack.length > 0 ? nav.gHazTrack[0] : [] } }
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cRed; peak: 0.55; mid: 0.75 }
                PathPolyline { path: nav.gHazTrack.length > 1 ? nav.gHazTrack[1] : [] } }
            // hazard ground zone
            ShapePath {
                strokeColor: Qt.rgba(1, 0.27, 0.33, 0.95); strokeWidth: 1.6 * nav.sf; strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                fillColor: Qt.rgba(1, 0.2, 0.28, 0.22)
                PathMultiline { paths: nav.gHazFill }
            }
            ShapePath { strokeColor: "transparent"; fillColor: Qt.rgba(1, 0.23, 0.30, 0.38); PathMultiline { paths: nav.gHazPillar } }
            ShapePath { strokeColor: "white"; strokeWidth: 1.0 * nav.sf; fillColor: Qt.rgba(1, 0.23, 0.30, 0.95); PathMultiline { paths: nav.gHazMark } }
            // ribbon body
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.accent === nav.cCyan ? "#00b8ff" : "#ffa010"; peak: 0.34; mid: 0.8 }
                PathPolyline { path: nav.gRibbon } }
            // edge glow + core
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.accent; peak: 0.20; mid: 0.8 }
                PathPolyline { path: nav.gEdgeLg } }
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.accent; peak: 0.20; mid: 0.8 }
                PathPolyline { path: nav.gEdgeRg } }
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cIce; peak: 0.95; mid: 0.9 }
                PathPolyline { path: nav.gEdgeL } }
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cIce; peak: 0.95; mid: 0.9 }
                PathPolyline { path: nav.gEdgeR } }
            // distance marks
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cIce; peak: 0.65; mid: 0.9 }
                PathMultiline { paths: nav.gTicks } }
            // chevrons (glow, then core)
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.accent; peak: 0.26; mid: 0.85 }
                PathMultiline { paths: nav.gChevGlow } }
            ShapePath { strokeColor: "transparent"; fillGradient: Fade { base: nav.cIce; peak: 0.98; mid: 0.9 }
                PathMultiline { paths: nav.gChev } }
            // waypoint beacon
            ShapePath { strokeColor: "transparent"; fillGradient: LinearGradient {
                    x1: 0; y1: nav.bcnBaseY; x2: 0; y2: nav.bcnTopY
                    GradientStop { position: 0.0; color: Qt.rgba(nav.accent.r, nav.accent.g, nav.accent.b, 0.85) }
                    GradientStop { position: 1.0; color: Qt.rgba(nav.accent.r, nav.accent.g, nav.accent.b, 0.0) } }
                PathMultiline { paths: nav.gPillar } }
            ShapePath { strokeColor: Qt.rgba(0.56, 0.97, 1, 0.95); strokeWidth: 2.0 * nav.sf; fillColor: Qt.rgba(0, 0.94, 1, 0.16)
                PathPolyline { path: nav.gRingA } }
            ShapePath { strokeColor: Qt.rgba(0.56, 0.97, 1, nav.ringAlpha); strokeWidth: 1.6 * nav.sf; fillColor: "transparent"
                PathPolyline { path: nav.gRingB } }
            ShapePath { strokeColor: "white"; strokeWidth: 1.2 * nav.sf; fillColor: Qt.rgba(0.56, 0.97, 1, 0.9)
                PathMultiline { paths: nav.gDiamond } }
        }
      }
    }

    // ---------------------------------------------------------------------------------- labels (kept upright)
    component Tag: Rectangle {
        id: tg
        property string title: ""
        property string sub: ""
        property color accent: "#00f0ff"
        property real sf: 1
        implicitWidth: Math.max(tt.implicitWidth, ts.implicitWidth) + 24 * sf
        implicitHeight: (ts.text === "" ? 26 : 44) * sf
        width: implicitWidth; height: implicitHeight
        radius: 4 * sf
        color: Qt.rgba(0.02, 0.07, 0.12, 0.74)
        border.width: 1; border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.55)
        Rectangle { x: 0; y: 5 * sf; width: 3 * sf; height: parent.height - 10 * sf; radius: 1.5; color: tg.accent }
        Column {
            x: 13 * tg.sf; anchors.verticalCenter: parent.verticalCenter; spacing: 2 * tg.sf
            Text { id: tt; text: tg.title; color: "#ffffff"; font.pixelSize: Math.round(12 * tg.sf); font.bold: true; font.letterSpacing: 1.4; font.family: "Segoe UI, Inter, sans-serif" }
            Text { id: ts; visible: text !== ""; text: tg.sub; color: Qt.rgba(0.78, 0.93, 1, 0.9); font.pixelSize: Math.round(11 * tg.sf); font.family: "Segoe UI, Inter, sans-serif" }
        }
    }

    Repeater {                                                   // distance marks on the right edge
        model: nav.tickLabels
        delegate: Text {
            property point sp: nav.toScreen(modelData.p)
            x: sp.x; y: sp.y
            text: modelData.text
            color: Qt.rgba(0.78, 0.96, 1, 0.85)
            font.pixelSize: Math.round(10 * nav.sf); font.bold: true; font.letterSpacing: 1
            font.family: "Segoe UI, Inter, sans-serif"
            opacity: Math.max(0, Math.min(1, (sp.y - nav.horizonY) / (60 * nav.sf)))
        }
    }

    Repeater {                                                   // hazard tags
        model: nav.hazTags
        delegate: Item {
            property point sp: nav.toScreen(modelData.p)
            property point tp: nav.toScreen(modelData.top)
            Rectangle { x: parent.tp.x; y: parent.sp.y - 0.5; width: Math.max(0, parent.sp.x - parent.tp.x); height: 1; color: Qt.rgba(1, 0.3, 0.36, 0.8) }
            Tag {
                x: parent.sp.x; y: parent.sp.y - height / 2
                sf: nav.sf; accent: nav.cRed; title: modelData.title; sub: modelData.sub
            }
        }
    }

    Tag {                                                        // next waypoint
        visible: nav.hasWp && nav.wp !== null
        property point sp: nav.toScreen(nav.wpTagP)
        property real minX: 12 * nav.sf
        x: Math.max(minX, Math.min(nav.width - width - minX, sp.x - width / 2))
        y: sp.y - height
        sf: nav.sf; accent: nav.cCyan
        title: nav.wp ? nav.wp.name : ""
        sub: nav.wp ? (nav.fmtDist(nav.wp.distM) + (nav.fmtEta(nav.wp.etaS) !== "" ? "   ETA " + nav.fmtEta(nav.wp.etaS) : "")) : ""
    }

    Item {                                                       // what the boat is doing (left of the ribbon)
        visible: nav.capOk
        property point sp: nav.toScreen(nav.capP)
        Tag {
            id: capTag
            sf: nav.sf; accent: nav.accent
            title: nav.stateTitle()
            sub: nav.stale ? "PATH DATA STALE" : (nav.msg !== "" ? nav.msg : (nav.wp ? ("Next " + nav.wp.name + "  -  " + nav.fmtDist(nav.wp.distM)) : "Holding course"))
            x: Math.max(404 * nav.sf, parent.sp.x - width - 40 * nav.sf)
            y: parent.sp.y - height / 2
        }
        Rectangle { x: capTag.x + capTag.width; y: parent.sp.y - 0.5; width: Math.max(0, parent.sp.x - (capTag.x + capTag.width)); height: 1; color: Qt.rgba(nav.accent.r, nav.accent.g, nav.accent.b, 0.7) }
        Rectangle { x: parent.sp.x - 3 * nav.sf; y: parent.sp.y - 3 * nav.sf; width: 6 * nav.sf; height: 6 * nav.sf; radius: width / 2; color: nav.accent }
    }

    Tag {                                                        // coming turn
        visible: nav.turnOk
        property point sp: nav.toScreen(nav.turnP)
        x: nav.turnDeg > 0 ? sp.x : sp.x - width
        y: sp.y - height / 2
        sf: nav.sf; accent: nav.cCyan
        title: (nav.turnDeg > 0 ? "TURN STBD " : "TURN PORT ") + Math.round(Math.abs(nav.turnDeg)) + "°"
        sub: "NEW COURSE " + ("00" + Math.round((nav.heading + nav.turnDeg + 720) % 360)).slice(-3) + "°"
    }
}
