"""
lora_bridge.py  -  manual-control link of the TANDAV GCS:  PC --USB serial--> ESP32 --LoRa 433 MHz--> STM32.

Straight port of the OLD React teleop console (useSerialLink.ts, useKeyboardControls.ts, lib/protocol.ts) to PySide6,
so the NEW QML UI drives the boat exactly like the old one did.  The ESP32_LoRa_Ground.ino protocol is used byte for byte.

    ARROW UP / DOWN     throttle + / -            \
    ARROW LEFT / RIGHT  steer left / right         >  one packet on every press AND release (never on auto-repeat):
    SPACE               brake (hold)              /   "KEYS:U1D0L0R0S0\\n"   (all five flags in a fixed order)
    1 / 2 / 3 / 4       Engine / Mode / VTS up / VTS down - one-shot, "BTN:E\\n" "BTN:M\\n" "BTN:VU\\n" "BTN:VD\\n"

Safety rules (unchanged from the first version):
    * a key PRESS is only sent while the LoRa link is up (requireLoraForMotors), releases always go out;
    * window focus loss releases every key; link up / disconnect / quit send an idle packet.

NEW in this version  -  "Arduino-IDE-less" serial terminal (used by the SERIAL TERMINAL tab of the System pop-up):
    * every byte the ESP32 sends is shown raw (terminalLine signal: time, direction, text, hex, kind) - nothing is hidden,
      incomplete lines (no newline for 0.5 s) are shown too;
    * live "raw values": every KEY=VALUE pair found in the incoming lines (T=,B=,S=, HB:STM:VS=,HDG=,SPD=,LAT=,...) is kept
      in `rawValues` with its source, age and hit count;
    * port + baud rate can be chosen in the UI; the port you choose is PINNED (saved in QSettings) and re-opened
      automatically every 3 s whenever it is closed / unplugged / re-enumerated, so no Arduino IDE is needed to keep it up;
    * ALL serial ports are listed (not only the known ESP32 USB chips);
    * a port that is busy (Arduino IDE serial monitor, PuTTY, ...) gives a clear message instead of a silent "not connected";
    * resetEsp32()  = the EN pulse the Arduino IDE does (RTS), also done once automatically when the port is open but silent;
    * terminal send with line ending none / NL / CR / CR+NL;
    * motorEnabled: the QML sets it to False while the terminal tab is on screen, so Up / Down / Space can never drive
      the boat while somebody is just scrolling the log.

What QML sees (context property `loraBridge`, set in launch_qml.py):
    status            "disconnected" | "usb" | "lora"
    usbConnected / loraLinked / portName / error / baudRate / pinnedPort / autoConnect / autoResetWhenSilent / motorEnabled
    ports             [{name, description, vid, pid, likely}]   (all ports)
    keys              {Up, Down, Left, Right, Space: bool}
    solenoidStates    {E, M, VU, VD, AUTO, MANUAL: "idle"|"pending"|"ok"|"rejected"|"timeout"}
    throttlePct / brakePct / steeringPct / feedbackFresh
    rxBytes / txBytes / lastRxAge (s, -1 = never)  / rxRate (bytes per second)
    rawValues         [{k, v, src, age, hits}]
    slots             connectAuto() connectPort(name) connectPortBaud(name, baud) disconnectPort() refreshPorts() setKey(name, pressed)
                      releaseAll() fireSolenoid(ch) sendMode(auto) sendRaw(line) sendText(text, ending) resetEsp32() clearLog()
                      clearValues() forgetPinnedPort()
    signals           logLine(text, direction, kind)                       (parsed log, as before)
                      terminalLine(ts, direction, text, hex, kind)          (raw terminal: direction in/out/sys, kind info/heartbeat/key/btn/ack/warning/partial/terminal)
Python side:   install_on(window)  health_check()  shutdown()  attach_device(QIODevice)   (the last one is for tests)
"""
import os
import re
import time

from PySide6.QtCore import QEvent, QIODevice, QObject, Property, QSettings, Qt, QTimer, Signal, Slot
from PySide6.QtSerialPort import QSerialPort, QSerialPortInfo

DEFAULT_BAUD = int(os.environ.get("TANDAV_LORA_BAUD", "115200"))
BAUDS = (9600, 19200, 38400, 57600, 74880, 115200, 230400, 460800, 921600)
PORT_OVERRIDE = os.environ.get("TANDAV_LORA_PORT", "").strip()          # e.g. COM5 or /dev/ttyUSB0
# USB-UART bridges used on ESP32 boards: Silicon Labs CP210x, WCH CH340/CH9102, FTDI, Prolific, Espressif native USB
KNOWN_VIDS = {0x10C4, 0x1A86, 0x0403, 0x067B, 0x303A, 0x2341, 0x2A03, 0x1B4F}
FEEDBACK_FRESH_S = 2.0
SILENT_WARN_S = 6.0
PARTIAL_FLUSH_S = 0.5
SETTINGS_ORG = "Ci4"
SETTINGS_APP = "TandavGCS"

KEY_NAMES = ("Up", "Down", "Left", "Right", "Space")
IDLE_PACKET = "KEYS:U0D0L0R0S0"
SOLENOID_CHANNELS = ("E", "M", "VU", "VD")
SOLENOID_LABELS = {"E": "Engine", "M": "Mode", "VU": "VTS Up", "VD": "VTS Down", "AUTO": "Auto", "MANUAL": "Manual"}
LINE_ENDINGS = {"none": "", "nl": "\n", "cr": "\r", "crlf": "\r\n"}

_K = Qt.Key
MOTOR_KEYS = {_K.Key_Up.value: "Up", _K.Key_Down.value: "Down", _K.Key_Left.value: "Left",
              _K.Key_Right.value: "Right", _K.Key_Space.value: "Space"}
SOLENOID_KEYS = {_K.Key_1.value: "E", _K.Key_2.value: "M", _K.Key_3.value: "VU", _K.Key_4.value: "VD"}

_FB_RE = re.compile(r"T=(-?[\d.]+),B=(-?[\d.]+),S=(-?[\d.]+)")
_VAL_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^,\s;]*)")


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

    if line in ("Link established with STM32.", "*** LINK ESTABLISHED ***"):
        out.update(kind="info", link_up=True)
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


def parse_values(line):
    """All KEY=VALUE pairs of one line -> (source, [(key, value), ...]).  source = the label in front of the first pair
    ("HB:STM", "STM_ACK", ...), numeric tokens (sequence numbers) are skipped."""
    pairs = _VAL_RE.findall(line)
    if not pairs:
        return "", []
    first = _VAL_RE.search(line)
    head = line[:first.start()]
    toks = [t for t in re.split(r"[:\s]+", head) if t and not re.fullmatch(r"-?[\d.]+", t) and t not in ("RX", "TX", "<-", "->")]
    return ":".join(toks[:2]), pairs


def _hex(b):
    return " ".join("%02X" % x for x in b)


def _ts():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + ".%03d" % int((t % 1) * 1000)


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
    baudChanged = Signal()
    pinnedChanged = Signal()
    statsChanged = Signal()
    rawValuesChanged = Signal()
    logLine = Signal(str, str, str)                  # text, direction (in/out/sys), kind
    terminalLine = Signal(str, str, str, str, str)   # time, direction (in/out/sys), text, hex, kind
    solenoidAcked = Signal(str, str)                 # channel, "ok" | "rejected"

    def __init__(self, parent=None):
        super().__init__(parent)
        self._dev = None
        self._status = "disconnected"
        self._port_name = ""
        self._error = ""
        self._ports = []
        self._buf = bytearray()
        self._buf_t = 0.0
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
        self._motor_enabled = True
        self._auto_reset = True
        self._auto_reset_done = False
        self._window = None
        self._filter = _KeyFilter(self)
        self._rx_bytes = 0
        self._tx_bytes = 0
        self._rate_bytes = 0
        self._rate_t = time.monotonic()
        self._rx_rate = 0.0
        self._values = {}                            # key -> [value, src, t, hits]
        self._vals_dirty = False
        self._vals_emit_t = 0.0
        self._last_open_err = ""

        s = QSettings(SETTINGS_ORG, SETTINGS_APP)
        try:
            self._baud = int(s.value("lora/baud", DEFAULT_BAUD))
        except Exception:
            self._baud = DEFAULT_BAUD
        self._pinned = str(s.value("lora/pinnedPort", "") or "")

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

    def _get_motor(self): return self._motor_enabled
    def _set_motor(self, v):
        v = bool(v)
        if v != self._motor_enabled:
            self._motor_enabled = v
            if not v:
                self.releaseAll()                    # never leave a key latched when the keys get disabled
            self.optionsChanged.emit()
    motorEnabled = Property(bool, _get_motor, _set_motor, notify=optionsChanged)

    def _get_ar(self): return self._auto_reset
    def _set_ar(self, v):
        if bool(v) != self._auto_reset:
            self._auto_reset = bool(v)
            self.optionsChanged.emit()
    autoResetWhenSilent = Property(bool, _get_ar, _set_ar, notify=optionsChanged)

    def _get_baud(self): return self._baud
    def _set_baud(self, v):
        try:
            v = int(v)
        except Exception:
            return
        if v <= 0 or v == self._baud:
            return
        self._baud = v
        QSettings(SETTINGS_ORG, SETTINGS_APP).setValue("lora/baud", v)
        self.baudChanged.emit()
        if isinstance(self._dev, QSerialPort):                  # live change, like the Arduino IDE dropdown
            self._dev.setBaudRate(v)
            self._log("Baud rate set to %d." % v, "sys", "info")
    baudRate = Property(int, _get_baud, _set_baud, notify=baudChanged)

    def _get_bauds(self): return list(BAUDS)
    baudRates = Property("QVariantList", _get_bauds, constant=True)

    def _get_pinned(self): return self._pinned
    pinnedPort = Property(str, _get_pinned, notify=pinnedChanged)

    def _get_rxb(self): return self._rx_bytes
    rxBytes = Property(int, _get_rxb, notify=statsChanged)

    def _get_txb(self): return self._tx_bytes
    txBytes = Property(int, _get_txb, notify=statsChanged)

    def _get_rate(self): return self._rx_rate
    rxRate = Property(float, _get_rate, notify=statsChanged)

    def _get_age(self): return (time.monotonic() - self._rx_t) if self._rx_t else -1.0
    lastRxAge = Property(float, _get_age, notify=statsChanged)

    def _get_vals(self):
        now = time.monotonic()
        return [{"k": k, "v": v[0], "src": v[1], "age": round(now - v[2], 2), "hits": v[3]} for k, v in self._values.items()]
    rawValues = Property("QVariantList", _get_vals, notify=rawValuesChanged)

    # ---------------------------------------------------------------------------------------------------- helpers
    def _log(self, text, direction, kind, raw=None):
        self.logLine.emit(text, direction, kind)
        data = raw if raw is not None else text.encode("utf-8", "replace")
        self.terminalLine.emit(_ts(), direction, text, _hex(data), kind)

    def _set_status(self, s):
        if s != self._status:
            self._status = s
            self.statusChanged.emit()

    def _set_error(self, e):
        if e != self._error:
            self._error = e
            self.errorChanged.emit()

    def _write_bytes(self, data, text, kind):
        d = self._dev
        if d is None or not d.isOpen():
            return False
        n = d.write(data)
        if n > 0:
            self._tx_bytes += n
            self._log(text, "out", kind, raw=bytes(data))
            return True
        return False

    def _write_line(self, text, kind):
        return self._write_bytes((text + "\n").encode("ascii", "ignore"), text, kind)

    # ------------------------------------------------------------------------------------------------ port handling
    @Slot()
    def refreshPorts(self):
        res = []
        for i in QSerialPortInfo.availablePorts():
            res.append({"name": i.portName(), "description": i.description() or i.manufacturer() or "serial port",
                        "vid": i.vendorIdentifier() if i.hasVendorIdentifier() else 0,
                        "pid": i.productIdentifier() if i.hasProductIdentifier() else 0,
                        "likely": bool(i.hasVendorIdentifier() and i.vendorIdentifier() in KNOWN_VIDS) or any(k in (i.description() or i.manufacturer() or "").lower() for k in ("cp210", "ch34", "ftdi", "espressif", "uart", "usb-serial", "arduino"))})
        res.sort(key=lambda p: (not p["likely"], p["name"]))
        if res != self._ports:
            self._ports = res
            self.portsChanged.emit()

    def _candidates(self):
        """Order: env override, the port the user pinned, then every port that looks like an ESP32 USB-UART chip."""
        names = [p["name"] for p in self._ports]
        out = []
        if PORT_OVERRIDE:
            out.append(PORT_OVERRIDE)
        if self._pinned and self._pinned in names and self._pinned not in out:
            out.append(self._pinned)
        for p in self._ports:
            if p["likely"] and "bluetooth" not in p["description"].lower() and p["name"] not in out:
                out.append(p["name"])
        if not out:
            for p in self._ports:
                if "bluetooth" not in p["description"].lower() and p["name"] not in out:
                    out.append(p["name"])
        return out

    @Slot()
    def connectAuto(self):
        """Connect to $TANDAV_LORA_PORT, else the pinned port, else the first USB-UART bridge that looks like an ESP32 board."""
        self._user_disconnected = False
        self.refreshPorts()
        c = self._candidates()
        if not c:
            self._set_error("No ESP32 USB-serial port found - plug in the ground ESP32, or pick the port in the SERIAL TERMINAL tab.")
            return
        self._open(c[0], pin=False)

    @Slot(str)
    def connectPort(self, name):
        """The user picked this port: open it and PIN it (re-opened automatically whenever it drops)."""
        self._user_disconnected = False
        self._open(name, pin=True)

    @Slot(str, int)
    def connectPortBaud(self, name, baud):
        self._set_baud(baud)
        self.connectPort(name)

    @Slot()
    def forgetPinnedPort(self):
        if self._pinned:
            self._pinned = ""
            QSettings(SETTINGS_ORG, SETTINGS_APP).remove("lora/pinnedPort")
            self.pinnedChanged.emit()

    def _busy_hint(self, name, err):
        low = err.lower()
        if any(w in low for w in ("denied", "busy", "in use", "permission", "access")):
            if os.name == "nt":
                return "%s is in use by another program (Arduino IDE serial monitor / uploader, PuTTY ...). Close it - this terminal replaces it." % name
            return "%s cannot be opened (%s). Another program may hold it (Arduino IDE / minicom), or add your user to the 'dialout' group." % (name, err)
        return "Cannot open %s: %s" % (name, err)

    def _open(self, name, pin):
        if self._dev is not None:
            self.disconnectPort(user=False)
        sp = QSerialPort(name, self)
        sp.setBaudRate(self._baud)
        sp.setDataBits(QSerialPort.DataBits.Data8)
        sp.setParity(QSerialPort.Parity.NoParity)
        sp.setStopBits(QSerialPort.StopBits.OneStop)
        sp.setFlowControl(QSerialPort.FlowControl.NoFlowControl)
        if not sp.open(QIODevice.OpenModeFlag.ReadWrite):
            msg = self._busy_hint(name, sp.errorString())
            self._set_error(msg)
            if msg != self._last_open_err:                  # the 3 s auto-retry must not spam the terminal
                self._last_open_err = msg
                self._log(msg, "sys", "warning")
            sp.deleteLater()
            return
        self._last_open_err = ""
        sp.setDataTerminalReady(False)                  # keep DTR/RTS idle: ESP32 runs, no bootloader pulse
        sp.setRequestToSend(False)
        sp.errorOccurred.connect(self._on_serial_error)
        if pin and name != self._pinned:
            self._pinned = name
            QSettings(SETTINGS_ORG, SETTINGS_APP).setValue("lora/pinnedPort", name)
            self.pinnedChanged.emit()
        self._attach(sp, name)
        self._log("Connected to %s (%d baud, 8N1)." % (name, self._baud), "sys", "info")

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
        self._auto_reset_done = False
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
        self._buf.clear()
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
            self._set_error("Serial device disconnected - will reconnect automatically.")
            self.disconnectPort(user=False)

    def _on_serial_error(self, err):
        if err == QSerialPort.SerialPortError.NoError or err == QSerialPort.SerialPortError.TimeoutError:
            return
        if err in (QSerialPort.SerialPortError.ResourceError, QSerialPort.SerialPortError.DeviceNotFoundError,
                   QSerialPort.SerialPortError.PermissionError):
            self._set_error("Serial error: %s - will reconnect automatically." % (self._dev.errorString() if self._dev else err))
            self._log("Serial error: %s" % err, "sys", "warning")
            self.disconnectPort(user=False)

    def _auto_try(self):
        if self._dev is not None:
            return
        self.refreshPorts()
        if self._auto and not self._user_disconnected:
            c = self._candidates()
            if c:
                self._open(c[0], pin=False)

    # ------------------------------------------------------------------------------------------------- receive path
    def _on_ready(self):
        dev = self._dev
        if dev is None:
            return
        chunk = bytes(dev.readAll())
        if not chunk:
            return
        self._buf += chunk
        self._rx_bytes += len(chunk)
        self._rate_bytes += len(chunk)
        self._rx_t = time.monotonic()
        while True:
            i = self._buf.find(b"\n")
            if i < 0:
                break
            rawb = bytes(self._buf[:i]).rstrip(b"\r")
            del self._buf[:i + 1]
            if rawb:
                self._handle_line(rawb.decode("utf-8", "replace"), rawb)
        self._buf_t = time.monotonic() if self._buf else 0.0
        if len(self._buf) > 4096:                       # never-ending junk without a newline
            self._flush_partial()

    def _flush_partial(self):
        if not self._buf:
            return
        rawb = bytes(self._buf)
        self._buf.clear()
        self._buf_t = 0.0
        txt = rawb.decode("utf-8", "replace").rstrip("\r")
        if txt:
            self._log(txt, "in", "partial", raw=rawb)    # shown, but not parsed: it is not a complete line

    def _note_values(self, text):
        src, pairs = parse_values(text)
        if not pairs:
            return
        now = time.monotonic()
        for k, v in pairs:
            cur = self._values.get(k)
            if cur is None:
                self._values[k] = [v, src, now, 1]
            else:
                cur[0], cur[1], cur[2], cur[3] = v, src or cur[1], now, cur[3] + 1
        self._vals_dirty = True

    def _handle_line(self, raw, rawb=None):
        p = parse_line(raw)
        self._log(raw, "in", p["kind"], raw=rawb)
        self._note_values(raw)
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
        if pressed and (not self._motor_enabled or (self._require_lora and self._status != "lora")):
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
        if channel not in SOLENOID_CHANNELS or self._status != "lora" or not self._motor_enabled:
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

    @Slot(str, str, result=bool)
    def sendText(self, text, ending="nl"):
        """Serial-monitor style send: the text exactly as typed + the chosen line ending (none / nl / cr / crlf)."""
        if self._status == "disconnected":
            self._log("Not connected - nothing sent.", "sys", "warning")
            return False
        end = LINE_ENDINGS.get(ending, "\n")
        data = (text + end).encode("utf-8", "replace")
        if not data:
            return False
        return self._write_bytes(data, text if text else "<line ending>", "terminal")

    @Slot(result=bool)
    def resetEsp32(self):
        """Hardware reset of an ESP32 dev board over USB: pulse EN low through RTS (what the Arduino IDE does)."""
        d = self._dev
        if not isinstance(d, QSerialPort) or not d.isOpen():
            self._log("Reset needs an open USB serial port.", "sys", "warning")
            return False
        d.setDataTerminalReady(False)                   # IO0 high = normal boot, not the bootloader
        d.setRequestToSend(True)                        # EN low
        QTimer.singleShot(150, lambda: self._release_reset(d))
        self._log("ESP32 reset pulse sent (RTS/EN).", "sys", "info")
        if self._status == "lora":
            self._link_lost("ESP32 reset")
        self._rx_t = 0.0
        self._opened_t = time.monotonic()
        return True

    def _release_reset(self, d):
        try:
            if self._dev is d and d.isOpen():
                d.setRequestToSend(False)
        except Exception:
            pass

    @Slot()
    def clearLog(self):
        self._log("", "sys", "clear")

    @Slot()
    def clearValues(self):
        self._values.clear()
        self._vals_dirty = True

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
        if self._buf and self._buf_t and now - self._buf_t > PARTIAL_FLUSH_S:
            self._flush_partial()
        # byte rate + stats (4 Hz)
        dt = now - self._rate_t
        if dt >= 0.9:
            self._rx_rate = self._rate_bytes / dt
            self._rate_bytes = 0
            self._rate_t = now
        self.statsChanged.emit()
        if self._vals_dirty or (self._values and now - self._vals_emit_t > 1.0):
            self._vals_dirty = False
            self._vals_emit_t = now
            self.rawValuesChanged.emit()
        # open but silent: one automatic Arduino-style reset per connection, then a clear message
        if self._dev is not None and self._status == "usb" and self._rx_t == 0.0 and now - self._opened_t > SILENT_WARN_S:
            if self._auto_reset and not self._auto_reset_done and isinstance(self._dev, QSerialPort):
                self._auto_reset_done = True
                self._log("%s is open but silent for %.0f s - resetting the ESP32 once." % (self._port_name, SILENT_WARN_S), "sys", "warning")
                self.resetEsp32()
            elif self._auto_reset_done or not self._auto_reset:
                self._set_error("%s is open but the ESP32 sends nothing - wrong port, wrong baud (%d) or wrong firmware?" % (self._port_name, self._baud))

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
            if self._status == "disconnected" or self._typing() or not self._motor_enabled:
                return False
            if mods & (Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.AltModifier | Qt.KeyboardModifier.MetaModifier):
                return False                            # Ctrl+Up / Ctrl+Down belong to the horizon shortcuts
            if ev.isAutoRepeat():
                return True                             # swallow repeats: no packet, no focus navigation
            return self.setKey(mk, True) or (self._status != "disconnected")
        sk = SOLENOID_KEYS.get(key)
        if sk is not None and pressed:
            if self._status == "disconnected" or self._typing() or not self._motor_enabled:
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
                "(then the boat does SAFE STOP).  The SERIAL TERMINAL tab shows every raw byte." % self._baud)
        if self._status == "disconnected":
            return dict(status="warn", chip="NO USB", note=note,
                        detail="no ESP32 serial port open" + ("  -  " + self._error if self._error else
                                                              "  -  pick the port in the SERIAL TERMINAL tab"))
        age = (time.monotonic() - self._rx_t) if self._rx_t else None
        if self._status == "usb":
            if age is None or age > SILENT_WARN_S:
                return dict(status="fail", chip="SILENT", note=note,
                            detail="%s open at %d baud, but no data from the ESP32  -  wrong port / baud / firmware?" % (self._port_name, self._baud))
            return dict(status="warn", chip="NO LORA", note=note,
                        detail="%s  -  ESP32 alive, waiting for the STM32 hand-shake (is the boat powered?)" % self._port_name)
        fb = ("  -  pots T %.0f%% B %.0f%% S %.0f%%" % self._fb) if self._fresh else ""
        return dict(status="ok", chip="LINKED", metric="LoRa", note=note,
                    detail="%s  -  link established %.0f s ago%s" % (self._port_name, time.monotonic() - self._link_t, fb))
