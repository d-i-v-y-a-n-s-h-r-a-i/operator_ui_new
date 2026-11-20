import QtQuick
import QtQuick.Shapes

// =============================================================================
//  MissionMapView  -  GPU vector map for mission planning (right 2/3 of the screen)
//
//   * tiles come from the Python backend (`missionMap`, see mission_map_backend.py): offline MBTiles,
//     decoded off the UI thread and handed over as ready SVG path strings.
//   * every tile is a QtQuick.Shapes item, a whole tile LEVEL is moved / scaled as ONE item, so
//     panning and pinch-zoom never touch the tile geometry again (no per-frame re-tessellation).
//   * the level you are looking at is kept on screen until the next level is complete, and a coarse
//     fill-only level always sits underneath -> no blank tiles while loading.
//   * theme: dark / light is a single blend value `lm` (same one the rest of the UI uses).
//   * map style = the grey, depth-shaded Neuboat look (light land, 3 water tones, slate route).
// =============================================================================
Item {
    id: mv
    clip: true

    // ------------------------------------------------------------------ public API
    property real lm: 0.0                                   // 0 = dark UI, 1 = light UI
    property var backend: (typeof missionMap !== "undefined") ? missionMap : null
    property real topInset: 0                               // height of the app header that floats above the map
    property bool active: true

    // own-ship (from GnssSource.qml, see Main.qml)
    property real vesselLat: NaN
    property real vesselLon: NaN
    property real vesselHdg: 0
    property real vesselKn: 0
    property bool gnssLive: false                           // true = a real GNSS fix
    property string gnssText: ""                            // e.g. "GNSS 3D  -  GPSD"

    // mission
    property var waypoints: []                              // [{lat, lon}, ...]
    property bool navigating: false
    property real planSpeedKn: 6.0                          // used for the leg ETA when the boat is not moving
    signal startRequested(var waypoints)
    signal endRequested()
    signal waypointsEdited(var waypoints)

    // view
    property real centerLat: 20.0
    property real centerLon: 0.0
    property real zoom: 2.0
    property bool following: true
    property real openZoom: 14.0                            // zoom used by openAtVessel() (limited by the detail of the pack)

    // named points that are always marked on the map (launch sites, harbours ...): [{name, lat, lon}, ...]
    property var namedPoints: [ { name: "RMSC Launch Point", lat: 12.451754, lon: 76.552337 } ]
    onNamedPointsChanged: labelsDirty = true

    // ------------------------------------------------------------------ geometry helpers
    readonly property real u: Math.max(0.8, Math.min(1.35, height / 960.0))
    readonly property real worldPx: 512.0 * Math.pow(2, zoom)
    readonly property real cx: mercX(centerLon) * worldPx
    readonly property real cy: mercY(centerLat) * worldPx
    readonly property bool hasFix: !isNaN(vesselLat) && !isNaN(vesselLon)

    function mercX(lon) { return (lon + 180.0) / 360.0; }
    function mercY(lat) {
        var s = Math.sin(Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI / 180.0);
        return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
    }
    function lonOf(mx) { return mx * 360.0 - 180.0; }
    function latOf(my) { var n = Math.PI * (1 - 2 * my); return 180.0 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n))); }
    function sx(lon) { return mercX(lon) * worldPx - cx + width / 2; }
    function sy(lat) { return mercY(lat) * worldPx - cy + height / 2; }
    function geoAt(px, py) { return { lat: latOf((cy + py - height / 2) / worldPx), lon: lonOf((cx + px - width / 2) / worldPx) }; }
    function haversineNm(a, b) {
        var R = 3440.065, d2r = Math.PI / 180;
        var dLat = (b.lat - a.lat) * d2r, dLon = (b.lon - a.lon) * d2r;
        var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a.lat * d2r) * Math.cos(b.lat * d2r) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
    }
    function fmtLat(v) { return Math.abs(v).toFixed(4) + "° " + (v >= 0 ? "N" : "S"); }
    function fmtLon(v) { return Math.abs(v).toFixed(4) + "° " + (v >= 0 ? "E" : "W"); }
    function fmtLat6(v) { return Math.abs(v).toFixed(6) + "° " + (v >= 0 ? "N" : "S"); }
    function fmtLon6(v) { return Math.abs(v).toFixed(6) + "° " + (v >= 0 ? "E" : "W"); }
    function fmtEta(min) {
        if (!(min >= 0)) return "--";
        if (min < 1) return "<1 min";
        if (min < 60) return Math.round(min) + " min";
        return Math.floor(min / 60) + " h " + Math.round(min % 60) + " min";
    }

    // ------------------------------------------------------------------ theme / palette (grey, depth-shaded)
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }
    function mix2(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    // 0 = overview (3 water tones), 1 = harbour zoom (one water tone) - keeps the look consistent at every scale
    readonly property real harbourF: { var t = Math.max(0, Math.min(1, (zoom - 8.8) / 2.6)); return t * t * (3 - 2 * t); }
    readonly property color cLand: mixc("#dddddd", "#ececec")
    readonly property color cFar: mixc("#abacb0", "#c6c8cc")
    readonly property color cMid: mixc("#989a9e", "#aeb1b6")
    readonly property color cNear: mixc("#6d6e72", "#8b8d92")
    readonly property color cBandMid: mix2(cMid, cFar, harbourF)
    readonly property color cBandNear: mix2(cNear, cFar, harbourF)
    readonly property bool bandsOn: zoom < 11.7
    readonly property color cCoast: mixc("#8c8d91", "#9b9da2")
    readonly property color cPark: mixc("#d0d3cf", "#e0e3df")
    readonly property color cWood: mixc("#c3c9c2", "#d3dad1")                 // forest, scrub, orchards
    readonly property color cFarm: mixc("#e2e3de", "#f1f2ec")                 // farmland
    readonly property color cUrban: mixc("#d1d1d4", "#e0e0e4")                // built-up land
    readonly property color cLakeMid: mix2(cFar, cMid, 0.75)                  // inland water: two shore tones (real polygons from the pack)
    readonly property color cLakeNear: mix2(cMid, cNear, 0.32)
    readonly property color cRoadCase: mixc("#c3c3c7", "#cfcfd4")
    readonly property color cRiver: mixc("#a4a5a9", "#bfc1c5")
    readonly property color cBuilding: mixc("#c4c4c6", "#d3d3d6")
    readonly property color cTrack: mixc("#f2f2f2", "#fbfbfb")                // tracks, paths, footways (thin, un-cased)
    readonly property color cRoadMajor: mixc("#fafafa", "#ffffff")
    readonly property color cRoadMinor: mixc("#f2f2f2", "#f8f8f8")
    readonly property color cNoData: mixc("#6c6d71", "#9a9ca1")
    readonly property color cLabel: "#1c1c1e"
    readonly property color cLabelHalo: mixc("#e6e6e6", "#f4f4f5")
    readonly property color cRoute: "#7d889e"
    readonly property color cNavy: "#1d2a8f"
    readonly property color cBlue: "#2f6fe0"
    readonly property color cChipFill: mixc("#e61a1c22", "#ebf6f7f9")
    readonly property color cChipText: mixc("#eef1f5", "#1c1f24")
    readonly property color cChipSub: mixc("#a8b0bd", "#5c6470")

    // ------------------------------------------------------------------ tile plumbing
    property var tileStore: ({})                             // "z/x/y" -> decoded tile (dict from Python)
    property var storeOrder: []
    signal tileLoaded(string key)
    signal viewTouched()

    readonly property bool dataOk: backend !== null && backend.available
    readonly property int dataMinZ: dataOk ? backend.minZoom : 0
    readonly property int dataMaxZ: dataOk ? backend.maxZoom : 0
    readonly property int tz: Math.max(dataMinZ, Math.min(dataMaxZ, Math.floor(zoom)))
    readonly property real minZoomView: Math.max(dataMinZ, Math.log(Math.max(width, height, 512) / 512.0) / Math.LN2)
    readonly property real maxZoomView: dataMaxZ + 2.5

    function askTile(z, x, y) { if (backend) backend.requestTile(z, x, y); }
    function dropTile(z, x, y) { if (backend) backend.cancelTile(z, x, y); }

    Connections {
        target: mv.backend
        ignoreUnknownSignals: true
        function onTileReady(z, x, y, d) {
            var k = z + "/" + x + "/" + y;
            mv.tileStore[k] = d;
            mv.storeOrder.push(k);
            if (mv.storeOrder.length > 700) {
                var old = mv.storeOrder.splice(0, 150);
                for (var i = 0; i < old.length; ++i) delete mv.tileStore[old[i]];
            }
            mv.tileLoaded(k);
            mv.labelsDirty = true;
        }
    }

    onCxChanged: touch()
    onCyChanged: touch()
    onZoomChanged: touch()
    onWidthChanged: touch()
    onHeightChanged: touch()
    function touch() { Qt.callLater(function() { mv.viewTouched(); }); labelsDirty = true; }

    // two "main" levels that ping-pong while zooming + one coarse fill-only base level
    property int zA: -1
    property int zB: -1
    property int zBaseCap: 7                                                // coarse fallback level (the world pack) shown wherever a regional pack has no tile
    readonly property int zBase: (dataOk && tz >= dataMinZ + 2) ? Math.max(dataMinZ, Math.min(tz - 4, zBaseCap)) : -1
    onTzChanged: assignLevel()
    onDataOkChanged: assignLevel()
    function assignLevel() {
        if (!dataOk) return;
        if (zA === tz || zB === tz) return;
        if (zA < 0) zA = tz;
        else if (zB < 0) zB = tz;
        else if (Math.abs(zA - tz) > Math.abs(zB - tz)) zA = tz;
        else zB = tz;
        settleTimer.restart();
    }
    Timer {
        id: settleTimer
        interval: 140
        repeat: true
        onTriggered: {
            var done = true;
            if (mv.zA === mv.tz && mv.zB >= 0 && mv.zB !== mv.tz) { if (lvlA.isComplete()) mv.zB = -1; else done = false; }
            else if (mv.zB === mv.tz && mv.zA >= 0 && mv.zA !== mv.tz) { if (lvlB.isComplete()) mv.zA = -1; else done = false; }
            if (done) stop();
        }
    }

    // ------------------------------------------------------------------ one tile: body (fills, lines)
    component TileBody: Item {
        id: tb
        required property string key
        required property int tx
        required property int ty
        property int lz: 0
        property real ax: 0
        property real ay: 0
        property bool under: false
        property var d: null
        x: (tx - ax) * 512
        y: (ty - ay) * 512
        width: 512
        height: 512
        readonly property real wk: 1 + Math.max(0, lz - 16) * 0.7              // line widths grow with the detail levels (z17 / z18 of the launch-point zone)
        function p(n) { return d ? d[n] : ""; }
        function has(n) { return d !== null && d[n] !== undefined && d[n].length > 0; }
        Component.onCompleted: { var c = mv.tileStore[key]; if (c) d = c; else mv.askTile(lz, tx, ty); }
        Component.onDestruction: { if (!d) mv.dropTile(lz, tx, ty); }
        Connections { target: mv; function onTileLoaded(k) { if (k === tb.key) tb.d = mv.tileStore[k]; } }

        Rectangle { visible: tb.under && tb.d !== null && tb.d.noData === true; width: 512; height: 512; color: mv.cNoData }
        Rectangle { visible: tb.d !== null && tb.d.landBg === true; width: 512; height: 512; color: mv.cLand }

        Shape {
            width: 512
            height: 512
            visible: tb.d !== null && tb.d.empty !== true
            asynchronous: true
            preferredRendererType: Shape.GeometryRenderer
            ShapePath { fillColor: tb.has("earth") ? mv.cLand : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.p("earth") } }
            ShapePath { fillColor: (!tb.under && tb.has("farm")) ? mv.cFarm : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("farm") } }
            ShapePath { fillColor: (!tb.under && tb.has("urban")) ? mv.cUrban : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("urban") } }
            ShapePath { fillColor: tb.has("parks") ? mv.cPark : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.p("parks") } }
            ShapePath { fillColor: (!tb.under && tb.has("wood")) ? mv.cWood : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("wood") } }
            ShapePath { fillColor: tb.has("water") ? mv.cFar : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.p("water") } }
            ShapePath { fillColor: (!tb.under && tb.has("shoreMid")) ? mv.cLakeMid : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("shoreMid") } }
            ShapePath { fillColor: (!tb.under && tb.has("shoreNear")) ? mv.cLakeNear : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("shoreNear") } }
            ShapePath { fillColor: (!tb.under && tb.has("buildings")) ? mv.cBuilding : "transparent"; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.OddEvenFill; PathSvg { path: tb.under ? "" : tb.p("buildings") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("coast")) ? mv.cCoast : "transparent"; strokeWidth: (!tb.under && tb.has("coast")) ? 1.2 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("coast") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("rivers")) ? mv.cRiver : "transparent"; strokeWidth: (!tb.under && tb.has("rivers")) ? 1.5 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("rivers") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("tracks")) ? mv.cTrack : "transparent"; strokeWidth: (!tb.under && tb.has("tracks")) ? 1.15 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("tracks") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads3")) ? mv.cRoadCase : "transparent"; strokeWidth: (!tb.under && tb.has("roads3")) ? 2.1 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads3") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads2")) ? mv.cRoadCase : "transparent"; strokeWidth: (!tb.under && tb.has("roads2")) ? 3.1 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads2") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads1")) ? mv.cRoadCase : "transparent"; strokeWidth: (!tb.under && tb.has("roads1")) ? 4.0 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads1") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads0")) ? mv.cRoadCase : "transparent"; strokeWidth: (!tb.under && tb.has("roads0")) ? 5.0 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads0") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads3")) ? mv.cRoadMinor : "transparent"; strokeWidth: (!tb.under && tb.has("roads3")) ? 1.1 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads3") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads2")) ? mv.cRoadMinor : "transparent"; strokeWidth: (!tb.under && tb.has("roads2")) ? 1.7 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads2") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads1")) ? mv.cRoadMajor : "transparent"; strokeWidth: (!tb.under && tb.has("roads1")) ? 2.4 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads1") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("roads0")) ? mv.cRoadMajor : "transparent"; strokeWidth: (!tb.under && tb.has("roads0")) ? 3.2 * tb.wk : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: tb.under ? "" : tb.p("roads0") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("piers")) ? mv.cRoadCase : "transparent"; strokeWidth: (!tb.under && tb.has("piers")) ? 6.4 * tb.wk : -1; capStyle: ShapePath.FlatCap; joinStyle: ShapePath.MiterJoin; PathSvg { path: tb.under ? "" : tb.p("piers") } }
            ShapePath { fillColor: "transparent"; strokeColor: (!tb.under && tb.has("piers")) ? mv.cRoadMajor : "transparent"; strokeWidth: (!tb.under && tb.has("piers")) ? 4.4 * tb.wk : -1; capStyle: ShapePath.FlatCap; joinStyle: ShapePath.MiterJoin; PathSvg { path: tb.under ? "" : tb.p("piers") } }
        }
    }

    // ------------------------------------------------------------------ one tile: depth bands (drawn for ALL tiles first, land goes on top)
    component TileHalo: Item {
        id: th
        required property string key
        required property int tx
        required property int ty
        property int lz: 0
        property real ax: 0
        property real ay: 0
        property var d: null
        // geographic band widths -> pixels of this level (2 x because half of the stroke is hidden under the land)
        readonly property real kmPx: 512.0 * Math.pow(2, lz) / 40075.017
        readonly property bool inland: d !== null && d.shelf === false          // lake / reservoir pack: thin shore shading instead of an ocean shelf
        readonly property bool on: d !== null && d.coast !== undefined && d.coast.length > 0 && (!inland && mv.bandsOn)
        x: (tx - ax) * 512
        y: (ty - ay) * 512
        width: 512
        height: 512
        Component.onCompleted: { var c = mv.tileStore[key]; if (c) d = c; }
        Connections { target: mv; function onTileLoaded(k) { if (k === th.key) th.d = mv.tileStore[k]; } }
        Shape {
            width: 512
            height: 512
            visible: th.on
            asynchronous: true
            preferredRendererType: Shape.GeometryRenderer
            ShapePath { fillColor: "transparent"; strokeColor: th.on ? (th.inland ? mv.cLakeMid : mv.cBandMid) : "transparent"; strokeWidth: th.on ? 2 * (th.inland ? 0.32 : 46) * th.kmPx : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: th.on ? th.d.coast : "" } }
            ShapePath { fillColor: "transparent"; strokeColor: th.on ? (th.inland ? mv.cLakeNear : mv.cBandNear) : "transparent"; strokeWidth: th.on ? 2 * (th.inland ? 0.10 : 13) * th.kmPx : -1; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: th.on ? th.d.coast : "" } }
        }
    }

    // ------------------------------------------------------------------ one tile level = one item (moved / scaled as a whole)
    component TileLevel: Item {
        id: lvl
        property int lvZ: -1
        property bool under: false
        readonly property real s: Math.pow(2, mv.zoom - Math.max(0, lvZ))
        // Tiles are positioned relative to an ANCHOR tile near the view centre (re-anchored in sync()).
        // The scene graph works in float32: absolute positions of ~2e7 px (zoom 16) would jitter by 1-2 px.
        property real ax: 0
        property real ay: 0
        visible: lvZ >= 0
        x: mv.width / 2 - mv.cx + s * 512 * ax
        y: mv.height / 2 - mv.cy + s * 512 * ay
        scale: s
        transformOrigin: Item.TopLeft
        ListModel { id: tm }
        property var have: ({})

        function isComplete() {
            for (var i = 0; i < tm.count; ++i) if (mv.tileStore[tm.get(i).key] === undefined) return false;
            return true;
        }
        function sync() {
            if (lvZ < 0) {
                if (tm.count > 0) { tm.clear(); have = ({}); }
                return;
            }
            var n = Math.pow(2, lvZ), ts = 512 * s, m = under ? 0 : 1;
            var ctx = Math.floor(mv.cx / ts), cty = Math.floor(mv.cy / ts);
            if (Math.abs(ctx - ax) > 3 || Math.abs(cty - ay) > 3) { ax = ctx; ay = cty; }
            var x0 = Math.max(0, Math.floor((mv.cx - mv.width / 2) / ts) - m), x1 = Math.min(n - 1, Math.floor((mv.cx + mv.width / 2) / ts) + m);
            var y0 = Math.max(0, Math.floor((mv.cy - mv.height / 2) / ts) - m), y1 = Math.min(n - 1, Math.floor((mv.cy + mv.height / 2) / ts) + m);
            var want = {}, xx, yy;
            for (xx = x0; xx <= x1; ++xx) for (yy = y0; yy <= y1; ++yy) want[lvZ + "/" + xx + "/" + yy] = [xx, yy];
            for (var i = tm.count - 1; i >= 0; --i) {
                var k = tm.get(i).key;
                if (!want[k]) { tm.remove(i); delete have[k]; }
            }
            for (var key in want) {
                if (!have[key]) { tm.append({ key: key, tx: want[key][0], ty: want[key][1] }); have[key] = true; }
            }
        }
        onLvZChanged: Qt.callLater(sync)
        Connections { target: mv; function onViewTouched() { lvl.sync(); } }

        Repeater { model: lvl.under ? 0 : tm; delegate: TileHalo { lz: lvl.lvZ; ax: lvl.ax; ay: lvl.ay } }
        Repeater { model: tm; delegate: TileBody { lz: lvl.lvZ; under: lvl.under; ax: lvl.ax; ay: lvl.ay } }
    }

    // ------------------------------------------------------------------ MAP LAYERS
    Rectangle { anchors.fill: parent; color: mv.cFar }

    TileLevel { id: lvlBase; lvZ: mv.zBase; under: true }
    TileLevel { id: lvlB; lvZ: mv.zB }
    TileLevel { id: lvlA; lvZ: mv.zA }

    // simple graticule while there is no map backend at all (never an empty grey screen)
    Item {
        anchors.fill: parent
        visible: !mv.dataOk
        Repeater {
            model: 24
            delegate: Rectangle { x: index * mv.width / 24; y: 0; width: 1; height: mv.height; color: Qt.rgba(1, 1, 1, 0.18) }
        }
        Repeater {
            model: 18
            delegate: Rectangle { y: index * mv.height / 18; x: 0; height: 1; width: mv.width; color: Qt.rgba(1, 1, 1, 0.18) }
        }
        Text {
            anchors.centerIn: parent
            text: "No offline map pack found\n(copy a .mbtiles file into the maps folder)"
            horizontalAlignment: Text.AlignHCenter
            color: mv.cChipText
            font.pixelSize: Math.round(15 * mv.u)
        }
    }

    // ------------------------------------------------------------------ place labels (screen-space, collision checked)
    ListModel { id: labelModel }
    property bool labelsDirty: false
    Timer {
        interval: 200
        repeat: true
        running: mv.visible && mv.active
        onTriggered: if (mv.labelsDirty) { mv.labelsDirty = false; mv.rebuildLabels(); }
    }
    function rebuildLabels() {
        if (!dataOk) { labelModel.clear(); return; }
        var n = Math.pow(2, tz), ts = 512 * Math.pow(2, zoom - tz);
        var x0 = Math.max(0, Math.floor((cx - width / 2) / ts)), x1 = Math.min(n - 1, Math.floor((cx + width / 2) / ts));
        var y0 = Math.max(0, Math.floor((cy - height / 2) / ts)), y1 = Math.min(n - 1, Math.floor((cy + height / 2) / ts));
        var cand = [];
        for (var x = x0; x <= x1; ++x) for (var y = y0; y <= y1; ++y) {
            var d = tileStore[tz + "/" + x + "/" + y];
            if (!d || !d.places) continue;
            for (var i = 0; i < d.places.length; ++i) {
                var pl = d.places[i];
                cand.push({ name: pl.name, rank: pl.rank, kind: pl.kind || "", mx: (x + pl.x / 512) / n, my: (y + pl.y / 512) / n });
            }
        }
        cand.sort(function(a, b) { return a.rank - b.rank; });
        var boxes = [], out = {}, count = 0, fs = 13 * u;
        if (hasFix) { var vx = sx(vesselLon), vy = sy(vesselLat); boxes.push([vx - 30 * u, vy - 30 * u, vx + 30 * u, vy + 30 * u]); }
        for (var ni = 0; ni < namedPoints.length; ++ni) { var nx_ = sx(namedPoints[ni].lon), ny_ = sy(namedPoints[ni].lat); boxes.push([nx_ - 16 * u, ny_ - 16 * u, nx_ + 270 * u, ny_ + 46 * u]); }
        for (var wi = 0; wi < waypoints.length; ++wi) { var wx = sx(waypoints[wi].lon), wy = sy(waypoints[wi].lat); boxes.push([wx - 22 * u, wy - 58 * u, wx + 22 * u, wy + 22 * u]); }
        for (var j = 0; j < cand.length && count < 44; ++j) {
            var c = cand[j];
            var px = c.mx * worldPx - cx + width / 2, py = c.my * worldPx - cy + height / 2;
            if (px < 10 || px > width - 10 || py < topInset + 10 || py > height - 10) continue;
            var w = c.name.length * fs * 0.56 + 16, h = fs + 6;
            var bx = px - 6, by = py - h / 2, ok = true;
            for (var q = 0; q < boxes.length; ++q) {
                var b = boxes[q];
                if (bx < b[2] + 6 && bx + w > b[0] - 6 && by < b[3] + 4 && by + h > b[1] - 4) { ok = false; break; }
            }
            if (!ok) continue;
            boxes.push([bx, by, bx + w, by + h]);
            c.key = c.name + "|" + Math.round(c.mx * 1e5) + "|" + Math.round(c.my * 1e5);
            out[c.key] = c;
            count++;
        }
        var have = {};
        for (var r = labelModel.count - 1; r >= 0; --r) {
            var kk = labelModel.get(r).key;
            if (!out[kk]) labelModel.remove(r); else have[kk] = true;
        }
        for (var k2 in out) if (!have[k2]) labelModel.append({ key: k2, name: out[k2].name, kind: out[k2].kind, mx: out[k2].mx, my: out[k2].my });
    }
    Repeater {
        model: labelModel
        delegate: Item {
            required property string name
            required property string kind
            required property real mx
            required property real my
            readonly property bool isWater: kind === "water"
            readonly property bool isPoi: kind === "poi"
            x: mx * mv.worldPx - mv.cx + mv.width / 2
            y: my * mv.worldPx - mv.cy + mv.height / 2
            Rectangle { visible: !parent.isWater && !parent.isPoi; x: -3.5; y: -3.5; width: 7; height: 7; radius: 3.5; color: mv.cLabel }
            Rectangle { visible: parent.isPoi; x: -3; y: -3; width: 6; height: 6; radius: 3; color: "transparent"; border.color: mv.cLabel; border.width: 1.4 }
            Text {
                x: parent.isWater ? -width / 2 : 7
                y: -height / 2
                text: parent.name
                font.italic: parent.isWater
                font.letterSpacing: parent.isWater ? 2 : 0
                color: parent.isWater ? mv.mixc("#3e4a5c", "#4c5b72") : (parent.isPoi ? mv.mixc("#3a3a3e", "#4a4a50") : mv.cLabel)
                font.pixelSize: Math.round((parent.isPoi ? 11.5 : 13) * mv.u)
                font.family: "Inter, Segoe UI, sans-serif"
                style: Text.Outline
                styleColor: mv.cLabelHalo
            }
        }
    }

    // ------------------------------------------------------------------ route + markers
    readonly property var routeNodes: {
        var a = [];
        if (hasFix) a.push({ lat: vesselLat, lon: vesselLon });
        for (var i = 0; i < waypoints.length; ++i) a.push(waypoints[i]);
        return a;
    }
    readonly property var routePts: {
        var a = [];
        for (var i = 0; i < routeNodes.length; ++i) a.push(Qt.point(sx(routeNodes[i].lon), sy(routeNodes[i].lat)));
        return a;
    }
    readonly property real legSpeedKn: vesselKn > 0.8 ? vesselKn : planSpeedKn
    readonly property real totalNm: {
        var t = 0;
        for (var i = 1; i < routeNodes.length; ++i) t += haversineNm(routeNodes[i - 1], routeNodes[i]);
        return t;
    }

    Shape {
        anchors.fill: parent
        visible: mv.routeNodes.length > 1
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeColor: Qt.rgba(mv.cRoute.r, mv.cRoute.g, mv.cRoute.b, 0.72)
            strokeWidth: 10 * mv.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: mv.routePts }
        }
    }

    // leg time tags ("6min")
    Repeater {
        model: Math.max(0, mv.routeNodes.length - 1)
        delegate: Item {
            id: leg
            required property int index
            readonly property var a: mv.routeNodes[index]
            readonly property var b: mv.routeNodes[index + 1]
            readonly property real mins: a && b ? mv.haversineNm(a, b) / mv.legSpeedKn * 60.0 : 0
            readonly property real ax: a ? mv.sx(a.lon) : 0
            readonly property real ay: a ? mv.sy(a.lat) : 0
            readonly property real bx: b ? mv.sx(b.lon) : 0
            readonly property real by: b ? mv.sy(b.lat) : 0
            visible: Math.hypot(bx - ax, by - ay) > 64 * mv.u
            x: (ax + bx) / 2
            y: (ay + by) / 2
            z: 3
            Rectangle {
                x: -width / 2 - 24 * mv.u
                y: -height - 22 * mv.u
                width: legText.implicitWidth + 24 * mv.u
                height: 34 * mv.u
                radius: 4 * mv.u
                color: "#474747"
                Text {
                    id: legText
                    anchors.centerIn: parent
                    text: mv.fmtEta(leg.mins).replace(" min", "min").replace(" h ", "h ")
                    color: "#e2e2e2"
                    font.pixelSize: Math.round(15 * mv.u)
                    font.family: "Inter, Segoe UI, sans-serif"
                }
                Rectangle { x: parent.width - 20 * mv.u; y: parent.height - 3 * mv.u; width: 10 * mv.u; height: 10 * mv.u; rotation: 45; color: "#474747" }
            }
        }
    }

    // waypoints 1..n-1 = numbered rings, last one = pin
    Repeater {
        model: mv.waypoints.length
        delegate: Item {
            id: wp
            required property int index
            readonly property bool isLast: index === mv.waypoints.length - 1
            readonly property var w: mv.waypoints[index]
            x: w ? mv.sx(w.lon) : -100
            y: w ? mv.sy(w.lat) : -100
            z: 5
            Rectangle {
                visible: !wp.isLast
                x: -15 * mv.u
                y: -15 * mv.u
                width: 30 * mv.u
                height: 30 * mv.u
                radius: width / 2
                color: "#ffffff"
                border.color: mv.cNavy
                border.width: 3.5 * mv.u
                Text { anchors.centerIn: parent; text: wp.index + 1; color: mv.cNavy; font.pixelSize: Math.round(14 * mv.u); font.bold: true }
            }
            Shape {
                visible: wp.isLast
                scale: mv.u
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: "#e4e4e4"
                    strokeColor: "#3e79a4"
                    strokeWidth: 3.5
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M0 -2 C-7 -12 -19 -24 -19 -35 A19 19 0 1 1 19 -35 C19 -24 7 -12 0 -2 Z" }
                }
                ShapePath {
                    fillColor: "#3e79a4"
                    strokeColor: "transparent"
                    PathSvg { path: "M-7 -35 A7 7 0 1 0 7 -35 A7 7 0 1 0 -7 -35 Z" }
                }
            }
            Item {
                x: -22 * mv.u
                y: (wp.isLast ? -56 : -22) * mv.u
                width: 44 * mv.u
                height: (wp.isLast ? 60 : 44) * mv.u
                TapHandler {
                    enabled: !mv.navigating
                    onLongPressed: mv.removeWaypoint(wp.index)
                }
            }
        }
    }

    // named points (launch site ...): navy ring + flag, name and exact coordinates
    Repeater {
        model: mv.namedPoints.length
        delegate: Item {
            id: np
            required property int index
            readonly property var pt: mv.namedPoints[index]
            readonly property bool onScreen: x > -300 && x < mv.width + 300 && y > -100 && y < mv.height + 100
            x: pt ? mv.sx(pt.lon) : -1000
            y: pt ? mv.sy(pt.lat) : -1000
            z: 4
            visible: onScreen && mv.zoom >= 8.5
            Rectangle {
                x: -13 * mv.u; y: -13 * mv.u; width: 26 * mv.u; height: 26 * mv.u; radius: width / 2
                color: "#ffffff"; border.color: mv.cNavy; border.width: 3 * mv.u
                Rectangle { x: 8.2 * mv.u; y: 5 * mv.u; width: 1.8 * mv.u; height: 14 * mv.u; color: mv.cNavy }
                Shape {
                    preferredRendererType: Shape.GeometryRenderer
                    scale: mv.u
                    transformOrigin: Item.TopLeft
                    ShapePath { fillColor: mv.cNavy; strokeColor: "transparent"; PathSvg { path: "M10 5 L18 8.2 L10 11.4 Z" } }
                }
            }
            Rectangle {
                x: 20 * mv.u; y: -16 * mv.u
                width: Math.max(npName.implicitWidth, npCoord.implicitWidth) + 22 * mv.u
                height: (mv.zoom >= 12.5 ? 50 : 30) * mv.u
                radius: 6 * mv.u
                color: mv.cChipFill; border.color: Qt.rgba(1, 1, 1, 0.12)
                Text { id: npName; x: 11 * mv.u; y: 6 * mv.u; text: np.pt ? np.pt.name : ""; color: mv.cChipText; font.bold: true; font.pixelSize: Math.round(14 * mv.u); font.family: "Inter, Segoe UI, sans-serif" }
                Text {
                    id: npCoord; x: 11 * mv.u; y: 27 * mv.u; visible: mv.zoom >= 12.5
                    text: np.pt ? mv.fmtLat6(np.pt.lat) + "   " + mv.fmtLon6(np.pt.lon) : ""
                    color: mv.cChipSub; font.pixelSize: Math.round(11.5 * mv.u); font.family: "Inter, Segoe UI, sans-serif"
                }
            }
            Item {                                              // tap = fly there
                x: -22 * mv.u; y: -22 * mv.u; width: 44 * mv.u; height: 44 * mv.u
                TapHandler { onTapped: mv.flyToPoint(np.index) }
            }
        }
    }

    // own ship: grey disc + blue arrow, heading up
    Item {
        id: shipMarker
        visible: mv.hasFix
        x: mv.sx(mv.vesselLon)
        y: mv.sy(mv.vesselLat)
        z: 6
        Rectangle { x: -24 * mv.u; y: -24 * mv.u; width: 48 * mv.u; height: 48 * mv.u; radius: width / 2; color: Qt.rgba(0.78, 0.78, 0.78, 0.85)
            SequentialAnimation on opacity { running: mv.gnssLive; loops: Animation.Infinite; NumberAnimation { to: 0.75; duration: 1100 } NumberAnimation { to: 1.0; duration: 1100 } }
        }
        Shape {
            rotation: mv.vesselHdg
            width: 1
            height: 1
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: mv.gnssLive ? "#0a6da4" : "#7b8794"
                strokeColor: "transparent"
                PathPolyline { path: [Qt.point(0, -18 * mv.u), Qt.point(13 * mv.u, 15 * mv.u), Qt.point(0, 7 * mv.u), Qt.point(-13 * mv.u, 15 * mv.u), Qt.point(0, -18 * mv.u)] }
            }
        }
    }

    // ------------------------------------------------------------------ interaction
    function clampZoom(z) { return Math.max(minZoomView, Math.min(maxZoomView, z)); }
    function stopAnims() { flyAnim.stop(); followAnim.stop(); zoomAnim.stop(); wheelAnim.stop(); }
    function panBy(dx, dy) {
        var mx = Math.max(0, Math.min(1, (cx - dx) / worldPx)), my = Math.max(0.0005, Math.min(0.9995, (cy - dy) / worldPx));
        centerLon = lonOf(mx);
        centerLat = latOf(my);
    }
    function zoomAt(px, py, nz) {
        nz = clampZoom(nz);
        var mx = (cx + px - width / 2) / worldPx, my = (cy + py - height / 2) / worldPx;
        var w2 = 512.0 * Math.pow(2, nz);
        var ncx = mx * w2 - (px - width / 2), ncy = my * w2 - (py - height / 2);
        zoom = nz;
        centerLon = lonOf(Math.max(0, Math.min(1, ncx / w2)));
        centerLat = latOf(Math.max(0.0005, Math.min(0.9995, ncy / w2)));
    }
    function zoomBy(dz) {
        zoomAnim.stop();
        zoomAnim.from = zoom;
        zoomAnim.to = clampZoom(zoom + dz);
        zoomAnim.start();
    }
    function flyTo(lat, lon, z) {
        stopAnims();
        flyLat.to = lat; flyLon.to = lon; flyZoom.to = clampZoom(z);
        flyAnim.start();
    }
    function flyToPoint(i) {                  // jump to a named point (launch site) at the best detail the pack has
        var p = namedPoints[i];
        if (!p) return;
        following = false;
        var z = 16.5;
        if (dataOk && backend.covers(p.lat, p.lon)) z = Math.min(z, backend.maxDetailZoomAt(p.lat, p.lon) + 0.9);
        flyTo(p.lat, p.lon, z);
    }
    function openAtVessel() {                 // called by Main.qml whenever the mission pane is opened
        following = true;
        var lat = hasFix ? vesselLat : centerLat, lon = hasFix ? vesselLon : centerLon;
        var z = openZoom;
        if (dataOk && backend.covers(lat, lon)) z = Math.min(z, backend.maxDetailZoomAt(lat, lon) + 0.9);
        z = clampZoom(z);
        zoom = clampZoom(z - 3.2);              // start wide, then fly in
        centerLat = lat; centerLon = lon;
        flyTo(lat, lon, z);
    }
    function recenter() {
        following = true;
        if (!hasFix) return;
        stopAnims();
        flyLat.to = vesselLat; flyLon.to = vesselLon; flyZoom.to = Math.max(zoom, Math.min(openZoom, maxZoomView));
        flyAnim.start();
    }
    onVesselLatChanged: followUpdate()
    onVesselLonChanged: followUpdate()
    function followUpdate() {
        if (!following || !hasFix || dragH.active || pinchH.active) return;
        // a far jump (first real fix after the default position, or the saved one) = fly there at a sensible zoom
        if (haversineNm({ lat: flyAnim.running ? flyLat.to : centerLat, lon: flyAnim.running ? flyLon.to : centerLon }, { lat: vesselLat, lon: vesselLon }) > 15) { openAtVessel(); return; }
        if (flyAnim.running) return;
        followAnim.stop();
        followLat.to = vesselLat; followLon.to = vesselLon;
        followAnim.start();
    }
    ParallelAnimation {
        id: flyAnim
        NumberAnimation { id: flyLat; target: mv; property: "centerLat"; duration: 1100; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyLon; target: mv; property: "centerLon"; duration: 1100; easing.type: Easing.InOutCubic }
        NumberAnimation { id: flyZoom; target: mv; property: "zoom"; duration: 1100; easing.type: Easing.InOutCubic }
    }
    ParallelAnimation {
        id: followAnim
        NumberAnimation { id: followLat; target: mv; property: "centerLat"; duration: 700; easing.type: Easing.OutQuad }
        NumberAnimation { id: followLon; target: mv; property: "centerLon"; duration: 700; easing.type: Easing.OutQuad }
    }
    NumberAnimation { id: zoomAnim; target: mv; property: "zoom"; duration: 240; easing.type: Easing.OutCubic }
    property real wheelZ: 0
    property point wheelAt: Qt.point(0, 0)
    NumberAnimation { id: wheelAnim; target: mv; property: "wheelZ"; duration: 170; easing.type: Easing.OutCubic }
    onWheelZChanged: if (wheelAnim.running) zoomAt(wheelAt.x, wheelAt.y, wheelZ)

    DragHandler {
        id: dragH
        target: null
        property point last: Qt.point(0, 0)
        onActiveChanged: { if (active) { mv.stopAnims(); mv.following = false; last = Qt.point(0, 0); } }
        onTranslationChanged: {
            if (!active) return;
            mv.panBy(translation.x - last.x, translation.y - last.y);
            last = Qt.point(translation.x, translation.y);
        }
    }
    PinchHandler {
        id: pinchH
        target: null
        property real z0: 0
        onActiveChanged: { if (active) { mv.stopAnims(); mv.following = false; z0 = mv.zoom; } }
        onActiveScaleChanged: if (active) mv.zoomAt(centroid.position.x, centroid.position.y, z0 + Math.log(activeScale) / Math.LN2)
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => {
            mv.stopAnims();
            mv.following = false;
            mv.wheelAt = Qt.point(e.x, e.y);
            mv.wheelZ = mv.zoom;
            wheelAnim.to = mv.clampZoom(mv.zoom + e.angleDelta.y / 360.0);
            wheelAnim.from = mv.zoom;
            wheelAnim.restart();
        }
    }
    function overUi(px, py) {
        var items = [ctrl, actionRow, infoChip];
        for (var i = 0; i < items.length; ++i) {
            var q = items[i].mapFromItem(mv, px, py);
            if (items[i].visible && q.x >= 0 && q.y >= 0 && q.x <= items[i].width && q.y <= items[i].height) return true;
        }
        for (var j = 0; j < waypoints.length; ++j)
            if (Math.hypot(sx(waypoints[j].lon) - px, sy(waypoints[j].lat) - py) < 30 * u) return true;
        return false;
    }
    TapHandler {
        enabled: !mv.navigating
        onTapped: (pt) => {
            if (mv.overUi(pt.position.x, pt.position.y)) return;
            var g = mv.geoAt(pt.position.x, pt.position.y);
            mv.addWaypoint(g.lat, g.lon);
        }
    }

    // ------------------------------------------------------------------ mission editing
    function addWaypoint(lat, lon) {
        var a = waypoints.slice();
        a.push({ lat: lat, lon: lon });
        waypoints = a;
        waypointsEdited(a);
    }
    function removeWaypoint(i) {
        var a = waypoints.slice();
        a.splice(i, 1);
        waypoints = a;
        waypointsEdited(a);
    }
    function clearWaypoints() { waypoints = []; waypointsEdited([]); armed = false; }
    property bool armed: false
    Timer { id: armTimer; interval: 3200; onTriggered: mv.armed = false }

    // ------------------------------------------------------------------ HUD overlays
    // mission summary + position (top left, under the header)
    Rectangle {
        id: infoChip
        x: 18 * mv.u
        y: mv.topInset + 14 * mv.u
        width: infoCol.implicitWidth + 28 * mv.u
        height: infoCol.implicitHeight + 22 * mv.u
        radius: 12 * mv.u
        color: mv.cChipFill
        border.color: Qt.rgba(1, 1, 1, 0.10)
        z: 20
        Column {
            id: infoCol
            x: 14 * mv.u
            y: 11 * mv.u
            spacing: 4 * mv.u
            Text { text: "MISSION PLAN"; color: mv.cChipSub; font.pixelSize: Math.round(11 * mv.u); font.bold: true; font.letterSpacing: 1.4 }
            Text {
                text: mv.waypoints.length === 0 ? "Tap the map to add waypoints"
                      : mv.waypoints.length + " WP   ·   " + mv.totalNm.toFixed(1) + " NM   ·   ETA " + mv.fmtEta(mv.totalNm / mv.legSpeedKn * 60.0)
                color: mv.cChipText
                font.pixelSize: Math.round(14 * mv.u)
                font.bold: true
                font.family: "Inter, Segoe UI, sans-serif"
            }
            Text {
                visible: mv.hasFix
                text: mv.fmtLat(mv.vesselLat) + "   " + mv.fmtLon(mv.vesselLon)
                color: mv.cChipSub
                font.pixelSize: Math.round(12 * mv.u)
                font.family: "Inter, Segoe UI, sans-serif"
            }
            Row {
                spacing: 7 * mv.u
                Rectangle { width: 8 * mv.u; height: 8 * mv.u; radius: width / 2; anchors.verticalCenter: parent.verticalCenter; color: mv.gnssLive ? "#10b981" : "#f59e0b" }
                Text { text: mv.gnssText; color: mv.cChipSub; font.pixelSize: Math.round(11 * mv.u); font.family: "Inter, Segoe UI, sans-serif" }
            }
        }
    }

    // scale bar (bottom left)
    readonly property real mpp: 40075016.686 * Math.cos(centerLat * Math.PI / 180.0) / worldPx
    readonly property var scaleNm: {
        var cands = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000];
        var best = cands[0];
        for (var i = 0; i < cands.length; ++i) { if (cands[i] * 1852 / mpp <= 150 * u) best = cands[i]; }
        return best;
    }
    Item {
        x: 18 * mv.u
        y: mv.height - 38 * mv.u
        z: 20
        Rectangle { y: 8 * mv.u; width: mv.scaleNm * 1852 / mv.mpp; height: 3; color: mv.cLabel; opacity: 0.8 }
        Rectangle { y: 3 * mv.u; width: 2; height: 11 * mv.u; color: mv.cLabel; opacity: 0.8 }
        Rectangle { x: mv.scaleNm * 1852 / mv.mpp - 2; y: 3 * mv.u; width: 2; height: 11 * mv.u; color: mv.cLabel; opacity: 0.8 }
        Text { y: -9 * mv.u; text: (mv.scaleNm < 1 ? mv.scaleNm.toFixed(2) : mv.scaleNm.toFixed(0)) + " NM"; color: mv.cLabel; font.pixelSize: Math.round(11 * mv.u); font.bold: true; style: Text.Outline; styleColor: mv.cLabelHalo }
    }
    // attribution + "outside pack" warning
    Text {
        x: 18 * mv.u + 120 * mv.u
        y: mv.height - 26 * mv.u
        z: 20
        text: mv.dataOk ? ("© " + mv.backend.attribution) : ""
        color: mv.cLabel
        opacity: 0.55
        font.pixelSize: Math.round(10 * mv.u)
    }
    Rectangle {
        readonly property bool outside: mv.dataOk && !mv.backend.covers(mv.centerLat, mv.centerLon)
        visible: outside
        anchors.horizontalCenter: parent.horizontalCenter
        y: mv.topInset + 14 * mv.u
        width: warnT.implicitWidth + 28 * mv.u
        height: 34 * mv.u
        radius: height / 2
        color: "#d9a43a22"
        border.color: "#f59e0b"
        z: 20
        Text { id: warnT; anchors.centerIn: parent; text: "No offline map data for this area"; color: "#f59e0b"; font.pixelSize: Math.round(13 * mv.u); font.bold: true }
    }
    // hint
    property bool hintVisible: true
    Timer { interval: 7000; running: mv.visible && mv.hintVisible; onTriggered: mv.hintVisible = false }
    Text {
        visible: mv.hintVisible && mv.waypoints.length === 0 && !mv.navigating
        anchors.horizontalCenter: parent.horizontalCenter
        y: mv.height - 70 * mv.u
        z: 20
        text: "Tap the map to place waypoints  ·  long-press a waypoint to remove it"
        color: mv.cLabel
        opacity: 0.6
        font.pixelSize: Math.round(12 * mv.u)
        font.family: "Inter, Segoe UI, sans-serif"
    }

    // right-hand control column (zoom pill, locate, compass) - Neuboat style
    Column {
        id: ctrl
        anchors.right: parent.right
        anchors.rightMargin: 22 * mv.u
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20 * mv.u
        spacing: 12 * mv.u
        z: 20

        Rectangle {                                             // launch point shortcut
            visible: mv.namedPoints.length > 0
            width: 48 * mv.u; height: 48 * mv.u; radius: 8 * mv.u
            color: "#f1f1f1"; border.color: Qt.rgba(0, 0, 0, 0.12)
            Rectangle { x: 17 * mv.u; y: 11 * mv.u; width: 2.6 * mv.u; height: 26 * mv.u; color: mv.cNavy }
            Shape {
                preferredRendererType: Shape.GeometryRenderer
                scale: mv.u
                transformOrigin: Item.TopLeft
                ShapePath { fillColor: mv.cNavy; strokeColor: "transparent"; PathSvg { path: "M19.5 11 L33 16.5 L19.5 22 Z" } }
            }
            MouseArea { anchors.fill: parent; onClicked: mv.flyToPoint(0) }
        }

        Rectangle {
            width: 48 * mv.u
            height: 118 * mv.u
            radius: 8 * mv.u
            color: "#f1f1f1"
            border.color: Qt.rgba(0, 0, 0, 0.12)
            Item {
                width: parent.width; height: parent.height / 2
                Rectangle { anchors.centerIn: parent; width: 18 * mv.u; height: 3.5 * mv.u; radius: 1; color: "#6b6b6b" }
                Rectangle { anchors.centerIn: parent; width: 3.5 * mv.u; height: 18 * mv.u; radius: 1; color: "#6b6b6b" }
                MouseArea { anchors.fill: parent; onClicked: mv.zoomBy(1) }
            }
            Rectangle { y: parent.height / 2; x: 6 * mv.u; width: parent.width - 12 * mv.u; height: 1; color: "#c9c9c9" }
            Item {
                y: parent.height / 2; width: parent.width; height: parent.height / 2
                Rectangle { anchors.centerIn: parent; width: 18 * mv.u; height: 3.5 * mv.u; radius: 1; color: "#6b6b6b" }
                MouseArea { anchors.fill: parent; onClicked: mv.zoomBy(-1) }
            }
        }
        Rectangle {
            width: 48 * mv.u; height: 48 * mv.u; radius: 8 * mv.u
            color: "#f1f1f1"; border.color: Qt.rgba(0, 0, 0, 0.12)
            Rectangle { anchors.centerIn: parent; width: 22 * mv.u; height: width; radius: width / 2; color: "transparent"; border.color: mv.following ? "#2f6fe0" : "#5d5d5d"; border.width: 2.4 * mv.u }
            Rectangle { anchors.centerIn: parent; width: 8 * mv.u; height: width; radius: width / 2; color: mv.following ? "#2f6fe0" : "#5d5d5d" }
            Repeater {
                model: 4
                delegate: Rectangle {
                    width: index % 2 === 0 ? 2.4 * mv.u : 7 * mv.u; height: index % 2 === 0 ? 7 * mv.u : 2.4 * mv.u
                    color: mv.following ? "#2f6fe0" : "#5d5d5d"
                    x: parent.width / 2 - width / 2 + (index === 1 ? 14 * mv.u : index === 3 ? -14 * mv.u : 0)
                    y: parent.height / 2 - height / 2 + (index === 0 ? -14 * mv.u : index === 2 ? 14 * mv.u : 0)
                }
            }
            MouseArea { anchors.fill: parent; onClicked: mv.recenter() }
        }
        Rectangle {
            width: 48 * mv.u; height: 48 * mv.u; radius: 8 * mv.u
            color: "#f1f1f1"; border.color: Qt.rgba(0, 0, 0, 0.12)
            Rectangle {
                anchors.centerIn: parent; width: 36 * mv.u; height: width; radius: width / 2; color: "#1c1c1c"
                Rectangle { x: parent.width / 2 - 2.5 * mv.u; y: 3 * mv.u; width: 5 * mv.u; height: width; radius: width / 2; color: "#e0443c" }
                Text {
                    anchors.centerIn: parent
                    text: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((mv.vesselHdg % 360) + 360) % 360 / 45) % 8]
                    color: "#f2f2f2"; font.pixelSize: Math.round(12 * mv.u); font.bold: true
                }
            }
        }
    }

    // bottom action row (left of the control column)
    Row {
        id: actionRow
        anchors.right: ctrl.left
        anchors.rightMargin: 16 * mv.u
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20 * mv.u
        spacing: 12 * mv.u
        z: 20

        // planning: clear + start
        Rectangle {
            visible: !mv.navigating && mv.waypoints.length > 0
            width: 110 * mv.u; height: 48 * mv.u; radius: 6 * mv.u
            color: Qt.rgba(0.40, 0.44, 0.52, 0.80)
            border.color: Qt.rgba(1, 1, 1, 0.18)
            Text { anchors.centerIn: parent; text: "Clear"; color: "#eef1f6"; font.pixelSize: Math.round(17 * mv.u); font.family: "Inter, Segoe UI, sans-serif" }
            MouseArea { anchors.fill: parent; onClicked: mv.clearWaypoints() }
        }
        Rectangle {
            visible: !mv.navigating && mv.waypoints.length > 0
            width: 200 * mv.u; height: 48 * mv.u; radius: 6 * mv.u
            color: mv.armed ? Qt.rgba(0.15, 0.62, 0.40, 0.92) : Qt.rgba(0.18, 0.40, 0.78, 0.90)
            border.color: Qt.rgba(1, 1, 1, 0.22)
            Text { anchors.centerIn: parent; text: mv.armed ? "Tap again to confirm" : "Start Mission"; color: "#ffffff"; font.pixelSize: Math.round(17 * mv.u); font.bold: true; font.family: "Inter, Segoe UI, sans-serif" }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!mv.armed) { mv.armed = true; armTimer.restart(); }
                    else { mv.armed = false; armTimer.stop(); mv.startRequested(mv.waypoints); }
                }
            }
        }
        // navigating: End Navigation (steel blue, as in the reference)
        Rectangle {
            visible: mv.navigating
            width: 220 * mv.u; height: 48 * mv.u; radius: 3 * mv.u
            color: Qt.rgba(0.56, 0.60, 0.69, 0.78)
            border.color: Qt.rgba(1, 1, 1, 0.20)
            Text { anchors.centerIn: parent; text: "End Navigation"; color: "#eaf1f6"; font.pixelSize: Math.round(18 * mv.u); font.family: "Inter, Segoe UI, sans-serif" }
            MouseArea { anchors.fill: parent; onClicked: mv.endRequested() }
        }
    }

    Component.onCompleted: { assignLevel(); touch(); }
}
