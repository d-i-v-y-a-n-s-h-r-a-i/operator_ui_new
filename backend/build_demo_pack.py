#!/usr/bin/env python3
"""
Build the DEMO offline map pack (MBTiles, gzip MVT, Protomaps-style layer names)
from Natural Earth 10 m vector data.

    python3 build_demo_pack.py  demo_world.mbtiles  7

This is only a coarse "world-lite" pack (Natural Earth is ~1:10 000 000) so the map works the
moment you plug it in.  For real work build a REGIONAL pack from OpenStreetMap (see
OFFLINE_MAP_SETUP.txt): same file format, same layer names, nothing in the app changes.

Layers written
    earth      land polygons            (+ minor islands)
    water      lakes (polygons)
    waterway   rivers (lines)
    places     populated places (points: name, rank, kind)
"""
import gzip, json, math, os, sqlite3, sys, time
import numpy as np
import shapely
from shapely import STRtree
from shapely.geometry import shape, box, Point
import mapbox_vector_tile as mvt

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "demo_world.mbtiles")
MAXZ = int(sys.argv[2]) if len(sys.argv) > 2 else 7
EXT = 4096          # MVT extent
BUF = 80            # tile buffer in extent units (no seams at tile borders)
LATMAX = 85.0511287798


def load(name):
    with open(os.path.join(DATA, name + ".geojson")) as fh:
        return json.load(fh)["features"]


def geoms_of(name):
    out = []
    for f in load(name):
        g = f.get("geometry")
        if g:
            gs = shape(g)
            if not gs.is_valid:
                gs = gs.buffer(0)
            out.append(gs)
    return out


def tile_bounds(z, x, y, buf):
    n = 2 ** z
    mx0, mx1 = (x - buf) / n, (x + 1 + buf) / n
    my0, my1 = (y - buf) / n, (y + 1 + buf) / n
    lat = lambda my: math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * min(max(my, 0.0), 1.0)))))
    return mx0 * 360 - 180, lat(my1), mx1 * 360 - 180, lat(my0)


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
    t = g.geom_type
    if t == "Polygon":
        return [g]
    if t in ("MultiPolygon", "GeometryCollection"):
        r = []
        for p in g.geoms:
            r += polys(p)
        return r
    return []


def lines(g):
    if g.is_empty:
        return []
    t = g.geom_type
    if t == "LineString":
        return [g]
    if t in ("MultiLineString", "GeometryCollection"):
        r = []
        for p in g.geoms:
            r += lines(p)
        return r
    return []


def main():
    t0 = time.time()
    land = geoms_of("ne_10m_land") + geoms_of("ne_10m_minor_islands")
    lakes = geoms_of("ne_10m_lakes")
    rivers = geoms_of("ne_10m_rivers_lake_centerlines")
    places = []
    for f in load("ne_10m_populated_places_simple"):
        p = f["properties"]
        name = p.get("name")
        if not name:
            continue
        lon, lat = f["geometry"]["coordinates"][:2]
        mz = p.get("min_zoom")
        sr = p.get("scalerank", 6)
        try:
            mz = float(mz)
        except Exception:
            mz = float(sr) + 1.0
        places.append((lon, lat, name, int(sr) if sr is not None else 6, mz, p.get("featurecode") or ""))
    print("loaded", len(land), "land,", len(lakes), "lakes,", len(rivers), "rivers,", len(places), "places in", round(time.time() - t0, 1), "s")

    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript("""
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    """)
    pl_arr = np.array([(p[0], p[1]) for p in places])
    total = 0
    for z in range(0, MAXZ + 1):
        tol = 360.0 / (512 * 2 ** z) * 0.45
        gl = shapely.simplify(np.array(land, dtype=object), tol, preserve_topology=True)
        gk = shapely.simplify(np.array(lakes, dtype=object), tol, preserve_topology=True)
        gr = shapely.simplify(np.array(rivers, dtype=object), tol, preserve_topology=True)
        tl, tk, tr = STRtree(gl), STRtree(gk), STRtree(gr)
        n = 2 ** z
        cnt = 0
        for x in range(n):
            for y in range(n):
                bb = tile_bounds(z, x, y, BUF / EXT)
                bx = box(*bb)
                f = xform(z, x, y)
                layers = []

                feats = []
                for i in tl.query(bx):
                    for p in polys(shapely.clip_by_rect(gl[i], *bb)):
                        feats.append({"geometry": shapely.transform(p, f), "properties": {}})
                if feats:
                    layers.append({"name": "earth", "features": feats})

                feats = []
                for i in tk.query(bx):
                    for p in polys(shapely.clip_by_rect(gk[i], *bb)):
                        feats.append({"geometry": shapely.transform(p, f), "properties": {"kind": "lake"}})
                if feats:
                    layers.append({"name": "water", "features": feats})

                feats = []
                for i in tr.query(bx):
                    for l in lines(shapely.clip_by_rect(gr[i], *bb)):
                        feats.append({"geometry": shapely.transform(l, f), "properties": {"kind": "river"}})
                if feats:
                    layers.append({"name": "waterway", "features": feats})

                # places that fall inside this tile (exact bounds) and are allowed at this zoom
                b0 = tile_bounds(z, x, y, 0.0)
                feats = []
                inside = np.where((pl_arr[:, 0] >= b0[0]) & (pl_arr[:, 0] < b0[2]) & (pl_arr[:, 1] >= b0[1]) & (pl_arr[:, 1] < b0[3]))[0]
                for i in inside:
                    lon, lat, name, sr, mz, fc = places[i]
                    if z + 1.0 < mz:
                        continue
                    pt = shapely.transform(Point(lon, lat), f)
                    feats.append({"geometry": pt, "properties": {"name": name, "rank": sr, "min_zoom": mz, "kind": "locality"}})
                if feats:
                    layers.append({"name": "places", "features": feats})

                if not layers:
                    continue
                data = mvt.encode(layers, default_options={"extents": EXT, "y_coord_down": True})
                db.execute("INSERT INTO tiles VALUES (?,?,?,?)", (z, x, n - 1 - y, gzip.compress(data, 9)))
                cnt += 1
        total += cnt
        db.commit()
        print("z%d  %6d tiles   (%.0fs)" % (z, cnt, time.time() - t0), flush=True)

    meta = {
        "name": "TANDAV demo world (Natural Earth 10m)",
        "format": "pbf",
        "type": "baselayer",
        "version": "1",
        "minzoom": "0",
        "maxzoom": str(MAXZ),
        "bounds": "-180,-85.0511,180,85.0511",
        "center": "0,20,2",
        "attribution": "Natural Earth (public domain)",
        "schema": "protomaps",
        "description": "Coarse world-lite DEMO pack. Replace by a regional OpenStreetMap pack for real navigation.",
    }
    db.executemany("INSERT INTO metadata VALUES (?,?)", list(meta.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print("done:", total, "tiles ->", OUT, round(os.path.getsize(OUT) / 1e6, 2), "MB in", round(time.time() - t0), "s")


if __name__ == "__main__":
    main()
