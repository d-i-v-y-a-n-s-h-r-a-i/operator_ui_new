TANDAV GCS - Mission Plan = full-screen map, new SPLIT VIEW button
==================================================================
Only file changed: Main.qml  (replace the old one; NavPath / HorizonTracker / TacticalMapView etc. unchanged)

Behaviour
  MISSION PLAN  -> only the map, full screen (above the bottom dock). Press again -> back to where you were.
  SPLIT VIEW    -> new dock button (between MISSION PLAN and Autonomous). Puts whatever you are watching
                   (3D simulation OR live video) in the LEFT 1/3 and the map in the RIGHT 2/3.
                   Works from the plain video / 3D view and from the full-screen map.
                   Press again -> returns to where you came from (plain view or full map).
  MAP button    -> still switches 3D simulation <-> video (also works while split).
  ESC           -> closes the map first, then 3D -> video, then quits.

Video in the left third
  video + AR path + horizon tape are cropped to the left 1/3 (same scale as full screen, centre crop),
  telemetry cards become 3 pages x 3 cards (same compact pager as the 3D view), cluster is 22% smaller,
  cruise bar moves to the right of the cluster. HorizonTracker keeps running while the video is visible.

Code map (Main.qml)
  top:  missionOpen / splitOn / splitFromClosed, missionT, splitT, leftW, toggleMission(), toggleSplit()
  layer0/layer1/layer1_5/layer3/layer4: sized by appWindow.leftW
  layer3 carousel: compact pager (pagePos/pageIndex/goPage, cPage/cSlot tables)
  missionPane: width = 2/3 .. full, x slides with missionT
  dock: splitBtn (new), missionBtn (now toggleMission())
Rename the button text: search for "SPLIT VIEW" in Main.qml.

Tested: software-GL render of every state (video/3D x full/map/split) and toggle sequences, light mode.
NOT tested: Jetson performance of the animated width change, touch drags on the compact video pager.
