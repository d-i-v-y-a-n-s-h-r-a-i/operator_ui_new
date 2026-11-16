import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
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
    color: "#0a0e15"

    readonly property real baseWidth: 1920.0
    readonly property real baseHeight: 1080.0
    readonly property real scaleRatio: Math.min(appWindow.width / baseWidth, appWindow.height / baseHeight)
    readonly property real scaleFactor: Math.min(Math.max(scaleRatio, 0.75), 1.65)

    property bool mapViewOpen: true
    property bool hudVisible: true
    property bool sensorActive: false
    property bool settingsViewOpen: false

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
            if (mapViewOpen) {
                mapViewOpen = false;
            } else {
                Qt.quit();
            }
        }
    }

    Item {
        id: layer0_backgroundVideo
        anchors.fill: parent
        z: 0

        MediaPlayer {
            id: mainMediaPlayer
            videoOutput: backgroundVideoSink
            source: Qt.resolvedUrl("../../main_camera.webm")
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
        anchors.fill: parent
        z: 1
        visible: hudVisible

        Item {
            id: dynamicHorizonPlane
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: vesselState ? (vesselState.pitch * (3.5 * scaleFactor)) : 0
            height: 2
            rotation: vesselState ? -vesselState.roll : 0

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 240, 255, 0.25)
            }

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

        Canvas {
            id: navTrajectoryCorridor
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var cx = width / 2;
                var cy = height * 0.52;
                var btm = height * 0.90;

                var grad = ctx.createLinearGradient(cx, btm, cx, cy);
                grad.addColorStop(0.0, "rgba(0, 240, 255, 0.45)");
                grad.addColorStop(0.35, "rgba(16, 185, 129, 0.35)");
                grad.addColorStop(1.0, "rgba(0, 240, 255, 0.00)");

                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.moveTo(cx - (36 * scaleFactor), btm);
                ctx.lineTo(cx + (36 * scaleFactor), btm);
                ctx.lineTo(cx + 4, cy);
                ctx.lineTo(cx - 4, cy);
                ctx.closePath();
                ctx.fill();

                ctx.strokeStyle = "rgba(0, 240, 255, 0.85)";
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.moveTo(cx - (36 * scaleFactor), btm);
                ctx.lineTo(cx - 4, cy);
                ctx.moveTo(cx + (36 * scaleFactor), btm);
                ctx.lineTo(cx + 4, cy);
                ctx.stroke();
            }
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

    Item {
        id: layer1_5_pipDashboard
        z: 1.5
        width: Math.round(Math.min(appWindow.width * 0.25, Math.max(260.0, 320.0 * scaleFactor)))
        height: Math.round(width * 9 / 16)
        anchors.left: parent.left
        anchors.leftMargin: Math.round(24 * scaleFactor)
        anchors.bottom: layer5_bottomDockBar.top
        anchors.bottomMargin: Math.round(20 * scaleFactor)

        MediaPlayer {
            id: pipMediaPlayer
            videoOutput: pipVideoOutput
            source: Qt.resolvedUrl("../../screen.mp4")
            loops: MediaPlayer.Infinite
            Component.onCompleted: play()
        }

        Rectangle {
            id: pipContainer
            anchors.fill: parent
            radius: 14
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#17202d" }
                GradientStop { position: 1.0; color: "#0e131c" }
            }
            border.color: Qt.rgba(0.68, 0.78, 0.90, 0.20)
            border.width: 1
            clip: true

            VideoOutput {
                id: pipVideoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                visible: false
                layer.enabled: true
            }

            Rectangle {
                id: pipMask
                anchors.fill: parent
                radius: 14
                visible: false
                layer.enabled: true
            }

            OpacityMask {
                anchors.fill: parent
                source: pipVideoOutput
                maskSource: pipMask
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(28 * scaleFactor)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1d2737" }
                    GradientStop { position: 1.0; color: "#131a26" }
                }
                radius: 14
                z: 3

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.round(12 * scaleFactor)
                    color: "#131a26"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(10 * scaleFactor)
                    anchors.rightMargin: Math.round(10 * scaleFactor)

                    RowLayout {
                        spacing: 6
                        Layout.fillWidth: true

                        Rectangle {
                            width: Math.round(6 * scaleFactor)
                            height: Math.round(6 * scaleFactor)
                            radius: width / 2
                            color: "#10b981"
                        }

                        Text {
                            text: "DASHBOARD OPTICAL"
                            color: Qt.rgba(0.85, 0.90, 0.98, 0.85)
                            font.pixelSize: Math.round(10 * scaleFactor)
                            font.bold: true
                            font.family: "Segoe UI, Inter, sans-serif"
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: "•••"
                        color: Qt.rgba(0.68, 0.78, 0.90, 0.40)
                        font.pixelSize: Math.round(10 * scaleFactor)
                    }
                }
            }
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

            Text {
                text: "TANDAV"
                color: "#eef3fb"
                font.pixelSize: Math.round(22 * scaleFactor)
                font.bold: true
                font.weight: Font.Black
                font.letterSpacing: Math.round(4 * scaleFactor)
                font.capitalization: Font.AllUppercase
                font.family: "Saira Stencil One, Rajdhani, Orbitron, Montserrat, Segoe UI, sans-serif"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            anchors.centerIn: parent
            height: Math.round(36 * scaleFactor)
            width: Math.min(Math.round(460 * scaleFactor), parent.width * 0.42)
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#18212e" }
                GradientStop { position: 1.0; color: "#0e141d" }
            }
            border.color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
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
                    color: Qt.rgba(0.0, 240, 255, 0.15)
                    Text {
                        anchors.centerIn: parent
                        text: "⚓"
                        color: "#00f0ff"
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
                    GradientStop { position: 0.0; color: "#18212e" }
                    GradientStop { position: 1.0; color: "#0e141d" }
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
                        color: "#00f0ff"
                        font.pixelSize: Math.round(11 * scaleFactor)
                        font.bold: true
                        font.family: "Segoe UI, Inter, sans-serif"
                    }
                }
            }

            Rectangle {
                id: fullscreenToggleBtn
                width: Math.round(34 * scaleFactor)
                height: Math.round(34 * scaleFactor)
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: fsMouseArea.containsMouse ? "#222c3c" : "#18212e" }
                    GradientStop { position: 1.0; color: fsMouseArea.containsMouse ? "#141c28" : "#0e141d" }
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
                    GradientStop { position: 0.0; color: quitMouseArea.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.50) : "#2a171d" }
                    GradientStop { position: 1.0; color: quitMouseArea.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.30) : "#180e12" }
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

    Component {
        id: weatherCardComp
        TelemetryCard {
            title: "Tampa, FL"
            primaryValue: "6"
            unit: "°F"
            subtitle: "Mostly Cloudy\nRain: 30% | Vis: 10nm"
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "rgba(180, 205, 235, 0.35)";
                    ctx.beginPath();
                    ctx.arc(54, 64, 24, 0, Math.PI * 2);
                    ctx.arc(78, 56, 30, 0, Math.PI * 2);
                    ctx.arc(36, 68, 18, 0, Math.PI * 2);
                    ctx.fill();

                    ctx.fillStyle = "rgba(140, 175, 215, 0.18)";
                    ctx.beginPath();
                    ctx.arc(84, 70, 22, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    Component {
        id: rollCardComp
        TelemetryCard {
            title: "Roll"
            primaryValue: vesselState ? Math.abs(vesselState.roll).toFixed(0) : "0"
            unit: "°"
            valueColor: "#00f0ff"
            subtitle: vesselState ? ("Tilted " + Math.abs(vesselState.roll).toFixed(0) + "° " + (vesselState.roll >= 0 ? "stbd" : "port")) : "Level"

            Item {
                anchors.fill: parent
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = "rgba(0, 240, 255, 0.35)";
                        ctx.lineWidth = 2.5;
                        ctx.beginPath();
                        ctx.arc(64, 64, 48, Math.PI * 0.75, Math.PI * 1.25);
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.arc(64, 64, 48, -Math.PI * 0.25, Math.PI * 0.25);
                        ctx.stroke();

                        ctx.strokeStyle = "rgba(180, 200, 225, 0.25)";
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(10, 64);
                        ctx.lineTo(118, 64);
                        ctx.stroke();
                    }
                }

                Item {
                    anchors.centerIn: parent
                    width: 68
                    height: 44
                    rotation: vesselState ? vesselState.roll : 0

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = "#00f0ff";
                            ctx.beginPath();
                            ctx.moveTo(8, 26);
                            ctx.lineTo(60, 26);
                            ctx.lineTo(52, 40);
                            ctx.lineTo(16, 40);
                            ctx.closePath();
                            ctx.fill();

                            ctx.fillStyle = "rgba(220, 235, 255, 0.85)";
                            ctx.beginPath();
                            ctx.moveTo(20, 14);
                            ctx.lineTo(48, 14);
                            ctx.lineTo(52, 26);
                            ctx.lineTo(16, 26);
                            ctx.closePath();
                            ctx.fill();

                            ctx.fillStyle = "rgba(0, 240, 255, 0.50)";
                            ctx.fillRect(30, 40, 8, 4);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pitchCardComp
        TelemetryCard {
            title: "Pitch"
            primaryValue: vesselState ? Math.abs(vesselState.pitch).toFixed(0) : "0"
            unit: "°"
            valueColor: "#00f0ff"
            subtitle: vesselState ? ("Bow " + (vesselState.pitch >= 0 ? "up " : "down ") + Math.abs(vesselState.pitch).toFixed(0) + "°") : "Level"

            Item {
                anchors.fill: parent
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = "rgba(0, 240, 255, 0.35)";
                        ctx.lineWidth = 2.5;
                        ctx.beginPath();
                        ctx.arc(64, 64, 48, -Math.PI * 0.25, Math.PI * 0.25);
                        ctx.stroke();

                        ctx.strokeStyle = "rgba(180, 200, 225, 0.25)";
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(10, 64);
                        ctx.lineTo(118, 64);
                        ctx.stroke();
                    }
                }

                Item {
                    anchors.centerIn: parent
                    width: 74
                    height: 38
                    rotation: vesselState ? -vesselState.pitch : 0

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = "#00f0ff";
                            ctx.beginPath();
                            ctx.moveTo(4, 26);
                            ctx.lineTo(70, 16);
                            ctx.lineTo(65, 30);
                            ctx.lineTo(12, 30);
                            ctx.closePath();
                            ctx.fill();

                            ctx.fillStyle = "rgba(220, 235, 255, 0.85)";
                            ctx.beginPath();
                            ctx.moveTo(18, 16);
                            ctx.lineTo(44, 12);
                            ctx.lineTo(52, 22);
                            ctx.lineTo(16, 26);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }
            }
        }
    }

    Component {
        id: depthCardComp
        TelemetryCard {
            title: "Depth"
            primaryValue: vesselState ? vesselState.depth.toFixed(1) : "8.2"
            unit: "m"
            valueColor: "#10b981"
            subtitle: "Cruising in nominal subsea corridor"

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = "rgba(16, 185, 129, 0.35)";
                    ctx.lineWidth = 2;
                    ctx.beginPath();
                    ctx.moveTo(24, 18);
                    ctx.lineTo(24, 108);
                    ctx.stroke();

                    for (var y = 24; y <= 104; y += 16) {
                        ctx.beginPath();
                        ctx.moveTo(18, y);
                        ctx.lineTo(24, y);
                        ctx.stroke();
                    }

                    var grad = ctx.createLinearGradient(42, 24, 42, 104);
                    grad.addColorStop(0.0, "rgba(16, 185, 129, 0.20)");
                    grad.addColorStop(1.0, "rgba(16, 185, 129, 0.85)");
                    ctx.fillStyle = grad;
                    ctx.fillRect(42, 42, 60, 60);

                    ctx.strokeStyle = "#10b981";
                    ctx.lineWidth = 2;
                    ctx.strokeRect(42, 42, 60, 60);
                }
            }
        }
    }

    Component {
        id: windCardComp
        TelemetryCard {
            title: "Wind"
            primaryValue: "12"
            unit: "km/h"
            subtitle: "Direction: 110° ESE\nGusts: 18 km/h"

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = 64;
                    var cy = 64;
                    var r = 44;

                    ctx.strokeStyle = "rgba(180, 200, 225, 0.25)";
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    ctx.stroke();

                    ctx.fillStyle = "rgba(180, 205, 235, 0.65)";
                    ctx.font = "bold 10px sans-serif";
                    ctx.textAlign = "center";
                    ctx.fillText("N", cx, cy - r + 13);
                    ctx.fillText("S", cx, cy + r - 4);
                    ctx.fillText("E", cx + r - 9, cy + 4);
                    ctx.fillText("W", cx - r + 9, cy + 4);

                    ctx.strokeStyle = "#00f0ff";
                    ctx.lineWidth = 3.5;
                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.lineTo(cx + 28, cy + 20);
                    ctx.stroke();

                    ctx.fillStyle = "#00f0ff";
                    ctx.beginPath();
                    ctx.arc(cx + 28, cy + 20, 4.5, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    Component {
        id: speedCardComp
        TelemetryCard {
            title: "Speed (SOG)"
            primaryValue: vesselState ? vesselState.speed.toFixed(1) : "0.0"
            unit: "kts"
            valueColor: "#f59e0b"
            subtitle: vesselState ? ("HDG: " + Math.round(vesselState.heading) + "° | RPM: " + vesselState.rpm) : "Stationary"

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = 64;
                    var cy = 64;
                    var r = 42;

                    ctx.strokeStyle = "rgba(245, 158, 11, 0.25)";
                    ctx.lineWidth = 7;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 2.25);
                    ctx.stroke();

                    ctx.strokeStyle = "#f59e0b";
                    ctx.lineWidth = 7;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 1.65);
                    ctx.stroke();

                    ctx.fillStyle = "#ffffff";
                    ctx.beginPath();
                    ctx.arc(cx, cy, 4, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    Item {
        id: layer3_telemetryCardsCarousel
        anchors.top: layer2_topHeaderBar.bottom
        anchors.topMargin: Math.round(14 * scaleFactor)
        anchors.horizontalCenter: parent.horizontalCenter
        width: carouselViewport.width
        height: Math.round(cardH + 24 * scaleFactor)
        z: 3

        property real scrollPos: 1.0
        property int currentIndex: 1
        readonly property int maxIndex: 4

        readonly property real containerWidth: Math.round(appWindow.width * 0.74)
        readonly property real cardSpacing: Math.round(14 * scaleFactor)
        readonly property real peekWidth: Math.round(92 * scaleFactor)
        readonly property real peekScale: 0.94
        readonly property real cardW: Math.round((containerWidth - cardSpacing - (2 * peekWidth)) / 2)
        readonly property real cardH: Math.round(Math.min(220, Math.max(185, 205 * scaleFactor)))

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

        function getCardX(k, s) {
            var rel = k - s;
            var cx = containerWidth / 2;
            var f1 = cx - (cardW / 2) - (cardSpacing / 2);
            var f2 = cx + (cardW / 2) + (cardSpacing / 2);
            var rPeek = (cx + cardW + (cardSpacing / 2) + peekWidth) - (cardW * peekScale / 2);
            var lPeek = (cx - cardW - (cardSpacing / 2) - peekWidth) + (cardW * peekScale / 2);

            if (rel <= -1.0) {
                return lPeek + (rel + 1.0) * (cardW * 0.45);
            } else if (rel <= 0.0) {
                var t = rel + 1.0;
                return lPeek + t * (f1 - lPeek);
            } else if (rel <= 1.0) {
                var t = rel;
                return f1 + t * (f2 - f1);
            } else if (rel <= 2.0) {
                var t = rel - 1.0;
                return f2 + t * (rPeek - f2);
            } else {
                return rPeek + (rel - 2.0) * (cardW * 0.45);
            }
        }

        function getCardScale(k, s) {
            var rel = k - s;
            if (rel >= 0.0 && rel <= 1.0) {
                return 1.0;
            } else if (rel < 0.0 && rel >= -1.0) {
                return peekScale + (rel + 1.0) * (1.0 - peekScale);
            } else if (rel > 1.0 && rel <= 2.0) {
                return 1.0 - (rel - 1.0) * (1.0 - peekScale);
            } else {
                return 0.88;
            }
        }

        function getCardOpacity(k, s) {
            var rel = k - s;
            if (rel >= 0.0 && rel <= 1.0) {
                return 1.0;
            } else if (rel < 0.0 && rel >= -1.0) {
                return 0.70 + (rel + 1.0) * 0.30;
            } else if (rel > 1.0 && rel <= 2.0) {
                return 1.0 - (rel - 1.0) * 0.30;
            } else if (rel < -1.0 && rel >= -1.6) {
                return Math.max(0.0, 0.70 * (1.0 - (-rel - 1.0) / 0.6));
            } else if (rel > 2.0 && rel <= 2.6) {
                return Math.max(0.0, 0.70 * (1.0 - (rel - 2.0) / 0.6));
            } else {
                return 0.0;
            }
        }

        function getCardZ(k, s) {
            var rel = k - s;
            if (rel >= -0.2 && rel <= 1.2) {
                return 10;
            } else {
                return 4;
            }
        }

        Item {
            id: carouselViewport
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: layer3_telemetryCardsCarousel.containerWidth
            height: layer3_telemetryCardsCarousel.cardH
            clip: true

            Repeater {
                model: [
                    weatherCardComp,
                    rollCardComp,
                    pitchCardComp,
                    depthCardComp,
                    windCardComp,
                    speedCardComp
                ]

                delegate: Item {
                    id: cardWrapper
                    width: layer3_telemetryCardsCarousel.cardW
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
                    startScrollPos = layer3_telemetryCardsCarousel.scrollPos;
                    posAnim.stop();
                }

                onPositionChanged: (mouse) => {
                    if (dragActive) {
                        var deltaX = mouse.x - startMouseX;
                        var dragStep = layer3_telemetryCardsCarousel.cardW * 0.85;
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
                    layer3_telemetryCardsCarousel.animateTo(layer3_telemetryCardsCarousel.currentIndex);
                }

                onWheel: (wheel) => {
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
                model: layer3_telemetryCardsCarousel.maxIndex + 1
                delegate: Rectangle {
                    width: (index === layer3_telemetryCardsCarousel.currentIndex) ? Math.round(18 * scaleFactor) : Math.round(5 * scaleFactor)
                    height: Math.round(4 * scaleFactor)
                    radius: height / 2
                    color: (index === layer3_telemetryCardsCarousel.currentIndex) ? "#00f0ff" : Qt.rgba(0.68, 0.78, 0.90, 0.30)

                    Behavior on width {
                        NumberAnimation { duration: 200 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
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
        anchors.horizontalCenter: parent.horizontalCenter
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
        anchors.fill: parent
        z: 50
        active: mapViewOpen
        source: mapViewOpen ? "TacticalMapView.qml" : ""
        opacity: mapViewOpen ? 1.0 : 0.0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
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
                GradientStop { position: 0.0; color: "#161d29" }
                GradientStop { position: 1.0; color: "#0d121a" }
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
                        GradientStop { position: 0.0; color: settingsMouse.containsMouse || settingsViewOpen ? "#222c3c" : "#141c28" }
                        GradientStop { position: 1.0; color: settingsMouse.containsMouse || settingsViewOpen ? "#16202e" : "#0d131c" }
                    }
                    border.color: settingsViewOpen ? "#00f0ff" : (settingsMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: settingsViewOpen ? "#00f0ff" : (settingsMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.65))
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
                        GradientStop { position: 0.0; color: helmMouse.containsMouse || (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? "#222c3c" : "#141c28" }
                        GradientStop { position: 1.0; color: helmMouse.containsMouse || (typeof vesselState !== "undefined" && vesselState && vesselState.mode === "TELEOP") ? "#16202e" : "#0d131c" }
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
                        GradientStop { position: 0.0; color: mapViewOpen ? "#162838" : (mapMouse.containsMouse ? "#202a3a" : "#141c28") }
                        GradientStop { position: 1.0; color: mapViewOpen ? "#0c1824" : (mapMouse.containsMouse ? "#141c28" : "#0d131c") }
                    }
                    border.color: mapViewOpen ? "#00f0ff" : (mapMouse.containsMouse ? Qt.rgba(0.0, 240, 255, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
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
                            color: mapViewOpen ? "#00f0ff" : (mapMouse.containsMouse ? "#ffffff" : Qt.rgba(0.82, 0.88, 0.96, 0.85))
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
                        }
                    }
                }

                Rectangle {
                    width: Math.round(136 * scaleFactor)
                    height: Math.round(34 * scaleFactor)
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? "#142838" : (autoMouse.containsMouse ? "#202a3a" : "#141c28") }
                        GradientStop { position: 1.0; color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? "#0a1824" : (autoMouse.containsMouse ? "#141c28" : "#0d131c") }
                    }
                    border.color: (typeof vesselState === "undefined" || !vesselState || vesselState.mode === "AUTO") ? "#00f0ff" : (autoMouse.containsMouse ? Qt.rgba(0.0, 240, 255, 0.50) : Qt.rgba(0.68, 0.78, 0.90, 0.22))
                    border.width: 1.5

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "⚓"
                            color: "#00f0ff"
                            font.pixelSize: Math.round(12 * scaleFactor)
                        }
                        Text {
                            text: (typeof vesselState !== "undefined" && vesselState && vesselState.mode !== "AUTO") ? "Manual Teleop" : "Autonomous"
                            color: (typeof vesselState !== "undefined" && vesselState && vesselState.mode !== "AUTO") ? "#f59e0b" : "#00f0ff"
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
                        GradientStop { position: 0.0; color: hudMouse.containsMouse || hudVisible ? "#222c3c" : "#141c28" }
                        GradientStop { position: 1.0; color: hudMouse.containsMouse || hudVisible ? "#16202e" : "#0d131c" }
                    }
                    border.color: hudVisible ? Qt.rgba(0.0, 240, 255, 0.40) : (hudMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "⌖"
                        color: hudVisible ? "#00f0ff" : (hudMouse.containsMouse ? "#ffffff" : Qt.rgba(0.68, 0.78, 0.90, 0.50))
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
                        GradientStop { position: 0.0; color: sensorMouse.containsMouse || sensorActive ? "#222c3c" : "#141c28" }
                        GradientStop { position: 1.0; color: sensorMouse.containsMouse || sensorActive ? "#16202e" : "#0d131c" }
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
                        GradientStop { position: 0.0; color: gridMouse.containsMouse || layer1_5_pipDashboard.visible ? "#222c3c" : "#141c28" }
                        GradientStop { position: 1.0; color: gridMouse.containsMouse || layer1_5_pipDashboard.visible ? "#16202e" : "#0d131c" }
                    }
                    border.color: layer1_5_pipDashboard.visible ? Qt.rgba(0.0, 240, 255, 0.40) : (gridMouse.containsMouse ? Qt.rgba(0.68, 0.78, 0.90, 0.45) : Qt.rgba(0.68, 0.78, 0.90, 0.18))
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
