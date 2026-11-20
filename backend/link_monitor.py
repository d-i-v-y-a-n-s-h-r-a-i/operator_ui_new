"""
link_monitor.py  -  health of every connection of the TANDAV system, for the "SYSTEM CONNECTIONS" pop-up.

Put it next to mission_map_backend.py (backend/link_monitor.py) and hook it up in launch_qml.py (see INTEGRATION.md).
QML side: ConnectionsPanel.qml reads  linkMonitor.checks / running / live  and calls  runAll() / setPanelOpen().

Two kinds of checks
  PASSIVE - nothing is sent.  The monitor listens to what launch_qml.py already receives (telemetry, CAN, autonomy
            status, video frames, GNSS) and judges it by age / rate / loss.  Cheap, evaluated once a second, only while
            the pop-up is open.
  ACTIVE  - short probes run in worker threads, only when you press RUN ALL CHECKS (and every 8 s while the pop-up is
            open): ping, TCP connect.  A probe never talks to a control port: the Jetson<->STM32 TCP :8080 link is NOT
            probed (the Jetson server may accept a single client - a probe could steal the slot).

What the GCS can and cannot know (be honest in the UI)
  * LoRa 433 MHz: the GCS has no LoRa radio.  The STM32 reports its LoRa link quality byte inside the telemetry frame -
    that is what is shown.
  * UDP uplink (:9000): UDP has no acknowledgement.  We only check where the commands go versus where telemetry comes from.
  * Jetson <-> STM32 guidance link: inferred from AUTONOMY_STATUS / THREATS packets reaching the GCS.
"""
import os
import re
import socket
import subprocess
import sys
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor

from PySide6.QtCore import QObject, QTimer, Property, Signal, Slot

try:
    from PySide6.QtNetwork import QNetworkInterface
except Exception:                                   # pragma: no cover
    QNetworkInterface = None

# ------------------------------------------------------------------------------------------------ configuration
JETSON_HOST = os.environ.get("TANDAV_JETSON_HOST", "192.168.1.200")      # NOTE: UVS_Ip_Details.txt says .239 - set the real one
TELEMETRY_PORT = 9001
UPLINK_PORT = 9000
VIDEO_PORT = 5000
GPSD = ("127.0.0.1", 2947)
GNSS_SERIAL = "/dev/ttyACM0"
BOAT_LAN_PREFIX = "192.168.1."

# marine LAN devices (UVS_Ip_Details.txt).  (id, name, ip, tcp_port or None, label of what is tested)
#   tcp_port set  -> TCP connect (answer or "connection refused" both prove the host is alive)
#   tcp_port None -> ping only (the device speaks UDP)
# Left out on purpose: PTZ / environmental suite (192.168.1.200) - the same IP is used for the Jetson in the system
# architecture document, and the auxiliary camera (192.168.1.201) - same IP as the Oculus sonar.  Fix the IP plan first.
LAN_DEVICES = [
    ("d_cam1",   "Main IP camera",      "192.168.1.205", 554,   "RTSP 554"),
    ("d_cam2",   "Wide-angle camera",   "192.168.1.167", 554,   "RTSP 554"),
    ("d_sonar",  "Oculus sonar",        "192.168.1.201", None,  "ping (UDP 52100)"),
    ("d_mcu",    "Hardware controller", "192.168.1.20",  None,  "ping (UDP 25000)"),
    ("d_bms",    "Battery BMS",         "192.168.1.208", None,  "ping"),
    ("d_gnss",   "GNSS receiver",       "192.168.1.215", None,  "ping"),
    ("d_metal",  "Metal detector",      "192.168.1.62",  None,  "ping"),
    ("d_dec",    "Video decoder",       "192.168.1.27",  None,  "ping"),
]

# thresholds
TLM_LIVE_S = 1.0          # launch_qml.py switches to simulated values after 1 s without a packet
TLM_STALE_S = 0.5
LOSS_WARN_PCT = 2.0
CAN_WARN_S = 2.0
CAN_FAIL_S = 10.0
AUTONOMY_FRESH_S = 5.0
VIDEO_MIN_FPS = 10.0
GNSS_FRESH_S = 5.0


def _ok(**k):    return dict(status="ok", **k)
def _warn(**k):  return dict(status="warn", **k)
def _fail(**k):  return dict(status="fail", **k)
def _na(**k):    return dict(status="na", **k)


def _is_loopback(host):
    return host in ("localhost", "::1") or str(host).startswith("127.")


# ------------------------------------------------------------------------------------------------ active probes
def _ping(host, timeout=1.0):
    """-> (reachable, ms)  or None when no ping program exists on this machine"""
    if sys.platform.startswith("win"):
        cmd = ["ping", "-n", "1", "-w", str(int(timeout * 1000)), host]
        kw = {"creationflags": 0x08000000}                           # CREATE_NO_WINDOW
    else:
        cmd = ["ping", "-c", "1", "-W", str(max(1, int(round(timeout)))), host]
        kw = {}
    t0 = time.monotonic()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 2.0, **kw)
    except FileNotFoundError:
        return None
    except Exception:
        return (False, 0.0)
    if p.returncode != 0:
        return (False, 0.0)
    m = re.search(r"time[=<]\s*([\d.]+)\s*ms", p.stdout or "")
    return (True, float(m.group(1)) if m else (time.monotonic() - t0) * 1000.0)


def _tcp(host, port, timeout=1.0):
    """-> ('open'|'refused'|'timeout'|'error', ms)"""
    t0 = time.monotonic()
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return ("open", (time.monotonic() - t0) * 1000.0)
    except ConnectionRefusedError:
        return ("refused", (time.monotonic() - t0) * 1000.0)
    except socket.timeout:
        return ("timeout", timeout * 1000.0)
    except OSError:
        return ("error", (time.monotonic() - t0) * 1000.0)


def _fmt_ms(ms):
    return ("%.0f ms" % ms) if ms >= 1.0 else "<1 ms"


def probe_host(ip, port=None, label="ping"):
    """one device on the LAN -> check fields"""
    if port:
        st, ms = _tcp(ip, port)
        if st == "open":
            return _ok(detail="%s  -  %s  -  %s" % (ip, label, _fmt_ms(ms)), metric=_fmt_ms(ms))
        if st == "refused":
            return _warn(detail="%s  -  host answers, %s closed" % (ip, label), chip="PORT CLOSED",
                         note="The device is alive (it refused the connection) but the service is not listening.")
        r = _ping(ip)
        if r and r[0]:
            return _warn(detail="%s  -  pings, %s does not answer" % (ip, label), chip="NO SERVICE", metric=_fmt_ms(r[1]))
        return _fail(detail="%s  -  no reply" % ip, chip="OFFLINE")
    r = _ping(ip)
    if r is None:
        st, ms = _tcp(ip, 22, 0.8)                                    # no ping program: any TCP answer proves life
        if st in ("open", "refused"):
            return _ok(detail="%s  -  reachable (tcp)  -  %s" % (ip, _fmt_ms(ms)), metric=_fmt_ms(ms))
        return _na(detail="%s  -  cannot test (no ping program)" % ip)
    if r[0]:
        return _ok(detail="%s  -  %s  -  %s" % (ip, label, _fmt_ms(r[1])), metric=_fmt_ms(r[1]))
    return _fail(detail="%s  -  no reply" % ip, chip="OFFLINE",
                 note="No ICMP answer within 1 s. Some devices block ping - if the device works, ignore this.")


class LinkMonitor(QObject):
    checksChanged = Signal()
    runningChanged = Signal()
    liveChanged = Signal()
    _result = Signal(str, object)                    # worker thread -> GUI thread

    def __init__(self, parent=None, log_path=None):
        super().__init__(parent)
        self._vs = None
        self._mm = None
        self._tm = None
        self._lora = None
        self._uplink = None                          # (host, port) override; default = telemetry_mgr.uplink_addr
        self._log_path = log_path

        self._t = {}                                 # kind -> monotonic time of last packet
        self._can_t = {}                             # can id -> monotonic time
        self._bin_times = deque(maxlen=600)
        self._seq_last = None
        self._lost = deque(maxlen=600)               # (t, packets lost)
        self._src = None                             # IP the telemetry comes from
        self._video_sink = None
        self._video_times = deque(maxlen=400)
        self._video_size = (0, 0)

        self._active = {}                            # id -> last probe result
        self._on_lan = None
        self._lan_ip = ""
        self._panel_open = False
        self._running = False
        self._pending = 0
        self._live = False
        self._checks = []
        self._pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="linkmon")

        self._result.connect(self._on_result)
        self._tick_timer = QTimer(self)
        self._tick_timer.setInterval(1000)
        self._tick_timer.timeout.connect(self._tick)
        self._tick_timer.start()
        self._auto_timer = QTimer(self)
        self._auto_timer.setInterval(8000)
        self._auto_timer.timeout.connect(self._auto)

    # ================================================================================== wiring
    def attach(self, vessel_state, mission_map=None, telemetry_mgr=None, uplink=None):
        self._vs, self._mm, self._tm = vessel_state, mission_map, telemetry_mgr
        if uplink:
            self._uplink = tuple(uplink)
        try:
            vessel_state.videoSinkChanged.connect(self._on_sink_changed)
            self._on_sink_changed()
        except Exception:
            pass

    def attach_lora(self, bridge):
        self._lora = bridge
        try:
            bridge.statusChanged.connect(self._rebuild_if_open)
            bridge.feedbackChanged.connect(self._rebuild_if_open)
        except Exception:
            pass

    def _rebuild_if_open(self):
        if self._panel_open:
            self._rebuild()

    def note_telemetry(self, kind, src=None, seq=None):
        """kind: 'bin' (77-byte frame) | 'json' (telemetry JSON) | 'autonomy' (AUTONOMY_STATUS) | 'threats'"""
        now = time.monotonic()
        if kind in ("bin", "json"):
            self._t["tlm"] = now
            if src:
                self._src = src
            if kind == "bin":
                self._bin_times.append(now)
                if seq is not None:
                    if self._seq_last is not None and 0 < (seq - self._seq_last) < 100000:
                        gap = seq - self._seq_last - 1
                        if gap > 0:
                            self._lost.append((now, gap))
                    self._seq_last = seq
        else:
            self._t[kind] = now

    def note_can(self, can_id):
        self._can_t[int(can_id)] = time.monotonic()

    def _on_sink_changed(self):
        sink = getattr(self._vs, "videoSink", None) if self._vs is not None else None
        if sink is self._video_sink:
            return
        self._video_sink = sink
        self._video_times.clear()
        if sink is not None:
            try:
                sink.videoFrameChanged.connect(self._on_frame)
            except Exception as e:
                print("[linkMonitor] cannot watch the video sink:", e)

    @Slot()
    def _on_frame(self):
        n = len(self._video_times)
        self._video_times.append(time.monotonic())
        if n % 60 == 0 or self._video_size == (0, 0):
            try:
                if self._video_sink is not None:
                    f = self._video_sink.videoFrame()
                    if f is not None and f.isValid():
                        self._video_size = (int(f.width()), int(f.height()))
            except Exception:
                pass

    def shutdown(self):
        self._tick_timer.stop()
        self._auto_timer.stop()
        self._pool.shutdown(wait=False, cancel_futures=True)

    # ================================================================================== QML interface
    @Property("QVariantList", notify=checksChanged)
    def checks(self):
        return self._checks

    @Property(bool, notify=runningChanged)
    def running(self):
        return self._running

    @Property(bool, notify=liveChanged)
    def live(self):
        """True while real telemetry arrives (False = the UI is showing simulated values)"""
        return self._live

    @Slot(bool)
    def setPanelOpen(self, v):
        self._panel_open = bool(v)
        if v:
            self._auto_timer.start()
            self._rebuild()
        else:
            self._auto_timer.stop()

    @Slot()
    def runAll(self):
        if self._running:
            return
        self._refresh_nic()
        jobs = [("jetson", self._job_jetson), ("gpsd", self._job_gpsd)]
        for (cid, name, ip, port, label) in LAN_DEVICES:
            jobs.append((cid, (lambda ip=ip, port=port, label=label: self._job_device(ip, port, label))))
        self._running = True
        self.runningChanged.emit()
        self._pending = len(jobs)
        for cid, _ in jobs:
            self._active[cid] = dict(status="checking", detail="checking...")
        self._rebuild()
        for cid, fn in jobs:
            self._pool.submit(self._run_job, cid, fn)

    def _auto(self):
        if self._panel_open and not self._running:
            self.runAll()

    # ================================================================================== workers
    def _run_job(self, cid, fn):
        try:
            res = fn()
        except Exception as e:                       # a probe must never take the UI down
            res = _na(detail="probe error: %s" % e)
        self._result.emit(cid, res)

    @Slot(str, object)
    def _on_result(self, cid, res):
        self._active[cid] = res
        self._pending -= 1
        if self._pending <= 0:
            self._running = False
            self.runningChanged.emit()
            self._write_log()
        self._rebuild()

    def _job_jetson(self):
        host = JETSON_HOST
        if host.startswith(BOAT_LAN_PREFIX) and not self._on_lan:
            return _na(detail="%s  -  GCS is not on the boat LAN" % host, chip="NOT ON LAN")
        r = _ping(host)
        if r is None:
            st, ms = _tcp(host, 22, 1.0)
            if st in ("open", "refused"):
                return _ok(detail="%s  -  reachable  -  %s" % (host, _fmt_ms(ms)), metric=_fmt_ms(ms))
            return _fail(detail="%s  -  no reply" % host, chip="OFFLINE")
        if r[0]:
            return _ok(detail="%s  -  ping %s" % (host, _fmt_ms(r[1])), metric=_fmt_ms(r[1]),
                       note="ICMP ping only. The Jetson <-> STM32 TCP :8080 link is deliberately not probed.")
        st, ms = _tcp(host, 22, 1.0)
        if st in ("open", "refused"):
            return _warn(detail="%s  -  no ping reply, but reachable (ssh port)" % host, chip="NO PING", metric=_fmt_ms(ms))
        return _fail(detail="%s  -  no reply (ping and ssh)" % host, chip="OFFLINE",
                     note="Check cable / switch / Jetson power and the IP in link_monitor.py (JETSON_HOST).")

    def _job_gpsd(self):
        st, ms = _tcp(GPSD[0], GPSD[1], 1.0)
        if st == "open":
            return _ok(detail="%s:%d  -  connected  -  %s" % (GPSD[0], GPSD[1], _fmt_ms(ms)), metric=_fmt_ms(ms))
        return _warn(detail="%s:%d  -  not running" % GPSD, chip="NOT RUNNING",
                     note="Start gpsd (sudo systemctl start gpsd) or use another GNSS source (serial / socket / telemetry).")

    def _job_device(self, ip, port, label):
        if ip.startswith(BOAT_LAN_PREFIX) and not self._on_lan:
            return _na(detail="%s  -  GCS is not on the boat LAN" % ip)
        return probe_host(ip, port, label)

    # ================================================================================== passive evaluation
    def _tick(self):
        live = self._eval_live()
        if live != self._live:
            self._live = live
            self.liveChanged.emit()
        if self._panel_open:
            self._rebuild()

    def _eval_live(self):
        t = self._t.get("tlm")
        return t is not None and (time.monotonic() - t) <= TLM_LIVE_S

    def _refresh_nic(self):
        on, ip, name = False, "", ""
        if QNetworkInterface is not None:
            try:
                for itf in QNetworkInterface.allInterfaces():
                    fl = itf.flags()
                    if not (fl & QNetworkInterface.InterfaceFlag.IsUp) or (fl & QNetworkInterface.InterfaceFlag.IsLoopBack):
                        continue
                    for e in itf.addressEntries():
                        a = e.ip().toString()
                        if a.startswith(BOAT_LAN_PREFIX):
                            on, ip, name = True, a, itf.humanReadableName()
            except Exception:
                pass
        self._on_lan, self._lan_ip, self._lan_if = on, ip, name

    def _tlm_age(self, now):
        t = self._t.get("tlm")
        return None if t is None else now - t

    def _rate_loss(self, now):
        ts = [x for x in self._bin_times if now - x <= 3.0]
        rate = len(ts) / 3.0
        lost = sum(n for (t, n) in self._lost if now - t <= 10.0)
        recv = sum(1 for x in self._bin_times if now - x <= 10.0)
        loss = (100.0 * lost / (lost + recv)) if (lost + recv) > 0 else 0.0
        return rate, loss

    def _vs_get(self, name, default=None):
        try:
            return getattr(self._vs, name)
        except Exception:
            return default

    # ---- one method per check; each returns a dict of check fields
    def _c_tlm(self, now, live):
        age = self._tlm_age(now)
        note = ("Binary 77-byte frames (magic TNDV) and telemetry JSON on UDP :%d. launch_qml.py shows SIMULATED values "
                "when nothing arrives for 1 s - this row tells you which one you are looking at." % TELEMETRY_PORT)
        if age is None:
            return _fail(detail="nothing received yet on UDP :%d  -  UI shows SIMULATED values" % TELEMETRY_PORT, chip="SIM", note=note)
        if age > TLM_LIVE_S:
            return _fail(detail="no packet for %.1f s  -  UI shows SIMULATED values" % age, chip="SIM", note=note)
        rate, loss = self._rate_loss(now)
        d = "UDP :%d  -  %.0f pkt/s  -  age %.2f s  -  loss %.1f %%" % (TELEMETRY_PORT, rate, age, loss)
        if loss > LOSS_WARN_PCT:
            return _warn(detail=d, chip="LOSS", metric="%.0f Hz" % rate, note=note)
        if age > TLM_STALE_S:
            return _warn(detail=d, chip="STALE", metric="%.0f Hz" % rate, note=note)
        return _ok(detail=d, chip="LIVE", metric="%.0f Hz" % rate, note=note)

    def _c_uplink(self, now, live):
        tgt = self._uplink or getattr(self._tm, "uplink_addr", None)
        note = "UDP has no acknowledgement, so delivery cannot be confirmed from the GCS. This only compares where commands go with where telemetry comes from."
        if not tgt:
            return _na(detail="uplink target unknown", note=note)
        host, port = tgt[0], tgt[1]
        d = "UDP to %s:%d  -  no ack channel" % (host, port)
        remote = live and self._src and not _is_loopback(self._src)
        if _is_loopback(host):
            if remote:
                return _fail(detail="commands go to %s:%d but the boat answers from %s  -  NOT reaching the boat" % (host, port, self._src),
                             chip="WRONG TARGET", note=note + " Fix: set the uplink address (TelemetryManager.uplink_addr) to the boat.")
            return _warn(detail="%s:%d is this computer  -  simulation target" % (host, port), chip="LOOPBACK", note=note)
        if live and self._src and self._src != host:
            return _warn(detail="%s  -  telemetry comes from %s" % (d, self._src), chip="MISMATCH", note=note)
        if not live:
            return _na(detail=d + "  -  no telemetry to compare with", note=note)
        return _ok(detail=d, note=note)

    def _c_lora(self, now, live):
        b = getattr(self, "_lora", None)
        if b is not None and getattr(b, "usbConnected", False):
            h = b.health_check()
            return {"ok": _ok, "warn": _warn, "fail": _fail}[h.pop("status")](**h)
        note = ("The GCS has no LoRa radio. The STM32 reports the LoRa link quality (0-100 %) inside the telemetry frame. "
                "Boat side: heartbeat lost after 5 s, SAFE STOP (throttle 0, brake 100, engine cut) after 10 s of silence.")
        if not live:
            return _na(detail="unknown  -  no live telemetry", chip="NO DATA", note=note)
        lq = int(self._vs_get("linkQuality", 0) or 0)
        mode = self._vs_get("mode", "")
        d = "link quality %d %%  -  mode %s" % (lq, mode)
        if lq >= 70:
            return _ok(detail=d, metric="%d %%" % lq, note=note)
        if lq >= 40:
            return _warn(detail=d, chip="WEAK", metric="%d %%" % lq, note=note)
        return _fail(detail=d, chip="POOR", metric="%d %%" % lq, note=note)

    def _c_autonomy(self, now, live):
        note = "Inferred: AUTONOMY_STATUS / THREATS packets from the Jetson reaching the GCS. The Jetson <-> STM32 TCP :8080 link itself is not visible from here."
        mode = self._vs_get("mode", "")
        if not live:
            return _na(detail="unknown  -  no live telemetry", chip="NO DATA", note=note)
        t = max([x for x in (self._t.get("autonomy"), self._t.get("threats")) if x] or [0])
        if t == 0:
            if mode == "AUTO":
                return _warn(detail="mode AUTO but no AUTONOMY_STATUS received", chip="NO STATUS", note=note)
            return _na(detail="idle  -  no autonomy status yet (mode %s)" % mode, note=note)
        age = now - t
        if age <= AUTONOMY_FRESH_S:
            return _ok(detail="autonomy status  -  age %.1f s  -  mode %s" % (age, mode), note=note)
        if mode == "AUTO":
            return _fail(detail="autonomy status stale  -  %.0f s  -  mode AUTO" % age, chip="STALE", note=note)
        return _na(detail="idle  -  last status %.0f s ago" % age, note=note)

    def _c_video(self, now, live):
        note = "Measured on the video sink inside the UI (frames per second and size). Source: Jetson H.265 RTP to UDP :%d." % VIDEO_PORT
        if self._video_sink is None:
            return _na(detail="no video sink attached", note=note)
        ts = [x for x in self._video_times if now - x <= 1.0]
        fps = float(len(ts))
        last = self._video_times[-1] if self._video_times else None
        if last is None or now - last > 3.0:
            return _fail(detail="no frames%s  -  RTP UDP :%d" % ("" if last is None else " for %.0f s" % (now - last), VIDEO_PORT), chip="NO VIDEO", note=note)
        w, h = self._video_size
        d = "%dx%d  -  %.0f fps  -  RTP UDP :%d" % (w, h, fps, VIDEO_PORT)
        if now - last > 1.0:
            return _warn(detail=d, chip="STALLED", metric="%.0f fps" % fps, note=note)
        if fps < VIDEO_MIN_FPS:
            return _warn(detail=d, chip="LOW FPS", metric="%.0f fps" % fps, note=note)
        return _ok(detail=d, chip="LIVE", metric="%.0f fps" % fps, note=note)

    def _c_can(self, cid, now, live, what, extra):
        note = "CAN frame 0x%X forwarded by vessel_daemon.py as a 17-byte UDP packet." % cid
        if not live:
            return _na(detail="unknown  -  no live telemetry", chip="NO DATA", note=note)
        t = self._can_t.get(cid)
        if t is None:
            return _warn(detail="no frames received yet", chip="NO FRAMES", note=note + " Engine off, or the daemon does not forward this frame.")
        age = now - t
        d = "%s  -  age %.1f s" % (extra(), age)
        if age <= CAN_WARN_S:
            return _ok(detail=d, note=note)
        if age <= CAN_FAIL_S:
            return _warn(detail=d, chip="STALE", note=note)
        return _fail(detail=d, chip="LOST", note=note)

    def _c_leak(self, now, live):
        note = "Bilge float switch (CAN 0x18FF) arrives as the leak flag of the binary telemetry frame."
        if not live:
            return _na(detail="unknown  -  no live telemetry", chip="NO DATA", note=note)
        if bool(self._vs_get("leakDetected", False)):
            return _fail(detail="WATER IN BILGE", chip="LEAK", note=note)
        return _ok(detail="bilge dry", chip="DRY", note=note)

    def _c_boat_gnss(self, now, live):
        note = "Position the boat's own GNSS puts into the telemetry frame."
        if not live:
            return _na(detail="unknown  -  no live telemetry", chip="NO DATA", note=note)
        lat, lon = float(self._vs_get("latitude", 0.0) or 0.0), float(self._vs_get("longitude", 0.0) or 0.0)
        if abs(lat) < 1e-6 and abs(lon) < 1e-6:
            return _warn(detail="telemetry position is 0, 0  -  no fix on the boat", chip="NO FIX", note=note)
        return _ok(detail="%.5f %s  %.5f %s" % (abs(lat), "N" if lat >= 0 else "S", abs(lon), "E" if lon >= 0 else "W"), note=note)

    def _c_gnss(self, now, live):
        note = "GCS-side position used for the mission map (gpsd / serial / socket / telemetry cascade in GnssSource.qml)."
        mm = self._mm
        if mm is None:
            return _na(detail="map backend not attached", note=note)
        g = getattr(mm, "_gnss", None) or {}
        fix = int(getattr(mm, "gnssFix", 0) or 0)
        t = g.get("t", 0.0)
        age = (time.time() - t) if t else None
        if fix >= 2 and age is not None:
            lat, lon = mm.gnssLat, mm.gnssLon
            d = "%s fix  -  %.5f %s  %.5f %s  -  age %.0f s" % ("3D" if fix >= 3 else "2D", abs(lat), "N" if lat >= 0 else "S", abs(lon), "E" if lon >= 0 else "W", age)
            if age > GNSS_FRESH_S:
                return _warn(detail=d, chip="STALE", note=note)
            return (_ok if fix >= 3 else _warn)(detail=d, chip="3D" if fix >= 3 else "2D", note=note)
        return _warn(detail="no fix  -  map uses last known / default position", chip="NO FIX", note=note)

    def _c_gnss_dev(self, now, live):
        note = "Only needed when the GNSS receiver is plugged in by USB serial (u-blox on the Jetson)."
        if sys.platform.startswith("win"):
            return _na(detail="not applicable on Windows", note=note)
        if os.path.exists(GNSS_SERIAL):
            return _ok(detail="%s present" % GNSS_SERIAL, note=note)
        return _warn(detail="%s not found" % GNSS_SERIAL, chip="MISSING", note=note)

    def _best_position(self, live):
        if live:
            la, lo = float(self._vs_get("latitude", 0.0) or 0.0), float(self._vs_get("longitude", 0.0) or 0.0)
            if abs(la) > 1e-6 or abs(lo) > 1e-6:
                return la, lo
        mm = self._mm
        if mm is not None and int(getattr(mm, "gnssFix", 0) or 0) >= 2:
            return mm.gnssLat, mm.gnssLon
        return None

    def _c_pack(self, now, live):
        mm = self._mm
        if mm is None:
            return _na(detail="map backend not attached")
        if not mm.available:
            return _fail(detail="no map pack found in maps/", chip="NO PACK",
                         note="Put the .mbtiles region pack(s) in the maps/ folder and restart.")
        return _ok(detail=mm.packSummary or "pack loaded", note="Offline vector tiles; the smallest (most local) pack wins.")

    def _c_cover(self, now, live):
        mm = self._mm
        pos = self._best_position(live)
        if mm is None or not mm.available:
            return _na(detail="no map pack")
        if pos is None:
            return _na(detail="no position yet")
        la, lo = pos
        if mm.covers(la, lo):
            return _ok(detail="inside pack  -  detail up to z%d" % mm.maxDetailZoomAt(la, lo))
        return _warn(detail="position is outside every pack  -  base map only", chip="OUTSIDE",
                     note="The vessel is outside the area covered by the installed region pack(s).")

    def _c_nic(self, now, live):
        note = "The boat LAN is 192.168.1.0/24 (GCS 192.168.1.50 in the architecture document, 192.168.1.3 in uvs_lan.ps1)."
        if self._on_lan is None:
            self._refresh_nic()
        if self._on_lan:
            return _ok(detail="%s on %s" % (self._lan_ip, self._lan_if), note=note)
        return _warn(detail="no 192.168.1.x address  -  simulation only", chip="NOT ON LAN", note=note)

    # ---------------------------------------------------------------------------------- assemble
    def _active_check(self, cid, default_detail="press RUN ALL CHECKS"):
        r = self._active.get(cid)
        if r is None:
            return _na(detail=default_detail)
        return dict(r)

    def _rebuild(self):
        now = time.monotonic()
        live = self._eval_live()
        rows = []

        def add(cid, group, name, res, tile=False):
            r = dict(res)
            r.update(id=cid, group=group, name=name, tile=tile)
            r.setdefault("chip", "")
            r.setdefault("metric", "")
            r.setdefault("note", "")
            r.setdefault("detail", "")
            rows.append(r)

        add("tlm", "vessel", "Telemetry downlink", self._c_tlm(now, live))
        add("uplink", "vessel", "Command uplink", self._c_uplink(now, live))
        add("lora", "vessel", "LoRa 433 MHz (via STM32)", self._c_lora(now, live))
        add("autonomy", "vessel", "Jetson to STM32 guidance", self._c_autonomy(now, live))
        add("video", "video", "FPV video stream", self._c_video(now, live))
        add("jetson", "onboard", "Jetson autonomy node", self._active_check("jetson"))
        add("can_eng", "onboard", "Engine ECU (CAN 0x200)",
            self._c_can(0x200, now, live, "engine", lambda: "RPM %s  -  coolant %.0f C" % (self._vs_get("rpm", 0), float(self._vs_get("coolantTemp", 0.0) or 0.0))))
        add("can_bat", "onboard", "Battery BMS (CAN 0x300)",
            self._c_can(0x300, now, live, "battery", lambda: "%.1f V" % float(self._vs_get("batteryVoltage", 0.0) or 0.0)))
        add("leak", "onboard", "Hull leak sensor", self._c_leak(now, live))
        add("gnss", "nav", "GNSS position (GCS)", self._c_gnss(now, live))
        add("boat_gnss", "nav", "Boat GNSS (in telemetry)", self._c_boat_gnss(now, live))
        add("gpsd", "nav", "gpsd daemon", self._active_check("gpsd"))
        add("gnss_dev", "nav", "GNSS receiver port", self._c_gnss_dev(now, live))
        add("mappack", "maps", "Offline map pack", self._c_pack(now, live))
        add("mapcov", "maps", "Coverage at vessel position", self._c_cover(now, live))
        add("nic", "lan", "GCS network adapter", self._c_nic(now, live))
        for (cid, name, ip, port, label) in LAN_DEVICES:
            add(cid, "lan", name, self._active_check(cid, "%s  -  not checked yet" % ip), tile=True)

        self._checks = rows
        self.checksChanged.emit()

    def _write_log(self):
        if not self._log_path:
            return
        try:
            with open(self._log_path, "a", encoding="utf-8") as f:
                f.write("--- %s ---\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
                for c in self._checks:
                    f.write("%-8s %-28s %s\n" % (c["status"].upper(), c["name"], c["detail"]))
        except Exception:
            pass
