"""Headless test of the serial terminal: bridge (fake ESP32 on a TCP socket) + QML tab.  Run under xvfb with xcb + OpenGL:
   xvfb-run -a -s "-screen 0 1920x1080x24" env QT_QPA_PLATFORM=xcb python test_terminal.py <backend dir>"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp()                    # QSettings sandbox
sys.path.insert(0, os.path.abspath(sys.argv[1]))
from PySide6.QtCore import QCoreApplication, QEvent, QObject, Qt, QTimer, QUrl
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QSGRendererInterface
from PySide6.QtTest import QTest
QQuickWindow.setGraphicsApi(QSGRendererInterface.GraphicsApi.OpenGL)
app = QGuiApplication(sys.argv)
import lora_bridge as LB

bridge = LB.LoraBridge(); bridge.autoConnect = False
srv = QTcpServer(); srv.listen(QHostAddress.SpecialAddress.LocalHost, 0)
cli = QTcpSocket(); cli.connectToHost(QHostAddress.SpecialAddress.LocalHost, srv.serverPort())
assert cli.waitForConnected(2000) and srv.waitForNewConnection(2000)
esp = srv.nextPendingConnection()
got = []; buf = bytearray()
def esp_read():
    global buf
    buf += bytes(esp.readAll())
    while b"\n" in buf:
        i = buf.index(b"\n"); got.append(bytes(buf[:i + 1])); del buf[:i + 1]
esp.readyRead.connect(esp_read)
def say(*lines, raw=None):
    for ln in lines: esp.write((ln + "\r\n").encode())
    if raw: esp.write(raw)
    esp.flush()
def spin(ms=80): QTest.qWait(ms)
res = []
def check(n, c, extra=""):
    res.append(bool(c)); print(("PASS  " if c else "FAIL  ") + n + ((" " + str(extra)) if not c and extra else ""))

tl = []                                                              # terminalLine signal log
bridge.terminalLine.connect(lambda ts, d, t, h, k: tl.append((ts, d, t, h, k)))

eng = QQmlApplicationEngine()
eng.rootContext().setContextProperty("loraBridge", bridge)
eng.addImportPath(HERE)
eng.load(QUrl.fromLocalFile(os.path.join(HERE, "win.qml")))
assert eng.rootObjects(), "QML load failed"
win = eng.rootObjects()[0]
bridge.install_on(win)
panel = win.findChild(QObject, "panel")
panel.setProperty("tab", 0)
spin(300)

# 1 - attach + raw lines
bridge.attach_device(cli, "FAKE-ESP32")
say("=== ESP32 LoRa Ground Station V2 ===", "RX <- HB:STM:VS=1,HDG=87,SPD=6.5,FIX=3,LAT=12451754,LON=76552337,WP=2/5,CML=98,CAM=1/2,OBS=0")
say("STM_ACK:276552:T=4.3,B=3.5,S=48.0"); spin(150)
ins = [x for x in tl if x[1] == "in"]
check("every incoming line reaches terminalLine", len(ins) == 3, ins)
check("hex of a line is the real bytes", ins[0][3].startswith("3D 3D 3D 20 45 53 50 33 32"), ins[0][3][:40])
check("kinds: heartbeat / ack", ins[1][4] == "heartbeat" and ins[2][4] == "ack", [i[4] for i in ins])
vals = {v["k"]: v for v in bridge.rawValues}
check("raw values parsed (HDG, SPD, LAT, T, B, S)", all(k in vals for k in ("HDG", "SPD", "LAT", "T", "B", "S")), list(vals))
check("value + source correct", vals["HDG"]["v"] == "87" and vals["HDG"]["src"] == "HB:STM" and vals["T"]["v"] == "4.3" and vals["T"]["src"] == "STM_ACK", (vals.get("HDG"), vals.get("T")))
check("WP=2/5 kept as text", vals["WP"]["v"] == "2/5")
check("rx byte counter", bridge.rxBytes > 100, bridge.rxBytes)

# 2 - partial line (no newline) is flushed after 0.5 s
say("", raw=b"boot garbage no newline"); spin(900)
check("partial line shown after 0.5 s (kind=partial)", any(x[4] == "partial" and "no newline" in x[2] for x in tl), tl[-3:])

# 3 - terminal send with endings
got.clear()
check("sendText NEWLINE", bridge.sendText("hello", "nl") and (spin(60) or True) and got[-1:] == [b"hello\n"], got)
bridge.sendText("a", "crlf"); spin(40); bridge.sendText("b", "cr"); spin(40); bridge.sendText("c", "none"); spin(40)
joined = b"".join(got) + bytes(buf)
check("endings: CRLF / CR / none", joined.endswith(b"hello\na\r\nb\rc"), joined)
check("sent text is logged as out/terminal", any(x[1] == "out" and x[4] == "terminal" and x[2] == "c" for x in tl))

panel.setProperty("tab", 0); spin(100)
# 4 - link + keys still work; motorEnabled safety
say("*** LINK ESTABLISHED ***"); spin(150)
check("lora link", bridge.status == "lora")
got.clear()
QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
check("Up goes to the boat while motorEnabled", any(g.startswith(b"KEYS:U1") for g in got), got)
QTest.keyRelease(win, Qt.Key.Key_Up); spin(40)
panel.setProperty("tab", 1); spin(100)
check("terminal tab on screen -> motorEnabled False", bridge.motorEnabled is False, bridge.motorEnabled)
got.clear()
QTest.keyPress(win, Qt.Key.Key_Up); spin(40); QTest.keyRelease(win, Qt.Key.Key_Up); spin(40)
QTest.keyClick(win, Qt.Key.Key_1); spin(40)
check("terminal tab: Up / key 1 send NOTHING", not any(g.startswith(b"KEYS:U1") or g.startswith(b"BTN:") for g in got), got)
# a key held while the tab opens is released (idle packet)
panel.setProperty("tab", 0); spin(100)
check("back on CONNECTIONS tab -> keys enabled again", bridge.motorEnabled is True)
QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
got.clear()
panel.setProperty("tab", 1); spin(100)
check("opening the terminal while holding Up releases it (idle packet)", got[-1:] == [b"KEYS:U0D0L0R0S0\n"] and not any(bridge.keys.values()), (got, bridge.keys))
QTest.keyRelease(win, Qt.Key.Key_Up)

# 5 - baud + pin + busy hint + reset on non-serial
bridge.baudRate = 921600
check("baudRate property", bridge.baudRate == 921600)
bridge.baudRate = 115200
check("busy-port message names the cause", "in use" in bridge._busy_hint("COM3", "Access is denied.") or "dialout" in bridge._busy_hint("COM3", "Permission denied"), bridge._busy_hint("COM3", "Permission denied"))
check("reset refuses on a non-serial device (no crash)", bridge.resetEsp32() is False)
bridge._pinned = ""; bridge._ports = [{"name": "COM9", "description": "x", "vid": 0, "pid": 0, "likely": False}]
bridge._pinned = "COM9"
check("pinned port is a candidate even if its chip is not a known ESP32 one", bridge._candidates() == ["COM9"], bridge._candidates())
bridge.forgetPinnedPort(); check("forgetPinnedPort", bridge.pinnedPort == "")

# 6 - screenshots of the tab (night/day) with a busy-looking feed
for i in range(6):
    say("RX <- HB:STM:VS=1,HDG=%d,SPD=%.1f,FIX=3,LAT=12451754,LON=76552337,WP=2/5,CML=98,CAM=1/2,OBS=0" % (84 + i, 6 + i / 10.0), "STM_ACK:%d:T=%.1f,B=3.5,S=%.1f" % (276600 + i, 4 + i, 48 + i * 0.5)); spin(40)
bridge.sendText("STATUS?", "nl"); spin(60)
say("WARNING: Link lost, retrying"); spin(100)
bridge.setKey("Up", True); spin(50)
spin(600)
win.grabWindow().save(os.path.join(HERE, "tab_night.png"))
win.setProperty("lmv", 1.0); spin(500)
win.grabWindow().save(os.path.join(HERE, "tab_day.png"))
win.setProperty("lmv", 0.0)
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
