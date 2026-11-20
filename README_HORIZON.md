# Heading tape (W NW N NE E SE S SW) follows the video horizon

Sirf Main.qml badla hai, baaki sab same. Change: top par naye `horizon*` properties + `dynamicHorizonPlane` (rotation, offset).

| Property | Matlab |
|---|---|
| `horizonTiltDeg` (default -2.0) | camera fixed hai, to video horizon ka fixed tilt. - = anti-clockwise |
| `horizonAddImuRoll` (default false) | true karo to live boat roll (-roll) bhi add hoga (sirf tab jab vesselState.roll ka sign video se match kare) |
| `horizonAngleDeg` | boat video se horizon angle measure karke `vesselState.horizonDeg` bheje -> ye sabse upar, calibration ki zaroorat nahi |
| `horizonOffsetY` | tape ko upar(-)/neeche(+) sarkaane ke liye (px @1080p) |

Calibration: app me camera view me `[` ya `]` dabao (0.1 deg step). Screen par "HORIZON TILT -x.x" dikhega.
Jab labels horizon ke parallel baith jaayein, wo value `horizonTiltDeg` me likh do.

Note: -2.0 default aapke ek screenshot se nikala andaaza hai (~-2.2 deg), real camera par fine-tune zaroor karna.
