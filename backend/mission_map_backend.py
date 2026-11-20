"""
mission_map_backend.py  -  offline vector-tile + GNSS backend for MissionMapView.qml
=================================================================================

WHY THIS DESIGN  (short version, details in the chat answer)
  * map data  = MBTiles files holding Mapbox-Vector-Tiles (OpenStreetMap / Protomaps / OpenMapTiles).
    A regional pack (e.g. 100 km x 100 km, z0..z14) is only ~15-60 MB, a raster pack of the same
    area is 5-10x bigger.  Everything is read from local disk: no network, works at sea.
  * decoding is done here (pure Python, no extra dependency) on 2 worker threads, newest request
    first, and returns ready-made SVG path strings, so the QML side only has to draw them on the GPU.
  * several packs can be dropped into one folder; a small regional pack automatically overrides a
    coarse world pack where it has tiles.
  * GNSS: three independent routes (any one is enough)
        1. gpsd           ->  backend.startGpsd()                       (recommended on the Jetson)
        2. your telemetry ->  backend.setGnss(lat, lon, hdg, kn, fix)   (e.g. from the autopilot)
        3. NMEA / OS      ->  QtPositioning, handled in GnssSource.qml

Hook-up (one place, next to your other setContextProperty calls):

    from mission_map_backend import MissionMapBackend
    missionMap = MissionMapBackend(os.path.join(APP_DIR, "maps"))      # folder with *.mbtiles
    missionMap.startGpsd()                                             # optional, harmless if no gpsd
    engine.rootContext().setContextProperty("missionMap", missionMap)

Only needs PySide6 + the Python standard library.
"""
import glob
import gzip
import json
import math
import os
import queue
import socket
import sqlite3
import threading
import time
import zlib
from collections import OrderedDict

from PySide6.QtCore import QObject, Property, Signal, Slot, QStandardPaths

TILE_PX = 512.0          # logical size of one tile in the QML engine

# --------------------------------------------------------------------------
#  minimal protobuf / MVT decoder
# --------------------------------------------------------------------------


def _varint(buf, pos):
    r = 0
    s = 0
    while True:
        b = buf[pos]
        pos += 1
        r |= (b & 0x7F) << s
        if b < 0x80:
            return r, pos
        s += 7


def _skip(buf, pos, wt):
    if wt == 0:
        return _varint(buf, pos)[1]
    if wt == 1:
        return pos + 8
    if wt == 5:
        return pos + 4
    ln, pos = _varint(buf, pos)
    return pos + ln


def _packed(buf, a, b):
    out = []
    pos = a
    while pos < b:
        v, pos = _varint(buf, pos)
        out.append(v)
    return out


def _decode_value(buf, a, b):
    pos = a
    val = None
    while pos < b:
        k, pos = _varint(buf, pos)
        fn, wt = k >> 3, k & 7
        if fn == 1 and wt == 2:
            ln, pos = _varint(buf, pos)
            val = bytes(buf[pos:pos + ln]).decode("utf-8", "replace")
            pos += ln
        elif fn == 3 and wt == 1:
            import struct
            val = struct.unpack("<d", bytes(buf[pos:pos + 8]))[0]
            pos += 8
        elif fn == 2 and wt == 5:
            import struct
            val = struct.unpack("<f", bytes(buf[pos:pos + 4]))[0]
            pos += 4
        elif wt == 0:
            v, pos = _varint(buf, pos)
            if fn == 6:
                v = (v >> 1) ^ -(v & 1)
            elif fn == 7:
                v = bool(v)
            val = v
        else:
            pos = _skip(buf, pos, wt)
    return val


def _decode_layer(buf, a, b):
    name = ""
    extent = 4096
    keys = []
    values = []
    feats = []                     # (type, tags, geometry) spans decoded lazily
    pos = a
    while pos < b:
        k, pos = _varint(buf, pos)
        fn, wt = k >> 3, k & 7
        if wt == 2:
            ln, pos = _varint(buf, pos)
            end = pos + ln
            if fn == 1:
                name = bytes(buf[pos:end]).decode("utf-8", "replace")
            elif fn == 2:
                feats.append((pos, end))
            elif fn == 3:
                keys.append(bytes(buf[pos:end]).decode("utf-8", "replace"))
            elif fn == 4:
                values.append(_decode_value(buf, pos, end))
            pos = end
        elif wt == 0:
            v, pos = _varint(buf, pos)
            if fn == 5:
                extent = v
        else:
            pos = _skip(buf, pos, wt)
    return {"name": name, "extent": extent, "keys": keys, "values": values, "feats": feats, "buf": buf}


def decode_tile(buf):
    layers = []
    pos = 0
    n = len(buf)
    while pos < n:
        k, pos = _varint(buf, pos)
        fn, wt = k >> 3, k & 7
        if fn == 3 and wt == 2:
            ln, pos = _varint(buf, pos)
            layers.append(_decode_layer(buf, pos, pos + ln))
            pos += ln
        else:
            pos = _skip(buf, pos, wt)
    return layers


def _feature(layer, span):
    """-> (geomtype, props dict (lazy values), rings)"""
    buf = layer["buf"]
    pos, end = span
    gtype = 0
    tags = []
    geom = []
    while pos < end:
        k, pos = _varint(buf, pos)
        fn, wt = k >> 3, k & 7
        if wt == 2:
            ln, pos = _varint(buf, pos)
            if fn == 2:
                tags = _packed(buf, pos, pos + ln)
            elif fn == 4:
                geom = _packed(buf, pos, pos + ln)
            pos += ln
        elif wt == 0:
            v, pos = _varint(buf, pos)
            if fn == 3:
                gtype = v
        else:
            pos = _skip(buf, pos, wt)
    keys, vals = layer["keys"], layer["values"]
    props = {}
    for i in range(0, len(tags) - 1, 2):
        try:
            props[keys[tags[i]]] = vals[tags[i + 1]]
        except IndexError:
            pass
    return gtype, props, geom


def _rings(geom):
    x = y = 0
    i = 0
    n = len(geom)
    out = []
    cur = None
    while i < n:
        c = geom[i]
        i += 1
        cmd, cnt = c & 7, c >> 3
        if cmd == 1 or cmd == 2:
            for _ in range(cnt):
                dx, dy = geom[i], geom[i + 1]
                i += 2
                x += (dx >> 1) ^ -(dx & 1)
                y += (dy >> 1) ^ -(dy & 1)
                if cmd == 1:
                    cur = [(x, y)]
                    out.append(cur)
                else:
                    cur.append((x, y))
        elif cmd == 7 and cur:
            cur.append(cur[0])
    return out


# --------------------------------------------------------------------------
#  schema mapping  (Protomaps  +  OpenMapTiles)  ->  fixed style classes
# --------------------------------------------------------------------------
PARK_KINDS = {"park", "nature_reserve", "national_park", "grass", "meadow", "golf_course", "recreation_ground", "garden",
              "grassland", "protected_area", "village_green", "wetland", "cemetery", "sand", "bare_rock", "scree"}
WOOD_KINDS = {"forest", "wood", "scrub", "heath", "orchard", "plantation", "vineyard"}
FARM_KINDS = {"farmland", "farm", "farmyard", "allotments", "greenhouse_horticulture", "cropland"}
URBAN_KINDS = {"residential", "industrial", "commercial", "retail", "urban_area", "built_up_area", "village",
               "quarry", "construction", "brownfield", "military", "urban"}
ROAD_LEVEL = {   # kind -> (level 0 = highway ... 4 = other)
    "highway": 0, "motorway": 0, "trunk": 0, "motorway_link": 0, "trunk_link": 0,
    "major_road": 1, "primary": 1, "primary_link": 1,
    "medium_road": 2, "secondary": 2, "secondary_link": 2, "tertiary": 2, "tertiary_link": 2,
    "minor_road": 3, "minor": 3, "service": 3, "residential": 3, "unclassified": 3, "living_street": 3,
    "other": 4,
}
PIER_KINDS = {"pier", "jetty", "breakwater", "groyne"}
TRACK_KINDS = {"track", "path", "footway", "pedestrian", "bridleway", "cycleway", "steps", "trail", "bridge_path"}   # thin, un-cased lines (z14+)
PLACE_RANK = {"continent": 0, "country": 1, "region": 2, "state": 2, "province": 2, "island": 3, "locality": 3,
              "city": 3, "town": 4, "village": 5, "macrohood": 6, "suburb": 6, "neighbourhood": 7,
              "hamlet": 7, "quarter": 7}


def _ov(rings, f, ox, oy, ext):
    """overzoom: re-express rings of an ANCESTOR tile in the coordinate space of one of its sub-tiles
       (x' = x*f - ox, ox = sub_x*ext); rings that miss the sub-tile entirely are dropped"""
    out = []
    lo, hi = -ext * 0.05, ext * 1.05
    for r in rings:
        rr = [(x * f - ox, y * f - oy) for x, y in r]
        xs = [p[0] for p in rr]
        ys = [p[1] for p in rr]
        if max(xs) < lo or min(xs) > hi or max(ys) < lo or min(ys) > hi:
            continue
        out.append(rr)
    return out


def _fmt(rings, s, closed):
    parts = []
    for r in rings:
        if len(r) < 2:
            continue
        seg = ["M%.1f %.1f" % (r[0][0] * s, r[0][1] * s)]
        seg.append("L" + " ".join("%.1f %.1f" % (px * s, py * s) for px, py in r[1:]))
        if closed:
            seg.append("Z")
        parts.append("".join(seg))
    return "".join(parts)


def _coast(rings, ext, s):
    """outline of land polygons but WITHOUT the segments that only lie on the tile border"""
    runs = []
    for r in rings:
        run = [r[0]]
        for a, b in zip(r, r[1:]):
            if (a[0] == b[0] and (a[0] <= 0 or a[0] >= ext)) or (a[1] == b[1] and (a[1] <= 0 or a[1] >= ext)):
                if len(run) > 1:
                    runs.append(run)
                run = [b]
            else:
                run.append(b)
        if len(run) > 1:
            runs.append(run)
    return _fmt(runs, s, False)


def build_tile(raw, z, shelf=True, ov=None):
    """raw = decompressed MVT bytes  ->  dict of path strings / label list for QML.
       ov = (k, sub_x, sub_y): the tile is a 2^k overzoomed sub-tile of `raw` (which belongs to zoom z)"""
    layers = decode_tile(raw)
    if ov:
        ov_f = float(1 << ov[0])
        _rings0 = _rings
        _rings_ov = lambda g, ext: _ov(_rings0(g), ov_f, ov[1] * ext, ov[2] * ext, ext)
    byname = {l["name"]: l for l in layers}
    out = {"earth": "", "water": "", "parks": "", "wood": "", "farm": "", "urban": "", "shoreMid": "", "shoreNear": "", "buildings": "", "rivers": "", "coast": "",
           "roads0": "", "roads1": "", "roads2": "", "roads3": "", "tracks": "", "piers": "", "places": [], "landBg": False, "empty": False, "shelf": shelf}
    polys = {"earth": [], "water": [], "parks": [], "wood": [], "farm": [], "urban": [], "shoreMid": [], "shoreNear": [], "buildings": []}
    lines = {"rivers": [], "r0": [], "r1": [], "r2": [], "r3": [], "tr": [], "pr": []}
    coast_rings = []
    s_of = lambda l: TILE_PX / float(l["extent"])
    ext_of = lambda l: l["extent"]
    max_road = 0 if z < 8 else 1 if z < 10 else 2 if z < 12 else 3 if z < 15 else 4

    for l in layers:
        name = l["name"]
        s = s_of(l)
        R = (lambda g, _e=l["extent"]: _rings_ov(g, _e)) if ov else _rings
        for span in l["feats"]:
            gtype, p, geom = _feature(l, span)
            kind = p.get("kind") or p.get("pmap:kind") or p.get("class") or ""
            if name == "earth" and gtype == 3:
                r = R(geom)
                polys["earth"].append((r, s))
                coast_rings.append((r, l["extent"], s))
            elif name == "water":
                if gtype == 3:
                    r = R(geom)
                    polys["water"].append((r, s))
                    if "earth" not in byname and kind in ("ocean", "sea", "bay", ""):
                        coast_rings.append((r, l["extent"], s))
                elif gtype == 2:
                    lines["rivers"].append((R(geom), s))
            elif name == "shore" and gtype == 3:
                polys["shoreMid" if kind == "mid" else "shoreNear"].append((R(geom), s))
            elif name == "waterway" and gtype == 2:
                if kind in ("river", "canal", "stream", "") and (kind != "stream" or z >= 13):
                    lines["rivers"].append((R(geom), s))
            elif name in ("landuse", "natural", "landcover") and gtype == 3 and kind:
                if kind in WOOD_KINDS:
                    polys["wood"].append((R(geom), s))
                elif kind in FARM_KINDS:
                    polys["farm"].append((R(geom), s))
                elif kind in URBAN_KINDS:
                    polys["urban"].append((R(geom), s))
                elif kind in PARK_KINDS:
                    polys["parks"].append((R(geom), s))
            elif name in ("buildings", "building") and gtype == 3 and z >= 15:
                polys["buildings"].append((R(geom), s))
            elif name in ("roads", "transportation") and gtype == 2 and kind in PIER_KINDS:
                if z >= 14:
                    lines["pr"].append((R(geom), s))
            elif name in ("roads", "transportation") and gtype == 2 and kind in TRACK_KINDS:
                if z >= 14:
                    lines["tr"].append((R(geom), s))
            elif name in ("roads", "transportation") and gtype == 2:
                lv = ROAD_LEVEL.get(kind, 9)
                if lv <= max_road:
                    lines["r%d" % min(lv, 3)].append((R(geom), s))
            elif name in ("places", "place") and gtype == 1:
                nm = p.get("name:en") or p.get("name") or ""
                if not nm:
                    continue
                pt = R(geom)
                if not pt:
                    continue
                x, y = pt[0][0]
                if ov and not (0 <= x <= l["extent"] and 0 <= y <= l["extent"]):
                    continue
                rk = p.get("rank", p.get("pmap:rank", p.get("scalerank")))
                if rk is None:
                    rk = PLACE_RANK.get(kind, 5)
                try:
                    rk = float(rk)
                except Exception:
                    rk = 5.0
                out["places"].append({"x": x * s, "y": y * s, "name": nm, "rank": rk, "kind": kind})
    if "earth" not in byname and "water" in byname:
        out["landBg"] = True            # OpenMapTiles: land is the background, water is drawn on top
    for key in ("earth", "water", "parks", "wood", "farm", "urban", "shoreMid", "shoreNear", "buildings"):
        out[key] = "".join(_fmt(r, s, True) for r, s in polys[key])
    out["rivers"] = "".join(_fmt(r, s, False) for r, s in lines["rivers"])
    for i in range(4):
        out["roads%d" % i] = "".join(_fmt(r, s, False) for r, s in lines["r%d" % i])
    out["tracks"] = "".join(_fmt(r, s, False) for r, s in lines["tr"])
    out["piers"] = "".join(_fmt(r, s, False) for r, s in lines["pr"])
    out["coast"] = "".join(_coast(r, e, s) for r, e, s in coast_rings)
    out["empty"] = not any(out[k] for k in ("earth", "water", "parks", "wood", "farm", "urban", "rivers", "roads0", "roads1", "roads2", "roads3", "tracks", "piers", "buildings"))
    return out


# --------------------------------------------------------------------------
#  MBTiles pack
# --------------------------------------------------------------------------
class _Pack:
    def __init__(self, path):
        self.path = path
        self._tl = threading.local()
        con = self._con()
        meta = dict(con.execute("SELECT name, value FROM metadata").fetchall())
        self.name = meta.get("name") or os.path.basename(path)
        self.attribution = meta.get("attribution", "")
        self.minzoom = int(float(meta.get("minzoom", 0)))
        self.maxzoom = int(float(meta.get("maxzoom", 14)))
        b = [float(v) for v in meta.get("bounds", "-180,-85.0511,180,85.0511").split(",")]
        self.bounds = b                                  # w s e n
        self.area = max(1e-6, (b[2] - b[0]) * (b[3] - b[1]))
        self.fmt = meta.get("format", "pbf")
        self.shelf = str(meta.get("shelf", "1")).strip().lower() not in ("0", "false", "no")   # ocean packs: depth-shelf shading; inland packs: thin shore shading

    def _con(self):
        c = getattr(self._tl, "c", None)
        if c is None:
            c = sqlite3.connect("file:%s?mode=ro" % self.path, uri=True, check_same_thread=False)
            self._tl.c = c
        return c

    def covers_tile(self, z, x, y):
        if z < self.minzoom or z > self.maxzoom:
            return False
        n = 2 ** z
        w, s, e, nn = self.bounds
        lon0, lon1 = x / n * 360 - 180, (x + 1) / n * 360 - 180
        lat = lambda ty: math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * ty / n))))
        lat_top, lat_bot = lat(y), lat(y + 1)
        return not (lon1 <= w or lon0 >= e or lat_top <= s or lat_bot >= nn)

    def get(self, z, x, y):
        row = self._con().execute(
            "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
            (z, x, (1 << z) - 1 - y)).fetchone()
        if not row:
            return None
        d = row[0]
        if d[:2] == b"\x1f\x8b":
            d = gzip.decompress(d)
        elif d[:1] == b"x":
            d = zlib.decompress(d)
        return d


# --------------------------------------------------------------------------
#  the QObject exposed to QML
# --------------------------------------------------------------------------
class MissionMapBackend(QObject):
    tileReady = Signal(int, int, int, "QVariantMap")
    packsChanged = Signal()
    gnssChanged = Signal()

    def __init__(self, maps_dir=None, parent=None, workers=2, cache_tiles=300):
        super().__init__(parent)
        self._packs = []
        self._cache = OrderedDict()
        self._cache_max = cache_tiles
        self._lock = threading.Lock()
        self._wanted = set()
        self._q = queue.LifoQueue()
        self._alive = True
        self._gnss = {"lat": float("nan"), "lon": float("nan"), "hdg": 0.0, "kn": 0.0, "fix": 0, "hdop": 99.0, "t": 0.0}
        self.rescan(maps_dir)
        self._threads = []
        for i in range(max(1, workers)):
            t = threading.Thread(target=self._worker, name="mm-tile-%d" % i, daemon=True)
            t.start()
            self._threads.append(t)

    # ---------------- packs ----------------
    def rescan(self, maps_dir=None):
        paths = []
        if maps_dir:
            if os.path.isfile(maps_dir):
                paths = [maps_dir]
            else:
                paths = sorted(glob.glob(os.path.join(maps_dir, "*.mbtiles")))
        packs = []
        for p in paths:
            try:
                packs.append(_Pack(p))
            except Exception as e:                              # a broken file must never kill the UI
                print("[missionMap] cannot open", p, e)
        packs.sort(key=lambda k: k.area)                        # smallest (most local) pack wins
        self._packs = packs
        with self._lock:
            self._cache.clear()
        self.packsChanged.emit()

    @Property(bool, notify=packsChanged)
    def available(self):
        return bool(self._packs)

    @Property(int, notify=packsChanged)
    def minZoom(self):
        return min([p.minzoom for p in self._packs] or [0])

    @Property(int, notify=packsChanged)
    def maxZoom(self):
        return max([p.maxzoom for p in self._packs] or [0])

    @Property(str, notify=packsChanged)
    def attribution(self):
        seen = []
        for p in self._packs:
            if p.attribution and p.attribution not in seen:
                seen.append(p.attribution)
        return "  |  ".join(seen)

    @Property(str, notify=packsChanged)
    def packSummary(self):
        return ", ".join("%s (z%d-%d)" % (p.name, p.minzoom, p.maxzoom) for p in self._packs)

    @Slot(float, float, result=bool)
    def covers(self, lat, lon):
        return any(p.bounds[0] <= lon <= p.bounds[2] and p.bounds[1] <= lat <= p.bounds[3] for p in self._packs)

    @Slot(float, float, result=int)
    def maxDetailZoomAt(self, lat, lon):
        z = -1
        for p in self._packs:
            if p.bounds[0] <= lon <= p.bounds[2] and p.bounds[1] <= lat <= p.bounds[3]:
                z = max(z, p.maxzoom)
        return z

    # ---------------- tiles ----------------
    @Slot(int, int, int)
    def requestTile(self, z, x, y):
        key = (z, x, y)
        with self._lock:
            self._wanted.add(key)
        self._q.put(key)

    @Slot(int, int, int)
    def cancelTile(self, z, x, y):
        with self._lock:
            self._wanted.discard((z, x, y))

    def _load(self, z, x, y):
        key = (z, x, y)
        with self._lock:
            hit = self._cache.get(key)
            if hit is not None:
                self._cache.move_to_end(key)
                return hit
        res = None
        covered = False
        for p in self._packs:
            if not p.covers_tile(z, x, y):
                continue
            covered = True
            raw = p.get(z, x, y)
            if raw:
                res = build_tile(raw, z, p.shelf)
                break
        if res is None:                                          # overzoom: use the nearest ancestor tile that exists (up to 4 levels up)
            for p in self._packs:
                for k in range(1, 5):
                    zk = z - k
                    if zk < p.minzoom or zk > p.maxzoom:
                        continue
                    axk, ayk = x >> k, y >> k
                    if not p.covers_tile(zk, axk, ayk):
                        continue
                    raw = p.get(zk, axk, ayk)
                    if raw:
                        res = build_tile(raw, zk, p.shelf, ov=(k, x - (axk << k), y - (ayk << k)))
                        covered = True
                        break
                if res is not None:
                    break
        if res is None:
            res = {"empty": True, "noData": not covered, "earth": "", "water": "", "parks": "", "wood": "", "farm": "", "urban": "", "shoreMid": "", "shoreNear": "", "shelf": True, "buildings": "",
                   "rivers": "", "coast": "", "roads0": "", "roads1": "", "roads2": "", "roads3": "", "tracks": "", "piers": "",
                   "places": [], "landBg": False}
        else:
            res["noData"] = False
        with self._lock:
            self._cache[key] = res
            while len(self._cache) > self._cache_max:
                self._cache.popitem(last=False)
        return res

    def _worker(self):
        while self._alive:
            try:
                key = self._q.get(timeout=0.5)
            except queue.Empty:
                continue
            with self._lock:
                if key not in self._wanted:
                    continue
            try:
                res = self._load(*key)
            except Exception as e:
                print("[missionMap] tile", key, "failed:", e)
                continue
            with self._lock:
                if key not in self._wanted:
                    continue
            self.tileReady.emit(key[0], key[1], key[2], res)

    # ---------------- GNSS ----------------
    @Slot(float, float, float, float, int)
    def setGnss(self, lat, lon, heading_deg, speed_kn, fix):
        g = self._gnss
        g.update(lat=lat, lon=lon, hdg=heading_deg, kn=speed_kn, fix=fix, t=time.time())
        self.gnssChanged.emit()

    @Property(float, notify=gnssChanged)
    def gnssLat(self):
        return self._gnss["lat"]

    @Property(float, notify=gnssChanged)
    def gnssLon(self):
        return self._gnss["lon"]

    @Property(float, notify=gnssChanged)
    def gnssHeading(self):
        return self._gnss["hdg"]

    @Property(float, notify=gnssChanged)
    def gnssSpeedKn(self):
        return self._gnss["kn"]

    @Property(int, notify=gnssChanged)
    def gnssFix(self):               # 0 none, 2 = 2D, 3 = 3D
        return self._gnss["fix"]

    def startGpsd(self, host="127.0.0.1", port=2947):
        """read gpsd (JSON TPV reports) in a background thread; silently retries if gpsd is not running"""
        def run():
            while self._alive:
                try:
                    s = socket.create_connection((host, port), timeout=3)
                    s.sendall(b'?WATCH={"enable":true,"json":true};\n')
                    s.settimeout(5)
                    f = s.makefile("r")
                    for line in f:
                        if not self._alive:
                            break
                        try:
                            d = json.loads(line)
                        except Exception:
                            continue
                        if d.get("class") == "TPV":
                            mode = int(d.get("mode", 0))
                            if mode >= 2 and "lat" in d and "lon" in d:
                                self.setGnss(float(d["lat"]), float(d["lon"]), float(d.get("track", self._gnss["hdg"])),
                                             float(d.get("speed", 0.0)) * 1.943844, mode)
                            else:
                                self.setGnss(self._gnss["lat"], self._gnss["lon"], self._gnss["hdg"], 0.0, 0)
                except Exception:
                    time.sleep(3)
        threading.Thread(target=run, name="mm-gpsd", daemon=True).start()

    # ---------------- last known position (survives restarts) ----------------
    def _pos_file(self):
        d = QStandardPaths.writableLocation(QStandardPaths.AppDataLocation) or os.path.expanduser("~/.tandav")
        os.makedirs(d, exist_ok=True)
        return os.path.join(d, "last_position.json")

    @Slot(float, float)
    def saveLastPosition(self, lat, lon):
        try:
            with open(self._pos_file(), "w") as fh:
                json.dump({"lat": lat, "lon": lon}, fh)
        except Exception:
            pass

    @Slot(result="QVariantMap")
    def loadLastPosition(self):
        try:
            with open(self._pos_file()) as fh:
                d = json.load(fh)
            return {"ok": True, "lat": float(d["lat"]), "lon": float(d["lon"])}
        except Exception:
            return {"ok": False, "lat": 0.0, "lon": 0.0}

    def shutdown(self):
        self._alive = False
