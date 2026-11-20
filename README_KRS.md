# KRS backwaters - detailed regional map pack  (v3: RMSC Launch Point detail zone)

## What is new in v3
- **RMSC Launch Point = 12.451754 N, 76.552337 E** is a named point on the map: navy flag marker, name chip with the exact
  coordinates (shown from zoom 12.5), always collision-free. Tap it = fly there. A flag button at the top of the right-hand
  control column does the same (`flyToPoint(0)`).
  Change / add points in one place:  `namedPoints: [ {name:"RMSC Launch Point", lat:12.451754, lon:76.552337} ]`
  (property of MissionMapView; Main.qml may override it, e.g. from a mission file).
- **Detail zone** (default 3 km around the launch point): extra Overpass query for EVERYTHING mapped there, tiles up to **z18**
  (rest of the box stays z16), 4x finer shoreline simplification, more tracks/paths from z13, small areas kept, and
  - piers / jetties / breakwaters / slipways / embankments, named marina, temple, view points, hotels, parking, bays,
    peninsulas, islands (POI labels = small ring + name, from z15)
  - shore-depth bands get narrower when zoomed in (0.22/0.07 km -> 0.10/0.03 km at z15-16 -> 0.035/0.012 km at z17+)
  - line widths grow on z17/z18 so roads, tracks and piers keep a realistic width
- **Overzoom**: anywhere the pack has no deeper tile, the nearest coarser tile is re-used (up to 4 levels, sharp lines, no
  blurry scaling). So you can zoom to ~z20 everywhere.
- **BUG FIXED**: tracks, paths and footways were never drawn (unknown road class was silently dropped). They are now a thin
  un-cased class from z14. Most rural roads around the backwaters are exactly these.
- Map opens at zoom 14 (was 12.5) at the GNSS position; PC test default position = RMSC Launch Point (see Main.qml below).

## Step 1  build the pack (on a PC with internet, once)
    pip install shapely mapbox-vector-tile numpy
    python3 build_region_pack.py
        -> krs_backwaters.mbtiles
    options:
      --bbox W,S,E,N              whole region (default 76.32,12.33,76.76,12.64)
      --focus LAT,LON             detail point (default = RMSC Launch Point)
      --focus-radius 3            km of the detail zone  (4-5 km = more area, bigger file)
      --focus-maxzoom 18          --no-focus   --maxzoom 16   --no-buildings   --from-json osm_cache
    Downloads in small chunks (cache = ./osm_cache, re-runs are instant). The detail zone is one extra small query.
    If Overpass says "busy" it retries by itself; if it still fails run it again later (evenings IST are quieter).
    The old osm_cache can stay: new queries get new cache names. Delete it only if a run printed the WARNING below.

## Step 1b  read the WATER REPORT the script prints
    water report: N relations (X built, Y failed) ...
       water body  1xx.x km2  near 12.4xx N 76.5xx E      <- must exist: the KRS reservoir (~100+ km2)
    "detail zone 3.00 km around 12.45175 N 76.55234 E:  roads/tracks N  streams N  landuse N  buildings N"
       <- send me this line too: it shows how much OSM really has around the launch point.
    Biggest water body under 40 km2 = WARNING (reservoir missing). Then run again later or send me the report.

## Step 2  copy krs_backwaters.mbtiles into the app's maps/ folder (keep demo_world.mbtiles there too)

## Step 3  replace in the app:  qml/MissionMapView.qml   and   backend/mission_map_backend.py
    Main.qml: only two numbers change (PC-test start position = launch point; real GNSS overrides them):
        property real gnssHomeLat: 12.451754
        property real gnssHomeLon: 76.552337
    (TacticalMapView.qml / GnssSource.qml unchanged)

## Fonts
Names that OSM has only in Kannada script need a Kannada font on the Jetson (sudo apt install fonts-noto-core), otherwise
they show as empty boxes. Labels use name:en when OSM has it.

## Honest limits
- Detail can never be better than what OpenStreetMap contains. The map shows what mappers drew (shoreline, islands, roads,
  tracks, buildings, named places). It is NOT satellite imagery: no field patterns, trees, water colour, sandbars.
  If a feature you see on Google is missing here, it is missing in OSM (can be added at openstreetmap.org, then rebuild).
- NOT verified (sandbox cannot reach OpenStreetMap): the live download, real pack size / build time, real look.
  Tested only on a synthetic scene around the launch point (SYNTHETIC_launch_point_*.png: invented peninsula, jetty, tracks).
- Depth tones are shore-distance, not real bathymetry. Not tested on the Jetson / real GNSS.

## Plan B if the reservoir still does not appear (Protomaps basemap; assembles big lakes itself)
    pmtiles extract https://build.protomaps.com/<latest build date>.pmtiles krs_pm.pmtiles --bbox=76.32,12.33,76.76,12.64 --maxzoom=15
    pmtiles convert krs_pm.pmtiles krs_pm.mbtiles        (put it in maps/ instead of krs_backwaters.mbtiles)
    (the backend reads this schema, but it is NOT tested on real Protomaps tiles; no shore tones / farmland on this path)
