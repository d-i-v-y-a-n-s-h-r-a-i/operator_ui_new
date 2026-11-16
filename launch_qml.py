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

    @Property(float, notify=positionChanged)
    def longitude(self):
        return self._longitude

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

    engine.rootContext().setContextProperty("vesselState", vessel_state)
    engine.rootContext().setContextProperty("telemetry", telemetry_mgr)

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
                data, _ = udp_sock.recvfrom(2048)
                last_packet_time[0] = time.time()
                received = True
                if len(data) == 77:
                    magic, seq, p, r, y, lat, lon, spd, hdg, bv, ba, bpct, btmp, tl, tr, dpt, wt, lk, arm, md, lq = struct.unpack('<IIfffddffffBfffffBBBB', data)
                    if magic == 0x544E4456:
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
                elif len(data) == 17:
                    can_id, dlc, payload, ts = struct.unpack('<IB8sI', data)
                    if can_id == 0x200:
                        vessel_state.rpm = (payload[0] << 8) | payload[1]
                        vessel_state.coolantTemp = float(payload[2] - 40)
                    elif can_id == 0x300:
                        raw_v = (payload[4] << 8) | payload[5]
                        vessel_state._batteryVoltage = raw_v * 0.01
                        vessel_state.powerChanged.emit()
                else:
                    try:
                        obj = json.loads(data.decode("utf-8"))
                        if obj.get("type") == "THREATS":
                            vessel_state.threats = obj.get("threats", [])
                        elif obj.get("type") == "AUTONOMY_STATUS":
                            if "mode" in obj:
                                vessel_state.mode = obj["mode"]
                    except Exception:
                        pass
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

    timer = QTimer()
    timer.timeout.connect(process_telemetry)
    timer.start(16)

    font_file = os.path.join(base_dir, "src", "qml", "assets", "fonts", "SairaStencilOne.ttf")
    if os.path.exists(font_file):
        QFontDatabase.addApplicationFont(font_file)

    qml_file = os.path.join(base_dir, "src", "qml", "main.qml")
    engine.load(qml_file)

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()
