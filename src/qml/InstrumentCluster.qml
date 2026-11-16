import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

Item {
    id: root

    implicitWidth: 480
    implicitHeight: 270
    width: Math.round(480 * sf)
    height: Math.round(270 * sf)

    property real scaleFactor: (typeof appWindow !== "undefined" && appWindow) ? appWindow.scaleFactor : 1.0
    readonly property real sf: Math.min(Math.max(scaleFactor, 0.65), 1.45)
    readonly property real u: width / 480.0

    property real currentRPM: (typeof vesselState !== "undefined" && vesselState && vesselState.rpm !== undefined) ? vesselState.rpm : 5400
    property real currentSpeed: (typeof vesselState !== "undefined" && vesselState && vesselState.speed !== undefined) ? vesselState.speed : 13.0
    property bool telemetryStale: (typeof vesselState !== "undefined" && vesselState && vesselState.telemetryStale !== undefined) ? vesselState.telemetryStale : false

    property real animatedRPM: 0
    property real animatedSpeed: 0
    Behavior on animatedRPM { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    Behavior on animatedSpeed { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

    Component.onCompleted: {
        animatedRPM = currentRPM
        animatedSpeed = currentSpeed
        dialCanvas.requestPaint()
        horizonCanvas.requestPaint()
    }
    onCurrentRPMChanged: animatedRPM = currentRPM
    onCurrentSpeedChanged: animatedSpeed = currentSpeed
    onPitchChanged: horizonCanvas.requestPaint()
    onRollChanged: horizonCanvas.requestPaint()

    readonly property string typeface: "Bahnschrift, DIN, Segoe UI, sans-serif"

    readonly property color ink: "#EDF2F6"
    readonly property color sec: "#8C9AA6"
    readonly property color ter: "#5A6670"
    readonly property color accent: "#45E0F2"
    readonly property color alarm: "#FF5566"
    readonly property color hair: Qt.rgba(1, 1, 1, 0.055)

    readonly property var vs: (typeof vesselState !== "undefined" && vesselState) ? vesselState : null
    readonly property real coolant: (vs && vs.coolantTemp !== undefined) ? vs.coolantTemp : 71
    readonly property real fuel: (vs && vs.fuelPercentage !== undefined)
                                   ? vs.fuelPercentage
                                   : ((vs && vs.batteryPercentage !== undefined) ? vs.batteryPercentage : 84)
    readonly property real battery: (vs && vs.batteryVoltage !== undefined) ? vs.batteryVoltage : 24.8
    readonly property real pitch: (vs && vs.pitch !== undefined) ? vs.pitch : 2.5
    readonly property real roll: (vs && vs.roll !== undefined) ? vs.roll : -0.4

    readonly property real dialCX: 240
    readonly property real dialCY: 146
    readonly property real dialR: 106
    readonly property real angleStart: 145
    readonly property real angleSweep: 250
    readonly property real speedMax: 50
    readonly property real redline: 44

    readonly property real frac: Math.max(0, Math.min(1, animatedSpeed / speedMax))
    readonly property real needleAngle: angleStart + frac * angleSweep - 270

    function barColor(v, limit) { return limit ? alarm : ink }

    function paintDial(canvas) {
        var ctx = canvas.getContext("2d")
        var w = canvas.width, h = canvas.height
        if (w <= 0 || h <= 0) return
        var cx = dialCX * u, cy = dialCY * u, R = dialR * u
        var a0 = angleStart * Math.PI / 180
        var a1 = (angleStart + angleSweep) * Math.PI / 180

        ctx.clearRect(0, 0, w, h)

        var bloom = ctx.createRadialGradient(cx, cy + 22 * u, 0, cx, cy + 22 * u, 74 * u)
        bloom.addColorStop(0, "rgba(70,180,200,0.065)")
        bloom.addColorStop(1, "rgba(70,180,200,0.000)")
        ctx.fillStyle = bloom
        ctx.fillRect(0, 0, w, h)

        ctx.beginPath()
        ctx.strokeStyle = "rgba(255,255,255,0.12)"
        ctx.lineWidth = Math.max(1, 1 * u)
        ctx.arc(cx, cy, R, 0, Math.PI * 2)
        ctx.stroke()

        for (var v = 0; v <= speedMax; v += 2) {
            var a = a0 + (a1 - a0) * (v / speedMax)
            var major = (v % 10 === 0)
            var hot = (v >= redline)
            var r1 = (major ? 88 : 96) * u
            var r2 = 101 * u
            ctx.beginPath()
            ctx.strokeStyle = hot ? "rgba(255,85,102,0.90)"
                                  : (major ? "rgba(237,242,246,0.62)" : "rgba(237,242,246,0.14)")
            ctx.lineWidth = Math.max(1, (major ? 1.7 : 1.0) * u)
            ctx.moveTo(cx + r1 * Math.cos(a), cy + r1 * Math.sin(a))
            ctx.lineTo(cx + r2 * Math.cos(a), cy + r2 * Math.sin(a))
            ctx.stroke()
        }
    }

    function paintHorizon(canvas) {
        var ctx = canvas.getContext("2d")
        var w = canvas.width
        if (w <= 0) return
        var c = w / 2, r = c - 2 * u
        var pxDeg = 1.15 * u

        ctx.clearRect(0, 0, w, w)
        ctx.save()
        ctx.beginPath()
        ctx.arc(c, c, r, 0, Math.PI * 2)
        ctx.clip()

        ctx.translate(c, c)
        ctx.rotate(-roll * Math.PI / 180)
        ctx.translate(0, pitch * pxDeg)

        var ext = r * 2
        ctx.fillStyle = "rgba(18, 26, 34, 0.60)"
        ctx.fillRect(-ext, -ext, ext * 2, ext)
        ctx.fillStyle = "rgba(8, 11, 16, 0.70)"
        ctx.fillRect(-ext, 0, ext * 2, ext)

        ctx.strokeStyle = "rgba(237,242,246,0.42)"
        ctx.lineWidth = Math.max(1, 0.9 * u)
        ctx.beginPath()
        ctx.moveTo(-ext, 0)
        ctx.lineTo(ext, 0)
        ctx.stroke()

        for (var d = -20; d <= 20; d += 10) {
            if (d === 0) continue
            var y = -d * pxDeg
            var half = (Math.abs(d) === 10 ? 10 : 6) * u
            ctx.strokeStyle = "rgba(237,242,246,0.16)"
            ctx.beginPath()
            ctx.moveTo(-half, y)
            ctx.lineTo(half, y)
            ctx.stroke()
        }
        ctx.restore()

        ctx.beginPath()
        ctx.strokeStyle = "rgba(255,255,255,0.15)"
        ctx.lineWidth = Math.max(1, 1 * u)
        ctx.arc(c, c, r, 0, Math.PI * 2)
        ctx.stroke()

        ctx.strokeStyle = accent
        ctx.lineWidth = Math.max(1, 1.2 * u)
        ctx.beginPath()
        ctx.moveTo(c - 13 * u, c)
        ctx.lineTo(c - 3.5 * u, c)
        ctx.moveTo(c + 3.5 * u, c)
        ctx.lineTo(c + 13 * u, c)
        ctx.stroke()
        ctx.beginPath()
        ctx.fillStyle = accent
        ctx.arc(c, c, 1.1 * u, 0, Math.PI * 2)
        ctx.fill()
    }

    RectangularGlow {
        anchors.fill: shell
        anchors.margins: -Math.round(4 * u)
        glowRadius: Math.round(16 * u)
        spread: 0.0
        color: Qt.rgba(0.0, 0.0, 0.0, 0.65)
        cornerRadius: shell.radius + glowRadius
        z: 0
    }

    Rectangle {
        id: shell
        anchors.fill: parent
        radius: Math.round(12 * u)
        clip: true
        border.width: 1
        border.color: Qt.rgba(1.0, 1.0, 1.0, 0.14)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.05, 0.08, 0.12, 0.52) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.04, 0.07, 0.62) }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1.0, 1.0, 1.0, 0.22)
            radius: parent.radius
            z: 10
        }

        Canvas {
            id: dialCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onPaint: root.paintDial(dialCanvas)
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        Repeater {
            model: 6
            delegate: Text {
                readonly property real ang: (root.angleStart + (index / 5) * root.angleSweep) * Math.PI / 180
                x: root.dialCX * root.u + 74 * root.u * Math.cos(ang) - width / 2
                y: root.dialCY * root.u + 74 * root.u * Math.sin(ang) - height / 2
                text: index * 10
                color: "#97A5B1"
                font.family: root.typeface
                font.pixelSize: Math.round(9 * root.u)
                font.letterSpacing: Math.round(0.4 * root.u)
            }
        }

        Item {
            id: needle
            width: Math.round(10 * u)
            height: Math.round(96 * u)
            x: Math.round(root.dialCX * u - width / 2)
            y: Math.round(root.dialCY * u - 90 * u)
            opacity: root.telemetryStale ? 0.28 : 1.0

            transform: Rotation {
                origin.x: needle.width / 2
                origin.y: 90 * root.u
                angle: root.needleAngle
            }

            Shape {
                anchors.fill: parent
                ShapePath {
                    fillColor: root.ink
                    strokeColor: "transparent"
                    startX: needle.width / 2
                    startY: 0
                    PathLine { x: needle.width / 2 + 1.3 * root.u; y: 18 * root.u }
                    PathLine { x: needle.width / 2 + 1.3 * root.u; y: 88 * root.u }
                    PathLine { x: needle.width / 2; y: 94 * root.u }
                    PathLine { x: needle.width / 2 - 1.3 * root.u; y: 88 * root.u }
                    PathLine { x: needle.width / 2 - 1.3 * root.u; y: 18 * root.u }
                    PathLine { x: needle.width / 2; y: 0 }
                }
            }
        }

        Rectangle {
            width: Math.round(16 * u); height: width; radius: width / 2
            x: Math.round(root.dialCX * u - width / 2)
            y: Math.round(root.dialCY * u - height / 2)
            color: Qt.rgba(0.04, 0.06, 0.09, 0.85)
            border.width: 1
            border.color: Qt.rgba(237, 242, 246, 0.30)

            Rectangle {
                width: Math.round(3 * u); height: width; radius: width / 2
                anchors.centerIn: parent
                color: root.accent
            }
        }

        Text {
            width: Math.round(160 * u)
            x: Math.round(root.dialCX * u - width / 2)
            y: Math.round(156 * u)
            horizontalAlignment: Text.AlignHCenter
            text: root.animatedSpeed.toFixed(1)
            color: root.ink
            opacity: root.telemetryStale ? 0.32 : 1.0
            font.family: root.typeface
            font.pixelSize: Math.round(50 * u)
            font.weight: Font.DemiBold
            font.letterSpacing: Math.round(-2.4 * u)
        }

        Text {
            width: Math.round(160 * u)
            x: Math.round(root.dialCX * u - width / 2)
            y: Math.round(210 * u)
            horizontalAlignment: Text.AlignHCenter
            text: "KTS"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(7 * u)
            font.bold: true
            font.letterSpacing: Math.round(2.6 * u)
        }

        Text {
            width: Math.round(160 * u)
            x: Math.round(root.dialCX * u - width / 2)
            y: Math.round(224 * u)
            horizontalAlignment: Text.AlignHCenter
            text: "AUTO-NAV"
            color: root.telemetryStale ? root.alarm : root.accent
            opacity: 0.85
            font.family: root.typeface
            font.pixelSize: Math.round(6 * u)
            font.bold: true
            font.letterSpacing: Math.round(2.4 * u)
        }

        Text {
            x: Math.round(14 * u); y: Math.round(26 * u)
            text: "STATUS"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5.2 * u)
            font.bold: true
            font.letterSpacing: Math.round(2.2 * u)
        }
        Text {
            x: Math.round(14 * u); y: Math.round(37 * u)
            text: root.telemetryStale ? "LINK LOST" : "NOMINAL"
            color: root.telemetryStale ? root.alarm : root.ink
            font.family: root.typeface
            font.pixelSize: Math.round(9.5 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.6 * u)
        }
        Rectangle {
            x: Math.round(14 * u); y: Math.round(55 * u)
            width: Math.round(112 * u); height: 1
            color: root.hair
        }

        Canvas {
            id: horizonCanvas
            x: Math.round(30 * u); y: Math.round(68 * u)
            width: Math.round(80 * u); height: Math.round(80 * u)
            renderStrategy: Canvas.Cooperative
            onPaint: root.paintHorizon(horizonCanvas)
            onWidthChanged: requestPaint()
        }

        Item {
            x: Math.round(14 * u); y: Math.round(158 * u)
            width: Math.round(112 * u); height: Math.round(14 * u)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "PITCH"
                color: root.ter
                font.family: root.typeface
                font.pixelSize: Math.round(5.2 * u)
                font.bold: true
                font.letterSpacing: Math.round(1.8 * u)
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (root.pitch >= 0 ? "+" : "") + root.pitch.toFixed(1) + "\u00B0"
                color: root.ink
                font.family: root.typeface
                font.pixelSize: Math.round(9 * u)
                font.bold: true
            }
        }
        Item {
            x: Math.round(14 * u); y: Math.round(176 * u)
            width: Math.round(112 * u); height: Math.round(14 * u)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ROLL"
                color: root.ter
                font.family: root.typeface
                font.pixelSize: Math.round(5.2 * u)
                font.bold: true
                font.letterSpacing: Math.round(1.8 * u)
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (root.roll >= 0 ? "+" : "") + root.roll.toFixed(1) + "\u00B0"
                color: root.ink
                font.family: root.typeface
                font.pixelSize: Math.round(9 * u)
                font.bold: true
            }
        }
        Rectangle {
            x: Math.round(14 * u); y: Math.round(198 * u)
            width: Math.round(112 * u); height: 1
            color: root.hair
        }

        Text {
            x: Math.round(354 * u); y: Math.round(18 * u)
            width: Math.round(112 * u)
            horizontalAlignment: Text.AlignRight
            text: "C14"
            color: root.ink
            font.family: root.typeface
            font.pixelSize: Math.round(17 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.4 * u)
        }

        Item {
            x: Math.round(354 * u); y: Math.round(44 * u)
            width: Math.round(112 * u); height: Math.round(58 * u)

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(1, 1, 1, 0.07)
                    strokeWidth: Math.round(2.6 * root.u)
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 33 * root.u; centerY: 29 * root.u
                        radiusX: 21 * root.u; radiusY: 21 * root.u
                        startAngle: 135; sweepAngle: 270
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.coolant > 95 ? root.alarm : root.ink
                    strokeWidth: Math.round(2.6 * root.u)
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 33 * root.u; centerY: 29 * root.u
                        radiusX: 21 * root.u; radiusY: 21 * root.u
                        startAngle: 135
                        sweepAngle: 1 + 269 * Math.min(1, Math.max(0, root.coolant / 120))
                    }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(1, 1, 1, 0.07)
                    strokeWidth: Math.round(2.6 * root.u)
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 79 * root.u; centerY: 29 * root.u
                        radiusX: 21 * root.u; radiusY: 21 * root.u
                        startAngle: 135; sweepAngle: 270
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.battery < 23 ? root.alarm : root.accent
                    strokeWidth: Math.round(2.6 * root.u)
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 79 * root.u; centerY: 29 * root.u
                        radiusX: 21 * root.u; radiusY: 21 * root.u
                        startAngle: 135
                        sweepAngle: 1 + 269 * Math.min(1, Math.max(0, (root.battery - 20) / 10))
                    }
                }
            }

            Text {
                x: Math.round(33 * root.u - width / 2)
                y: Math.round(29 * root.u - height / 2)
                text: Math.round(root.coolant) + "\u00B0"
                color: root.ink
                font.family: root.typeface
                font.pixelSize: Math.round(8 * root.u)
                font.bold: true
            }
            Text {
                x: Math.round(79 * root.u - width / 2)
                y: Math.round(29 * root.u - height / 2)
                text: root.battery.toFixed(1)
                color: root.ink
                font.family: root.typeface
                font.pixelSize: Math.round(8 * root.u)
                font.bold: true
            }
        }

        Text {
            x: Math.round(365 * u); y: Math.round(104 * u)
            width: Math.round(44 * u)
            horizontalAlignment: Text.AlignHCenter
            text: "COOL"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.6 * u)
        }
        Text {
            x: Math.round(411 * u); y: Math.round(104 * u)
            width: Math.round(44 * u)
            horizontalAlignment: Text.AlignHCenter
            text: "BATT"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.6 * u)
        }

        Rectangle {
            x: Math.round(354 * u); y: Math.round(120 * u)
            width: Math.round(112 * u); height: 1
            color: root.hair
        }

        Text {
            x: Math.round(354 * u); y: Math.round(126 * u)
            text: "FUEL"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.6 * u)
        }
        Text {
            x: Math.round(354 * u); y: Math.round(122 * u)
            width: Math.round(112 * u)
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.fuel) + "%"
            color: root.fuel < 15 ? root.alarm : root.ink
            font.family: root.typeface
            font.pixelSize: Math.round(8 * u)
            font.bold: true
        }
        Rectangle {
            x: Math.round(354 * u); y: Math.round(139 * u)
            width: Math.round(112 * u); height: Math.round(2 * u)
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, root.fuel / 100))
                height: parent.height
                color: root.fuel < 15 ? root.alarm : root.ink
            }
        }

        Text {
            x: Math.round(354 * u); y: Math.round(150 * u)
            text: "RPM"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.6 * u)
        }
        Text {
            x: Math.round(354 * u); y: Math.round(146 * u)
            width: Math.round(112 * u)
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.animatedRPM).toString()
            color: root.animatedRPM >= 7000 ? root.alarm
                 : (root.animatedRPM >= 6000 ? "#F5A524" : root.ink)
            font.family: root.typeface
            font.pixelSize: Math.round(8 * u)
            font.bold: true
        }
        Rectangle {
            x: Math.round(354 * u); y: Math.round(163 * u)
            width: Math.round(112 * u); height: Math.round(2 * u)
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, root.animatedRPM / 8000))
                height: parent.height
                color: root.animatedRPM >= 7000 ? root.alarm
                     : (root.animatedRPM >= 6000 ? "#F5A524" : root.ink)
            }
        }

        Rectangle {
            x: Math.round(354 * u); y: Math.round(178 * u)
            width: Math.round(112 * u); height: 1
            color: root.hair
        }

        Repeater {
            model: [
                { k: "OPTICAL", v: root.telemetryStale ? "LOST" : "OK",
                  c: root.telemetryStale ? root.alarm : root.accent },
                { k: "GPS", v: "3D", c: root.ink },
                { k: "SEQ", v: "4092", c: root.sec }
            ]
            delegate: Item {
                x: Math.round(354 * root.u)
                y: Math.round((186 + index * 13) * root.u)
                width: Math.round(112 * root.u)
                height: Math.round(11 * root.u)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.k
                    color: root.ter
                    font.family: root.typeface
                    font.pixelSize: Math.round(5 * root.u)
                    font.bold: true
                    font.letterSpacing: Math.round(1.6 * root.u)
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.v
                    color: modelData.c
                    font.family: root.typeface
                    font.pixelSize: Math.round(7.5 * root.u)
                    font.bold: true
                }
            }
        }

        Text {
            x: Math.round(14 * u); y: Math.round(232 * u)
            text: "TANDAV C14"
            color: root.ter
            font.family: root.typeface
            font.pixelSize: Math.round(5 * u)
            font.bold: true
            font.letterSpacing: Math.round(2.2 * u)
        }

        Text {
            x: Math.round(354 * u); y: Math.round(232 * u)
            width: Math.round(112 * u)
            horizontalAlignment: Text.AlignRight
            text: "11:28"
            color: root.sec
            font.family: root.typeface
            font.pixelSize: Math.round(10 * u)
            font.bold: true
            font.letterSpacing: Math.round(1.2 * u)
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }
    }
}
