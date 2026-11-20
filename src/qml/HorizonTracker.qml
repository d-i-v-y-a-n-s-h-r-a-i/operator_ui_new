import QtQuick

// =====================================================================================================
//  HorizonTracker.qml  -  finds the real water line in the live video, every frame, in pure QML.
//
//  Why: the camera rolls and pitches with the boat, so the horizon in the picture moves. A fixed number
//  (or IMU numbers that are not in sync with the picture) makes the AR path hang in the air or sink in the
//  water. This item looks at the very pixels that are on screen and measures:
//       yNorm     horizon height at the centre of the picture, 0 = top .. 1 = bottom of `target`
//       angleDeg  tilt of the horizon, + = clockwise on screen (same sign as QML rotation)
//       valid     true while a clear straight edge is being tracked
//
//  How: every `interval` ms the video item is rendered to a small image (grabToImage, 320 px wide), read in a
//  hidden Canvas, strong vertical brightness steps are collected column by column, and the straight line that
//  most of them agree on is found (RANSAC) and smoothed. Costs well under a millisecond of JS per frame.
//
//  Usage (Main.qml):   HorizonTracker { id: horizonTracker; target: backgroundVideoSink }
//  Nothing is drawn by this item.
// =====================================================================================================
Item {
    id: ht
    width: 0; height: 0

    property Item target: null
    property bool running: true
    property int interval: 120                 // ms between measurements (~8 per second)
    property int procW: 480                    // analysis width in pixels
    property real searchTop: 0.20              // look for the horizon between these fractions of the height
    property real searchBottom: 0.74
    property real minEdge: 5.0                 // minimum brightness step (0..255) to count as an edge
    property real smoothing: 0.45              // 0..1, higher = follows faster

    // results
    property real yNorm: 0.5
    property real angleDeg: 0
    property real confidence: 0
    property bool valid: false
    property real rawYNorm: 0.5
    property real rawAngleDeg: 0
    property double lastGood: 0
    property int misses: 0

    property bool _busy: false
    property real _seed: 12345

    function rnd() { _seed = (_seed * 1664525 + 1013904223) % 4294967296; return _seed / 4294967296; }

    function analyze(px, w, h) {
        var cols = [], i, x, y;
        var y0 = Math.floor(h * searchTop), y1 = Math.floor(h * searchBottom), k = 3, sepRows = 6;
        var P = new Float32Array(h + 1);
        var cand = [];
        for (x = 3; x < w - 3; x += 4) {
            P[0] = 0;
            for (y = 0; y < h; y++) {
                var s = 0;
                for (var dx = -1; dx <= 1; dx++) {
                    var o = (y * w + x + dx) * 4;
                    s += 0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2];
                }
                P[y + 1] = P[y] + s / 3;
            }
            var b1 = -1, s1 = 0, b2 = -1, s2 = 0;
            for (y = y0 + k; y < y1 - k; y++) {
                var sc = Math.abs((P[y + k] - P[y]) - (P[y] - P[y - k])) / k;
                if (sc < minEdge) continue;
                // local maximum within +-k rows
                var isMax = true;
                for (var q = -k; q <= k && isMax; q++) {
                    if (q === 0) continue;
                    var yy = y + q;
                    if (yy < y0 + k || yy >= y1 - k) continue;
                    var sq = Math.abs((P[yy + k] - P[yy]) - (P[yy] - P[yy - k])) / k;
                    if (sq > sc || (sq === sc && q < 0)) isMax = false;
                }
                if (!isMax) continue;
                if (sc > s1) { b2 = b1; s2 = s1; b1 = y; s1 = sc; }
                else if (sc > s2 && Math.abs(y - b1) > sepRows) { b2 = y; s2 = sc; }
            }
            if (b1 >= 0) cand.push({ x: x, y: b1 + 0.5, s: s1 });
            if (b2 >= 0 && Math.abs(b2 - b1) > sepRows) cand.push({ x: x, y: b2 + 0.5, s: s2 });
        }
        var nCols = Math.floor((w - 6) / 4);
        if (cand.length < nCols * 0.35) return null;

        // RANSAC: straight lines that many strong edges agree on. Up to 3 are found one after the other
        // (each time the edges it explains are removed). The water line is the LOWEST of the strong ones:
        // tree tops, clouds and the sky/shore edge all lie above it.
        var tol = Math.max(1.2, h / 130.0), lines = [], pool = cand.slice(), firstScore = 0;
        for (var ln = 0; ln < 3 && pool.length >= 8; ln++) {
            var n = pool.length, best = null, bestScore = 0, it;
            for (it = 0; it < 220; it++) {
                var A = pool[Math.floor(rnd() * n)], B = pool[Math.floor(rnd() * n)];
                if (Math.abs(B.x - A.x) < w * 0.25) continue;
                var m = (B.y - A.y) / (B.x - A.x);
                if (Math.abs(Math.atan(m)) > 14 * Math.PI / 180) continue;
                var sum = 0;
                for (i = 0; i < n; i++) if (Math.abs(pool[i].y - (A.y + m * (pool[i].x - A.x))) <= tol) sum += pool[i].s;
                if (sum > bestScore) { bestScore = sum; best = { a: A.y - m * A.x, b: m }; }
            }
            if (best === null) break;
            if (ln === 0) firstScore = bestScore;
            else if (bestScore < firstScore * 0.45) break;
            var fit = null;
            for (var pass = 0; pass < 2; pass++) {                       // weighted least squares on the inliers
                var sw = 0, sx = 0, sy = 0, sxx = 0, sxy = 0, cnt = 0, minX = 1e9, maxX = -1e9;
                for (i = 0; i < n; i++) {
                    var c = pool[i];
                    if (Math.abs(c.y - (best.a + best.b * c.x)) > tol) continue;
                    sw += c.s; sx += c.s * c.x; sy += c.s * c.y; sxx += c.s * c.x * c.x; sxy += c.s * c.x * c.y;
                    cnt++; if (c.x < minX) minX = c.x; if (c.x > maxX) maxX = c.x;
                }
                var den = sw * sxx - sx * sx;
                if (cnt < 8 || Math.abs(den) < 1e-6) { fit = null; break; }
                var bb = (sw * sxy - sx * sy) / den;
                best = { a: (sy - bb * sx) / sw, b: bb };
                fit = { a: best.a, b: best.b, cnt: cnt, span: (maxX - minX) / w, score: bestScore };
            }
            // take the explained edges out of the pool
            var rest = [];
            for (i = 0; i < n; i++) if (Math.abs(pool[i].y - (best.a + best.b * pool[i].x)) > tol * 1.6) rest.push(pool[i]);
            pool = rest;
            if (fit !== null && fit.cnt >= nCols * 0.25 && fit.span >= 0.35) lines.push(fit);
        }
        if (lines.length === 0) return null;
        var pick = lines[0], pickY = lines[0].a + lines[0].b * (w / 2);
        for (i = 1; i < lines.length; i++) {
            var yy2 = lines[i].a + lines[i].b * (w / 2);
            if (yy2 > pickY) { pick = lines[i]; pickY = yy2; }
        }
        return { y: pickY / h, deg: Math.atan(pick.b) * 180 / Math.PI, conf: Math.min(1, pick.cnt / (nCols * 0.8)) };
    }

    function feed(px, w, h) {
        var r = analyze(px, w, h);
        if (r === null) {
            misses++;
            confidence = Math.max(0, confidence - 0.2);
            if (valid && Date.now() - lastGood > 1500) valid = false;
            return;
        }
        misses = 0;
        rawYNorm = r.y; rawAngleDeg = r.deg; confidence = r.conf;
        if (!valid) { yNorm = r.y; angleDeg = r.deg; }
        else {
            var a = smoothing;
            // ignore one wild jump (>8% of the height), accept it if it repeats
            if (Math.abs(r.y - yNorm) > 0.08 && _jump < 1) { _jump++; return; }
            _jump = 0;
            yNorm += (r.y - yNorm) * a;
            angleDeg += (r.deg - angleDeg) * a;
        }
        valid = true; lastGood = Date.now();
    }
    property int _jump: 0

    function grab() {
        if (_busy || target === null || target.width < 8 || target.height < 8 || !target.visible) return;
        _busy = true;
        var w = procW, h = Math.max(32, Math.round(procW * target.height / target.width));
        var ok = target.grabToImage(function(res) { cv._w = w; cv._h = h; grabbed.source = res.url; }, Qt.size(w, h));
        if (!ok) _busy = false;
    }

    Timer { interval: ht.interval; repeat: true; running: ht.running && ht.target !== null; onTriggered: ht.grab() }
    Timer { id: watchdog; interval: 1500; repeat: true; running: ht._busy; onTriggered: { ht._busy = false; } }

    Image {                                    // holds the little snapshot, never shown
        id: grabbed
        x: -3000; y: -3000
        cache: false
        asynchronous: false
        onStatusChanged: if (status === Image.Ready) cv.requestPaint()
    }

    Canvas {
        id: cv
        property int _w: 320
        property int _h: 180
        x: -2000; y: -2000
        width: _w; height: _h
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onPaint: {
            if (grabbed.status !== Image.Ready) return;
            var ctx = getContext("2d");
            ctx.drawImage(grabbed, 0, 0, _w, _h);
            var d = ctx.getImageData(0, 0, _w, _h);
            grabbed.source = "";
            ht.feed(d.data, _w, _h);
            ht._busy = false;
        }
    }
}
