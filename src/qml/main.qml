import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import QtMultimedia
import Qt5Compat.GraphicalEffects

ApplicationWindow {
    id: appWindow
    visible: true
    visibility: Window.FullScreen
    width: Screen.desktopAvailableWidth ? Screen.desktopAvailableWidth : 1920
    height: Screen.desktopAvailableHeight ? Screen.desktopAvailableHeight : 1080
    minimumWidth: 1024
    minimumHeight: 600
    title: "TANDAV"
    color: mixc("#0a0e15", "#aec2c9")

    readonly property real baseWidth: 1920.0
    readonly property real baseHeight: 1080.0
    readonly property real scaleRatio: Math.min(appWindow.width / baseWidth, appWindow.height / baseHeight)
    readonly property real scaleFactor: Math.min(Math.max(scaleRatio, 0.75), 1.65)

    property bool mapViewOpen: true

    // ---- VIEWS ------------------------------------------------------------------------------------------
    //  primary view  = what you watch:   mapViewOpen true = 3D simulation (TacticalMapView),  false = live video + HUD
    //  mission map   = the offline map:  missionOpen
    //  three layouts:
    //     A  primary view alone, full screen                    (missionOpen false)
    //     B  MISSION PLAN: the map alone, full screen           (missionOpen true,  splitOn false)
    //     C  SPLIT VIEW:   primary view 1/3 left + map 2/3      (missionOpen true,  splitOn true)
    //  MISSION PLAN button toggles A <-> B (from C it closes the map).  SPLIT VIEW button toggles the primary view next to
    //  the map: A -> C and back to A, or B -> C and back to B.  MAP button switches the primary view 3D <-> video.
    property bool missionOpen: false
    property bool splitOn: false
    property bool splitFromClosed: false         // C was entered from A (so the SPLIT button returns to A, not to B)
    property real missionT: missionOpen ? 1.0 : 0.0       // 0..1  how far the map has slid in
    property real splitT: (missionOpen && splitOn) ? 1.0 : 0.0   // 0..1  how far the primary view has shrunk to the left third
    Behavior on missionT { enabled: appWindow.themeAnimated; NumberAnimation { duration: 460; easing.type: Easing.InOutCubic } }
    Behavior on splitT { enabled: appWindow.themeAnimated; NumberAnimation { duration: 460; easing.type: Easing.InOutCubic } }
    readonly property real leftW: Math.round(width * (1.0 - (2.0 / 3.0) * splitT))
    // the primary view is hidden only while the map fully covers it (layout B at rest)
    readonly property bool primaryVisible: !(missionT > 0.999 && splitT < 0.002)
    readonly property bool videoShown: !mapViewOpen && primaryVisible
    function toggleMission() {
        if (missionOpen) { missionOpen = false; splitOn = false; splitFromClosed = false; }
        else { splitOn = false; splitFromClosed = false; missionOpen = true; }
    }
    function toggleSplit() {
        if (!missionOpen) { splitFromClosed = true; splitOn = true; missionOpen = true; }
        else if (!splitOn) { splitFromClosed = false; splitOn = true; }
        else if (splitFromClosed) { splitOn = false; splitFromClosed = false; missionOpen = false; }
        else { splitOn = false; }
    }
    property bool missionNavigating: false
    property bool gnssAllowIpLookup: false      // dev PC without GNSS: true = approximate position from the IP address (needs internet; keep false on the boat)
    property string gnssNmeaSource: ""          // "" = OS location / gpsd / telemetry;  e.g. "serial:/dev/ttyACM0"  or  "socket://127.0.0.1:22222"
    property real gnssHomeLat: 12.451754         // last-resort start position (used only when no fix and no saved position)
    property real gnssHomeLon: 76.552337
    // hook points for the mission API (the app does not invent a telemetry call):
    signal missionStartRequested(var waypoints)
    signal missionEndRequested()
    property bool hudVisible: true

    // ---- HORIZON (heading tape + AR path share ONE horizon) --------------------------------------------------
    // The camera rolls and pitches with the boat, so the horizon in the picture moves. Where it comes from, best first:
    //   1. the boat:   vesselState.horizonDeg (tilt, deg, + = clockwise) and vesselState.horizonY (0..1 of the picture height)
    //   2. the video:  HorizonTracker measures the real water line in the picture that is on screen (default, automatic)
    //   3. fallback:   IMU pitch + horizonTiltDeg (+ live roll if horizonAddImuRoll)   <- only when 1 and 2 are missing
    // Calibration keys (work in every mode):  Ctrl+Up / Ctrl+Down  move the horizon 1 px,  [ and ]  tilt 0.1 deg (fallback mode).
    //   horizonOffsetY   px at 1080p added to the horizon (e.g. +4 if the line sits slightly above the water line)
    //   horizonAuto      false = ignore the video measurement
    property bool horizonAuto: true
    property real horizonTiltDeg: 0
    property bool horizonAddImuRoll: true
    property real horizonOffsetY: 0
    property real horizonCamPitchDeg: 0                   // camera tilt down relative to the hull (fallback mode), deg
    property real horizonAngleDeg: (typeof vesselState !== "undefined" && vesselState && vesselState.horizonDeg !== undefined) ? Number(vesselState.horizonDeg) : NaN
    property real horizonBoatY: (typeof vesselState !== "undefined" && vesselState && vesselState.horizonY !== undefined) ? Number(vesselState.horizonY) : NaN
    readonly property bool horizonFromVideo: horizonAuto && horizonTracker.valid
    readonly property string horizonSource: (!isNaN(horizonAngleDeg) || !isNaN(horizonBoatY)) ? "BOAT" : (horizonFromVideo ? "VIDEO" : "IMU")
    readonly property real horizonRotationTarget: !isNaN(horizonAngleDeg) ? horizonAngleDeg
        : (horizonFromVideo ? horizonTracker.angleDeg
        : horizonTiltDeg + ((horizonAddImuRoll && typeof vesselState !== "undefined" && vesselState) ? -vesselState.roll : 0))
    readonly property real horizonYTarget: (!isNaN(horizonBoatY) ? horizonBoatY * height
        : (horizonFromVideo ? horizonTracker.yNorm * height
        : height / 2 + ((typeof vesselState !== "undefined" && vesselState ? vesselState.pitch : 0) - horizonCamPitchDeg) * (width * 0.714 * Math.PI / 180))) + horizonOffsetY * scaleFactor
    property real horizonRotation: horizonRotationTarget
    property real horizonY: horizonYTarget
    Behavior on horizonRotation { NumberAnimation { duration: 130; easing.type: Easing.Linear } }
    Behavior on horizonY { NumberAnimation { duration: 130; easing.type: Easing.Linear } }
    property real horizonNudgeShown: 0           // fades the on-screen read-out after a key nudge
    onHorizonTiltDegChanged: { horizonNudgeShown = 1.0; horizonNudgeHide.restart(); }
    onHorizonOffsetYChanged: { horizonNudgeShown = 1.0; horizonNudgeHide.restart(); }
    Timer { id: horizonNudgeHide; interval: 2500; onTriggered: appWindow.horizonNudgeShown = 0.0 }
    Shortcut { sequence: "["; onActivated: if (appWindow.videoShown) appWindow.horizonTiltDeg = Math.round((appWindow.horizonTiltDeg - 0.1) * 10) / 10 }
    Shortcut { sequence: "]"; onActivated: if (appWindow.videoShown) appWindow.horizonTiltDeg = Math.round((appWindow.horizonTiltDeg + 0.1) * 10) / 10 }
    Shortcut { sequence: "Ctrl+Up"; onActivated: if (appWindow.videoShown) appWindow.horizonOffsetY -= 1 }
    Shortcut { sequence: "Ctrl+Down"; onActivated: if (appWindow.videoShown) appWindow.horizonOffsetY += 1 }
    property bool sensorActive: false
    property bool settingsViewOpen: false

    // =====================================================================
    // THEME  -  one switch for the whole UI.
    //   lightMode : false = night look (default), true = Neuboat DAY look
    //   lm        : the same thing as a 0..1 number, animated, every colour mixes on it
    // Toggle: the sun / moon button in the header (right side), or the L key.
    // =====================================================================
    property bool lightMode: false
    property real lm: lightMode ? 1.0 : 0.0
    property bool themeAnimated: true            // false = switch instantly (screenshots / tests)
    Behavior on lm { enabled: appWindow.themeAnimated; NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    function mixc(a, b) {
        var A = Qt.color(a), B = Qt.color(b);
        return Qt.rgba(A.r + (B.r - A.r) * lm, A.g + (B.g - A.g) * lm, A.b + (B.b - A.b) * lm, A.a + (B.a - A.a) * lm);
    }
    // cyan accent of the night look  ->  Neuboat blue of the day look
    readonly property color accentCyan: mixc("#00f0ff", "#3d92ea")

    Shortcut {
        sequence: "L"
        onActivated: appWindow.lightMode = !appWindow.lightMode
    }

    Shortcut {
        sequence: "F11"
        onActivated: {
            if (appWindow.visibility === Window.FullScreen) {
                appWindow.visibility = Window.Windowed;
            } else {
                appWindow.visibility = Window.FullScreen;
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (settingsViewOpen) {
                settingsViewOpen = false;
            } else if (missionOpen) {
                missionOpen = false; splitOn = false; splitFromClosed = false;
            } else if (mapViewOpen) {
                mapViewOpen = false;
            } else {
                Qt.quit();
            }
        }
    }

    Item {
        id: layer0_backgroundVideo
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: appWindow.leftW                              // full screen, or the left third in SPLIT VIEW
        clip: true
        z: 0

        MediaPlayer {
            id: mainMediaPlayer
            videoOutput: backgroundVideoSink
            source: Qt.resolvedUrl("../../main_camera.mp4")
            loops: MediaPlayer.Infinite
            Component.onCompleted: play()
        }

        VideoOutput {
            id: backgroundVideoSink
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: true
            Component.onCompleted: {
                if (typeof vesselState !== "undefined" && vesselState && vesselState.videoSink !== undefined) {
                    vesselState.videoSink = videoSink;
                }
            }
        }

        HorizonTracker {                                 // measures the real water line in the picture (see HorizonTracker.qml)
            id: horizonTracker
            target: backgroundVideoSink
            running: appWindow.videoShown && appWindow.horizonAuto
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.09, 0.14, 0.68) }
                GradientStop { position: 0.18; color: Qt.rgba(0.04, 0.06, 0.10, 0.18) }
                GradientStop { position: 0.45; color: Qt.rgba(0.0, 0.0, 0.0, 0.0) }
                GradientStop { position: 0.80; color: Qt.rgba(0.04, 0.06, 0.10, 0.22) }
                GradientStop { position: 1.0; color: Qt.rgba(0.05, 0.08, 0.12, 0.78) }
            }
        }
    }

    Item {
        id: layer1_augmentedHorizon
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: appWindow.leftW
        z: 1
        visible: appWindow.videoShown && hudVisible
        clip: true

        Item {
            id: dynamicHorizonPlane
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: appWindow.horizonY - parent.height / 2
            height: 2
            rotation: appWindow.horizonRotation              // follows the real horizon (see the HORIZON properties on top)
            transformOrigin: Item.Center

            Repeater {
                model: ["W", "NW", "N", "NE", "E", "SE", "S", "SW"]
                delegate: Text {
                    property real baseAngle: index * 45
                    property real diff: (baseAngle - (vesselState ? vesselState.heading : 0) + 540) % 360 - 180
                    x: (parent.width / 2) + (diff * (8 * scaleFactor)) - (width / 2)
                    anchors.bottom: parent.top
                    anchors.bottomMargin: Math.round(4 * scaleFactor)
                    visible: Math.abs(diff) < 90
                    text: modelData
                    color: modelData === "N" ? "#00f0ff" : Qt.rgba(0.80, 0.88, 0.98, 0.55)
                    font.pixelSize: Math.round(10 * scaleFactor)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }
            }
        }

        Text {                                           // tilt read-out: shown ~2.5 s after pressing [ or ]
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + Math.round(92 * scaleFactor)
            opacity: appWindow.horizonNudgeShown
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 400 } }
            text: "HORIZON [" + appWindow.horizonSource + "]   y " + Math.round(appWindow.horizonY) + "   tilt " + (appWindow.horizonRotation >= 0 ? "+" : "") + appWindow.horizonRotation.toFixed(1) + "°   offset " + appWindow.horizonOffsetY
            color: "#00f0ff"
            font.pixelSize: Math.round(11 * scaleFactor); font.bold: true; font.letterSpacing: 1
            font.family: "Segoe UI, Inter, sans-serif"
        }

        Item {
            id: minimalistCrosshair
            anchors.centerIn: parent
            width: Math.round(220 * scaleFactor)
            height: Math.round(120 * scaleFactor)

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(14 * scaleFactor)
                height: Math.round(14 * scaleFactor)
                radius: width / 2
                color: "transparent"
                border.color: "#00f0ff"
                border.width: 1.5
            }

            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: 2
                color: "#00f0ff"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Math.round(60 * scaleFactor)
                height: 1.5
                color: "#00f0ff"
                opacity: 0.85
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Math.round(-8 * scaleFactor)
                width: 1.5
                height: Math.round(16 * scaleFactor)
                color: "#00f0ff"
                opacity: 0.85
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: Math.round(60 * scaleFactor)
                height: 1.5
                color: "#00f0ff"
                opacity: 0.85
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Math.round(-8 * scaleFactor)
                width: 1.5
                height: Math.round(16 * scaleFactor)
                color: "#00f0ff"
                opacity: 0.85
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(18 * scaleFactor)
                width: 1.5
                height: Math.round(16 * scaleFactor)
                color: "#00f0ff"
                opacity: 0.70
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(18 * scaleFactor)
                width: 1.5
                height: Math.round(16 * scaleFactor)
                color: "#00f0ff"
                opacity: 0.70
            }

            Text {
                anchors.top: parent.bottom
                anchors.topMargin: Math.round(6 * scaleFactor)
                anchors.horizontalCenter: parent.horizontalCenter
                text: "P: " + (vesselState ? vesselState.pitch.toFixed(1) : "0.0") + "°   R: " + (vesselState ? vesselState.roll.toFixed(1) : "0.0") + "°"
                color: "#00f0ff"
                font.pixelSize: Math.round(10 * scaleFactor)
                font.bold: true
                font.letterSpacing: 1
                font.family: "Segoe UI, Inter, sans-serif"
            }
        }

        NavPath {                                        // AR path over the video (see NavPath.qml for the JSON it accepts)
            id: navPath
            anchors.fill: parent
            sf: scaleFactor
            focalPx: 0.714 * Math.max(appWindow.leftW, appWindow.height * 16.0 / 9.0)     // the video keeps its scale when it is cropped to the left third
            horizonRot: appWindow.horizonRotation
            horizonY: appWindow.horizonY
            heading: vesselState ? vesselState.heading : 0
            speedMs: vesselState ? vesselState.speed * 0.5144 : 0
            autonomous: !(vesselState && vesselState.mode === "TELEOP")
            wpBearing: (vesselState && vesselState.wpBearing !== undefined) ? Number(vesselState.wpBearing) : NaN
            wpDistM: (vesselState && vesselState.wpDistanceNm !== undefined) ? Number(vesselState.wpDistanceNm) * 1852 : NaN
            wpName: (vesselState && vesselState.wpName !== undefined) ? String(vesselState.wpName) : "WP"
            json: (typeof vesselState !== "undefined" && vesselState && vesselState.navPathJson !== undefined) ? vesselState.navPathJson : ""
        }

        Item {
            id: vesselCenterAvatar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(85 * scaleFactor)
            width: Math.round(80 * scaleFactor)
            height: Math.round(95 * scaleFactor)

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(58 * scaleFactor)
                height: Math.round(72 * scaleFactor)
                radius: Math.round(12 * scaleFactor)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#161d29" }
                    GradientStop { position: 1.0; color: "#0f141d" }
                }
                border.color: "#00f0ff"
                border.width: 1.5

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(8 * scaleFactor)
                    width: Math.round(40 * scaleFactor)
                    height: Math.round(24 * scaleFactor)
                    radius: Math.round(6 * scaleFactor)
                    color: "#101620"
                    border.color: Qt.rgba(0.68, 0.78, 0.90, 0.25)
                    border.width: 1
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.round(6 * scaleFactor)
                    width: Math.round(32 * scaleFactor)
                    height: Math.round(12 * scaleFactor)
                    radius: Math.round(3 * scaleFactor)
                    color: "#00f0ff"
                    opacity: 0.85
                }
            }
        }
    }

    // ---- INSTRUMENT CLUSTER (bottom-left, same place the "DASHBOARD OPTICAL" video used to be) ------------
    // The boat now processes the cluster video itself and only sends TEXT. InstrumentCluster.qml draws it.
    // Feed it with  json: <text from the boat>  (see the header of InstrumentCluster.qml for the keys).
    Item {
        id: layer1_5_pipDashboard                // same id: the grid button in the dock still shows / hides it
        z: 1.5
        readonly property real fullW: Math.round(Math.min(appWindow.width * 0.25, Math.max(300.0, 360.0 * scaleFactor)))
        width: Math.round(fullW * (1.0 - 0.22 * appWindow.splitT))                  // 22 % smaller beside the map
        height: Math.round(width * 202 / 360)
        anchors.left: parent.left
        anchors.leftMargin: Math.round(24 * scaleFactor)
        anchors.bottom: layer5_bottomDockBar.top
        anchors.bottomMargin: Math.round(20 * scaleFactor)

        InstrumentCluster {
            id: instrumentCluster
            anchors.fill: parent
            lm: appWindow.lm
            // wire the boat's cluster text here (any property that carries the JSON string). Without it the cluster
            // falls back to vesselState.speed / rpm / fuelLevel / coolantTemp / mode.
            json: (typeof vesselState !== "undefined" && vesselState && vesselState.clusterJson !== undefined) ? vesselState.clusterJson : ""
        }
    }

    Item {
        id: layer2_topHeaderBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(Math.max(50, Math.min(68, 56 * scaleFactor)))
        z: 60

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(28 * scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(10 * scaleFactor)
            opacity: 1.0 - appWindow.splitT
            visible: opacity > 0.01

            FontLoader {
                id: tandavStencilFont
                source: Qt.resolvedUrl("assets/fonts/BunkerStencil.otf")
            }

            Text {
                objectName: "tandavBrandText"
                text: "TANDAV"
                color: appWindow.mixc("#eef3fb", "#12183f")
                font.pixelSize: Math.round(26 * scaleFactor)
                font.letterSpacing: Math.round(3 * scaleFactor)
                font.capitalization: Font.AllUppercase
                font.family: tandavStencilFont.name
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            readonly property real normalW: Math.min(Math.round(460 * scaleFactor), parent.width * 0.42)
            anchors.verticalCenter: parent.verticalCenter
            height: Math.round(36 * scaleFactor)
            width: Math.round(normalW + (appWindow.leftW - Math.round(56 * scaleFactor) - normalW) * appWindow.splitT)
            x: Math.round((appWindow.leftW - width) / 2)
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: appWindow.mixc("#18212e", "#d1425569") }
                GradientStop { position: 1.0; color: appWindow.mixc("#0e141d", "#d1394c60") }
            }
            border.color: Qt.rgba(0.68 + 0.32 * appWindow.lm, 0.78 + 0.22 * appWindow.lm, 0.90 + 0.10 * appWindow.lm, 0.22 - 0.04 * appWindow.lm)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(12 * scaleFactor)
                anchors.rightMargin: Math.round(12 * scaleFactor)
                spacing: Math.round(8 * scaleFactor)

                Rectangle {
                    width: Math.round(20 * scaleFactor)
                    height: Math.round(20 * scaleFactor)
                    radius: width / 2
                    color: Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: "⚓"
                        color: appWindow.accentCyan
                        font.pixelSize: Math.round(11 * scaleFactor)
                    }
                }



                Text {
                    text: (typeof vesselState !== "undefined" && vesselState && vesselState.leakDetected) ? "CRITICAL: Bilge Ingress Alert" : "Autonomous Mode Activated. Clear Waters."
                    color: (typeof vesselState !== "undefined" && vesselState && vesselState.leakDetected) ? "#ef4444" : "#eef3fb"
                    font.pixelSize: Math.round(11 * scaleFactor)
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: Math.round(8 * scaleFactor)
                    height: Math.round(8 * scaleFactor)
                    radius: width / 2
                    color: (typeof vesselState !== "undefined" && vesselState && vesselState.leakDetected) ? "#ef4444" : "#10b981"
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        PropertyAnimation { to: 0.3; duration: 600 }
                        PropertyAnimation { to: 1.0; duration: 600 }
                    }
                }
            }
        }

        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: Math.round(28 * scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(12 * scaleFactor)

            Rectangle {
                height: Math.round(34 * scaleFactor)
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: appWindow.mixc("#18212e", "#d1425569") }
                    GradientStop { position: 1.0; color: appWindow.mixc("#0e141d", "#d1394c60") }
                }
                border.color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
                border.width: 1
                implicitWidth: diagRow.implicitWidth + Math.round(24 * scaleFactor)

                RowLayout {
                    id: diagRow
                    anchors.centerIn: parent
                    spacing: Math.round(10 * scaleFactor)

                    Text {
                        text: "RPM: " + (typeof vesselState !== "undefined" && vesselState ? vesselState.rpm : "3458")
                        color: "#f59e0b"
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                        font.family: "Segoe UI, Inter, sans-serif"
                    }

                    Rectangle {
                        width: 1
                        height: Math.round(12 * scaleFactor)
                        color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
                    }

                    Text {
                        text: "CLNT: " + (typeof vesselState !== "undefined" && vesselState ? vesselState.coolantTemp.toFixed(1) : "68.7") + "°C"
                        color: (vesselState && vesselState.coolantTemp > 80.0) ? "#ef4444" : "#10b981"
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                        font.family: "Segoe UI, Inter, sans-serif"
                    }

                    Rectangle {
                        width: 1
                        height: Math.round(12 * scaleFactor)
                        color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
                    }

                    Text {
                        text: "PING: " + (typeof vesselState !== "undefined" && vesselState ? vesselState.latencyMs : "12") + "ms"
                        color: appWindow.accentCyan
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                        font.family: "Segoe UI, Inter, sans-serif"
                    }
                }
            }

            // ---- DAY / NIGHT toggle: shows the mode you will switch TO (sun while it is night, moon while it is day)
            Rectangle {
                id: themeToggleBtn
                width: Math.round(34 * scaleFactor)
                height: Math.round(34 * scaleFactor)
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: themeMouseArea.containsMouse ? appWindow.mixc("#222c3c", "#e04e6379") : appWindow.mixc("#18212e", "#d1425569") }
                    GradientStop { position: 1.0; color: themeMouseArea.containsMouse ? appWindow.mixc("#141c28", "#e0445b6f") : appWindow.mixc("#0e141d", "#d1394c60") }
                }
                border.color: Qt.rgba(0.68, 0.78, 0.90, themeMouseArea.containsMouse ? 0.45 : 0.22)
                border.width: 1

                Item {
                    id: themeIcon
                    anchors.centerIn: parent
                    width: Math.round(18 * scaleFactor)
                    height: width

                    // sun (night -> tap for day): disc + 8 rays, turns away as the moon arrives
                    Item {
                        anchors.fill: parent
                        opacity: 1.0 - appWindow.lm
                        rotation: 70 * appWindow.lm
                        scale: 1.0 - 0.35 * appWindow.lm
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.40
                            height: width
                            radius: width / 2
                            color: "#F5C451"
                        }
                        Repeater {
                            model: 8
                            delegate: Item {
                                anchors.centerIn: parent
                                width: 1
                                height: 1
                                rotation: index * 45
                                Rectangle {
                                    x: -width / 2
                                    y: -themeIcon.height * 0.50
                                    width: Math.max(1.5, themeIcon.width * 0.09)
                                    height: themeIcon.height * 0.15
                                    radius: width / 2
                                    color: "#F5C451"
                                }
                            }
                        }
                    }

                    // moon (day -> tap for night): crescent
                    Shape {
                        anchors.fill: parent
                        opacity: appWindow.lm
                        rotation: -70 * (1.0 - appWindow.lm)
                        scale: 0.65 + 0.35 * appWindow.lm
                        layer.enabled: true
                        layer.samples: 4
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: "#E8EEF8"
                            startX: themeIcon.width * 0.62
                            startY: themeIcon.height * 0.06
                            PathArc {
                                x: themeIcon.width * 0.62
                                y: themeIcon.height * 0.94
                                radiusX: themeIcon.width * 0.46
                                radiusY: themeIcon.height * 0.46
                                direction: PathArc.Counterclockwise
                                useLargeArc: true
                            }
                            PathArc {
                                x: themeIcon.width * 0.62
                                y: themeIcon.height * 0.06
                                radiusX: themeIcon.width * 0.36
                                radiusY: themeIcon.height * 0.36
                                direction: PathArc.Clockwise
                                useLargeArc: false
                            }
                        }
                    }
                }

                MouseArea {
                    id: themeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appWindow.lightMode = !appWindow.lightMode
                }
            }

            Rectangle {
                id: fullscreenToggleBtn
                width: Math.round(34 * scaleFactor)
                height: Math.round(34 * scaleFactor)
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: fsMouseArea.containsMouse ? appWindow.mixc("#222c3c", "#e04e6379") : appWindow.mixc("#18212e", "#d1425569") }
                    GradientStop { position: 1.0; color: fsMouseArea.containsMouse ? appWindow.mixc("#141c28", "#e0445b6f") : appWindow.mixc("#0e141d", "#d1394c60") }
                }
                border.color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "🗖"
                    color: "#eef3fb"
                    font.pixelSize: Math.round(13 * scaleFactor)
                }

                MouseArea {
                    id: fsMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (appWindow.visibility === Window.FullScreen) {
                            appWindow.visibility = Window.Windowed;
                        } else {
                            appWindow.visibility = Window.FullScreen;
                        }
                    }
                }
            }

            Rectangle {
                id: quitButton
                height: Math.round(34 * scaleFactor)
                width: Math.round(82 * scaleFactor)
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: quitMouseArea.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.50) : appWindow.mixc("#2a171d", "#d1823a45") }
                    GradientStop { position: 1.0; color: quitMouseArea.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.30) : appWindow.mixc("#180e12", "#d1692f38") }
                }
                border.color: "#ef4444"
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "✕"
                        color: "#ffffff"
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                    }

                    Text {
                        text: "EXIT"
                        color: "#ffffff"
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                        font.family: "Segoe UI, Inter, sans-serif"
                    }
                }

                MouseArea {
                    id: quitMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.quit()
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // TELEMETRY CARDS (Neuboat style): Account, Fuel, Weather, Roll, Pitch,
    // Depth, Wind, Waypoint, Speed.  Values read from vesselState where the
    // field exists, otherwise they fall back to the static demo value.
    // ---------------------------------------------------------------------
    Component {
        id: accountCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: ac
            title: "Account"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.70
            valueSize: 36
            readonly property real pct: (typeof vesselState !== "undefined" && vesselState && vesselState.accountHealth !== undefined) ? vesselState.accountHealth : 82
            cardValue: pct.toFixed(0)
            cardUnit: "%"
            cardSubtext: "327 hours logged"

            TelemetryCard.TickArc {
                lm: appWindow.lm
                anchors.fill: parent
                cx: width / 2; cy: height * 0.70; r: height * 0.255
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.010)
                segStart: 135
                segSweep: 270 * Math.max(0, Math.min(100, ac.pct)) / 100
                segWidth: Math.max(2, height * 0.020)
                capLen: height * 0.06
            }
        }
    }

    Component {
        id: fuelCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: fc
            title: "Fuel"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.50
            valueSize: 46
            readonly property real pct: (typeof vesselState !== "undefined" && vesselState && vesselState.fuelLevel !== undefined) ? vesselState.fuelLevel : 30
            readonly property real avail: (typeof vesselState !== "undefined" && vesselState && vesselState.fuelAvailable !== undefined) ? vesselState.fuelAvailable : 16
            cardValue: pct.toFixed(0)
            cardUnit: "%"

            TelemetryCard.TickArc {
                lm: appWindow.lm
                id: fuelArc
                anchors.fill: parent
                cx: width / 2; cy: height * 0.50; r: height * 0.30
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.008)
                segStart: 135
                segSweep: 270 * Math.max(0, Math.min(100, fc.pct)) / 100
                segWidth: Math.max(2, height * 0.018)
                capLen: height * 0.06
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.80
                textFormat: Text.StyledText
                text: "Available: <font color=\"" + fc.cTitle + "\"><b>" + fc.avail.toFixed(0) + " gal</b></font>"
                color: fc.cSoft
                font.pixelSize: Math.round(10.5 * fc.u)
                font.weight: Font.Light
                font.family: fc.fontText
            }
            Text {
                text: "E"
                x: fuelArc.cx - fuelArc.r * 0.707 - width / 2
                y: fuelArc.cy + fuelArc.r * 0.707 - height * 0.2
                color: fc.cFaint
                font.pixelSize: Math.round(9.5 * fc.u)
                font.family: fc.fontText
            }
            Text {
                text: "F"
                x: fuelArc.cx + fuelArc.r * 0.707 - width / 2
                y: fuelArc.cy + fuelArc.r * 0.707 - height * 0.2
                color: fc.cFaint
                font.pixelSize: Math.round(9.5 * fc.u)
                font.family: fc.fontText
            }
        }
    }

    Component {
        id: weatherCardComp
        TelemetryCard {
            lm: appWindow.lm
            title: "Tampa, FL"
            titleMoon: true
            cardValue: "6"
            cardUnit: "°F"
            cardSubtext: "Mostly Cloudy\nRain: 30%\nVisibility: 9 nm"

            // big cloud, flush with the right + bottom edge (clipped by the card corners)
            Image {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.60
                height: parent.height * 0.70
                source: Qt.resolvedUrl("assets/weather_cloud.png")
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignRight
                verticalAlignment: Image.AlignBottom
                smooth: true
                mipmap: true
                // day look: the smoky night cloud is lifted to a bright white cloud
                layer.enabled: appWindow.lm > 0.001
                layer.effect: MultiEffect { brightness: 0.34 * appWindow.lm; contrast: 0.08 * appWindow.lm }
            }
        }
    }

    Component {
        id: rollCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: rc
            title: "Roll"
            readonly property real ang: (typeof vesselState !== "undefined" && vesselState) ? vesselState.roll : 15
            cardValue: Math.abs(ang).toFixed(0)
            cardUnit: "°"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState)
                         ? ("The boat is tilted\n" + Math.abs(ang).toFixed(0) + "° " + (ang >= 0 ? "stbd" : "port"))
                         : "The boat is tilted\n15° upward"

            // dashed protractor arc over the boat + thin blue span from top-centre toward the heel side
            TelemetryCard.TickArc {
                lm: appWindow.lm
                anchors.fill: parent
                cx: width * 0.64; cy: height * 0.72; r: width * 0.31
                trackStart: 183; trackSweep: 174
                trackWidth: height * 0.050
                segStart: 270
                segSweep: (rc.ang >= 0 ? 1 : -1) * Math.min(80, Math.max(8, Math.abs(rc.ang) * 4))
                segWidth: Math.max(2, height * 0.014)
                capLen: height * 0.075
            }
            Text {
                text: "Left"
                x: parent.width * 0.64 - parent.width * 0.31 * 0.70 - width / 2
                y: parent.height * 0.72 - height / 2
                color: rc.cLabel
                font.pixelSize: Math.round(9 * rc.u)
                font.weight: Font.Light
                font.family: rc.fontText
            }
            Text {
                text: "Right"
                x: parent.width * 0.64 + parent.width * 0.31 * 0.70 - width / 2
                y: parent.height * 0.72 - height / 2
                color: rc.cLabel
                font.pixelSize: Math.round(9 * rc.u)
                font.weight: Font.Light
                font.family: rc.fontText
            }
            Image {
                width: parent.width * 0.34
                height: parent.height * 0.52
                x: parent.width * 0.64 - width / 2
                y: parent.height * 0.67 - height / 2
                source: Qt.resolvedUrl("assets/roll_yacht_render.png")
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                rotation: rc.ang
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            }
        }
    }

    Component {
        id: pitchCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: pc
            title: "Pitch"
            readonly property real ang: (typeof vesselState !== "undefined" && vesselState) ? vesselState.pitch : 7
            cardValue: Math.abs(ang).toFixed(0)
            cardUnit: "°"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState)
                         ? ("The boat is tilted\n" + Math.abs(ang).toFixed(0) + "° " + (ang >= 0 ? "bow up" : "bow down"))
                         : "The boat is tilted\n7° bow up"

            // dashed arc rising from the bow + blue bracket that opens toward the pitch direction
            TelemetryCard.TickArc {
                lm: appWindow.lm
                anchors.fill: parent
                cx: width * 0.77; cy: height * 0.73; r: width * 0.35
                trackStart: 190; trackSweep: 85
                trackWidth: height * 0.050
                segStart: 180
                segSweep: (pc.ang >= 0 ? 1 : -1) * Math.min(70, Math.max(8, Math.abs(pc.ang) * 3))
                segWidth: Math.max(2, height * 0.014)
                capLen: height * 0.075
            }
            Image {
                width: parent.width * 0.56
                height: parent.height * 0.44
                x: parent.width * 0.79 - width / 2
                y: parent.height * 0.74 - height / 2
                source: Qt.resolvedUrl("assets/pitch_yacht_render.png")
                fillMode: Image.PreserveAspectFit
                mirror: true                       // bow points left, like the reference
                smooth: true
                mipmap: true
                rotation: pc.ang
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            }
        }
    }

    Component {
        id: depthCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: dc
            title: "Depth"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.715
            cardValue: (typeof vesselState !== "undefined" && vesselState) ? (vesselState.depth * 3.28084).toFixed(0) : "27"
            cardUnit: "ft"
            cardSubtext: "Located in deep water"

            Item {
                id: depthGfx
                anchors.fill: parent
                readonly property real railTop: height * 0.42
                readonly property real railBot: height * 0.90
                readonly property real stemLen: height * 0.13
                readonly property color blue: dc.accentBlue

                // dim dashed rails across the card
                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: dc.cRail
                        strokeWidth: depthGfx.height * 0.024
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2.4, 2.8]
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        startX: depthGfx.width * 0.07; startY: depthGfx.railTop
                        PathLine { x: depthGfx.width * 0.93; y: depthGfx.railTop }
                    }
                    ShapePath {
                        strokeColor: dc.cRail
                        strokeWidth: depthGfx.height * 0.024
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2.4, 2.8]
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        startX: depthGfx.width * 0.07; startY: depthGfx.railBot
                        PathLine { x: depthGfx.width * 0.93; y: depthGfx.railBot }
                    }
                }
                // blue centre bars with soft ends
                Repeater {
                    model: [depthGfx.railTop, depthGfx.railBot]
                    delegate: Rectangle {
                        width: depthGfx.width * 0.30
                        height: Math.max(3, depthGfx.height * 0.028)
                        x: (depthGfx.width - width) / 2
                        y: modelData - height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.00; color: Qt.rgba(depthGfx.blue.r, depthGfx.blue.g, depthGfx.blue.b, 0.0) }
                            GradientStop { position: 0.22; color: depthGfx.blue }
                            GradientStop { position: 0.78; color: depthGfx.blue }
                            GradientStop { position: 1.00; color: Qt.rgba(depthGfx.blue.r, depthGfx.blue.g, depthGfx.blue.b, 0.0) }
                        }
                    }
                }
                // stems that form the two "T"s
                Rectangle {
                    width: Math.max(2, depthGfx.height * 0.010); height: depthGfx.stemLen
                    x: (depthGfx.width - width) / 2; y: depthGfx.railTop
                    color: depthGfx.blue
                }
                Rectangle {
                    width: Math.max(2, depthGfx.height * 0.010); height: depthGfx.stemLen
                    x: (depthGfx.width - width) / 2; y: depthGfx.railBot - height
                    color: depthGfx.blue
                }
            }
        }
    }

    Component {
        id: windCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: wc
            title: "Wind"
            centerDesign: true
            readonly property real windFrom: 113        // bearing the wind comes from
            readonly property real windKmh: 13
            readonly property var names16: ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
            cardSubtext: "Speed: " + windKmh.toFixed(0) + "km/h\nDirection: " + windFrom.toFixed(0) + "° " + names16[Math.round(windFrom / 22.5) % 16]

            TelemetryCard.CompassDial {
                lm: appWindow.lm
                width: parent.height * 0.50
                height: width
                x: (parent.width - width) / 2
                y: parent.height * 0.69 - height / 2
                windFrom: wc.windFrom
                heading: (typeof vesselState !== "undefined" && vesselState && vesselState.heading !== undefined) ? vesselState.heading : 45
            }
        }
    }

    Component {
        id: waypointCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: nc
            title: "Waypoint"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.58
            valueSize: 34
            readonly property real dist: (typeof vesselState !== "undefined" && vesselState && vesselState.wpDistanceNm !== undefined) ? vesselState.wpDistanceNm : 2.25
            cardValue: dist.toFixed(2)
            cardUnit: "NM"

            TelemetryCard.TickArc {
                lm: appWindow.lm
                id: wpArc
                anchors.fill: parent
                cx: width / 2; cy: height * 0.58; r: height * 0.335
                trackStart: 0; trackSweep: 360
                dashed: false
                trackWidth: Math.max(1, height * 0.010)
                trackColor: nc.cWpTrack
                segStart: 120
                segSweep: 300
                segWidth: Math.max(2, height * 0.026)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: wpArc.cy - wpArc.r * 0.62 - height / 2
                text: "To WP-02"
                color: nc.cFaint
                font.pixelSize: Math.round(9.5 * nc.u)
                font.weight: Font.Light
                font.family: nc.fontText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: wpArc.cy + wpArc.r * 0.62 - height / 2
                text: "Distance"
                color: nc.cFaint
                font.pixelSize: Math.round(9.5 * nc.u)
                font.weight: Font.Light
                font.family: nc.fontText
            }
        }
    }

    Component {
        id: speedCardComp
        TelemetryCard {
            lm: appWindow.lm
            id: sc
            title: "Speed (SOG)"
            centerDesign: true
            valueCentered: true
            valueCenterY: 0.64
            valueSize: 38
            readonly property real kts: (typeof vesselState !== "undefined" && vesselState) ? vesselState.speed : 12
            cardValue: kts.toFixed(1)
            cardUnit: "kts"
            cardSubtext: (typeof vesselState !== "undefined" && vesselState) ? ("HDG: " + Math.round(vesselState.heading) + "° | RPM: " + vesselState.rpm) : "Stationary"

            TelemetryCard.TickArc {
                lm: appWindow.lm
                anchors.fill: parent
                cx: width / 2; cy: height * 0.64; r: height * 0.30
                trackStart: 135; trackSweep: 270
                dashed: false
                trackWidth: Math.max(1, height * 0.008)
                segStart: 135
                segSweep: 270 * Math.max(0.02, Math.min(1, sc.kts / 30))
                segWidth: Math.max(2, height * 0.018)
                capLen: height * 0.06
            }
        }
    }

    Item {
        id: layer3_telemetryCardsCarousel
        anchors.top: layer2_topHeaderBar.bottom
        anchors.topMargin: Math.round(14 * scaleFactor)
        x: Math.round((appWindow.leftW - width) / 2)
        width: carouselViewport.width
        height: Math.round(cardH + 24 * scaleFactor)
        z: 3
        visible: appWindow.videoShown

        property real scrollPos: 3.0
        property int currentIndex: 3
        readonly property int maxIndex: 8

        // SPLIT VIEW: in the left third the cards become 3 pages x 3 cards (same pager as the 3D view's compact mode)
        readonly property real containerWidth: Math.round(appWindow.width * 0.90 + (appWindow.leftW - appWindow.width * 0.90) * appWindow.splitT)
        readonly property bool compact: appWindow.splitT > 0.5
        property real pagePos: 0.0
        property int pageIndex: 0
        readonly property var cPage: [1, 1, 0, 2, 2, 0, 0, 2, 1]       // card index -> page
        readonly property var cSlot: [0, 1, 0, 0, 1, 1, 2, 2, 2]       // card index -> slot in the page
        readonly property var cSlotW: [0.39, 0.25, 0.25]                // slot width (fraction of the pane width)
        readonly property real cMargin: 0.04
        readonly property real cGap: 0.016
        function cSlotLeft(sl) {
            var x = cMargin;
            for (var i = 0; i < sl; ++i) x += cSlotW[i] + cGap;
            return x * containerWidth;
        }
        function cCardX(k)  { return cSlotLeft(cSlot[k]) + cSlotW[cSlot[k]] * containerWidth / 2 + (cPage[k] - pagePos) * containerWidth; }
        function cCardW(k)  { return cSlotW[cSlot[k]] * containerWidth; }
        function cCardO(k)  { return Math.max(0.0, 1.0 - Math.abs(cPage[k] - pagePos) * 1.7); }
        function mixv(a, b) { return a + (b - a) * appWindow.splitT; }
        NumberAnimation { id: pageAnim; target: layer3_telemetryCardsCarousel; property: "pagePos"; duration: 300; easing.type: Easing.OutCubic }
        function goPage(p) {
            pageIndex = Math.max(0, Math.min(2, p));
            pageAnim.stop(); pageAnim.to = pageIndex; pageAnim.start();
        }
        readonly property real cardW: Math.round(appWindow.width * 0.161)
        readonly property real cardH: Math.round(appWindow.height * 0.175)
        readonly property real cardSpacing: Math.round(cardW * 0.07)
        readonly property real peekWidth: Math.round(cardW * 0.45)
        readonly property real peekScale: 0.78

        NumberAnimation {
            id: posAnim
            target: layer3_telemetryCardsCarousel
            property: "scrollPos"
            duration: 280
            easing.type: Easing.OutCubic
        }

        function animateTo(target) {
            posAnim.stop();
            posAnim.to = target;
            posAnim.start();
        }

        function nextCard() {
            if (currentIndex < maxIndex) {
                currentIndex++;
                animateTo(currentIndex);
            }
        }

        function prevCard() {
            if (currentIndex > 0) {
                currentIndex--;
                animateTo(currentIndex);
            }
        }


        // ---- Neuboat card-row layout --------------------------------------
        // Measured from the reference (card = 171 x 105 px @1061 x 600):
        //  * 3 FULL cards in the focus window  [current-1, current, current+1]
        //  * the next 2 cards on the right are NARROW (0.63 of a full card, same height)
        //  * 2 PEEK cards sit behind each end (scaled 0.78 / 0.64, dimmed, half hidden)
        //  * gap between cards = 0.07 x card width
        // Every value is in units of the full card width (cardW) and is interpolated
        // linearly on  rel = index - scrollPos,  so cards grow / shrink while sliding.
        // table index = rel + 4   (rel -4 .. +6)
        readonly property var layX: [-1.66, -1.63, -1.42, -1.07, 0.0, 1.07, 1.955, 2.655, 2.83, 3.08, 3.10]
        readonly property var layW: [ 1.00,  1.00,  1.00,  1.00, 1.0, 1.00, 0.63,  0.63,  1.00, 1.00, 1.00]
        readonly property var layS: [ 0.64,  0.64,  0.78,  1.00, 1.0, 1.00, 1.00,  1.00,  0.78, 0.64, 0.64]
        readonly property var layO: [ 0.00,  0.55,  0.72,  1.00, 1.0, 1.00, 1.00,  1.00,  0.72, 0.55, 0.00]
        readonly property var layZ: [ 2,     3,     4,     10,   12,  10,   8,     8,     4,    3,    2   ]
        readonly property real rowShift: -0.62      // centre card sits 0.62 cards left of screen centre (as in the reference)

        function lay(tbl, k, s) {
            var r = Math.max(-4.0, Math.min(6.0, k - s));
            var f = Math.floor(r);
            if (f >= 6) f = 5;
            var t = r - f;
            var a = tbl[f + 4];
            var b = tbl[f + 5];
            return a + (b - a) * t;
        }

        function getCardX(k, s) {
            var n = containerWidth / 2.0 + (rowShift + lay(layX, k, s)) * cardW;
            return appWindow.splitT < 0.001 ? n : mixv(n, cCardX(k));
        }
        function getCardWidth(k, s)   { var n = cardW * lay(layW, k, s); return appWindow.splitT < 0.001 ? n : mixv(n, cCardW(k)); }
        function getCardScale(k, s)   { var n = lay(layS, k, s); return appWindow.splitT < 0.001 ? n : mixv(n, 1.0); }
        function getCardOpacity(k, s) { var n = lay(layO, k, s); return appWindow.splitT < 0.001 ? n : mixv(n, cCardO(k)); }
        function getCardZ(k, s)       { var n = Math.round(lay(layZ, k, s)); return appWindow.splitT < 0.5 ? n : 10; }

        Item {
            id: carouselViewport
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: layer3_telemetryCardsCarousel.containerWidth
            height: layer3_telemetryCardsCarousel.cardH
            clip: false

            Repeater {
                model: [
                    accountCardComp,
                    fuelCardComp,
                    weatherCardComp,
                    rollCardComp,
                    pitchCardComp,
                    depthCardComp,
                    windCardComp,
                    waypointCardComp,
                    speedCardComp
                ]

                delegate: Item {
                    id: cardWrapper
                    width: layer3_telemetryCardsCarousel.getCardWidth(index, layer3_telemetryCardsCarousel.scrollPos)
                    height: layer3_telemetryCardsCarousel.cardH
                    x: layer3_telemetryCardsCarousel.getCardX(index, layer3_telemetryCardsCarousel.scrollPos) - (width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    z: layer3_telemetryCardsCarousel.getCardZ(index, layer3_telemetryCardsCarousel.scrollPos)
                    scale: layer3_telemetryCardsCarousel.getCardScale(index, layer3_telemetryCardsCarousel.scrollPos)
                    opacity: layer3_telemetryCardsCarousel.getCardOpacity(index, layer3_telemetryCardsCarousel.scrollPos)
                    visible: opacity > 0.01
                    transformOrigin: Item.Center

                    Loader {
                        anchors.fill: parent
                        sourceComponent: modelData
                        onLoaded: {
                            if (item && typeof item.isActive !== "undefined") {
                                item.isActive = Qt.binding(function() { return layer3_telemetryCardsCarousel.compact ? (layer3_telemetryCardsCarousel.cPage[index] === layer3_telemetryCardsCarousel.pageIndex) : (index === layer3_telemetryCardsCarousel.currentIndex); });
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: carouselDragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: dragActive ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property bool dragActive: false
                property real startMouseX: 0
                property real startScrollPos: 0

                onPressed: (mouse) => {
                    dragActive = true;
                    startMouseX = mouse.x;
                    startScrollPos = layer3_telemetryCardsCarousel.compact ? layer3_telemetryCardsCarousel.pagePos : layer3_telemetryCardsCarousel.scrollPos;
                    posAnim.stop();
                    pageAnim.stop();
                }

                onPositionChanged: (mouse) => {
                    if (dragActive) {
                        var deltaX = mouse.x - startMouseX;
                        if (layer3_telemetryCardsCarousel.compact) {
                            var rp = startScrollPos - deltaX / Math.max(1, layer3_telemetryCardsCarousel.containerWidth * 0.9);
                            if (rp < 0) rp *= 0.28; else if (rp > 2) rp = 2 + (rp - 2) * 0.28;
                            layer3_telemetryCardsCarousel.pagePos = rp;
                            return;
                        }
                        var dragStep = layer3_telemetryCardsCarousel.cardW * 1.07;
                        var deltaPos = -deltaX / dragStep;
                        var rawPos = startScrollPos + deltaPos;
                        if (rawPos < 0) {
                            rawPos = rawPos * 0.35;
                        } else if (rawPos > layer3_telemetryCardsCarousel.maxIndex) {
                            rawPos = layer3_telemetryCardsCarousel.maxIndex + (rawPos - layer3_telemetryCardsCarousel.maxIndex) * 0.35;
                        }
                        layer3_telemetryCardsCarousel.scrollPos = rawPos;
                    }
                }

                onReleased: (mouse) => {
                    if (dragActive) {
                        dragActive = false;
                        var deltaX = mouse.x - startMouseX;
                        var threshold = Math.round(45 * scaleFactor);
                        if (layer3_telemetryCardsCarousel.compact) {
                            var pi = layer3_telemetryCardsCarousel.pageIndex;
                            layer3_telemetryCardsCarousel.goPage(deltaX < -threshold ? pi + 1 : deltaX > threshold ? pi - 1 : pi);
                            return;
                        }
                        var target = layer3_telemetryCardsCarousel.currentIndex;

                        if (Math.abs(deltaX) < 12) {
                            if (mouse.x > layer3_telemetryCardsCarousel.containerWidth - layer3_telemetryCardsCarousel.peekWidth - 25) {
                                target = Math.min(layer3_telemetryCardsCarousel.maxIndex, layer3_telemetryCardsCarousel.currentIndex + 1);
                            } else if (mouse.x < layer3_telemetryCardsCarousel.peekWidth + 25) {
                                target = Math.max(0, layer3_telemetryCardsCarousel.currentIndex - 1);
                            }
                        } else {
                            if (deltaX < -threshold) {
                                target = Math.min(layer3_telemetryCardsCarousel.maxIndex, layer3_telemetryCardsCarousel.currentIndex + 1);
                            } else if (deltaX > threshold) {
                                target = Math.max(0, layer3_telemetryCardsCarousel.currentIndex - 1);
                            }
                        }

                        layer3_telemetryCardsCarousel.currentIndex = target;
                        layer3_telemetryCardsCarousel.animateTo(target);
                    }
                }

                onCanceled: {
                    dragActive = false;
                    if (layer3_telemetryCardsCarousel.compact) { layer3_telemetryCardsCarousel.goPage(layer3_telemetryCardsCarousel.pageIndex); return; }
                    layer3_telemetryCardsCarousel.animateTo(layer3_telemetryCardsCarousel.currentIndex);
                }

                onWheel: (wheel) => {
                    if (layer3_telemetryCardsCarousel.compact) {
                        layer3_telemetryCardsCarousel.goPage(layer3_telemetryCardsCarousel.pageIndex + ((wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) ? 1 : -1));
                        return;
                    }
                    if (wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) {
                        layer3_telemetryCardsCarousel.nextCard();
                    } else if (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0) {
                        layer3_telemetryCardsCarousel.prevCard();
                    }
                }
            }
        }

        Row {
            anchors.top: carouselViewport.bottom
            anchors.topMargin: Math.round(6 * scaleFactor)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(5 * scaleFactor)

            Repeater {
                model: layer3_telemetryCardsCarousel.compact ? 3 : layer3_telemetryCardsCarousel.maxIndex + 1
                delegate: Rectangle {
                    readonly property int cur: layer3_telemetryCardsCarousel.compact ? layer3_telemetryCardsCarousel.pageIndex : layer3_telemetryCardsCarousel.currentIndex
                    width: (index === cur) ? Math.round(18 * scaleFactor) : Math.round(5 * scaleFactor)
                    height: Math.round(4 * scaleFactor)
                    radius: height / 2
                    color: (index === cur) ? "#00f0ff" : Qt.rgba(0.68, 0.78, 0.90, 0.30)

                    Behavior on width {
                        NumberAnimation { duration: 200 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (layer3_telemetryCardsCarousel.compact) { layer3_telemetryCardsCarousel.goPage(index); return; }
                            layer3_telemetryCardsCarousel.currentIndex = index;
                            layer3_telemetryCardsCarousel.animateTo(index);
                        }
                    }
                }
            }
        }
    }

    Item {
        id: layer4_floatingCruisingBar
        x: Math.round((appWindow.leftW - width) / 2 + (appWindow.leftW - width - Math.round(24 * scaleFactor) - (appWindow.leftW - width) / 2) * appWindow.splitT)
        anchors.bottom: layer5_bottomDockBar.top
        anchors.bottomMargin: Math.round(14 * scaleFactor)
        width: Math.round(230 * scaleFactor)
        height: Math.round(40 * scaleFactor)
        z: 4

        Rectangle {
            anchors.fill: parent
            radius: 8
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#18212e" }
                GradientStop { position: 1.0; color: "#0e141d" }
            }
            border.color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(12 * scaleFactor)
                anchors.rightMargin: Math.round(12 * scaleFactor)

                Text {
                    text: "∧"
                    color: "#00f0ff"
                    font.pixelSize: Math.round(12 * scaleFactor)
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                telemetry.sendTargetSpeed(vesselState.targetSpeed + 1.0);
                            }
                        }
                    }
                }

                Text {
                    text: vesselState ? (vesselState.targetSpeed > 0 ? Math.round(vesselState.targetSpeed) : Math.round(vesselState.speed * 2)) : "12"
                    color: "#eef3fb"
                    font.pixelSize: Math.round(16 * scaleFactor)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: "∨"
                    color: "#00f0ff"
                    font.pixelSize: Math.round(12 * scaleFactor)
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                telemetry.sendTargetSpeed(Math.max(0.0, vesselState.targetSpeed - 1.0));
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: Math.round(16 * scaleFactor)
                    color: Qt.rgba(0.68, 0.78, 0.90, 0.25)
                }

                Text {
                    text: "❚❚"
                    color: "#eef3fb"
                    font.pixelSize: Math.round(12 * scaleFactor)
                    font.bold: true
                }

                Text {
                    text: "◼"
                    color: "#ef4444"
                    font.pixelSize: Math.round(12 * scaleFactor)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry) {
                                telemetry.sendEmergencyStop();
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: layer6_tacticalMapLoader
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: appWindow.leftW
        z: 50
        active: mapViewOpen
        source: mapViewOpen ? "TacticalMapView.qml" : ""
        opacity: mapViewOpen ? 1.0 : 0.0
        visible: opacity > 0.01 && appWindow.primaryVisible
        onLoaded: {
            if (item && typeof item.lightMode !== "undefined")
                item.lightMode = Qt.binding(function() { return appWindow.lightMode; });
            if (item && typeof item.themeAnimated !== "undefined")
                item.themeAnimated = Qt.binding(function() { return appWindow.themeAnimated; });
            if (item && typeof item.splitT !== "undefined")
                item.splitT = Qt.binding(function() { return appWindow.splitT; });
        }

        Behavior on opacity {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
    }

    // ---- where is the boat?  (telemetry -> gpsd -> QtPositioning/NMEA -> last known -> home) ------------
    Loader {
        id: gnssLoader
        asynchronous: false
    }
    onMissionOpenChanged: {
        if (missionOpen && gnssLoader.status === Loader.Null)
            gnssLoader.setSource("GnssSource.qml", {
                "nmeaSource": appWindow.gnssNmeaSource,
                "allowIpLookup": appWindow.gnssAllowIpLookup,
                "homeLat": appWindow.gnssHomeLat,
                "homeLon": appWindow.gnssHomeLon
            });
    }
    onMissionTChanged: if (missionT === 0.0 && !missionOpen && gnssLoader.status !== Loader.Null) gnssLoader.source = ""     // stop the GNSS listener when the map is closed

    // ---- the mission map: slides in from the right above the bottom bar: full screen (B) or exactly 2/3 (C) -----
    Item {
        id: missionPane
        readonly property real paneW: Math.round(appWindow.width * (1.0 - appWindow.splitT / 3.0))
        width: paneW
        x: appWindow.width - paneW * appWindow.missionT
        y: 0
        height: appWindow.height - layer5_bottomDockBar.height
        visible: appWindow.missionT > 0.002
        clip: true
        z: 55

        Loader {
            id: missionLoader
            anchors.fill: parent
            active: (appWindow.missionOpen || appWindow.missionT > 0.002) && gnssLoader.status !== Loader.Null && gnssLoader.status !== Loader.Loading
            source: "MissionMapView.qml"
            onLoaded: {
                var g = gnssLoader;
                item.lm = Qt.binding(function() { return appWindow.lm; });
                item.topInset = Qt.binding(function() { return layer2_topHeaderBar.height; });
                item.navigating = Qt.binding(function() { return appWindow.missionNavigating; });
                item.vesselLat = Qt.binding(function() { return g.item ? g.item.lat : NaN; });
                item.vesselLon = Qt.binding(function() { return g.item ? g.item.lon : NaN; });
                item.vesselHdg = Qt.binding(function() { return g.item ? g.item.heading : 0; });
                item.vesselKn = Qt.binding(function() { return g.item ? g.item.speedKn : 0; });
                item.gnssLive = Qt.binding(function() { return g.item ? g.item.live : false; });
                item.gnssText = Qt.binding(function() { return g.item ? g.item.text : "NO GNSS MODULE"; });
                item.startRequested.connect(function(w) { appWindow.missionNavigating = true; appWindow.missionStartRequested(w); });
                item.endRequested.connect(function() { appWindow.missionNavigating = false; appWindow.missionEndRequested(); });
                item.openAtVessel();
            }
        }
        // soft shadow where the two halves meet
        Rectangle {
            x: 0; y: 0; width: 18; height: parent.height
            z: 5
            opacity: appWindow.splitT
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#70000000" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; z: 6; color: Qt.rgba(1, 1, 1, 0.07); opacity: appWindow.splitT }
    }

    // ---- SYSTEM CONNECTIONS: the gear button in the dock opens it (link_monitor.py feeds `linkMonitor`) -------
    ConnectionsPanel {
        id: connectionsPanel
        objectName: "connectionsPanel"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - layer5_bottomDockBar.height          // the dock stays usable
        z: 90
        open: appWindow.settingsViewOpen
        sf: scaleFactor
        lm: appWindow.lm
        accent: appWindow.accentCyan
        monitor: (typeof linkMonitor !== "undefined") ? linkMonitor : null
        onCloseRequested: {
            appWindow.settingsViewOpen = false
            if (monitor && typeof monitor.setPanelOpen === "function") monitor.setPanelOpen(false)
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: appWindow.settingsViewOpen
        onActivated: appWindow.settingsViewOpen = false
    }

    // ---- LORA MANUAL CONTROL HUD (keyboard + touch teleop, status pill, feedback bars) ----
    LoraControlHud {
        id: loraHud
        sf: scaleFactor
        lm: appWindow.lm
        accent: appWindow.accentCyan
        anchors.right: parent.right
        anchors.rightMargin: Math.round(24 * scaleFactor)
        anchors.bottom: layer5_bottomDockBar.top
        anchors.bottomMargin: Math.round(12 * scaleFactor)
        z: 60
    }

    Item {
        id: layer5_bottomDockBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(Math.max(50, Math.min(68, 56 * scaleFactor)))
        z: 60

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: appWindow.mixc("#161d29", "#111110") }
                GradientStop { position: 1.0; color: appWindow.mixc("#0d121a", "#0f0f0d") }
            }
            border.color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
            border.width: 1

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(24 * scaleFactor)
                anchors.rightMargin: Math.round(24 * scaleFactor)
                spacing: Math.round(Math.min(32, Math.max(14, appWindow.width * 0.018)))

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: Math.round(34 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: settingsMouse.containsMouse || settingsViewOpen ? appWindow.mixc("#222c3c", "#2b2b2a") : appWindow.mixc("#141c28", "#1b1b1a") }
                        GradientStop { position: 1.0; color: settingsMouse.containsMouse || settingsViewOpen ? appWindow.mixc("#16202e", "#1c1c1b") : appWindow.mixc("#0d131c", "#121211") }
                    }
                    border.color: settingsViewOpen ? appWindow.accentCyan : (settingsMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: settingsViewOpen ? appWindow.accentCyan : (settingsMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.65))
                        font.pixelSize: Math.round(16 * scaleFactor)
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsViewOpen = !settingsViewOpen;
                        }
                    }
                }

                Rectangle {
                    width: Math.round(34 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: helmMouse.containsMouse || (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? appWindow.mixc("#222c3c", "#2b2b2a") : appWindow.mixc("#141c28", "#1b1b1a") }
                        GradientStop { position: 1.0; color: helmMouse.containsMouse || (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? appWindow.mixc("#16202e", "#1c1c1b") : appWindow.mixc("#0d131c", "#121211") }
                    }
                    border.color: (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? "#f59e0b" : (helmMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "☸"
                        color: (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? "#f59e0b" : (helmMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.65))
                        font.pixelSize: Math.round(16 * scaleFactor)
                    }

                    MouseArea {
                        id: helmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                telemetry.sendMode(vesselState.mode === "TELEOP" ? "AUTO" : "TELEOP");
                            }
                        }
                    }
                }

                Rectangle {
                    id: mapToggleBtn
                    width: Math.round(92 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: mapViewOpen ? appWindow.mixc("#162838", "#142030") : (mapMouse.containsMouse ? appWindow.mixc("#202a3a", "#2a2a29") : appWindow.mixc("#141c28", "#1b1b1a")) }
                        GradientStop { position: 1.0; color: mapViewOpen ? appWindow.mixc("#0c1824", "#0e1620") : (mapMouse.containsMouse ? appWindow.mixc("#141c28", "#1b1b1a") : appWindow.mixc("#0d131c", "#121211")) }
                    }
                    border.color: mapViewOpen ? appWindow.accentCyan : (mapMouse.containsMouse ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
                    border.width: mapViewOpen ? 1.5 : 1.0

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: "📍"
                            font.pixelSize: Math.round(12 * scaleFactor)
                        }
                        Text {
                            text: "MAP"
                            color: mapViewOpen ? appWindow.accentCyan : (mapMouse.containsMouse ? "#ffffff" : Qt.rgba(0.82, 0.88, 0.96, 0.85))
                            font.pixelSize: Math.round(11 * scaleFactor)
                            font.bold: true
                            font.letterSpacing: 1
                            font.family: "Segoe UI, Inter, sans-serif"
                        }
                    }

                    MouseArea {
                        id: mapMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            mapViewOpen = !mapViewOpen;
                            if (missionOpen && !splitOn) { missionOpen = false; splitFromClosed = false; }
                        }
                    }
                }

                Rectangle {
                    id: missionBtn
                    readonly property bool on: appWindow.missionOpen && !appWindow.splitOn
                    width: Math.round(132 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: missionBtn.on ? appWindow.mixc("#162838", "#142030") : (missionMouse.containsMouse ? appWindow.mixc("#202a3a", "#2a2a29") : appWindow.mixc("#141c28", "#1b1b1a")) }
                        GradientStop { position: 1.0; color: missionBtn.on ? appWindow.mixc("#0c1824", "#0e1620") : (missionMouse.containsMouse ? appWindow.mixc("#141c28", "#1b1b1a") : appWindow.mixc("#0d131c", "#121211")) }
                    }
                    border.color: missionBtn.on ? appWindow.accentCyan : (missionMouse.containsMouse ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
                    border.width: missionBtn.on ? 1.5 : 1.0

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "🗺"
                            font.pixelSize: Math.round(12 * scaleFactor)
                        }
                        Text {
                            text: "MISSION PLAN"
                            color: missionBtn.on ? appWindow.accentCyan : (missionMouse.containsMouse ? "#ffffff" : Qt.rgba(0.82, 0.88, 0.96, 0.85))
                            font.pixelSize: Math.round(11 * scaleFactor)
                            font.bold: true
                            font.letterSpacing: 1
                            font.family: "Segoe UI, Inter, sans-serif"
                        }
                    }

                    MouseArea {
                        id: missionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            appWindow.toggleMission();
                        }
                    }
                }

                Rectangle {                                    // SPLIT VIEW: the primary view (3D sim or video) in the left 1/3 next to the map
                    id: splitBtn
                    readonly property bool on: appWindow.missionOpen && appWindow.splitOn
                    width: Math.round(120 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: splitBtn.on ? appWindow.mixc("#162838", "#142030") : (splitMouse.containsMouse ? appWindow.mixc("#202a3a", "#2a2a29") : appWindow.mixc("#141c28", "#1b1b1a")) }
                        GradientStop { position: 1.0; color: splitBtn.on ? appWindow.mixc("#0c1824", "#0e1620") : (splitMouse.containsMouse ? appWindow.mixc("#141c28", "#1b1b1a") : appWindow.mixc("#0d131c", "#121211")) }
                    }
                    border.color: splitBtn.on ? appWindow.accentCyan : (splitMouse.containsMouse ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
                    border.width: splitBtn.on ? 1.5 : 1.0

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 7
                        Item {                                 // little 1/3 | 2/3 icon, drawn (no font needed)
                            width: Math.round(18 * scaleFactor)
                            height: Math.round(13 * scaleFactor)
                            Layout.alignment: Qt.AlignVCenter
                            readonly property color ic: splitBtn.on ? appWindow.accentCyan : (splitMouse.containsMouse ? "#ffffff" : Qt.rgba(0.82, 0.88, 0.96, 0.85))
                            Rectangle { anchors.fill: parent; radius: 2; color: "transparent"; border.color: parent.ic; border.width: 1.4 }
                            Rectangle { x: Math.round(parent.width / 3); y: 0; width: 1.4; height: parent.height; color: parent.ic }
                            Rectangle { x: 1.4; y: 1.4; width: Math.round(parent.width / 3) - 1.4; height: parent.height - 2.8; color: parent.ic; opacity: 0.55 }
                        }
                        Text {
                            text: "SPLIT VIEW"
                            color: splitBtn.on ? appWindow.accentCyan : (splitMouse.containsMouse ? "#ffffff" : Qt.rgba(0.82, 0.88, 0.96, 0.85))
                            font.pixelSize: Math.round(11 * scaleFactor)
                            font.bold: true
                            font.letterSpacing: 1
                            font.family: "Segoe UI, Inter, sans-serif"
                        }
                    }

                    MouseArea {
                        id: splitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appWindow.toggleSplit()
                    }
                }

                Rectangle {
                    width: Math.round(136 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? appWindow.mixc("#142838", "#142030") : (autoMouse.containsMouse ? appWindow.mixc("#202a3a", "#2a2a29") : appWindow.mixc("#141c28", "#1b1b1a")) }
                        GradientStop { position: 1.0; color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? appWindow.mixc("#0a1824", "#0e1620") : (autoMouse.containsMouse ? appWindow.mixc("#141c28", "#1b1b1a") : appWindow.mixc("#0d131c", "#121211")) }
                    }
                    border.color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? appWindow.accentCyan : (autoMouse.containsMouse ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
                    border.width: 1.5

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "⚓"
                            color: appWindow.accentCyan
                            font.pixelSize: Math.round(12 * scaleFactor)
                        }
                        Text {
                            text: (typeof vesselState !== "undefined" && vesselState && vesselState.mode !== "AUTO") ? "Manual Teleop" : "Autonomous"
                            color: (typeof vesselState !== "undefined" && vesselState && vesselState.mode !== "AUTO") ? "#f59e0b" : appWindow.accentCyan
                            font.pixelSize: Math.round(12 * scaleFactor)
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: autoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof telemetry !== "undefined" && telemetry && vesselState) {
                                var nextMode = (vesselState.mode === "AUTO") ? "TELEOP" : "AUTO";
                                telemetry.sendMode(nextMode);
                            }
                        }
                    }
                }

                Rectangle {
                    width: Math.round(34 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: hudMouse.containsMouse || hudVisible ? appWindow.mixc("#222c3c", "#2b2b2a") : appWindow.mixc("#141c28", "#1b1b1a") }
                        GradientStop { position: 1.0; color: hudMouse.containsMouse || hudVisible ? appWindow.mixc("#16202e", "#1c1c1b") : appWindow.mixc("#0d131c", "#121211") }
                    }
                    border.color: hudVisible ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.40) : (hudMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "⌖"
                        color: hudVisible ? appWindow.accentCyan : (hudMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.50))
                        font.pixelSize: Math.round(16 * scaleFactor)
                    }

                    MouseArea {
                        id: hudMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            hudVisible = !hudVisible;
                        }
                    }
                }

                Rectangle {
                    width: Math.round(34 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: sensorMouse.containsMouse || sensorActive ? appWindow.mixc("#222c3c", "#2b2b2a") : appWindow.mixc("#141c28", "#1b1b1a") }
                        GradientStop { position: 1.0; color: sensorMouse.containsMouse || sensorActive ? appWindow.mixc("#16202e", "#1c1c1b") : appWindow.mixc("#0d131c", "#121211") }
                    }
                    border.color: sensorActive ? "#10b981" : (sensorMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "❚❚"
                        color: sensorActive ? "#10b981" : (sensorMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.50))
                        font.pixelSize: Math.round(12 * scaleFactor)
                    }

                    MouseArea {
                        id: sensorMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sensorActive = !sensorActive;
                        }
                    }
                }

                Rectangle {
                    width: Math.round(34 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: gridMouse.containsMouse || layer1_5_pipDashboard.visible ? appWindow.mixc("#222c3c", "#2b2b2a") : appWindow.mixc("#141c28", "#1b1b1a") }
                        GradientStop { position: 1.0; color: gridMouse.containsMouse || layer1_5_pipDashboard.visible ? appWindow.mixc("#16202e", "#1c1c1b") : appWindow.mixc("#0d131c", "#121211") }
                    }
                    border.color: layer1_5_pipDashboard.visible ? Qt.rgba(appWindow.accentCyan.r, appWindow.accentCyan.g, appWindow.accentCyan.b, 0.40) : (gridMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(12 * scaleFactor)
                        height: Math.round(12 * scaleFactor)
                        radius: width / 2
                        color: Qt.rgba(0.08, 0.12, 0.18, 0.9)
                        border.color: Qt.rgba(0.68, 0.78, 0.90, 0.25)
                        border.width: 1
                    }

                    MouseArea {
                        id: gridMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            layer1_5_pipDashboard.visible = !layer1_5_pipDashboard.visible;
                        }
                    }
                }

                Rectangle {
                    width: Math.round(32 * scaleFactor)
                    height: Math.round(32 * scaleFactor)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: eStopMouse.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.50) : "#2a171d" }
                        GradientStop { position: 1.0; color: eStopMouse.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.30) : "#180e12" }
                    }
                    border.color: "#ef4444"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "⊗"
                        color: "#ef4444"
                        font.pixelSize: Math.round(16 * scaleFactor)
                        font.bold: true
                    }

                    MouseArea {
                        id: eStopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof failsafe !== "undefined" && failsafe) {
                                failsafe.triggerManualEmergency();
                            } else if (typeof telemetry !== "undefined" && telemetry) {
                                telemetry.sendEmergencyStop();
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
