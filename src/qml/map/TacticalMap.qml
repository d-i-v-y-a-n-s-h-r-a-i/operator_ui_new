import QtQuick
import QtLocation
import QtPositioning
import QtQuick.Controls

Item {
    id: root
    width: 600
    height: 400

    property bool followVessel: true

    Plugin {
        id: mapPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.providerserial"; value: 1 }
        PluginParameter { name: "osm.mapping.offline.directory"; value: "C:/Tandav_GCS/offline_tiles" }
    }

    Map {
        id: map
        anchors.fill: parent
        plugin: mapPlugin
        center: vesselState ? vesselState.coordinate : QtPositioning.coordinate(12.9716, 77.5946)
        zoomLevel: 16

        gesture.acceptedGestures: MapGestureArea.PinchGesture | MapGestureArea.PanGesture | MapGestureArea.FlickGesture

        onCenterChanged: {
            if (gesture.panActive) {
                root.followVessel = false;
            }
        }

        MapQuickItem {
            id: vesselMarker
            coordinate: vesselState ? vesselState.coordinate : QtPositioning.coordinate(12.9716, 77.5946)
            anchorPoint.x: 16
            anchorPoint.y: 16

            sourceItem: Item {
                width: 32
                height: 32
                rotation: vesselState ? vesselState.heading : 0.0

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = "#00f0ff";
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.moveTo(16, 2);
                        ctx.lineTo(28, 28);
                        ctx.lineTo(16, 22);
                        ctx.lineTo(4, 28);
                        ctx.closePath();
                        ctx.fill();
                        ctx.stroke();
                    }
                }
            }
        }

        MapPolyline {
            id: missionRoute
            line.width: 3
            line.color: "#f59e0b"
            path: {
                var coords = [];
                if (missionPlan) {
                    var list = missionPlan.waypointsList;
                    for (var i = 0; i < list.length; ++i) {
                        coords.push(QtPositioning.coordinate(list[i].latitude, list[i].longitude));
                    }
                }
                return coords;
            }
        }

        MapItemView {
            model: missionPlan ? missionPlan.waypointsList : []
            delegate: MapQuickItem {
                coordinate: QtPositioning.coordinate(modelData.latitude, modelData.longitude)
                anchorPoint.x: 12
                anchorPoint.y: 12

                sourceItem: Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: modelData.index === (missionPlan.activeIndex + 1) ? "#10b981" : "#f59e0b"
                    border.color: "#ffffff"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: modelData.index.toString()
                        color: "#0a101d"
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "Monospace"
                    }
                }
            }
        }

        MapItemView {
            model: vesselState ? vesselState.threats : []
            delegate: MapQuickItem {
                coordinate: QtPositioning.coordinate(
                    vesselState ? (vesselState.latitude + ((modelData.range_m || 50.0) * Math.cos(((vesselState.heading || 0.0) + (modelData.bearing || 0.0)) * Math.PI / 180) / 111320.0)) : 0,
                    vesselState ? (vesselState.longitude + ((modelData.range_m || 50.0) * Math.sin(((vesselState.heading || 0.0) + (modelData.bearing || 0.0)) * Math.PI / 180) / (111320.0 * Math.cos((vesselState.latitude || 12.97) * Math.PI / 180)))) : 0
                )
                anchorPoint.x: 8
                anchorPoint.y: 8

                sourceItem: Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    color: (modelData.colregs === "GIVE_WAY") ? "#ef4444" : "#f59e0b"
                    border.color: "#ffffff"
                    border.width: 1.5
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: function(mouse) {
                var coord = map.toCoordinate(Qt.point(mouse.x, mouse.y));
                if (missionPlan) {
                    missionPlan.addWaypoint(coord.latitude, coord.longitude, 2.5, 5.0);
                }
            }
        }
    }

    Connections {
        target: vesselState
        function onPositionChanged() {
            if (root.followVessel && vesselState) {
                map.center = vesselState.coordinate;
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: 260
        height: 60
        color: "#0a101d"
        opacity: 0.9
        border.color: "#1e293b"
        border.width: 1
        radius: 4

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: "LAT: " + (vesselState ? vesselState.latitude.toFixed(6) : "0.0") + "° N"
                color: "#00f0ff"
                font.pixelSize: 11
                font.bold: true
                font.family: "Monospace"
            }
            Text {
                text: "LON: " + (vesselState ? vesselState.longitude.toFixed(6) : "0.0") + "° E"
                color: "#00f0ff"
                font.pixelSize: 11
                font.bold: true
                font.family: "Monospace"
            }
            Text {
                text: "SOG: " + (vesselState ? vesselState.speed.toFixed(1) : "0.0") + " kts   COG: " + (vesselState ? vesselState.heading.toFixed(0) : "0") + "°"
                color: "#94a3b8"
                font.pixelSize: 10
                font.family: "Monospace"
            }
        }
    }

    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 6

        Button {
            width: 36
            height: 36
            text: "+"
            onClicked: map.zoomLevel = Math.min(map.maximumZoomLevel, map.zoomLevel + 1)
        }

        Button {
            width: 36
            height: 36
            text: "-"
            onClicked: map.zoomLevel = Math.max(map.minimumZoomLevel, map.zoomLevel - 1)
        }

        Button {
            width: 36
            height: 36
            text: "⌖"
            onClicked: {
                root.followVessel = true;
                if (vesselState) map.center = vesselState.coordinate;
            }
        }

        Button {
            width: 36
            height: 36
            text: "CLR"
            onClicked: {
                if (missionPlan) missionPlan.clearWaypoints();
            }
        }

        Button {
            width: 36
            height: 36
            text: "UPL"
            onClicked: {
                if (telemetry) telemetry.uploadMission();
            }
        }
    }
}
