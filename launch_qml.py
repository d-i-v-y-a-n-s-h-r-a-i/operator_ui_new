import PySide6.QtQuick
import sys
import os
import socket
import struct
import json
import time
import math
import ctypes
from PySide6.QtCore import QObject, Signal, Property, Slot, QTimer
from PySide6.QtGui import QGuiApplication, QIcon, QFontDatabase
from PySide6.QtQml import QQmlApplicationEngine

class VesselState(QObject):
    attitudeChanged = Signal()
    navigationChanged = Signal()
    positionChanged = Signal()
    depthChanged = Signal()
    environmentChanged = Signal()
    safetyChanged = Signal()
    armedChanged = Signal()
    modeChanged = Signal()
    powerChanged = Signal()
    propulsionChanged = Signal()
    linkChanged = Signal()
    engineChanged = Signal()
    targetHeadingChanged = Signal()
    targetSpeedChanged = Signal()
    threatsChanged = Signal()
    videoSinkChanged = Signal()
    clusterJsonChanged = Signal()
    horizonDegChanged = Signal()
    horizonYChanged = Signal()
    wpBearingChanged = Signal()
    wpDistanceNmChanged = Signal()
    wpNameChanged = Signal()
    navPathJsonChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._pitch = 2.1
        self._roll = 0.0
        self._yaw = 42.0
        self._heading = 42.0
        self._speed = 12.4
        self._latitude = 12.9716
        self._longitude = 77.5946
        self._depth = 8.2
        self._waterTemp = 24.0
        self._leakDetected = False
        self._armed = True
        self._mode = "AUTO"
        self._batteryVoltage = 25.2
        self._batteryCurrent = 14.5
        self._batteryPercentage = 98
        self._batteryTemp = 28.5
        self._leftThruster = 0.65
        self._rightThruster = 0.65
        self._latencyMs = 12
        self._linkQuality = 99
        self._rpm = 3450
        self._coolantTemp = 68.4
        self._targetHeading = 45.0
        self._targetSpeed = 14.0
        self._threats = []
        self._videoSink = None
        self._clusterJson = ""
        self._horizonDeg = float("nan")
        self._horizonY = float("nan")
        self._wpBearing = 47.0
        self._wpDistanceNm = 0.22
        self._wpName = "WP 01"
        self._navPathJson = ""

    @Property(float, notify=attitudeChanged)
    def pitch(self):
        return self._pitch

    @pitch.setter
    def pitch(self, val):
        if self._pitch != val:
            self._pitch = val
            self.attitudeChanged.emit()

    @Property(float, notify=attitudeChanged)
    def roll(self):
        return self._roll

    @roll.setter
    def roll(self, val):
        if self._roll != val:
            self._roll = val
            self.attitudeChanged.emit()

    @Property(float, notify=attitudeChanged)
    def yaw(self):
        return self._yaw

    @yaw.setter
    def yaw(self, val):
        if self._yaw != val:
            self._yaw = val
            self.attitudeChanged.emit()

    @Property(float, notify=navigationChanged)
    def heading(self):
        return self._heading

    @heading.setter
    def heading(self, val):
        if self._heading != val:
            self._heading = val
            self.navigationChanged.emit()

    @Property(float, notify=navigationChanged)
    def speed(self):
        return self._speed

    @speed.setter
    def speed(self, val):
        if self._speed != val:
            self._speed = val
            self.navigationChanged.emit()

    @Property(float, notify=positionChanged)
    def latitude(self):
        return self._latitude

    @latitude.setter
    def latitude(self, val):
        if self._latitude != val:
            self._latitude = val
            self.positionChanged.emit()

    @Property(float, notify=positionChanged)
    def longitude(self):
        return self._longitude

    @longitude.setter
    def longitude(self, val):
        if self._longitude != val:
            self._longitude = val
            self.positionChanged.emit()

    @Property(float, notify=depthChanged)
    def depth(self):
        return self._depth

    @depth.setter
    def depth(self, val):
        if self._depth != val:
            self._depth = val
            self.depthChanged.emit()

    @Property(float, notify=environmentChanged)
    def waterTemp(self):
        return self._waterTemp

    @Property(bool, notify=safetyChanged)
    def leakDetected(self):
        return self._leakDetected

    @Property(bool, notify=armedChanged)
    def armed(self):
        return self._armed

    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @mode.setter
    def mode(self, val):
        if self._mode != val:
            self._mode = val
            self.modeChanged.emit()

    @Property(float, notify=powerChanged)
    def batteryVoltage(self):
        return self._batteryVoltage

    @Property(float, notify=powerChanged)
    def batteryCurrent(self):
        return self._batteryCurrent

    @Property(int, notify=powerChanged)
    def batteryPercentage(self):
        return self._batteryPercentage

    @Property(float, notify=powerChanged)
    def batteryTemp(self):
        return self._batteryTemp

    @Property(float, notify=propulsionChanged)
    def leftThruster(self):
        return self._leftThruster

    @Property(float, notify=propulsionChanged)
    def rightThruster(self):
        return self._rightThruster

    @Property(int, notify=linkChanged)
    def latencyMs(self):
        return self._latencyMs

    @Property(int, notify=linkChanged)
    def linkQuality(self):
        return self._linkQuality

    @Property(int, notify=engineChanged)
    def rpm(self):
        return self._rpm

    @rpm.setter
    def rpm(self, val):
        if self._rpm != val:
            self._rpm = val
            self.engineChanged.emit()

    @Property(float, notify=engineChanged)
    def coolantTemp(self):
        return self._coolantTemp

    @coolantTemp.setter
    def coolantTemp(self, val):
        if self._coolantTemp != val:
            self._coolantTemp = val
            self.engineChanged.emit()

    @Property(float, notify=targetHeadingChanged)
    def targetHeading(self):
        return self._targetHeading

    @targetHeading.setter
    def targetHeading(self, val):
        if self._targetHeading != val:
            self._targetHeading = val
            self.targetHeadingChanged.emit()

    @Property(float, notify=targetSpeedChanged)
    def targetSpeed(self):
        return self._targetSpeed

    @targetSpeed.setter
    def targetSpeed(self, val):
        if self._targetSpeed != val:
            self._targetSpeed = val
            self.targetSpeedChanged.emit()

    @Property(list, notify=threatsChanged)
    def threats(self):
        return self._threats

    @threats.setter
    def threats(self, val):
        self._threats = val
        self.threatsChanged.emit()

    @Property(QObject, notify=videoSinkChanged)
    def videoSink(self):
        return self._videoSink

    @videoSink.setter
    def videoSink(self, val):
        if self._videoSink != val:
            self._videoSink = val
            self.videoSinkChanged.emit()

    @Property(str, notify=clusterJsonChanged)
    def clusterJson(self):
        return self._clusterJson

    @clusterJson.setter
    def clusterJson(self, val):
        if self._clusterJson != val:
            self._clusterJson = val
            self.clusterJsonChanged.emit()

    @Property(float, notify=horizonDegChanged)
    def horizonDeg(self):
        return self._horizonDeg

    @horizonDeg.setter
    def horizonDeg(self, val):
        if self._horizonDeg != val:
            self._horizonDeg = val
            self.horizonDegChanged.emit()

    @Property(float, notify=horizonYChanged)
    def horizonY(self):
        return self._horizonY

    @horizonY.setter
    def horizonY(self, val):
        if self._horizonY != val:
            self._horizonY = val
            self.horizonYChanged.emit()

    @Property(float, notify=wpBearingChanged)
    def wpBearing(self):
        return self._wpBearing

    @wpBearing.setter
    def wpBearing(self, val):
        if self._wpBearing != val:
            self._wpBearing = val
            self.wpBearingChanged.emit()

    @Property(float, notify=wpDistanceNmChanged)
    def wpDistanceNm(self):
        return self._wpDistanceNm

    @wpDistanceNm.setter
    def wpDistanceNm(self, val):
        if self._wpDistanceNm != val:
            self._wpDistanceNm = val
            self.wpDistanceNmChanged.emit()

    @Property(str, notify=wpNameChanged)
    def wpName(self):
        return self._wpName

    @wpName.setter
    def wpName(self, val):
        if self._wpName != val:
            self._wpName = val
            self.wpNameChanged.emit()

    @Property(str, notify=navPathJsonChanged)
    def navPathJson(self):
        return self._navPathJson

    @navPathJson.setter
    def navPathJson(self, val):
        if self._navPathJson != val:
            self._navPathJson = val
            self.navPathJsonChanged.emit()

class TelemetryManager(QObject):
    connectionChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._connected = True
        self.uplink_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.uplink_addr = ("127.0.0.1", 9000)

    @Property(bool, notify=connectionChanged)
    def connected(self):
        return self._connected

    @Slot(float)
    def sendTargetSpeed(self, speed):
        payload = json.dumps({"type": "TARGET_SPEED", "speed": float(speed)}).encode("utf-8")
        try:
            self.uplink_sock.sendto(payload, self.uplink_addr)
        except Exception:
            pass

    @Slot(float)
    def sendTargetHeading(self, heading):
        payload = json.dumps({"type": "TARGET_HEADING", "heading": float(heading)}).encode("utf-8")
        try:
            self.uplink_sock.sendto(payload, self.uplink_addr)
        except Exception:
            pass

    @Slot(str)
    def sendMode(self, mode_str):
        payload = json.dumps({"type": "MODE_COMMAND", "mode": str(mode_str)}).encode("utf-8")
        try:
            self.uplink_sock.sendto(payload, self.uplink_addr)
        except Exception:
            pass

    @Slot()
    def sendEmergencyStop(self):
        payload = json.dumps({"type": "EMERGENCY_STOP"}).encode("utf-8")
        try:
            self.uplink_sock.sendto(payload, self.uplink_addr)
        except Exception:
            pass

def main():
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("TANDAV.CI4.Console")
    except Exception:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("TANDAV")
    app.setApplicationDisplayName("TANDAV")
    app.setOrganizationName("TANDAV")

    base_dir = os.path.dirname(os.path.abspath(__file__))
    ico_path = os.path.join(base_dir, "ci4-logo.ico")
    png_path = os.path.join(base_dir, "ci4-logo.png")
    if os.path.exists(ico_path):
        app.setWindowIcon(QIcon(ico_path))
    elif os.path.exists(png_path):
        app.setWindowIcon(QIcon(png_path))

    engine = QQmlApplicationEngine()

    vessel_state = VesselState()
    telemetry_mgr = TelemetryManager()

    # Offline Vector Map & GNSS Backend
    from backend.mission_map_backend import MissionMapBackend
    from backend.link_monitor import LinkMonitor
    maps_dir = os.path.join(base_dir, "maps")
    mission_map = MissionMapBackend(maps_dir)
    mission_map.startGpsd()
    app.aboutToQuit.connect(mission_map.shutdown)

    engine.rootContext().setContextProperty("vesselState", vessel_state)
    engine.rootContext().setContextProperty("telemetry", telemetry_mgr)
    engine.rootContext().setContextProperty("missionMap", mission_map)

    # SYSTEM CONNECTIONS pop-up (gear button): health of every link
    link_monitor = LinkMonitor(app)
    link_monitor.attach(vessel_state, mission_map, telemetry_mgr)
    app.aboutToQuit.connect(link_monitor.shutdown)
    engine.rootContext().setContextProperty("linkMonitor", link_monitor)

    # LoRa keyboard control + telemetry bridge (ESP32 via QSerialPort @ 115200)
    from backend.lora_bridge import LoraBridge
    lora = LoraBridge()
    engine.rootContext().setContextProperty("loraBridge", lora)

    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp_sock.bind(("0.0.0.0", 9001))
    udp_sock.setblocking(False)

    last_packet_time = [time.time()]
    sim_t = [0.0]

    def process_telemetry():
        received = False
        while True:
            try:
                data, _addr = udp_sock.recvfrom(2048)
                last_packet_time[0] = time.time()
                received = True
                if len(data) == 77:
                    magic, seq, p, r, y, lat, lon, spd, hdg, bv, ba, bpct, btmp, tl, tr, dpt, wt, lk, arm, md, lq = struct.unpack('<IIfffddffffBfffffBBBB', data)
                    if magic == 0x544E4456:
                        link_monitor.note_telemetry("bin", _addr[0], seq)
                        link_monitor.note_telemetry("autonomy")
                        link_monitor.note_can(0x200)
                        link_monitor.note_can(0x300)
                        vessel_state.pitch = p
                        vessel_state.roll = r
                        vessel_state.yaw = y
                        vessel_state.heading = hdg
                        vessel_state.speed = spd
                        vessel_state.depth = dpt
                        vessel_state._waterTemp = wt
                        vessel_state._leakDetected = bool(lk)
                        vessel_state._armed = bool(arm)
                        vessel_state._mode = "AUTO" if md == 2 else ("TELEOP" if md == 1 else "MANUAL")
                        vessel_state._batteryVoltage = bv
                        vessel_state._batteryCurrent = ba
                        vessel_state._batteryPercentage = bpct
                        vessel_state._batteryTemp = btmp
                        vessel_state._leftThruster = tl
                        vessel_state._rightThruster = tr
                        vessel_state._linkQuality = lq
                        if lat != 0.0 and lon != 0.0:
                            vessel_state.latitude = lat
                            vessel_state.longitude = lon
                            mission_map.setGnss(lat, lon, hdg, spd, 1)
                        vessel_state.attitudeChanged.emit()
                        vessel_state.navigationChanged.emit()
                        vessel_state.depthChanged.emit()
                        vessel_state.environmentChanged.emit()
                        vessel_state.safetyChanged.emit()
                        vessel_state.armedChanged.emit()
                        vessel_state.modeChanged.emit()
                        vessel_state.powerChanged.emit()
                        vessel_state.propulsionChanged.emit()
                        vessel_state.linkChanged.emit()
                        # Keep InstrumentCluster LIVE
                        vessel_state.clusterJson = json.dumps({
                            "seq": int(seq),
                            "speedKn": round(vessel_state.speed, 1),
                            "speedKmh": round(vessel_state.speed * 1.852, 1),
                            "rpm": vessel_state.rpm,
                            "gear": "F" if vessel_state.speed > 0.5 else "N",
                            "driveMode": "SPORT",
                            "control": vessel_state.mode,
                            "fuelPct": 85,
                            "coolantC": round(vessel_state.coolantTemp, 1),
                            "battV": round(vessel_state.batteryVoltage, 1),
                            "tripKm": round(seq * 0.001, 2),
                            "engineHours": 328.2
                        })
                elif len(data) == 17:
                    can_id, dlc, payload, ts = struct.unpack('<IB8sI', data)
                    link_monitor.note_can(can_id)
                    if can_id == 0x200:
                        vessel_state.rpm = (payload[0] << 8) | payload[1]
                        vessel_state.coolantTemp = float(payload[2] - 40)
                    elif can_id == 0x300:
                        raw_v = (payload[4] << 8) | payload[5]
                        vessel_state._batteryVoltage = raw_v * 0.01
                        vessel_state.powerChanged.emit()
                else:
                    text_str = ""
                    try:
                        text_str = data.decode("utf-8").strip()
                    except Exception:
                        pass

                    if "HB:STM" in text_str or "VS=" in text_str:
                        from backend.lora_serial import parse_lora_line, make_cluster_json
                        parsed = parse_lora_line(text_str)
                        if parsed:
                            seq_val = int(time.time() * 10) % 100000
                            link_monitor.note_telemetry("bin", _addr[0], seq_val)
                            vessel_state.heading = parsed.get("heading", vessel_state.heading)
                            vessel_state.yaw = vessel_state.heading
                            vessel_state.speed = parsed.get("speed", vessel_state.speed)
                            vessel_state.mode = parsed.get("mode", vessel_state.mode)
                            lat = parsed.get("lat", 0.0)
                            lon = parsed.get("lon", 0.0)
                            if lat != 0.0 and lon != 0.0:
                                vessel_state.latitude = lat
                                vessel_state.longitude = lon
                                mission_map.setGnss(lat, lon, vessel_state.heading, vessel_state.speed, parsed.get("fix", 1))
                            if parsed.get("threats"):
                                vessel_state.threats = parsed["threats"]
                            vessel_state.attitudeChanged.emit()
                            vessel_state.navigationChanged.emit()
                            vessel_state.modeChanged.emit()
                            vessel_state.clusterJson = make_cluster_json(parsed, seq_val)
                    elif text_str.startswith("{"):
                        try:
                            obj = json.loads(text_str)
                            if "speedKn" in obj or "speedKmh" in obj or "fuelPct" in obj:
                                vessel_state.clusterJson = text_str
                            elif obj.get("type") == "THREATS":
                                link_monitor.note_telemetry("threats")
                                vessel_state.threats = obj.get("threats", [])
                            elif obj.get("type") == "AUTONOMY_STATUS":
                                link_monitor.note_telemetry("autonomy")
                                if "mode" in obj:
                                    vessel_state.mode = obj["mode"]
                            elif obj.get("event") == "telemetry" or obj.get("type") == "TELEMETRY" or "speed" in obj or "speed_kmh" in obj:
                                link_monitor.note_telemetry("json", _addr[0])
                                if "speed_kmh" in obj and obj["speed_kmh"] is not None:
                                    vessel_state.speed = float(obj["speed_kmh"])
                                elif "speed" in obj and obj["speed"] is not None:
                                    vessel_state.speed = float(obj["speed"])
                                if "rpm" in obj and obj["rpm"] is not None:
                                    vessel_state.rpm = int(obj["rpm"])
                                if "mode" in obj and obj["mode"]:
                                    vessel_state.mode = str(obj["mode"])
                        except Exception:
                            pass
            except BlockingIOError:
                break
            except Exception:
                break
            except BlockingIOError:
                break
            except Exception:
                break

        if not received and (time.time() - last_packet_time[0]) > 1.0:
            sim_t[0] += 0.016
            t = sim_t[0]
            vessel_state.pitch = 2.1 + math.sin(t * 1.8) * 0.8
            vessel_state.roll = math.cos(t * 1.4) * 1.2
            vessel_state.heading = (42.0 + math.sin(t * 0.2) * 5.0) % 360.0
            vessel_state.speed = 12.4 + math.sin(t * 0.5) * 0.6
            vessel_state.depth = 8.2 + math.sin(t * 0.3) * 0.3
            vessel_state.rpm = int(3400 + math.sin(t * 2.0) * 80)
            vessel_state.coolantTemp = 68.4 + math.sin(t * 0.1) * 0.4
            vessel_state.attitudeChanged.emit()
            vessel_state.navigationChanged.emit()
            vessel_state.engineChanged.emit()
            vessel_state.clusterJson = json.dumps({
                "seq": int(t * 10),
                "speedKn": round(vessel_state.speed, 1),
                "rpm": vessel_state.rpm,
                "gear": "F",
                "driveMode": "SPORT",
                "control": vessel_state.mode,
                "fuelPct": 84,
                "coolantC": round(vessel_state.coolantTemp, 1),
                "battV": 13.8,
                "tripKm": round(t * 0.01, 1),
                "engineHours": 328.2
            })

    timer = QTimer()
    timer.timeout.connect(process_telemetry)
    timer.start(16)

    fonts_dir = os.path.join(base_dir, "src", "qml", "assets", "fonts")
    if os.path.exists(fonts_dir):
        for fname in sorted(os.listdir(fonts_dir)):
            if fname.lower().endswith((".ttf", ".otf")):
                QFontDatabase.addApplicationFont(os.path.join(fonts_dir, fname))

    qml_file = os.path.join(base_dir, "src", "qml", "main.qml")
    engine.load(qml_file)

    if not engine.rootObjects():
        sys.exit(-1)

    win = engine.rootObjects()[0]
    lora.install_on(win)                      # global key capture
    link_monitor.attach_lora(lora)            # popup ki LoRa row (Step 3)
    app.aboutToQuit.connect(lora.shutdown)    # quit par idle packet flush

    sys.exit(app.exec())

if __name__ == "__main__":
    main()
