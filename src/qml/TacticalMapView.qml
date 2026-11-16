import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers
import Qt5Compat.GraphicalEffects

Item {
    id: mapRoot
    anchors.fill: parent

    readonly property real sf: Math.min(Math.max(Math.min(width / 1920.0, height / 1080.0), 0.75), 1.65)

    property real scrollPos: 1.0
    property int currentIndex: 1
    readonly property int maxIndex: 4
    readonly property real cardW: Math.round(width * 0.185)
    readonly property real cardH: Math.round(height * 0.195)
    readonly property real cardSpacing: Math.round(14 * sf)
    readonly property real peekScale: 0.84

    NumberAnimation {
        id: carouselAnim
        target: mapRoot
        property: "scrollPos"
        duration: 300
        easing.type: Easing.OutCubic
    }

    function animateTo(t) {
        carouselAnim.stop();
        carouselAnim.to = t;
        carouselAnim.start();
    }

    function getCardX(k, s) {
        var cw = mapRoot.cardW;
        var cs = mapRoot.cardSpacing;
        var center = width / 2.0;
        var offset = (k - s) * (cw + cs);
        return center + offset;
    }

    function getCardScale(k, s) {
        var rel = Math.abs(k - s);
        if (rel <= 0.4) return 1.0;
        if (rel <= 1.4) return 1.0 - (rel - 0.4) * (1.0 - peekScale);
        return peekScale * 0.90;
    }

    function getCardOpacity(k, s) {
        var rel = Math.abs(k - s);
        if (rel <= 0.4) return 1.0;
        if (rel <= 1.4) return 1.0 - (rel - 0.4) * 0.35;
        return 0.65;
    }

    function getCardZ(k, s) {
        var rel = Math.abs(k - s);
        return rel <= 0.5 ? 12 : (rel <= 1.5 ? 8 : 4);
    }

    View3D {
        id: tacticalScene3D
        anchors.fill: parent
        camera: mapCamera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.SkyBox
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            lightProbe: Texture {
                textureData: ProceduralSkyTextureData {
                    skyTopColor: "#020305"
                    skyHorizonColor: "#1A2235"
                    groundHorizonColor: "#1A2235"
                    groundBottomColor: "#020305"
                    skyEnergy: 1.5
                    groundEnergy: 1.0
                    sunLatitude: -8
                    sunEnergy: 2.0
                }
            }
            fog: Fog {
                color: "#1A2235"
                depthEnabled: true
                depthNear: 800
                depthFar: 4000
            }
        }

        PerspectiveCamera {
            id: mapCamera
            position: Qt.vector3d(0, 22, 55)
            eulerRotation.x: -18
            clipNear: 1
            clipFar: 5000
        }

        DirectionalLight {
            id: mainSunLight
            eulerRotation.x: -25
            eulerRotation.y: 45
            color: "#FFFFFF"
            ambientColor: "#0A0C14"
            brightness: 1.5
            castsShadow: true
            shadowMapQuality: Light.ShadowMapQualityHigh
            shadowFilter: 2.0
            shadowBias: 0.005
        }

        Model {
            id: waterPlane
            source: "#Rectangle"
            scale: Qt.vector3d(8000, 8000, 1)
            eulerRotation.x: -90
            y: 0
            receivesShadows: true
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.FragmentLighting
                baseColor: "#080E1A"
                metalness: 0.65
                roughness: 0.15
                specularAmount: 1.0
                clearcoatAmount: 1.0
                clearcoatRoughnessAmount: 0.02
                cullMode: Material.NoCulling
            }
        }

        Model {
            id: navPathModel
            source: "#Rectangle"
            y: 0.05
            z: -140
            scale: Qt.vector3d(0.08, 2.8, 1.0)
            eulerRotation.x: 90
            materials: PrincipledMaterial {
                lighting: PrincipledMaterial.NoLighting
                baseColor: "#FFFFFF"
                baseColorMap: Texture {
                    source: "assets/nav_path_gradient.png"
                }
                alphaMode: PrincipledMaterial.Blend
                cullMode: Material.NoCulling
            }
        }

        Node {
            id: ownVesselNode
            position: Qt.vector3d(0, 0.2, 12)
            scale: Qt.vector3d(2.4, 2.4, 2.4)
            eulerRotation.x: (typeof vesselState !== "undefined" && vesselState) ? vesselState.pitch : 0
            eulerRotation.y: (typeof vesselState !== "undefined" && vesselState) ? ((vesselState.heading - (vesselState.targetHeading || vesselState.heading)) * 0.5) : 0
            eulerRotation.z: (typeof vesselState !== "undefined" && vesselState) ? vesselState.roll : 0

            Model {
                source: "assets/meshes/neuboatYacht_mesh.mesh"
                castsShadows: true
                receivesShadows: false
                materials: [
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#8E92A4"
                        roughness: 0.85
                        metalness: 0.0
                        cullMode: Material.NoCulling
                    },
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#101622"
                        roughness: 0.25
                        metalness: 0.0
                        cullMode: Material.NoCulling
                    },
                    PrincipledMaterial {
                        lighting: PrincipledMaterial.FragmentLighting
                        baseColor: "#323B4C"
                        roughness: 0.85
                        metalness: 0.0
                        cullMode: Material.NoCulling
                    }
                ]
            }
        }

        Node {
            id: threatContactsGroup

            Node {
                id: threatNode1
                position: Qt.vector3d(-26, 0.2, -20)
                eulerRotation.y: 40
                scale: Qt.vector3d(1.85, 1.85, 1.85)
                Model {
                    source: "assets/meshes/neuboatYacht_mesh.mesh"
                    castsShadows: true
                    receivesShadows: false
                    materials: [
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#8E92A4"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#101622"
                            roughness: 0.25
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#323B4C"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        }
                    ]
                }
            }

            Node {
                id: threatNode2
                position: Qt.vector3d(36, 0.2, -35)
                eulerRotation.y: -75
                scale: Qt.vector3d(1.9, 1.9, 1.9)
                Model {
                    source: "assets/meshes/neuboatYacht_mesh.mesh"
                    castsShadows: true
                    receivesShadows: false
                    materials: [
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#8E92A4"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#101622"
                            roughness: 0.25
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#323B4C"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        }
                    ]
                }
            }

            Node {
                id: threatNode3
                position: Qt.vector3d(-38, 0.2, -70)
                eulerRotation.y: 25
                scale: Qt.vector3d(1.4, 1.4, 1.4)
                Model {
                    source: "assets/meshes/neuboatYacht_mesh.mesh"
                    castsShadows: true
                    receivesShadows: false
                    materials: [
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#8E92A4"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#101622"
                            roughness: 0.25
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#323B4C"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        }
                    ]
                }
            }

            Node {
                id: threatNode4
                position: Qt.vector3d(26, 0.2, -65)
                eulerRotation.y: -20
                scale: Qt.vector3d(1.3, 1.3, 1.3)
                Model {
                    source: "assets/meshes/neuboatYacht_mesh.mesh"
                    castsShadows: true
                    receivesShadows: false
                    materials: [
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#8E92A4"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#101622"
                            roughness: 0.25
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#323B4C"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        }
                    ]
                }
            }

            Node {
                id: threatNode5
                position: Qt.vector3d(-8, 0.2, -100)
                eulerRotation.y: 10
                scale: Qt.vector3d(1.0, 1.0, 1.0)
                Model {
                    source: "assets/meshes/neuboatYacht_mesh.mesh"
                    castsShadows: true
                    receivesShadows: false
                    materials: [
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#8E92A4"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#101622"
                            roughness: 0.25
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        },
                        PrincipledMaterial {
                            lighting: PrincipledMaterial.FragmentLighting
                            baseColor: "#323B4C"
                            roughness: 0.85
                            metalness: 0.0
                            cullMode: Material.NoCulling
                        }
                    ]
                }
            }
        }
    }

    Item {
        id: threat1Badge
        property var screenPos: tacticalScene3D.mapFrom3DScene(threatNode1.scenePosition)
        x: screenPos ? Math.round(screenPos.x - width / 2) : -1000
        y: screenPos ? Math.round(screenPos.y - height - 16 * sf) : -1000
        visible: screenPos && screenPos.z > 0 && y > (carouselLayer.y + carouselLayer.height)
        z: 8
        width: threat1Content.implicitWidth + Math.round(16 * sf)
        height: Math.round(26 * sf)

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(0.06, 0.08, 0.12, 0.88)
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.12)
            border.width: 1
        }

        RowLayout {
            id: threat1Content
            anchors.centerIn: parent
            spacing: Math.round(6 * sf)

            Text {
                text: "03 kt"
                color: "#00E5FF"
                font.pixelSize: Math.round(11 * sf)
                font.bold: true
                font.family: "Segoe UI, Inter, sans-serif"
            }

            Text {
                text: "20 kt"
                color: Qt.rgba(0.75, 0.82, 0.95, 0.70)
                font.pixelSize: Math.round(11 * sf)
                font.bold: true
                font.family: "Segoe UI, Inter, sans-serif"
            }

            Rectangle {
                width: Math.round(8 * sf)
                height: Math.round(8 * sf)
                radius: 2
                color: "#ef4444"
            }
        }
    }

    Item {
        id: threat2Badge
        property var screenPos: tacticalScene3D.mapFrom3DScene(threatNode2.scenePosition)
        x: screenPos ? Math.round(screenPos.x - width / 2) : -1000
        y: screenPos ? Math.round(screenPos.y - height - 16 * sf) : -1000
        visible: screenPos && screenPos.z > 0 && y > (carouselLayer.y + carouselLayer.height)
        z: 8
        width: Math.round(24 * sf)
        height: Math.round(24 * sf)

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(0.06, 0.08, 0.12, 0.88)
            border.color: Qt.rgba(0.10, 0.85, 0.50, 0.45)
            border.width: 1

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(8 * sf)
                height: Math.round(8 * sf)
                radius: 2
                color: "#10b981"
            }
        }
    }

    Item {
        id: carouselLayer
        anchors.top: parent.top
        anchors.topMargin: Math.round(72 * sf)
        anchors.left: parent.left
        anchors.right: parent.right
        height: mapRoot.cardH + Math.round(26 * sf)
        z: 10
        clip: false

        Item {
            id: carouselViewport
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: mapRoot.cardH
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
                    id: mapCardWrapper
                    width: mapRoot.cardW
                    height: mapRoot.cardH
                    x: mapRoot.getCardX(index, mapRoot.scrollPos) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    z: mapRoot.getCardZ(index, mapRoot.scrollPos)
                    scale: mapRoot.getCardScale(index, mapRoot.scrollPos)
                    opacity: mapRoot.getCardOpacity(index, mapRoot.scrollPos)
                    visible: opacity > 0.01
                    transformOrigin: Item.Bottom

                    ShaderEffectSource {
                        id: cardBlurSource
                        sourceItem: tacticalScene3D
                        sourceRect: Qt.rect(mapCardWrapper.x, carouselLayer.y + mapCardWrapper.y, mapCardWrapper.width, mapCardWrapper.height)
                        live: true
                        visible: false
                    }

                    FastBlur {
                        anchors.fill: parent
                        source: cardBlurSource
                        radius: 28
                        transparentBorder: false
                        z: 0
                    }

                    Loader {
                        anchors.fill: parent
                        sourceComponent: modelData
                        z: 1
                        onLoaded: {
                            if (item && typeof item.isActive !== "undefined") {
                                item.isActive = Qt.binding(function() { return index === mapRoot.currentIndex; });
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                property bool dragActive: false
                property real startMouseX: 0
                property real startScrollPos: 0

                onPressed: (mouse) => {
                    dragActive = true;
                    startMouseX = mouse.x;
                    startScrollPos = mapRoot.scrollPos;
                    carouselAnim.stop();
                }

                onPositionChanged: (mouse) => {
                    if (dragActive) {
                        var dx = mouse.x - startMouseX;
                        var step = mapRoot.cardW * 0.78;
                        var raw = startScrollPos - dx / step;
                        if (raw < 0) raw = raw * 0.28;
                        else if (raw > mapRoot.maxIndex) raw = mapRoot.maxIndex + (raw - mapRoot.maxIndex) * 0.28;
                        mapRoot.scrollPos = raw;
                    }
                }

                onReleased: (mouse) => {
                    if (dragActive) {
                        dragActive = false;
                        var dx = mouse.x - startMouseX;
                        var thr = Math.round(38 * sf);
                        var target = mapRoot.currentIndex;
                        if (dx < -thr) target = Math.min(mapRoot.maxIndex, mapRoot.currentIndex + 1);
                        else if (dx > thr) target = Math.max(0, mapRoot.currentIndex - 1);
                        mapRoot.currentIndex = target;
                        mapRoot.animateTo(target);
                    }
                }

                onCanceled: {
                    dragActive = false;
                    mapRoot.animateTo(mapRoot.currentIndex);
                }

                onWheel: (wheel) => {
                    if (wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) {
                        mapRoot.currentIndex = Math.min(mapRoot.maxIndex, mapRoot.currentIndex + 1);
                        mapRoot.animateTo(mapRoot.currentIndex);
                    } else {
                        mapRoot.currentIndex = Math.max(0, mapRoot.currentIndex - 1);
                        mapRoot.animateTo(mapRoot.currentIndex);
                    }
                }
            }
        }

        Row {
            anchors.top: carouselViewport.bottom
            anchors.topMargin: Math.round(8 * sf)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(5 * sf)

            Repeater {
                model: mapRoot.maxIndex + 1
                delegate: Rectangle {
                    width: (index === mapRoot.currentIndex) ? Math.round(18 * sf) : Math.round(5 * sf)
                    height: Math.round(4 * sf)
                    radius: height / 2
                    color: (index === mapRoot.currentIndex) ? "#00E5FF" : Qt.rgba(0.68, 0.78, 0.90, 0.28)
                    Behavior on width { NumberAnimation { duration: 180 } }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            mapRoot.currentIndex = index;
                            mapRoot.animateTo(index);
                        }
                    }
                }
            }
        }
    }

    Item {
        id: leftHudBadge
        anchors.left: parent.left
        anchors.leftMargin: Math.round(28 * sf)
        anchors.bottom: speedPillBar.top
        anchors.bottomMargin: Math.round(16 * sf)
        z: 10

        Rectangle {
            height: Math.round(36 * sf)
            radius: Math.round(8 * sf)
            color: Qt.rgba(0.06, 0.08, 0.12, 0.82)
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.07)
            border.width: 1
            implicitWidth: leftBadgeContent.implicitWidth + Math.round(20 * sf)

            RowLayout {
                id: leftBadgeContent
                anchors.centerIn: parent
                spacing: Math.round(8 * sf)

                Text {
                    text: (typeof vesselState !== "undefined" && vesselState) ? vesselState.speed.toFixed(0) + " kt" : "12 kt"
                    color: "#00E5FF"
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }

                Rectangle {
                    width: 1
                    height: Math.round(14 * sf)
                    color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
                }

                Text {
                    text: (typeof vesselState !== "undefined" && vesselState && vesselState.targetSpeed > 0) ? vesselState.targetSpeed.toFixed(0) + " kt" : "14 kt"
                    color: Qt.rgba(0.72, 0.82, 0.95, 0.60)
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                }

                Rectangle {
                    width: Math.round(10 * sf)
                    height: Math.round(10 * sf)
                    radius: 3
                    color: "#ef4444"
                }
            }
        }
    }

    Item {
        id: speedPillBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(76 * sf)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(236 * sf)
        height: Math.round(42 * sf)
        z: 10

        RectangularGlow {
            anchors.fill: speedPillRect
            anchors.margins: -6
            glowRadius: 12
            spread: 0.0
            color: Qt.rgba(0.0, 0.88, 1.0, 0.12)
            cornerRadius: speedPillRect.radius + glowRadius
        }

        Rectangle {
            id: speedPillRect
            anchors.fill: parent
            radius: Math.round(10 * sf)
            color: Qt.rgba(0.07, 0.09, 0.13, 0.90)
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.09)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(16 * sf)
                anchors.rightMargin: Math.round(16 * sf)
                spacing: Math.round(14 * sf)

                Text {
                    text: "^"
                    color: "#00E5FF"
                    font.pixelSize: Math.round(13 * sf)
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
                    text: (typeof vesselState !== "undefined" && vesselState) ? (vesselState.targetSpeed > 0 ? Math.round(vesselState.targetSpeed) : Math.round(vesselState.speed * 2)) : "14"
                    color: "#eef3fb"
                    font.pixelSize: Math.round(18 * sf)
                    font.bold: true
                    font.family: "Segoe UI, Inter, sans-serif"
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: "v"
                    color: "#00E5FF"
                    font.pixelSize: Math.round(13 * sf)
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
                    height: Math.round(18 * sf)
                    color: Qt.rgba(0.68, 0.78, 0.90, 0.22)
                }

                Text {
                    text: "||"
                    color: "#c8d8ec"
                    font.pixelSize: Math.round(13 * sf)
                    font.bold: true
                }

                Text {
                    text: "■"
                    color: "#ef4444"
                    font.pixelSize: Math.round(13 * sf)
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
                    var cloudGrad = ctx.createRadialGradient(70, 58, 4, 70, 58, 32);
                    cloudGrad.addColorStop(0.0, "rgba(195,215,240,0.55)");
                    cloudGrad.addColorStop(1.0, "rgba(130,155,190,0.08)");
                    ctx.fillStyle = cloudGrad;
                    ctx.beginPath();
                    ctx.arc(58, 62, 22, 0, Math.PI * 2);
                    ctx.fill();
                    var cg2 = ctx.createRadialGradient(80, 54, 3, 80, 54, 28);
                    cg2.addColorStop(0.0, "rgba(180,205,235,0.60)");
                    cg2.addColorStop(1.0, "rgba(110,140,180,0.08)");
                    ctx.fillStyle = cg2;
                    ctx.beginPath();
                    ctx.arc(80, 54, 28, 0, Math.PI * 2);
                    ctx.fill();
                    var cg3 = ctx.createRadialGradient(42, 68, 2, 42, 68, 16);
                    cg3.addColorStop(0.0, "rgba(160,190,225,0.45)");
                    cg3.addColorStop(1.0, "rgba(100,130,170,0.05)");
                    ctx.fillStyle = cg3;
                    ctx.beginPath();
                    ctx.arc(42, 68, 16, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }

    Component {
        id: rollCardComp
        TelemetryCard {
            title: "Roll"
            primaryValue: (typeof vesselState !== "undefined" && vesselState) ? Math.abs(vesselState.roll).toFixed(0) : "1"
            unit: "°"
            valueColor: "#00f0ff"
            subtitle: (typeof vesselState !== "undefined" && vesselState) ? ("Tilted " + Math.abs(vesselState.roll).toFixed(0) + "° " + (vesselState.roll >= 0 ? "stbd" : "port")) : "Tilted 1°"

            Item {
                anchors.fill: parent

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var cx = 64; var cy = 64;
                        ctx.strokeStyle = "rgba(0,229,255,0.20)";
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.arc(cx, cy, 48, Math.PI * 0.72, Math.PI * 1.28);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(cx, cy, 48, -Math.PI * 0.28, Math.PI * 0.28);
                        ctx.stroke();
                    }
                }

                View3D {
                    anchors.fill: parent
                    camera: rollCam
                    environment: SceneEnvironment {
                        clearColor: "transparent"
                        backgroundMode: SceneEnvironment.Transparent
                    }
                    PerspectiveCamera {
                        id: rollCam
                        position: Qt.vector3d(0, 3.2, 13)
                        eulerRotation.x: -12
                    }
                    DirectionalLight {
                        eulerRotation.x: -45
                        eulerRotation.y: -35
                        color: "#FFFFFF"
                        brightness: 1.2
                    }
                    Node {
                        eulerRotation.z: (typeof vesselState !== "undefined" && vesselState) ? vesselState.roll : 0
                        scale: Qt.vector3d(0.70, 0.70, 0.70)
                        Model {
                            source: "assets/meshes/neuboatYacht_mesh.mesh"
                            materials: [
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#EAEFF7"
                                    metalness: 0.0
                                    roughness: 0.85
                                    cullMode: Material.NoCulling
                                },
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#101622"
                                    metalness: 0.0
                                    roughness: 0.25
                                    cullMode: Material.NoCulling
                                },
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#323B4C"
                                    metalness: 0.0
                                    roughness: 0.85
                                    cullMode: Material.NoCulling
                                }
                            ]
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
            primaryValue: (typeof vesselState !== "undefined" && vesselState) ? Math.abs(vesselState.pitch).toFixed(0) : "3"
            unit: "°"
            valueColor: "#00f0ff"
            subtitle: (typeof vesselState !== "undefined" && vesselState) ? ("Bow " + (vesselState.pitch >= 0 ? "up " : "down ") + Math.abs(vesselState.pitch).toFixed(0) + "°") : "Bow up 3°"

            Item {
                anchors.fill: parent

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var cx = 64; var cy = 64;
                        ctx.strokeStyle = "rgba(0,229,255,0.22)";
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.arc(cx, cy, 48, -Math.PI * 0.30, Math.PI * 0.30);
                        ctx.stroke();
                    }
                }

                View3D {
                    anchors.fill: parent
                    camera: pitchCam
                    environment: SceneEnvironment {
                        clearColor: "transparent"
                        backgroundMode: SceneEnvironment.Transparent
                    }
                    PerspectiveCamera {
                        id: pitchCam
                        position: Qt.vector3d(14, 2.2, 0)
                        eulerRotation.y: 90
                        eulerRotation.x: -8
                    }
                    DirectionalLight {
                        eulerRotation.x: -45
                        eulerRotation.y: 35
                        color: "#FFFFFF"
                        brightness: 1.2
                    }
                    Node {
                        eulerRotation.x: (typeof vesselState !== "undefined" && vesselState) ? vesselState.pitch : 0
                        scale: Qt.vector3d(0.70, 0.70, 0.70)
                        Model {
                            source: "assets/meshes/neuboatYacht_mesh.mesh"
                            materials: [
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#EAEFF7"
                                    metalness: 0.0
                                    roughness: 0.85
                                    cullMode: Material.NoCulling
                                },
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#101622"
                                    metalness: 0.0
                                    roughness: 0.25
                                    cullMode: Material.NoCulling
                                },
                                PrincipledMaterial {
                                    lighting: PrincipledMaterial.FragmentLighting
                                    baseColor: "#323B4C"
                                    metalness: 0.0
                                    roughness: 0.85
                                    cullMode: Material.NoCulling
                                }
                            ]
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
            primaryValue: (typeof vesselState !== "undefined" && vesselState) ? vesselState.depth.toFixed(1) : "8.4"
            unit: "m"
            valueColor: "#10b981"
            subtitle: "Cruising in"
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var waterBg = ctx.createLinearGradient(32, 20, 32, 108);
                    waterBg.addColorStop(0.0, "rgba(16,185,129,0.08)");
                    waterBg.addColorStop(1.0, "rgba(16,185,129,0.55)");
                    ctx.fillStyle = waterBg;
                    ctx.beginPath();
                    ctx.roundRect(26, 20, 16, 88, 4);
                    ctx.fill();
                    ctx.strokeStyle = "rgba(16,185,129,0.40)";
                    ctx.lineWidth = 1.2;
                    ctx.strokeRect(26, 20, 16, 88);
                    for (var d = 0; d < 6; d++) {
                        var dy = 20 + d * 14;
                        ctx.strokeStyle = "rgba(16,185,129,0.25)";
                        ctx.lineWidth = 0.8;
                        ctx.beginPath();
                        ctx.moveTo(20, dy); ctx.lineTo(26, dy);
                        ctx.stroke();
                    }
                    var barGrad = ctx.createLinearGradient(50, 32, 108, 32);
                    barGrad.addColorStop(0.0, "rgba(16,185,129,0.25)");
                    barGrad.addColorStop(0.5, "rgba(16,185,129,0.75)");
                    barGrad.addColorStop(1.0, "rgba(16,185,129,0.90)");
                    ctx.fillStyle = barGrad;
                    ctx.fillRect(50, 32, 58, 72);
                    ctx.strokeStyle = "rgba(16,185,129,0.60)";
                    ctx.lineWidth = 1.2;
                    ctx.strokeRect(50, 32, 58, 72);
                    ctx.fillStyle = "rgba(100,230,185,0.85)";
                    ctx.fillRect(50, 32, 58, 4);
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
                    var cx = 64; var cy = 64; var r = 44;
                    var ringGrad = ctx.createRadialGradient(cx, cy, r * 0.80, cx, cy, r * 1.02);
                    ringGrad.addColorStop(0.0, "rgba(80,110,155,0.0)");
                    ringGrad.addColorStop(0.6, "rgba(80,110,155,0.18)");
                    ringGrad.addColorStop(1.0, "rgba(60,90,135,0.30)");
                    ctx.fillStyle = ringGrad;
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill();
                    ctx.strokeStyle = "rgba(140,170,210,0.30)";
                    ctx.lineWidth = 1.2;
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
                    ctx.fillStyle = "rgba(175,200,235,0.70)";
                    ctx.font = "bold 10px Segoe UI, sans-serif";
                    ctx.textAlign = "center";
                    ctx.fillText("N", cx, cy - r + 13);
                    ctx.fillText("S", cx, cy + r - 4);
                    ctx.fillText("E", cx + r - 8, cy + 4);
                    ctx.fillText("W", cx - r + 8, cy + 4);
                    var needleGrad = ctx.createLinearGradient(cx, cy, cx + 28, cy + 20);
                    needleGrad.addColorStop(0.0, "rgba(0,229,255,0.90)");
                    needleGrad.addColorStop(1.0, "rgba(0,210,240,0.60)");
                    ctx.strokeStyle = needleGrad;
                    ctx.lineWidth = 3.5;
                    ctx.lineCap = "round";
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + 28, cy + 20); ctx.stroke();
                    var dotGrad = ctx.createRadialGradient(cx + 28, cy + 20, 0, cx + 28, cy + 20, 5.5);
                    dotGrad.addColorStop(0.0, "#00E5FF");
                    dotGrad.addColorStop(1.0, "rgba(0,180,220,0.0)");
                    ctx.fillStyle = dotGrad;
                    ctx.beginPath(); ctx.arc(cx + 28, cy + 20, 5.5, 0, Math.PI * 2); ctx.fill();
                    ctx.fillStyle = "rgba(80,110,155,0.45)";
                    ctx.beginPath(); ctx.arc(cx, cy, 5, 0, Math.PI * 2); ctx.fill();
                }
            }
        }
    }

    Component {
        id: speedCardComp
        TelemetryCard {
            title: "Speed (SOG)"
            primaryValue: (typeof vesselState !== "undefined" && vesselState) ? vesselState.speed.toFixed(1) : "0.0"
            unit: "kts"
            valueColor: "#f59e0b"
            subtitle: (typeof vesselState !== "undefined" && vesselState) ? ("HDG: " + Math.round(vesselState.heading) + "° | RPM: " + vesselState.rpm) : "Stationary"
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = 64; var cy = 64; var r = 42;
                    ctx.strokeStyle = "rgba(245,158,11,0.15)";
                    ctx.lineWidth = 8;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 2.25);
                    ctx.stroke();
                    var arcGrad = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
                    arcGrad.addColorStop(0.0, "rgba(245,120,11,0.75)");
                    arcGrad.addColorStop(0.5, "rgba(245,158,11,0.95)");
                    arcGrad.addColorStop(1.0, "rgba(255,190,50,0.85)");
                    ctx.strokeStyle = arcGrad;
                    ctx.lineWidth = 8;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 1.68);
                    ctx.stroke();
                    var centerGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, 7);
                    centerGrad.addColorStop(0.0, "#ffffff");
                    centerGrad.addColorStop(0.5, "rgba(220,230,245,0.90)");
                    centerGrad.addColorStop(1.0, "rgba(150,170,200,0.0)");
                    ctx.fillStyle = centerGrad;
                    ctx.beginPath(); ctx.arc(cx, cy, 7, 0, Math.PI * 2); ctx.fill();
                }
            }
        }
    }
}
