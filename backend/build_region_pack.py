#!/usr/bin/env python3
"""
build_region_pack.py  -  build a DETAILED regional offline map pack (MBTiles) from OpenStreetMap
=====================================================================================================
Run this ONCE on a PC that has internet (the boat computer never needs internet).

    pip install shapely mapbox-vector-tile numpy
    python3 build_region_pack.py                       # KRS backwaters + Srirangapatna (default box)
    python3 build_region_pack.py --bbox 76.32,12.33,76.76,12.64 --name krs_backwaters --maxzoom 16
    python3 build_region_pack.py --no-buildings        # smaller file
    python3 build_region_pack.py --from-json osm_cache # rebuild from the data already downloaded

Output:  krs_backwaters.mbtiles   ->  copy it into the app's  maps/  folder (next to demo_world.mbtiles).
The small regional pack automatically wins over the world demo pack inside its box; outside the box
you still see the coarse world map.

What it downloads (OpenStreetMap through the public Overpass API, in small chunks, cached on disk):
    water (reservoir / lake / river polygons, streams, canals, dams, weirs), islands (as holes in the water),
    forest, scrub, wetland, farmland, orchards, built-up areas, roads and tracks, buildings, village /
    town / island names, named water bodies and attractions.

Data (c) OpenStreetMap contributors (ODbL).  Please keep the attribution that is written into the pack.
"""
import argparse, gzip, hashlib, json, math, os, sqlite3, sys, time, urllib.parse, urllib.request

import numpy as np
import shapely
from shapely import STRtree
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import linemerge, polygonize, unary_union
import mapbox_vector_tile as mvt

EXT = 4096
BUF = 80
LATMAX = 85.0511287798
MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter",
           "https://overpass.private.coffee/api/interpreter"]
UA = "TANDAV-GCS-offline-pack-builder/1.0 (one-off regional extract)"

# ----------------------------------------------------------------------------- classification
WATER_TAGS = lambda t: (t.get("natural") == "water" or t.get("landuse") in ("reservoir", "basin")
                        or t.get("waterway") == "riverbank" or t.get("water") in ("reservoir", "lake", "river", "pond"))
WATERWAY_LINE = {"river", "stream", "canal", "drain"}
FOCUS_DEFAULT = (12.451754, 76.552337)                                   # RMSC Launch Point (first test site)
FOCUS_NAME = "RMSC Launch Point"
POI_AMENITY = {"place_of_worship", "restaurant", "cafe", "fast_food", "parking", "shelter", "toilets", "boat_rental", "school",
               "ferry_terminal", "bus_station", "drinking_water", "fuel", "police", "hospital", "clinic", "community_centre",
               "marketplace", "bank", "college", "university", "townhall", "post_office"}
POI_TOURISM = {"hotel", "guest_house", "camp_site", "picnic_site", "resort", "information", "hostel", "zoo", "theme_park", "gallery"}
POI_LEISURE = {"slipway", "marina", "sports_centre", "water_park", "fishing", "swimming_area", "resort", "pitch", "playground"}
POI_MAN_MADE = {"lighthouse", "water_tower", "pier", "jetty", "dam", "pumping_station", "bridge", "breakwater", "groyne"}
PARKLIKE_LEISURE = {"pitch", "sports_centre", "playground"}                 # drawn with the park tone
LAND_KIND_FROM = (("landuse", {"forest", "farmland", "farmyard", "orchard", "plantation", "vineyard", "meadow", "grass",
                                "residential", "industrial", "commercial", "retail", "cemetery", "quarry", "brownfield",
                                "construction", "military", "recreation_ground", "village_green", "allotments"}),
                  ("natural", {"wood", "scrub", "wetland", "grassland", "heath", "bare_rock", "sand", "scree"}),
                  ("leisure", {"park", "garden", "nature_reserve", "golf_course", "pitch", "sports_centre", "playground"}))
ROAD_KINDS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "service", "track",
              "path", "living_street", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
              "footway", "pedestrian", "bridleway", "cycleway"}
ROAD_MINZ = {"motorway": 8, "trunk": 8, "motorway_link": 10, "trunk_link": 10, "primary": 8, "primary_link": 10,
             "secondary": 10, "secondary_link": 11, "tertiary": 11, "tertiary_link": 12, "unclassified": 12,
             "residential": 12, "living_street": 13, "service": 13, "track": 14, "path": 15, "footway": 15,
             "pedestrian": 14, "bridleway": 15, "cycleway": 14}
PLACE_MINZ = {"city": 6, "town": 8, "suburb": 11, "village": 10, "hamlet": 12, "island": 10, "islet": 13,
              "locality": 13, "neighbourhood": 14, "quarter": 13, "isolated_dwelling": 15}
PLACE_RANK = {"city": 3, "town": 4, "suburb": 6, "village": 5, "hamlet": 7, "island": 4, "islet": 7, "locality": 7,
              "neighbourhood": 7, "quarter": 7, "isolated_dwelling": 8, "water": 4, "attraction": 6, "dam": 5, "poi": 8}


def overpass_query(s, w, n, e, part="rest", buildings=True):
    """part='water'  -> every water object (relations are big: asked once for the whole box)
       part='rest'   -> land cover, roads, buildings, places (asked in small chunks)"""
    bb = "(%.5f,%.5f,%.5f,%.5f)" % (s, w, n, e)
    q = ['[out:json][timeout:300][maxsize:2147483648];', "("]
    if part == "water":
        q.append('nwr["natural"="water"]%s;' % bb)
        q.append('nwr["landuse"~"^(reservoir|basin)$"]%s;' % bb)
        q.append('nwr["water"~"^(reservoir|lake|river|pond|canal)$"]%s;' % bb)
        q.append('way["waterway"~"^(riverbank|river|stream|canal|drain|dam|weir)$"]%s;' % bb)
        q.append('relation["waterway"="riverbank"]%s;' % bb)
        q.append('nwr["waterway"="dam"]["name"]%s;' % bb)
    elif part == "focus":                                              # EVERYTHING that exists around the launch point (small box, asked once)
        q.append('nwr["natural"~"^(wood|scrub|wetland|grassland|heath|bare_rock|sand|scree|bay|strait|peninsula|cape|island|islet|beach|reef|shingle|mud)$"]%s;' % bb)
        q.append('nwr["landuse"]%s;' % bb)
        q.append('nwr["leisure"]%s;' % bb)
        q.append('nwr["man_made"~"^(%s|embankment|dyke|groyne|storage_tank|tower)$"]%s;' % ("|".join(sorted(POI_MAN_MADE)), bb))
        q.append('nwr["amenity"]["name"]%s;' % bb)
        q.append('nwr["tourism"]%s;' % bb)
        q.append('nwr["historic"]%s;' % bb)
        q.append('nwr["place"]%s;' % bb)
        q.append('way["highway"~"^(%s)$"]%s;' % ("|".join(sorted(ROAD_KINDS)), bb))
        q.append('way["building"]%s;' % bb)
    else:
        q.append('nwr["natural"~"^(wood|scrub|wetland|grassland|heath|bare_rock|sand|scree|bay|strait|peninsula|cape|island|islet)$"]["name"]%s;' % bb)
        q.append('nwr["natural"~"^(wood|scrub|wetland|grassland|heath|bare_rock|sand|scree)$"]%s;' % bb)
        q.append('nwr["landuse"~"^(forest|farmland|farmyard|orchard|plantation|vineyard|meadow|grass|residential|industrial|'
                 'commercial|retail|cemetery|quarry|brownfield|construction|military|recreation_ground|village_green|allotments)$"]%s;' % bb)
        q.append('nwr["leisure"~"^(park|garden|nature_reserve|golf_course)$"]%s;' % bb)
        q.append('way["highway"~"^(%s)$"]%s;' % ("|".join(sorted(ROAD_KINDS)), bb))
        if buildings:
            q.append('way["building"]%s;' % bb)
        q.append('nwr["place"]%s;' % bb)
        q.append('nwr["tourism"~"^(attraction|viewpoint|museum)$"]["name"]%s;' % bb)
    q.append(");")
    q.append("out geom;")
    return "\n".join(q)


def _partial(js):
    """Overpass answers HTTP 200 with a 'remark' when it ran out of time / memory: the data is then INCOMPLETE."""
    r = (js.get("remark") or "").lower()
    return any(k in r for k in ("runtime error", "timed out", "out of memory", "too many", "dispatcher"))


def fetch_chunk(s, w, n, e, cache_dir, part, buildings):
    key = hashlib.md5(("%.5f%.5f%.5f%.5f%s%d" % (s, w, n, e, part, buildings)).encode()).hexdigest()[:12]
    path = os.path.join(cache_dir, "%s_%s.json" % (part, key))
    if os.path.exists(path):
        with open(path) as fh:
            js = json.load(fh)
        if not _partial(js):
            return js
    data = urllib.parse.urlencode({"data": overpass_query(s, w, n, e, part, buildings)}).encode()
    last = None
    for attempt in range(8):
        url = MIRRORS[attempt % len(MIRRORS)]
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=420) as r:
                js = json.loads(r.read().decode("utf-8"))
            if _partial(js):
                raise RuntimeError("server returned partial data: %s" % js.get("remark"))
            with open(path, "w") as fh:
                json.dump(js, fh)
            return js
        except Exception as ex:                                           # busy server, timeout, 429, partial result ...
            last = ex
            wait = 10 * (attempt + 1)
            print("   retry in %ds (%s)" % (wait, str(ex)[:120]), flush=True)
            time.sleep(wait)
    raise SystemExit("Overpass failed for this part: %s\nTry again later (evenings IST are usually quieter) - finished parts are cached." % last)


def download(bbox, cache_dir, buildings, cell=0.1, focus_box=None):
    w, s, e, n = bbox
    os.makedirs(cache_dir, exist_ok=True)
    elements = {}
    print("download: water (whole box, once) ...", flush=True)
    js = fetch_chunk(s, w, n, e, cache_dir, "water", False)
    for el in js.get("elements", []):
        elements[(el["type"], el["id"])] = el
    if focus_box:
        fw, fs_, fe, fn = focus_box
        print("download: launch-point detail (small box, everything) ...", flush=True)
        js = fetch_chunk(fs_, fw, fn, fe, cache_dir, "focus", True)
        for el in js.get("elements", []):
            elements[(el["type"], el["id"])] = el
    nx, ny = max(1, math.ceil((e - w) / cell)), max(1, math.ceil((n - s) / cell))
    k = 0
    for i in range(nx):
        for j in range(ny):
            k += 1
            cw, ce = w + (e - w) * i / nx, w + (e - w) * (i + 1) / nx
            cs, cn = s + (n - s) * j / ny, s + (n - s) * (j + 1) / ny
            print("download: land / roads / buildings chunk %d/%d ..." % (k, nx * ny), flush=True)
            js = fetch_chunk(cs, cw, cn, ce, cache_dir, "rest", buildings)
            for el in js.get("elements", []):
                elements[(el["type"], el["id"])] = el                    # an object in 3 chunks is stored once
            time.sleep(1.5)
    return list(elements.values())


def load_cache(cache_dir):
    elements = {}
    for fn in sorted(os.listdir(cache_dir)):
        if fn.endswith(".json"):
            with open(os.path.join(cache_dir, fn)) as fh:
                js = json.load(fh)
            for el in js.get("elements", []):
                elements[(el["type"], el["id"])] = el
    return list(elements.values())


# ----------------------------------------------------------------------------- OSM -> shapely
def way_coords(g):
    return [(p["lon"], p["lat"]) for p in g]


STATS = {"rel_total": 0, "rel_ok": 0, "rel_failed": [], "gaps_repaired": 0, "gaps_dropped": 0}


def _repair_open(paths, tol):
    """join open polylines end-to-end (nearest end within tol degrees) and close the final loop.
    Real OSM multipolygons sometimes have a missing way or a tiny gap; Google/OSM renderers still draw them."""
    done = []
    paths = [list(p) for p in paths]
    d2 = lambda a, b: (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
    while paths:
        cur = paths.pop()
        while True:
            if len(paths) == 0 and len(cur) > 3 and d2(cur[0], cur[-1]) <= tol * tol:
                cur.append(cur[0]); done.append(cur); STATS["gaps_repaired"] += 1; break
            best, bi, brev = None, -1, False
            for i, q in enumerate(paths):
                for rev, endpt in ((False, q[0]), (True, q[-1])):
                    dd = d2(cur[-1], endpt)
                    if best is None or dd < best:
                        best, bi, brev = dd, i, rev
            selfd = d2(cur[-1], cur[0])
            if best is not None and best <= tol * tol and best <= selfd:
                q = paths.pop(bi)
                cur = cur + (q[::-1] if brev else q)
                STATS["gaps_repaired"] += 1
                continue
            if selfd <= tol * tol and len(cur) > 3:
                cur.append(cur[0]); done.append(cur); STATS["gaps_repaired"] += 1
            else:
                STATS["gaps_dropped"] += 1
            break
    return done


def assemble_rings(members, role, tol=0.01):
    """-> list of valid Polygons built from the member ways with this role"""
    segs = []
    for m in members:
        if m.get("type") == "way" and m.get("role", "") == role and m.get("geometry") and len(m["geometry"]) > 1:
            segs.append(LineString(way_coords(m["geometry"])))
    if not segs:
        return []
    closed = [l for l in segs if l.is_closed and len(l.coords) >= 4]
    opened = [l for l in segs if not (l.is_closed and len(l.coords) >= 4)]
    lines = list(closed)
    if opened:
        merged = linemerge(opened)
        parts = list(merged.geoms) if hasattr(merged, "geoms") else [merged]
        rings = [p for p in parts if p.is_closed and len(p.coords) >= 4]
        rest = [list(p.coords) for p in parts if not (p.is_closed and len(p.coords) >= 4)]
        lines += rings
        if rest:
            lines += [LineString(r) for r in _repair_open(rest, tol if role != "inner" else 0.002)]
    if not lines:
        return []
    out = []
    try:
        faces = list(polygonize(unary_union(lines)))                   # unary_union nodes crossings / touching ways first
    except Exception:
        faces = []
    if not faces:
        faces = [Polygon(l) for l in lines if len(l.coords) >= 4]
    for f in faces:
        if not f.is_valid:
            f = f.buffer(0)
        if not f.is_empty:
            out.append(f)
    return out


def polygon_of(el):
    """closed way or multipolygon relation -> shapely (Multi)Polygon or None"""
    try:
        if el["type"] == "way":
            g = el.get("geometry")
            if not g or len(g) < 4 or (g[0]["lat"], g[0]["lon"]) != (g[-1]["lat"], g[-1]["lon"]):
                return None
            p = Polygon(way_coords(g))
            if not p.is_valid:
                p = p.buffer(0)
            return None if p.is_empty else p
        if el["type"] != "relation":
            return None
        mem = el.get("members", [])
        outers = assemble_rings(mem, "outer") or assemble_rings(mem, "")
        if not outers:
            return None
        p = unary_union(outers)
        for inn in assemble_rings(mem, "inner"):                          # subtract the islands one by one: one bad island must not kill the lake
            try:
                q = p.difference(inn)
                if not q.is_empty:
                    p = q
            except Exception:
                try:
                    p = p.difference(inn.buffer(0))
                except Exception:
                    pass
        if not p.is_valid:
            p = p.buffer(0)
        return None if p.is_empty else p
    except Exception as ex:
        STATS["rel_failed"].append((el.get("id"), (el.get("tags") or {}).get("name", ""), str(ex)[:80]))
        return None


def point_of(el):
    """a representative (lon, lat) of any OSM element, or None"""
    if el["type"] == "node":
        return el["lon"], el["lat"]
    g = el.get("geometry")
    if g:
        return sum(p["lon"] for p in g) / len(g), sum(p["lat"] for p in g) / len(g)
    pts = [p for m in el.get("members", []) if m.get("geometry") for p in m["geometry"]]
    if pts:
        return sum(p["lon"] for p in pts) / len(pts), sum(p["lat"] for p in pts) / len(pts)
    return None


def poi_kind(t):
    """(kind, min zoom) for a named point of interest / geographic feature, or None"""
    nat = t.get("natural")
    if nat in ("bay", "strait"):
        return "water", 12
    if nat in ("peninsula", "cape"):
        return "locality", 13
    if nat in ("island", "islet"):
        return nat, PLACE_MINZ[nat]
    if nat in ("beach", "reef"):
        return "poi", 15
    if (t.get("amenity") in POI_AMENITY or t.get("tourism") in POI_TOURISM or t.get("leisure") in POI_LEISURE
            or t.get("man_made") in POI_MAN_MADE or "historic" in t):
        return "poi", 15
    return None


def classify(elements):
    water, rivers, land, roads, buildings, places = [], [], [], [], [], []
    for el in elements:
        t = el.get("tags", {})
        if not t:
            continue
        et = el["type"]
        name = t.get("name:en") or t.get("name") or ""
        # ---- water polygons
        if WATER_TAGS(t) and et in ("way", "relation") and t.get("waterway") not in ("river", "stream", "canal", "drain"):
            if et == "relation":
                STATS["rel_total"] += 1
            p = polygon_of(el)
            if et == "relation" and p is None:
                STATS["rel_failed"].append((el.get("id"), name, "could not build a polygon (members: %d)" % len(el.get("members", []))))
            if p is not None:
                if et == "relation":
                    STATS["rel_ok"] += 1
                water.append(p)
                if name and p.area > 2e-5:                              # named lake / reservoir -> a label at its centre
                    c = p.representative_point()
                    places.append((c.x, c.y, name, "water", 9 if p.area > 1e-3 else 11))
                continue
        # ---- waterway lines
        if et == "way" and t.get("waterway") in WATERWAY_LINE and el.get("geometry"):
            rivers.append((LineString(way_coords(el["geometry"])), t["waterway"]))
            continue
        if et == "way" and t.get("waterway") in ("dam", "weir") and el.get("geometry"):
            roads.append((LineString(way_coords(el["geometry"])), "service" if t["waterway"] == "weir" else "tertiary"))
        # ---- piers, jetties, embankments, slipways (drawn as lines; closed ones as small solid shapes)
        mmk = t.get("man_made")
        if et == "way" and el.get("geometry") and len(el["geometry"]) > 1 and (
                mmk in ("pier", "jetty", "breakwater", "groyne", "embankment", "dyke") or t.get("leisure") == "slipway"):
            co = way_coords(el["geometry"])
            closed = len(co) > 3 and co[0] == co[-1]
            if closed and mmk in ("pier", "jetty", "breakwater", "groyne"):
                p_ = polygon_of(el)
                if p_ is not None:
                    buildings.append(p_)
            elif not closed:
                roads.append((LineString(co), "pier" if mmk in ("pier", "jetty", "breakwater", "groyne") else "track"))
        # ---- land cover / land use
        kind = None
        for key, allowed in LAND_KIND_FROM:
            if t.get(key) in allowed:
                kind = "recreation_ground" if (key == "leisure" and t[key] in PARKLIKE_LEISURE) else t[key]
                break
        if kind and et in ("way", "relation"):
            p = polygon_of(el)
            if p is not None:
                land.append((p, kind))
        # ---- roads
        if et == "way" and t.get("highway") in ROAD_KINDS and el.get("geometry") and len(el["geometry"]) > 1:
            if t.get("area") != "yes":
                roads.append((LineString(way_coords(el["geometry"])), t["highway"]))
        # ---- buildings
        if et == "way" and "building" in t:
            p = polygon_of(el)
            if p is not None:
                buildings.append(p)
        # ---- places and named points
        pl = t.get("place")
        if name and (pl in PLACE_MINZ or t.get("tourism") in ("attraction", "viewpoint", "museum") or t.get("waterway") == "dam"):
            if et == "node":
                x, y = el["lon"], el["lat"]
            elif el.get("geometry"):
                g = el["geometry"]
                x, y = sum(p["lon"] for p in g) / len(g), sum(p["lat"] for p in g) / len(g)
            elif el.get("members"):
                pts = [p for m in el["members"] if m.get("geometry") for p in m["geometry"]]
                if not pts:
                    continue
                x, y = sum(p["lon"] for p in pts) / len(pts), sum(p["lat"] for p in pts) / len(pts)
            else:
                continue
            if pl in PLACE_MINZ:
                places.append((x, y, name, pl, PLACE_MINZ[pl]))
            elif t.get("waterway") == "dam":
                places.append((x, y, name, "dam", 12))
            else:
                places.append((x, y, name, "attraction", 13))
        else:
            pk = poi_kind(t) if name else None                        # named amenities / viewpoints / bays / peninsulas ...
            if pk:
                pt = point_of(el)
                if pt:
                    places.append((pt[0], pt[1], name, pk[0], pk[1]))
    return water, rivers, land, roads, buildings, places


# ----------------------------------------------------------------------------- tile maths
def tile_bounds(z, x, y, buf):
    n = 2 ** z
    mx0, mx1 = (x - buf) / n, (x + 1 + buf) / n
    my0, my1 = (y - buf) / n, (y + 1 + buf) / n
    lat = lambda my: math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * min(max(my, 0.0), 1.0)))))
    return mx0 * 360 - 180, lat(my1), mx1 * 360 - 180, lat(my0)


def lonlat_to_tile(lon, lat, z):
    n = 2 ** z
    lat = max(-LATMAX, min(LATMAX, lat))
    x = (lon + 180.0) / 360.0 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def xform(z, x, y):
    n = 2 ** z

    def f(c):
        lon = c[:, 0]
        lat = np.clip(c[:, 1], -LATMAX, LATMAX)
        px = ((lon + 180.0) / 360.0 * n - x) * EXT
        s = np.sin(np.radians(lat))
        my = 0.5 - np.log((1 + s) / (1 - s)) / (4 * np.pi)
        return np.column_stack([px, (my * n - y) * EXT])
    return f


def polys(g):
    if g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    if g.geom_type in ("MultiPolygon", "GeometryCollection"):
        r = []
        for p in g.geoms:
            r += polys(p)
        return r
    return []


def lines(g):
    if g.is_empty:
        return []
    if g.geom_type == "LineString":
        return [g]
    if g.geom_type in ("MultiLineString", "GeometryCollection"):
        r = []
        for p in g.geoms:
            r += lines(p)
        return r
    return []


class Index:
    """geometry list + STRtree (+ simplification for one zoom)"""
    def __init__(self, geoms, props):
        self.g = np.array(geoms, dtype=object)
        self.p = props
        self.tree = None

    def simplified(self, tol):
        if len(self.g) == 0:
            return Index([], [])
        out = Index(list(shapely.simplify(self.g, tol, preserve_topology=True)) if tol > 0 else list(self.g), self.p)
        out.tree = STRtree(out.g)
        return out

    def query(self, bx):
        if self.tree is None or len(self.g) == 0:
            return []
        return self.tree.query(bx)


# ----------------------------------------------------------------------------- main build
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", default="76.32,12.33,76.76,12.64", help="west,south,east,north  (default: KRS backwaters + Srirangapatna)")
    ap.add_argument("--name", default="krs_backwaters")
    ap.add_argument("--minzoom", type=int, default=8)
    ap.add_argument("--maxzoom", type=int, default=16)
    ap.add_argument("--no-buildings", action="store_true")
    ap.add_argument("--cache", default="osm_cache")
    ap.add_argument("--from-json", default=None, help="folder with cached Overpass json (skips the download)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--focus", default="%.6f,%.6f" % FOCUS_DEFAULT, help="lat,lon of the launch point that gets EXTRA detail (default: RMSC Launch Point)")
    ap.add_argument("--focus-radius", type=float, default=3.0, help="km around the launch point that get the detail zone (default 3)")
    ap.add_argument("--focus-maxzoom", type=int, default=18, help="highest zoom inside the detail zone (default 18)")
    ap.add_argument("--no-focus", action="store_true", help="no detail zone: whole box at --maxzoom only")
    a = ap.parse_args()
    bbox = [float(v) for v in a.bbox.split(",")]
    w, s, e, n = bbox
    out_path = a.out or (a.name + ".mbtiles")
    t0 = time.time()

    focus = None                                                         # (lat, lon, radius_deg_lat, radius_deg_lon)
    if not a.no_focus:
        flat, flon = [float(v) for v in a.focus.split(",")]
        rkm = a.focus_radius
        focus = (flat, flon, rkm / 111.0, rkm / (111.0 * math.cos(math.radians(flat))))
        if not (w <= flon <= e and s <= flat <= n):
            raise SystemExit("the launch point %.5f,%.5f is outside --bbox" % (flat, flon))
    fbox = (focus[1] - focus[3], focus[0] - focus[2], focus[1] + focus[3], focus[0] + focus[2]) if focus else None   # w s e n
    margin = 0.01
    if a.from_json:
        elements = load_cache(a.from_json)
    else:
        elements = download([w - margin, s - margin, e + margin, n + margin], a.cache, not a.no_buildings,
                            focus_box=([fbox[0] - 0.004, fbox[1] - 0.004, fbox[2] + 0.004, fbox[3] + 0.004] if fbox else None))
    print("%d OSM elements" % len(elements), flush=True)
    water, rivers, land, roads, buildings, places = classify(elements)
    print("water %d  streams %d  landuse %d  roads %d  buildings %d  labels %d  (%.0fs)" %
          (len(water), len(rivers), len(land), len(roads), len(buildings), len(places), time.time() - t0), flush=True)
    if not water:
        print("WARNING: no water polygons found - check the bbox / internet.", file=sys.stderr)
    km2 = lambda g: g.area * 111.0 * 108.7                                # deg^2 -> km^2 at ~12 N
    big = sorted(((km2(g), g) for g in water), key=lambda t: -t[0])[:6]
    print("water report: %d relations (%d built, %d failed), %d ring gaps repaired, %d dropped" %
          (STATS["rel_total"], STATS["rel_ok"], len(STATS["rel_failed"]), STATS["gaps_repaired"], STATS["gaps_dropped"]))
    for a_, g in big:
        c = g.representative_point()
        print("   water body %8.1f km2  near %.3f N %.3f E" % (a_, c.y, c.x))
    for rid, nm, why in STATS["rel_failed"][:8]:
        print("   FAILED relation %s %r: %s" % (rid, nm, why))
    if not big or big[0][0] < 40:
        print("WARNING: the biggest water body is under 40 km2 - the KRS reservoir (~100+ km2) is NOT in the data. "
              "Send me this report. Quick checks: run again later (Overpass may have been busy), or delete the osm_cache folder.", file=sys.stderr)

    water_u = unary_union(water) if water else Polygon()
    if not water_u.is_valid:
        water_u = water_u.buffer(0)

    # shore bands: ring of water next to the shore (2 tones) -> real polygons, drawn right after the water fill.
    # widths shrink with the zoom (a 70 m band looks fine at z12 but is a huge stripe at z17)
    BAND_SETS = {"far": (0.22, 0.07), "mid": (0.10, 0.03), "close": (0.035, 0.012)}
    band_of = lambda z: "far" if z <= 14 else "mid" if z <= 16 else "close"
    bands = {}
    if not water_u.is_empty:
        deg = 1.0 / 111.0                                                # km -> degrees (good enough for shading)
        for key, (wm, wn) in BAND_SETS.items():
            im, inr = water_u.buffer(-wm * deg), water_u.buffer(-wn * deg)
            bands[key] = (water_u.difference(im), water_u.difference(inr))
        print("shore bands built", flush=True)
    else:
        bands = {k: (Polygon(), Polygon()) for k in BAND_SETS}

    if os.path.exists(out_path):
        os.remove(out_path)
    db = sqlite3.connect(out_path)
    db.executescript("""
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    """)
    total = 0
    top_z = max(a.maxzoom, a.focus_maxzoom) if focus else a.maxzoom
    DETAIL_FROM = 14                                                      # detail zone sets start here
    if focus:
        fb_poly = box(*fbox)
        fb_sel = box(fbox[0] - 360.0 / (2 ** DETAIL_FROM), fbox[1] - 180.0 / (2 ** DETAIL_FROM),
                     fbox[2] + 360.0 / (2 ** DETAIL_FROM), fbox[3] + 180.0 / (2 ** DETAIL_FROM))
        near = lambda items: [it for it in items if it[0].intersects(fb_sel)]
        f_water = water_u.intersection(fb_sel) if not water_u.is_empty else Polygon()
        f_bands = {k: (v[0].intersection(fb_sel), v[1].intersection(fb_sel)) for k, v in bands.items()}
        f_roads, f_rivers, f_land = near(roads), near(rivers), near(land)
        f_bld = [b for b in buildings if b.intersects(fb_sel)]
        print("detail zone %.2f km around %.5f N %.5f E:  roads/tracks %d  streams %d  landuse %d  buildings %d" %
              (a.focus_radius, focus[0], focus[1], len(f_roads), len(f_rivers), len(f_land), len(f_bld)), flush=True)

    def zoom_set(z, fine):
        """all indexes of one zoom. fine = the detail zone (finer simplification, every small feature, more roads / tracks)"""
        tol = 360.0 / (512 * 2 ** z) * (0.12 if fine else 0.45)
        SM, SN = (f_bands if fine else bands)[band_of(z)]
        W = f_water if fine else water_u
        R_, V_, L_, B_ = (f_roads, f_rivers, f_land, f_bld) if fine else (roads, rivers, land, buildings)
        S = {}
        S["iw"] = Index([W], [None]).simplified(tol) if not W.is_empty else Index([], [])
        S["isb"] = (Index([SM, SN], ["mid", "near"]).simplified(tol * 0.5) if (z >= 10 and not W.is_empty) else Index([], []))
        rd = [(g, k) for g, k in R_ if z >= max(12, ROAD_MINZ.get(k, 14) - (1 if fine else 0))]
        rv = [(g, k) for g, k in V_ if (z >= 12 if k in ("stream", "drain") else z >= 9)]
        S["ir"] = Index([g for g, _ in rd], [k for _, k in rd]).simplified(tol * 0.6)
        S["iv"] = Index([g for g, _ in rv], [k for _, k in rv]).simplified(tol * 0.6)
        min_area = (tol * (1.2 if fine else 3.0)) ** 2                    # drop specks
        ld = [(g, k) for g, k in L_ if g.area >= min_area]
        S["il"] = Index([g for g, _ in ld], [k for _, k in ld]).simplified(tol)
        S["ib"] = Index(B_, [None] * len(B_)).simplified(tol * 0.3) if (z >= 15 and B_) else Index([], [])
        S["pl"] = [p for p in places if z >= p[4] - 0.001]
        return S

    for z in range(a.minzoom, top_z + 1):
        norm = zoom_set(z, False) if z <= a.maxzoom else None
        fine_set = zoom_set(z, True) if (focus and z >= DETAIL_FROM) else None
        if z <= a.maxzoom:
            x0f, y1f = lonlat_to_tile(w, s, z)
            x1f, y0f = lonlat_to_tile(e, n, z)
        else:                                                             # beyond the regional maxzoom: ONLY the detail zone
            x0f, y1f = lonlat_to_tile(fbox[0], fbox[1], z)
            x1f, y0f = lonlat_to_tile(fbox[2], fbox[3], z)
        cnt = 0
        for x in range(int(x0f), int(x1f) + 1):
            for y in range(int(y0f), int(y1f) + 1):
                bb = tile_bounds(z, x, y, BUF / EXT)
                bx = box(*bb)
                b0 = tile_bounds(z, x, y, 0.0)
                in_focus = bool(focus) and not (b0[2] < fbox[0] or b0[0] > fbox[2] or b0[3] < fbox[1] or b0[1] > fbox[3])
                S = fine_set if (in_focus and fine_set) else norm
                if S is None:
                    continue
                iw, isb, il, iv, ir, ib, pl = S["iw"], S["isb"], S["il"], S["iv"], S["ir"], S["ib"], S["pl"]
                f = xform(z, x, y)
                layers = []

                # ---- water (clipped) and earth = tile - water (so islands are real land and the shore is a real edge)
                wpolys = []
                for i in iw.query(bx):
                    wpolys += polys(shapely.clip_by_rect(iw.g[i], *bb))
                feats = [{"geometry": shapely.transform(p, f), "properties": {"kind": "lake"}} for p in wpolys]
                land_geom = bx
                if wpolys:
                    try:
                        land_geom = bx.difference(unary_union(wpolys))
                    except Exception:
                        land_geom = bx.difference(unary_union(wpolys).buffer(0))
                ef = [{"geometry": shapely.transform(p, f), "properties": {"kind": "earth"}} for p in polys(land_geom)]
                if ef:
                    layers.append({"name": "earth", "features": ef})
                if feats:
                    layers.append({"name": "water", "features": feats})
                sf_ = []
                for i in isb.query(bx):
                    for p in polys(shapely.clip_by_rect(isb.g[i], *bb)):
                        sf_.append({"geometry": shapely.transform(p, f), "properties": {"kind": isb.p[i]}})
                if sf_:
                    layers.append({"name": "shore", "features": sf_})

                feats = []
                for i in il.query(bx):
                    for p in polys(shapely.clip_by_rect(il.g[i], *bb)):
                        feats.append({"geometry": shapely.transform(p, f), "properties": {"kind": il.p[i]}})
                if feats:
                    layers.append({"name": "landuse", "features": feats})

                feats = []
                for i in iv.query(bx):
                    for l in lines(shapely.clip_by_rect(iv.g[i], *bb)):
                        feats.append({"geometry": shapely.transform(l, f), "properties": {"kind": "stream" if iv.p[i] in ("stream", "drain") else iv.p[i]}})
                if feats:
                    layers.append({"name": "waterway", "features": feats})

                feats = []
                for i in ir.query(bx):
                    for l in lines(shapely.clip_by_rect(ir.g[i], *bb)):
                        feats.append({"geometry": shapely.transform(l, f), "properties": {"kind": ir.p[i]}})
                if feats:
                    layers.append({"name": "roads", "features": feats})

                feats = []
                for i in ib.query(bx):
                    for p in polys(shapely.clip_by_rect(ib.g[i], *bb)):
                        feats.append({"geometry": shapely.transform(p, f), "properties": {}})
                if feats:
                    layers.append({"name": "buildings", "features": feats})

                feats = []
                for (lon, lat, name, kind, mz) in pl:
                    if b0[0] <= lon < b0[2] and b0[1] <= lat < b0[3]:
                        pt = shapely.transform(Point(lon, lat), f)
                        feats.append({"geometry": pt, "properties": {"name": name, "kind": kind, "rank": PLACE_RANK.get(kind, 7)}})
                if feats:
                    layers.append({"name": "places", "features": feats})

                if not layers:
                    continue
                data = mvt.encode(layers, default_options={"extents": EXT, "y_coord_down": True})
                db.execute("INSERT INTO tiles VALUES (?,?,?,?)", (z, x, (1 << z) - 1 - y, gzip.compress(data, 9)))
                cnt += 1
        total += cnt
        db.commit()
        print("z%-2d %6d tiles   (%.0fs)%s" % (z, cnt, time.time() - t0, "   [detail zone only]" if z > a.maxzoom else ""), flush=True)

    meta = {
        "name": a.name,
        "format": "pbf",
        "type": "baselayer",
        "version": "1",
        "minzoom": str(a.minzoom),
        "maxzoom": str(top_z),
        "bounds": "%.5f,%.5f,%.5f,%.5f" % (w, s, e, n),
        "center": ("%.6f,%.6f,15" % (focus[1], focus[0])) if focus else "%.5f,%.5f,13" % ((w + e) / 2, (s + n) / 2),
        "focus": ("%.6f,%.6f,%.2f,%s" % (focus[0], focus[1], a.focus_radius, FOCUS_NAME)) if focus else "",
        "attribution": "OpenStreetMap contributors (ODbL)",
        "schema": "protomaps",
        "shelf": "0",                                                    # inland water: no ocean-shelf shading
        "description": "Regional pack built by build_region_pack.py",
    }
    db.executemany("INSERT INTO metadata VALUES (?,?)", list(meta.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print("done: %s  %.1f MB  %d tiles  (%.0fs)" % (out_path, os.path.getsize(out_path) / 1e6, total, time.time() - t0))


if __name__ == "__main__":
    main()
