import QtQuick
import QtPositioning

// =============================================================================
//  GnssSource  -  ONE place that decides where the boat is.            (loaded through a Loader in Main.qml,
//  so a Qt without QtPositioning only loses route 3, it can never break the UI)
//
//  priority (first valid wins):
//    1. vesselState.latitude / longitude      (your telemetry; also accepts .lat / .lon / .lng)
//    2. missionMap.gnssLat / gnssLon          (gpsd via backend.startGpsd(), or backend.setGnss(...))
//    3. QtPositioning PositionSource          (NMEA serial / socket, or the OS location service on a PC)
//    4. last known position                   (stored by the backend, survives restarts)
//    5. optional IP geolocation               (allowIpLookup, OFF by default: needs internet)
//    6. homeLat / homeLon                     (configurable default)
//
//  outputs: lat, lon, heading (deg), speedKn, fix (0 none, 2 = 2D, 3 = 3D), source (text), live (bool)
// =============================================================================
Item {
    id: g
    visible: false

    // ---- configuration
    property string nmeaSource: ""                 // "" = OS location service;  "serial:/dev/ttyACM0"  or  "socket://127.0.0.1:22222"
    property int nmeaBaud: 9600
    property real homeLat: 13.0827                 // used only when nothing else is known
    property real homeLon: 80.2707
    property bool allowIpLookup: false             // true on a dev PC without GNSS -> approximate city-level position
    property string ipLookupUrl: "https://ipapi.co/json/"
    property var vessel: (typeof vesselState !== "undefined") ? vesselState : null
    property var backend: (typeof missionMap !== "undefined") ? missionMap : null

    // ---- outputs
    property real lat: homeLat
    property real lon: homeLon
    property real heading: 0
    property real speedKn: 0
    property int fix: 0
    property string source: "DEFAULT"
    readonly property bool live: fix >= 2
    readonly property string text: (fix >= 3 ? "GNSS 3D" : fix === 2 ? "GNSS 2D" : "NO FIX") + "  ·  " + source

    property real _ipLat: NaN
    property real _ipLon: NaN
    property var _last: null

    function finite(v) { return v !== undefined && v !== null && isFinite(v); }
    function set(la, lo, hd, kn, fx, src) {
        if (Math.abs(la - lat) > 1e-7) lat = la;
        if (Math.abs(lo - lon) > 1e-7) lon = lo;
        if (hd !== heading) heading = hd;
        if (kn !== speedKn) speedKn = kn;
        if (fx !== fix) fix = fx;
        if (src !== source) source = src;
    }

    function refresh() {
        var v = vessel, b = backend;
        // 1. telemetry
        if (v) {
            var la = (v.latitude !== undefined) ? v.latitude : v.lat;
            var lo = (v.longitude !== undefined) ? v.longitude : (v.lon !== undefined ? v.lon : v.lng);
            if (finite(la) && finite(lo) && !(la === 0 && lo === 0)) {
                var fq = (v.gnssFix !== undefined) ? v.gnssFix : (v.gpsFix !== undefined ? v.gpsFix : 3);
                set(la, lo, finite(v.heading) ? v.heading : 0, finite(v.speed) ? v.speed : 0, Math.max(2, fq), "TELEMETRY");
                return;
            }
        }
        // 2. gpsd / setGnss
        if (b && b.gnssFix >= 2 && finite(b.gnssLat) && finite(b.gnssLon)) {
            set(b.gnssLat, b.gnssLon, (v && finite(v.heading)) ? v.heading : b.gnssHeading, b.gnssSpeedKn, b.gnssFix, "GPSD");
            return;
        }
        // 3. QtPositioning
        var pi = nmeaLoader.item ? nmeaLoader.item : osSource;
        var c = pi.position.coordinate;
        if (pi.valid && c.isValid) {
            var spd = pi.position.speedValid ? pi.position.speed * 1.943844 : 0;
            var dir = pi.position.directionValid ? pi.position.direction : ((v && finite(v.heading)) ? v.heading : 0);
            set(c.latitude, c.longitude, dir, spd, pi.position.altitudeValid ? 3 : 2, nmeaLoader.item ? "NMEA" : "OS LOCATION");
            return;
        }
        // 4. last known
        if (_last === null && b) _last = b.loadLastPosition();
        if (_last && _last.ok) { set(_last.lat, _last.lon, (v && finite(v.heading)) ? v.heading : 0, 0, 0, "LAST KNOWN"); return; }
        // 5. ip
        if (finite(_ipLat) && finite(_ipLon)) { set(_ipLat, _ipLon, 0, 0, 0, "IP (approx.)"); return; }
        // 6. default
        set(homeLat, homeLon, (v && finite(v.heading)) ? v.heading : 0, 0, 0, "DEFAULT");
    }

    PositionSource {
        id: osSource
        active: g.nmeaSource === ""
        updateInterval: 500
        preferredPositioningMethods: PositionSource.AllPositioningMethods
    }
    Loader {
        id: nmeaLoader
        active: g.nmeaSource !== ""
        sourceComponent: PositionSource {
            name: "nmea"
            active: true
            updateInterval: 500
            PluginParameter { name: "nmea.source"; value: g.nmeaSource }
            PluginParameter { name: "nmea.baudrate"; value: g.nmeaBaud }
        }
    }

    Timer { interval: 250; running: true; repeat: true; triggeredOnStart: true; onTriggered: g.refresh() }
    Component.onCompleted: refresh()

    // remember the last real fix (every 20 s)
    Timer {
        interval: 20000
        running: g.live && g.backend !== null
        repeat: true
        onTriggered: g.backend.saveLastPosition(g.lat, g.lon)
    }

    // optional, opt-in IP lookup (dev PC only)
    Timer {
        interval: 2500
        running: g.allowIpLookup && !g.live && !g.finite(g._ipLat)
        repeat: false
        onTriggered: {
            var x = new XMLHttpRequest();
            x.onreadystatechange = function() {
                if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200) return;
                try { var j = JSON.parse(x.responseText); if (g.finite(j.latitude) && g.finite(j.longitude)) { g._ipLat = j.latitude; g._ipLon = j.longitude; } } catch (e) {}
            };
            x.open("GET", g.ipLookupUrl);
            x.send();
        }
    }
}
