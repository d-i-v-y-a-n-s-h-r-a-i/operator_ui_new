# Naya AR path (NavPath.qml)

Files: `NavPath.qml` (NEW, CMake/qrc me add karo) + `Main.qml` (sirf purana `navTrajectoryCorridor` canvas hata kar `NavPath { }` block).

Kya dikhata hai: glowing ribbon (water par perspective), flowing chevrons (speed ke saath tez), 25/50/100/200/300 m marks,
next waypoint beacon (naam, distance, ETA), left tag "AUTONOMOUS NAVIGATION / COLLISION AVOIDANCE", "TURN PORT/STBD x deg - NEW COURSE",
hazard = red pillar + red predicted track + tag (distance, CPA). Horizon tape wale horizon ke saath hi tilt hota hai.

## Boat se data (text)
`vesselState.navPathJson` (string) me bhejo, har message me badhta `seq`:
{"seq":812,"state":"AVOID","msg":"Altering to port","wp":{"name":"WP 03","distM":412},"etaS":187,
 "pts":[[-1,18],[-4,40],[-10,70],[-17,100]],
 "hz":[{"x":5,"z":104,"r":9,"kind":"VESSEL","label":"CARGO VESSEL","cpa":42,"track":[[15,175],[10,130],[4,82],[0,52]]}]}
x = starboard(+)/port(-) metre, z = aage metre, origin = camera. `state`: NAV | AVOID | BERTH | HOLD.
`pts` ki jagah `"delta":16` (degree, + stbd) do to smooth arc banega.

## Agar boat kuch na bheje
vesselState.wpBearing (absolute deg) + wpDistanceNm (+ optional wpName) se arc banta hai. Bearing na ho to seedha ribbon.

## Test bina boat ke: camera view me F6 dabao (0 live, 1 straight, 2 turn, 3 collision avoidance).

## Tune
`camHeightM` (3.0), `halfWidthM` (0.7), `focalPx` (width*0.714 = 70 deg HFOV). Real camera height (~2 m) daalne se objects video se
exact match karte hain, par path door jaakar horizon ke paas dab jaata hai (physics). 3.0 padhne me behtar hai.

Note: sandbox me software render par test hua. Jetson par smooth chalna (30 fps) aur real boat feed abhi test nahi hua.
