# Path "udta" tha — fix: path ab asli waterline par chipakta hai

## Galti kya thi
Maine horizon ko fixed number (-2 deg) + IMU pitch (3.5 px/deg) se maana tha. Aapki video me horizon har frame badalta hai
(maine frames naapi: -6.5 deg se +1.1 deg tak, waterline y~434..578). Path ka vanishing point asli waterline se alag tha,
isliye beacon kabhi hawa me, kabhi pani me.

## Ab kya hai
`HorizonTracker.qml` (NAYA): har ~120 ms par screen par dikhti video ko chhota snapshot (480 px) banata hai, waterline
(trees ke neeche / sky-water edge) ki seedhi line dhoondhta hai (RANSAC), `yNorm` aur `angleDeg` deta hai. Pure QML, C++ change nahi.
Heading tape + NavPath dono ek hi horizon use karte hain: Main.qml me `horizonY`, `horizonRotation`.

Priority: 1) boat (`vesselState.horizonDeg` + `vesselState.horizonY` 0..1)  2) video tracker (default)  3) IMU fallback
(jab tracker ko horizon na dikhe: kohra/raat). On-screen read-out: key dabao to "HORIZON [VIDEO] y .. tilt .." dikhta hai.

Keys: Ctrl+Up / Ctrl+Down = horizon 1 px upar/neeche (calibration), [ ] = tilt (sirf IMU mode). F6 = path preview scenarios.

## Tests (sandbox, software GL)
- Aapki frame: tracker y=578.5, tilt +1.05 deg (haath se naapa: ~574, +1.16 deg) -> path waterline par.
- Pehli frame: y=460, tilt -6.46 deg -> path/tape tilt ke saath, beacon waterline par.
- Asli MediaPlayer->VideoOutput route par bhi chala (mp4 se), tracker valid.
- UI overlays (path/tape) frame me hon tab bhi sahi lock (robust).

## Files
NavPath.qml, HorizonTracker.qml (dono CMake/qrc me add karo), Main.qml.
NavPath: roll ab picture centre ke around (physically sahi), beacon ka ring minimum size ke saath pani par baitha dikhta hai.

## Limits (seedhi baat)
- Jetson par fps/CPU test nahi hua. Tracker ~8 Hz chalta hai; zyada load ho to `interval: 200` karo.
- Waterline dikhni chahiye (shore/sky edge). Poora kohra ya raat me IMU fallback chalega, jise `horizonOffsetY` / `horizonCamPitchDeg` se tune karna padega.
- Real boat par best: boat apni vision se `horizonDeg`/`horizonY` bheje (ye sabse upar rehta hai).
