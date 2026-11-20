"""
lora_bridge.py  -  manual-control link of the TANDAV GCS:  PC --USB serial 115200--> ESP32 --LoRa 433 MHz--> STM32.

This is a straight port of the OLD React teleop console (useSerialLink.ts, useKeyboardControls.ts, lib/protocol.ts) to
PySide6, so the NEW QML UI drives the boat exactly like the old one did.  The backend/firmware is untouched - the
ESP32_LoRa_Ground.ino protocol is used byte for byte.

    ARROW UP / DOWN     throttle + / -            \
    ARROW LEFT / RIGHT  steer left / right         >  one packet on every press AND release (never on auto-repeat):
    SPACE               brake (hold)              /   "KEYS:U1D0L0R0S0\\n"   (all five flags in a fixed order)
    1 / 2 / 3 / 4       Engine / Mode / VTS up / VTS down - one-shot, "BTN:E\\n" "BTN:M\\n" "BTN:VU\\n" "BTN:VD\\n"

Same guards as the old App.tsx:
    * keys are only tracked while the USB serial port is open;
    * solenoid buttons (1-4) only fire while the LoRa link to the STM32 is up;
    * window loses focus  ->  every key is released (one idle packet)   [old: window "blur"]
Deliberate differences (safety, see INTEGRATION.md):
    * a key PRESS is only sent while the LoRa link is up  (requireLoraForMotors, default True).  The ESP32 does not read
      the serial port while unlinked, so an early "KEYS:U1..." would sit in its buffer and be executed the moment the
      link comes up.  Releases are always sent.
    * on link-up an idle packet is sent, so a throttle that was held when the link dropped is not resumed by the ESP32.
    * on disconnect / application quit an idle packet is flushed first.

What QML sees (context property `loraBridge`, set in launch_qml.py):
    status            "disconnected" | "usb" | "lora"
    usbConnected / loraLinked / portName / error
    keys              {Up, Down, Left, Right, Space: bool}         live key state (for the on-screen key tiles)
    solenoidStates    {E, M, VU, VD, AUTO, MANUAL: "idle"|"pending"|"ok"|"rejected"|"timeout"}
    throttlePct / brakePct / steeringPct   real pot feedback from the STM32 (-1 = none),  feedbackFresh (< 2 s old)
    slots             connectAuto() connectPort(name) disconnectPort() refreshPorts() setKey(name, pressed) releaseAll()
                      fireSolenoid(ch) sendMode(auto) sendRaw(line) clearLog()
    signals           logLine(text, direction, kind)      direction in/out/sys, kind heartbeat/key/warning/info/ack/btn
Python side:   install_on(window)  health_check()  shutdown()  attach_device(QIODevice)   (the last one is for tests)
"""
import os
import re
import time

from PySide6.QtCore import QEvent, QIODevice, QObject, Property, Qt, QTimer, Signal, Slot
from PySide6.QtSerialPort import QSerialPort, QSerialPortInfo

BAUD = int(os.environ.get("TANDAV_LORA_BAUD", "115200"))
PORT_OVERRIDE = os.environ.get("TANDAV_LORA_PORT", "").strip()          # e.g. COM5 or /dev/ttyUSB0
# USB-UART bridges used on ESP32 boards: Silicon Labs CP210x, WCH CH340/CH9102, FTDI, Prolific, Espressif native USB
KNOWN_VIDS = {0x10C4, 0x1A86, 0x0403, 0x067B, 0x303A}
FEEDBACK_FRESH_S = 2.0
SILENT_WARN_S = 6.0

KEY_NAMES = ("Up", "Down", "Left", "Right", "Space")
IDLE_PACKET = "KEYS:U0D0L0R0S0"
SOLENOID_CHANNELS = ("E", "M", "VU", "VD")
SOLENOID_LABELS = {"E": "Engine", "M": "Mode", "VU": "VTS Up", "VD": "VTS Down", "AUTO": "Auto", "MANUAL": "Manual"}

_K = Qt.Key
MOTOR_KEYS = {_K.Key_Up.value: "Up", _K.Key_Down.value: "Down", _K.Key_Left.value: "Left",
              _K.Key_Right.value: "Right", _K.Key_Space.value: "Space"}
SOLENOID_KEYS = {_K.Key_1.value: "E", _K.Key_2.value: "M", _K.Key_3.value: "VU", _K.Key_4.value: "VD"}

_FB_RE = re.compile(r"T=(-?[\d.]+),B=(-?[\d.]+),S=(-?[\d.]+)")


# ============================================================================================ protocol (protocol.ts)
def build_keys_packet(keys):
    b = lambda v: "1" if v else "0"
    return "KEYS:U%sD%sL%sR%sS%s" % (b(keys["Up"]), b(keys["Down"]), b(keys["Left"]), b(keys["Right"]), b(keys["Space"]))


def parse_line(raw):
    """Classify one line from the ESP32 (port of parseIncomingLine).  Returns a dict:
       kind, link_up, link_lost, key_ack, btn_ack=(channel, "ok"|"rejected") | None, feedback=(t, b, s) | None, boot"""
    line = raw.strip()
    out = dict(kind="info", link_up=False, link_lost=False, key_ack=False, btn_ack=None, feedback=None, boot=False)
    m = _FB_RE.search(line)
    if m:
        out["feedback"] = (float(m.group(1)), float(m.group(2)), float(m.group(3)))

    if line in ("Link established with STM32.", "*** LINK ESTABLISHED ***") or line.startswith("RX <- HB:STM") or line.startswith("HB:STM:"):
        out.update(kind="info" if "LINK" in line else "heartbeat", link_up=True)
    elif line.startswith("WARNING: Link lost") or line == "=== LINK LOST ===":
        out.update(kind="warning", link_lost=True)
    elif line.startswith("=== ESP32"):                       # ESP32 (re)booted -> any previous link is gone
        out.update(kind="info", boot=True)
    elif line.startswith("RX <- HB:STM") or line.startswith("HB:STM") or line.startswith("TX -> HB:ESP"):
        out["kind"] = "heartbeat"
    elif line.startswith("TX -> KEYS:"):
        out["kind"] = "key"
    elif line.startswith("TX -> BTN:"):
        out["kind"] = "btn"
    elif line.startswith("STM_ACK:"):                       # KEY_ACK forwarded from the STM32 (also carries feedback)
        out.update(kind="ack", key_ack=True)
    elif line.startswith("STM_BTN_ACK:"):                   # STM_BTN_ACK:E:OK  /  STM_BTN_ACK:E:REJECTED
        parts = line[len("STM_BTN_ACK:"):].split(":")
        out["kind"] = "btn"
        if len(parts) >= 2:
            out["btn_ack"] = (parts[0], "ok" if parts[1].upper() == "OK" else "rejected")
    elif "WARNING" in line.upper() or "ERROR" in line.upper():
        out["kind"] = "warning"
    return out


# ================================================================================================= keyboard capture
class _KeyFilter(QObject):
    """Window-level key capture: works whatever item has focus, sees auto-repeat and the focus loss."""

    def __init__(self, bridge):
        super().__init__(bridge)
        self._b = bridge

    def eventFilter(self, obj, ev):                                           # noqa: N802 (Qt API)
        t = ev.type()
        if t == QEvent.Type.KeyPress or t == QEvent.Type.KeyRelease:
            return self._b._on_key_event(ev, t == QEvent.Type.KeyPress)
        if t == QEvent.Type.WindowDeactivate:
            self._b.releaseAll()
        return False


# =========================================================================================================== the bridge
class LoraBridge(QObject):
    statusChanged = Signal()
    portsChanged = Signal()
    errorChanged = Signal()
    keysChanged = Signal()
    solenoidChanged = Signal()
    feedbackChanged = Signal()
    portNameChanged = Signal()
    optionsChanged = Signal()
    logLine = Signal(str, str, str)                  # text, direction (in/out/sys), kind
    solenoidAcked = Signal(str, str)                 # channel, "ok" | "rejected"

    def __init__(self, parent=None):
        super().__init__(parent)
        self._dev = None
        self._status = "disconnected"
        self._port_name = ""
        self._error = ""
        self._ports = []
        self._buf = bytearray()
        self._keys = {k: False for k in KEY_NAMES}
        self._last_sent = None
        self._sol = {c: ("idle", 0.0) for c in SOLENOID_LABELS}
        self._fb = (-1.0, -1.0, -1.0)
        self._fb_t = 0.0
        self._fresh = False
        self._rx_t = 0.0
        self._opened_t = 0.0
        self._link_t = 0.0
        self._link_lost_count = 0
        self._auto = True
        self._user_disconnected = False
        self._require_lora = True
        self._window = None
        self._filter = _KeyFilter(self)

        self._tick_timer = QTimer(self)
        self._tick_timer.setInterval(250)
        self._tick_timer.timeout.connect(self._tick)
        self._tick_timer.start()
        self._auto_timer = QTimer(self)
        self._auto_timer.setInterval(3000)
        self._auto_timer.timeout.connect(self._auto_try)
        self._auto_timer.start()
        self.refreshPorts()
        QTimer.singleShot(400, self._auto_try)

    # ------------------------------------------------------------------------------------------------ properties
    def _get_status(self): return self._status
    status = Property(str, _get_status, notify=statusChanged)

    def _get_usb(self): return self._status != "disconnected"
    usbConnected = Property(bool, _get_usb, notify=statusChanged)

    def _get_lora(self): return self._status == "lora"
    loraLinked = Property(bool, _get_lora, notify=statusChanged)

    def _get_port(self): return self._port_name
    portName = Property(str, _get_port, notify=portNameChanged)

    def _get_err(self): return self._error
    error = Property(str, _get_err, notify=errorChanged)

    def _get_ports(self): return list(self._ports)
    ports = Property("QVariantList", _get_ports, notify=portsChanged)

    def _get_keys(self): return dict(self._keys)
    keys = Property("QVariantMap", _get_keys, notify=keysChanged)

    def _get_sol(self): return {c: v[0] for c, v in self._sol.items()}
    solenoidStates = Property("QVariantMap", _get_sol, notify=solenoidChanged)

    def _get_t(self): return self._fb[0]
    throttlePct = Property(float, _get_t, notify=feedbackChanged)

    def _get_b(self): return self._fb[1]
    brakePct = Property(float, _get_b, notify=feedbackChanged)

    def _get_s(self): return self._fb[2]
    steeringPct = Property(float, _get_s, notify=feedbackChanged)

    def _get_fresh(self): return self._fresh
    feedbackFresh = Property(bool, _get_fresh, notify=feedbackChanged)

    def _get_auto(self): return self._auto
    def _set_auto(self, v):
        if bool(v) != self._auto:
            self._auto = bool(v)
            self.optionsChanged.emit()
    autoConnect = Property(bool, _get_auto, _set_auto, notify=optionsChanged)

    def _get_req(self): return self._require_lora
    def _set_req(self, v):
        if bool(v) != self._require_lora:
            self._require_lora = bool(v)
            self.optionsChanged.emit()
    requireLoraForMotors = Property(bool, _get_req, _set_req, notify=optionsChanged)

    # ---------------------------------------------------------------------------------------------------- helpers
    def _log(self, text, direction, kind):
        self.logLine.emit(text, direction, kind)

    def _set_status(self, s):
        if s != self._status:
            self._status = s
            self.statusChanged.emit()

    def _set_error(self, e):
        if e != self._error:
            self._error = e
            self.errorChanged.emit()

    def _write_line(self, text, kind):
        d = self._dev
        if d is None or not d.isOpen():
            return False
        n = d.write((text + "\n").encode("ascii", "ignore"))
        if n > 0:
            self._log(text, "out", kind)
            return True
        return False

    # ------------------------------------------------------------------------------------------------ port handling
    @Slot()
    def refreshPorts(self):
        res = []
        for i in QSerialPortInfo.availablePorts():
            res.append({"name": i.portName(), "description": i.description() or i.manufacturer() or "serial port",
                        "vid": i.vendorIdentifier() if i.hasVendorIdentifier() else 0,
                        "pid": i.productIdentifier() if i.hasProductIdentifier() else 0,
                        "likely": bool(i.hasVendorIdentifier() and i.vendorIdentifier() in KNOWN_VIDS)})
        res.sort(key=lambda p: (not p["likely"], p["name"]))
        if res != self._ports:
            self._ports = res
            self.portsChanged.emit()

    def _candidates(self):
        if PORT_OVERRIDE:
            return [PORT_OVERRIDE]
        return [p["name"] for p in self._ports if p["likely"] and "bluetooth" not in p["description"].lower()]

    @Slot()
    def connectAuto(self):
        """Connect to $TANDAV_LORA_PORT, else the first USB-UART bridge that looks like an ESP32 board."""
        self._user_disconnected = False
        self.refreshPorts()
        c = self._candidates()
        if not c:
            self._set_error("No ESP32 USB-serial port found - plug in the ground ESP32 (or set TANDAV_LORA_PORT).")
            return
        self.connectPort(c[0])

    @Slot(str)
    def connectPort(self, name):
        if self._dev is not None:
            self.disconnectPort(user=False)
        self._user_disconnected = False
        sp = QSerialPort(name, self)
        sp.setBaudRate(BAUD)
        sp.setDataBits(QSerialPort.DataBits.Data8)
        sp.setParity(QSerialPort.Parity.NoParity)
        sp.setStopBits(QSerialPort.StopBits.OneStop)
        sp.setFlowControl(QSerialPort.FlowControl.NoFlowControl)
        if not sp.open(QIODevice.OpenModeFlag.ReadWrite):
            self._set_error("Cannot open %s: %s" % (name, sp.errorString()))
            sp.deleteLater()
            return
        sp.setDataTerminalReady(False)                  # keep DTR/RTS idle: no auto-reset pulse on the ESP32 board
        sp.setRequestToSend(False)
        sp.errorOccurred.connect(self._on_serial_error)
        self._attach(sp, name)
        self._log("Connected to ESP32 over USB serial (%s, %d baud)." % (name, BAUD), "sys", "info")

    def attach_device(self, dev, label="test"):
        """Use any open QIODevice as the serial link (unit tests: a fake ESP32 over a local socket)."""
        if self._dev is not None:
            self.disconnectPort(user=False)
        self._attach(dev, label)

    def _attach(self, dev, label):
        self._dev = dev
        self._buf.clear()
        self._port_name = label
        self._opened_t = time.monotonic()
        self._rx_t = 0.0
        self._last_sent = None
        self._clear_keys()
        dev.readyRead.connect(self._on_ready)
        dev.readChannelFinished.connect(self._on_closed)
        self._set_error("")
        self.portNameChanged.emit()
        self._set_status("usb")
        if dev.bytesAvailable():
            self._on_ready()

    @Slot()
    def disconnectPort(self, user=True):
        if user:
            self._user_disconnected = True              # stop auto-reconnecting until connectAuto()/connectPort()
        dev, self._dev = self._dev, None
        if dev is not None:
            try:                                        # leave the ESP32 in idle, never with a throttle still latched
                if dev.isOpen() and (self._last_sent not in (None, IDLE_PACKET) or any(self._keys.values())):
                    dev.write((IDLE_PACKET + "\n").encode())
                    dev.waitForBytesWritten(150)
            except Exception:
                pass
            try:
                dev.readyRead.disconnect(self._on_ready)
                dev.readChannelFinished.disconnect(self._on_closed)
            except Exception:
                pass
            try:
                dev.close()
            except Exception:
                pass
            try:
                dev.deleteLater()
            except RuntimeError:                        # C++ object already gone (interpreter / window shutdown)
                pass
        self._clear_keys()
        self._last_sent = None
        self._port_name = ""
        self.portNameChanged.emit()
        self._set_status("disconnected")
        self._log("Serial port closed.", "sys", "info")

    @Slot()
    def shutdown(self):
        self.disconnectPort(user=True)
        self._tick_timer.stop()
        self._auto_timer.stop()

    def _on_closed(self):
        if self._dev is not None:
            self._log("Serial device disconnected.", "sys", "warning")
            self._set_error("Serial device disconnected.")
            self.disconnectPort(user=False)

    def _on_serial_error(self, err):
        if err == QSerialPort.SerialPortError.NoError or err == QSerialPort.SerialPortError.TimeoutError:
            return
        if err in (QSerialPort.SerialPortError.ResourceError, QSerialPort.SerialPortError.DeviceNotFoundError,
                   QSerialPort.SerialPortError.PermissionError):
            self._set_error("Serial error: %s" % (self._dev.errorString() if self._dev else err))
            self._log("Serial error: %s" % err, "sys", "warning")
            self.disconnectPort(user=False)

    def _auto_try(self):
        if self._dev is not None:
            return
        self.refreshPorts()
        if self._auto and not self._user_disconnected:
            c = self._candidates()
            if c:
                self.connectPort(c[0])

    # ------------------------------------------------------------------------------------------------- receive path
    def _on_ready(self):
        dev = self._dev
        if dev is None:
            return
        self._buf += bytes(dev.readAll())
        self._rx_t = time.monotonic()
        while True:
            i = self._buf.find(b"\n")
            if i < 0:
                break
            raw = self._buf[:i].decode("utf-8", "replace").rstrip("\r")
            del self._buf[:i + 1]
            if raw:
                self._handle_line(raw)
        if len(self._buf) > 4096:                       # never-ending junk without a newline
            self._buf.clear()

    def _handle_line(self, raw):
        p = parse_line(raw)
        self._log(raw, "in", p["kind"])
        if p["boot"] and self._status == "lora":
            self._link_lost("ESP32 restarted")
        if p["link_up"]:
            self._link_up()
        elif p["link_lost"]:
            self._link_lost("link lost")
        elif raw.startswith("TX -> HELLO:") and self._status == "lora":     # ESP32 is hand-shaking again = link is down
            self._link_lost("link lost")
        if p["btn_ack"]:
            ch, res = p["btn_ack"]
            if ch in self._sol:
                self._sol[ch] = (res, time.monotonic())
                self.solenoidChanged.emit()
            self.solenoidAcked.emit(ch, res)
        if p["feedback"]:
            t, b, s = p["feedback"]
            self._fb = (t, b, s)
            self._fb_t = time.monotonic()
            self._fresh = True
            self.feedbackChanged.emit()
        if "HB:STM" in raw:
            try:
                if not hasattr(self, "_udp_tlm_sock"):
                    import socket
                    self._udp_tlm_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self._udp_tlm_sock.sendto(raw.encode("utf-8"), ("127.0.0.1", 9001))
            except Exception:
                pass

    def _link_up(self):
        if self._status == "lora":
            return
        self._link_t = time.monotonic()
        self._clear_keys()
        self._set_status("lora")
        self._write_line(IDLE_PACKET, "key")            # reset whatever the ESP32 still remembers as "last key state"
        self._last_sent = IDLE_PACKET

    def _link_lost(self, why):
        if self._status == "lora":
            self._link_lost_count += 1
            self._clear_keys()
            self._last_sent = None
            self._set_status("usb")
            self._log("LoRa link down (%s)." % why, "sys", "warning")

    # -------------------------------------------------------------------------------------------------- send path
    def _clear_keys(self):
        if any(self._keys.values()):
            self._keys = {k: False for k in KEY_NAMES}
            self.keysChanged.emit()

    def _send_keys(self):
        pkt = build_keys_packet(self._keys)
        if pkt != self._last_sent and self._write_line(pkt, "key"):
            self._last_sent = pkt

    @Slot(str, bool, result=bool)
    def setKey(self, name, pressed):
        """Motor key edge.  Called by the window key filter and by the on-screen (touch) key tiles."""
        if name not in self._keys or self._status == "disconnected":
            return False
        if pressed and self._require_lora and self._status != "lora":
            return False
        if self._keys[name] == pressed:
            return True
        self._keys[name] = pressed
        self.keysChanged.emit()
        self._send_keys()
        return True

    @Slot()
    def releaseAll(self):
        if any(self._keys.values()):
            self._keys = {k: False for k in KEY_NAMES}
            self.keysChanged.emit()
            if self._status != "disconnected":
                self._send_keys()

    @Slot(str, result=bool)
    def fireSolenoid(self, channel):
        """One-shot dashboard button (BTN:E / M / VU / VD).  Only while the LoRa link is up."""
        if channel not in SOLENOID_CHANNELS or self._status != "lora":
            return False
        if self._write_line("BTN:" + channel, "btn"):
            self._sol[channel] = ("pending", time.monotonic())
            self.solenoidChanged.emit()
            return True
        return False

    @Slot(bool, result=bool)
    def sendMode(self, auto):
        """AUTO / MANUAL toggle of the newest old UI (BTN:AUTO / BTN:MANUAL).  Only while the LoRa link is up."""
        ch = "AUTO" if auto else "MANUAL"
        if self._status != "lora":
            return False
        if self._write_line("BTN:" + ch, "btn"):
            self._sol[ch] = ("pending", time.monotonic())
            self.solenoidChanged.emit()
            return True
        return False

    @Slot(str, result=bool)
    def sendRaw(self, line):
        return self._write_line(line.strip(), "info") if self._status != "disconnected" else False

    @Slot()
    def clearLog(self):
        self._log("", "sys", "clear")

    # ------------------------------------------------------------------------------------------------ housekeeping
    def _tick(self):
        now = time.monotonic()
        fresh = self._fb_t > 0 and (now - self._fb_t) < FEEDBACK_FRESH_S
        if fresh != self._fresh:
            self._fresh = fresh
            self.feedbackChanged.emit()
        changed = False
        for c, (st, ts) in list(self._sol.items()):
            if st == "pending" and now - ts > 3.0:
                self._sol[c] = ("timeout", now)
                changed = True
            elif st in ("ok", "rejected", "timeout") and now - ts > 2.5:
                self._sol[c] = ("idle", 0.0)
                changed = True
        if changed:
            self.solenoidChanged.emit()
        if self._dev is not None and self._status == "usb" and self._rx_t == 0.0 and now - self._opened_t > SILENT_WARN_S:
            self._set_error("%s is open but the ESP32 sends nothing - wrong port or wrong firmware?" % self._port_name)

    # ------------------------------------------------------------------------------------------ keyboard capture
    def install_on(self, window):
        """Install the global key capture on the QQuickWindow (call once after engine.load())."""
        self._window = window
        window.installEventFilter(self._filter)
        try:
            window.activeChanged.connect(lambda: None if window.isActive() else self.releaseAll())
        except Exception:
            pass

    def _typing(self):
        w = self._window
        try:
            it = w.activeFocusItem() if w is not None else None
            return it is not None and it.property("cursorPosition") is not None        # TextInput / TextEdit / TextField
        except Exception:
            return False

    def _on_key_event(self, ev, pressed):
        key = ev.key()
        mods = ev.modifiers()
        mk = MOTOR_KEYS.get(key)
        if mk is not None:
            if not pressed:
                if self._keys.get(mk):                  # always honour a release of a key we hold, even with a modifier
                    self.setKey(mk, False)
                    return True
                return False
            if self._status == "disconnected" or self._typing():
                return False
            if mods & (Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.AltModifier | Qt.KeyboardModifier.MetaModifier):
                return False                            # Ctrl+Up / Ctrl+Down belong to the horizon shortcuts
            if ev.isAutoRepeat():
                return True                             # swallow repeats: no packet, no focus navigation
            return self.setKey(mk, True) or (self._status != "disconnected")
        sk = SOLENOID_KEYS.get(key)
        if sk is not None and pressed:
            if self._status == "disconnected" or self._typing():
                return False
            if mods & (Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.AltModifier | Qt.KeyboardModifier.MetaModifier
                       | Qt.KeyboardModifier.KeypadModifier):
                return False
            if ev.isAutoRepeat():
                return True                             # one-shot: a held key fires once (old: ev.repeat filter)
            self.fireSolenoid(sk)
            return True
        return False

    # ----------------------------------------------------------------------------------- for the connections pop-up
    def health_check(self):
        """One check row for link_monitor.py (same dict shape as its _ok/_warn/_fail/_na helpers)."""
        note = ("Manual-control link: PC -> ESP32 (USB serial %d baud) -> LoRa 433 MHz -> STM32.  The ESP32 hand-shakes with the "
                "STM32 (HELLO/ACK) and sends a heartbeat every 2 s; the link is declared lost after 10 s of silence "
                "(then the boat does SAFE STOP)." % BAUD)
        if self._status == "disconnected":
            return dict(status="warn", chip="NO USB", note=note,
                        detail="no ESP32 serial port open" + ("  -  " + self._error if self._error else
                                                              "  -  plug in the ground ESP32 or press the LoRa pill to connect"))
        age = (time.monotonic() - self._rx_t) if self._rx_t else None
        if self._status == "usb":
            if age is None or age > SILENT_WARN_S:
                return dict(status="fail", chip="SILENT", note=note,
                            detail="%s open, but no data from the ESP32  -  wrong port / firmware?" % self._port_name)
            return dict(status="warn", chip="NO LORA", note=note,
                        detail="%s  -  ESP32 alive, waiting for the STM32 hand-shake (is the boat powered?)" % self._port_name)
        fb = ("  -  pots T %.0f%% B %.0f%% S %.0f%%" % self._fb) if self._fresh else ""
        return dict(status="ok", chip="LINKED", metric="LoRa", note=note,
                    detail="%s  -  link established %.0f s ago%s" % (self._port_name, time.monotonic() - self._link_t, fb))
