# Mission Plan (split view) - integration notes

Files changed / added
- qml/Main.qml              CHANGED  (Mission Plan button, split transition, mission pane, GNSS wiring)
- qml/TacticalMapView.qml   CHANGED  (splitT compact mode: 3-card pager, glow, compass scale)
- qml/MissionMapView.qml    NEW      (GPU vector map, route, controls)
- qml/GnssSource.qml        NEW      (position priority chain)
- backend/mission_map_backend.py NEW (offline MBTiles reader, pure Python + PySide6, no extra pip packages)
- backend/build_demo_pack.py        (only to rebuild the tiny demo pack; needs shapely, mapbox-vector-tile, Natural Earth data)
- maps/demo_world.mbtiles           (7 MB world demo, z0-7, so the screen is never empty)
TelemetryCard.qml is unchanged.

1) Register the backend (main.py), before loading Main.qml
    from mission_map_backend import MissionMapBackend
    mm = MissionMapBackend("/path/to/maps")          # a folder of *.mbtiles, or one file
    engine.rootContext().setContextProperty("missionMap", mm)
    # optional: mm.startGpsd("127.0.0.1", 2947)      # if gpsd runs on the Jetson

2) Real map data (build ONCE on a PC with internet, copy the file to the Jetson)
    pmtiles extract https://build.protomaps.com/<latest>.pmtiles region.pmtiles --bbox=minLon,minLat,maxLon,maxLat --maxzoom=14
    pmtiles convert region.pmtiles region.mbtiles
    -> put region.mbtiles in the maps folder (several packs are fine, it picks the best one per tile)

3) GNSS (first valid wins)
    vesselState.latitude/longitude (also .lat/.lon/.lng, optional .gnssFix, .heading, .speed)
    -> gpsd (mm.startGpsd) or mm.setGnss(lat, lon, hdg, kn, fix)
    -> QtPositioning (OS location on a PC, or Main.qml: gnssNmeaSource: "serial:/dev/ttyACM0" / "socket://host:port")
    -> last saved position -> gnssHomeLat/gnssHomeLon
    Main.qml: gnssAllowIpLookup (default false) = approximate city-level position from the IP on a dev PC. Keep false on the boat.

4) Mission hooks (Main.qml signals, nothing invented on telemetry)
    onMissionStartRequested: (waypoints) => ...   // [{lat, lon}, ...]
    onMissionEndRequested: ...
    appWindow.missionNavigating shows the "End Navigation" button.

Known limits
- demo pack is coarse (Natural Earth, z<=7). Real detail needs a regional pack (step 2).
- protomaps / OpenMapTiles schema mapping is written from the schema docs; it was NOT tested on real regional tiles (sandbox had no access to them). Test with your first real pack.
- water depth shading is a distance-from-coast halo, not real bathymetry.
- not tested on the Jetson or with a real GNSS receiver.
