# Instrument cluster (replaces the "DASHBOARD OPTICAL" video)

The card lived in **Main.qml** (`layer1_5_pipDashboard`), not in TacticalMapView.qml. TacticalMapView.qml, VideoPipeline.cpp/.h
and the other files are NOT changed.

## Files
- `InstrumentCluster.qml`  NEW. Put it next to TelemetryCard.qml (and add it to CMake / qrc exactly like TelemetryCard.qml).
- `Main.qml`               only ONE block changed: the old pip block (MediaPlayer + VideoOutput + OpacityMask + header) is
                           replaced by an `InstrumentCluster {}` inside the same `layer1_5_pipDashboard` Item.
                           Same id, same anchors (bottom-left, above the dock) -> the grid button in the dock still shows / hides it.
                           Size: 360 x 202 at 1920x1080 (was 320 x 180), scales with `scaleFactor`.
                           If you cannot take the whole file: paste only that block (search `layer1_5_pipDashboard`).

## What it shows
RPM LED bar (cyan / amber / red zones), big speed (tap = km/h <-> knots), fuel and coolant gauges, gear F/N/R,
AUTO/MAN badge, drive mode (SPORT / ECO / ...), trip, engine hours, battery, alerts (flashing, cycles if several),
live / stale / no-data state. Night and day look follow `appWindow.lm`.

## Feeding it (the boat sends text)
Set one property from your telemetry layer:   `instrumentCluster.json = <string from the boat>`
(in Main.qml it is already bound to `vesselState.clusterJson` when that property exists, so adding a
`clusterJson` QString property to vesselState / the telemetry object is enough).

    {"seq":10482,"speedKmh":24,"rpm":3378,"rpmMax":6500,"gear":"F","driveMode":"SPORT","control":"AUTO",
     "tripKm":0.2,"tripLabel":"A","engineHours":327.4,"battV":13.8,"fuelPct":82,"coolantC":68.7,
     "alerts":["LOW OIL PRESSURE"]}

All keys optional. `speedKn` can be sent instead of `speedKmh`. Missing keys fall back to vesselState
(speed [kn], rpm, fuelLevel, coolantTemp, mode, leakDetected), then to "--".
Alerts also come from local limits: coolant >= 95 C, fuel <= 15 %, battery < 11.8 V, bilge leak.

C++ side (example, in the class that already parses the boat's telemetry):
    Q_PROPERTY(QString clusterJson READ clusterJson NOTIFY clusterJsonChanged)
    void setClusterJson(const QString& s) { if (s != m_clusterJson) { m_clusterJson = s; emit clusterJsonChanged(); } }
IMPORTANT - always put an increasing `"seq"` (or a timestamp) in every message, 5-10 Hz is plenty.
QML only notices a NEW string. A parked boat with engine off sends the same values again and again; without `seq`
the cluster would see "no update" and wrongly go to STALE / NO DATA. (Or assign `feed` from C++ as a new QVariantMap each time.)

## Safety behaviour
No new text for 1.5 s  -> header shows "STALE x.x s" (amber), values dim.
No new text for 4 s    -> values blank out, "NO DATA FROM VESSEL" is shown. Never shows old numbers as if they were live.
If you do not use json/feed, bind `dataAgeMs` yourself.

## Not verified
Tested in the sandbox with synthetic values only (states sheet + full-app render). Not tested on the Jetson or with the
real boat feed. The exact JSON keys are my proposal: rename them in InstrumentCluster.qml (functions num()/str()) to match
what the boat actually sends. Minimum sensible width is about 300 px.
