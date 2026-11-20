"""
Headless end-to-end test of lora_bridge.py + LoraControlHud.qml against a FAKE ESP32 (local TCP socket standing in for the
serial port).  The fake speaks the real ESP32_LoRa_Ground.ino protocol.  Run:
    QT_QPA_PLATFORM=offscreen python3 test_lora_bridge.py <path to out/>
"""
import os
import sys
import time

OUT = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.join(OUT, "backend"))

from PySide6.QtCore import QCoreApplication, QEvent, QTimer, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QSGRendererInterface
from PySide6.QtTest import QTest

QQuickWindow.setGraphicsApi(QSGRendererInterface.GraphicsApi.Software)
app = QGuiApplication(sys.argv)

import lora_bridge as LB                                                  # noqa: E402

bridge = LB.LoraBridge()
bridge.autoConnect = False

# ---------------------------------------------------------------- fake ESP32 on a local socket
srv = QTcpServer()
srv.listen(QHostAddress.SpecialAddress.LocalHost, 0)
cli = QTcpSocket()
cli.connectToHost(QHostAddress.SpecialAddress.LocalHost, srv.serverPort())
assert cli.waitForConnected(2000) and srv.waitForNewConnection(2000)
esp = srv.nextPendingConnection()
got = []                                                                  # lines the ESP32 received from the PC
esp_buf = bytearray()


def esp_read():
    global esp_buf
    esp_buf += bytes(esp.readAll())
    while b"\n" in esp_buf:
        i = esp_buf.index(b"\n")
        got.append(esp_buf[:i].decode())
        del esp_buf[:i + 1]


esp.readyRead.connect(esp_read)


def esp_say(*lines):
    for ln in lines:
        esp.write((ln + "\r\n").encode())
    esp.flush()


def spin(ms=80):
    QTest.qWait(ms)


results = []


def check(name, cond, extra=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name + (("   " + str(extra)) if extra and not cond else ""))


# ---------------------------------------------------------------- QML: hud + a text field (typing must not trigger keys)
qml = os.path.join(os.path.dirname(os.path.abspath(__file__)), "TestWin.qml")
open(qml, "w").write('''
import QtQuick
import QtQuick.Window
Window {
    id: w; width: 900; height: 520; visible: true; color: "#0b121b"
    LoraControlHud { id: hud; x: 24; y: 20; sf: 1.3; accent: "#00f0ff" }
    TextInput { id: ti; objectName: "ti"; x: 600; y: 20; width: 200; height: 30; color: "white"; text: "" }
}
''')
eng = QQmlApplicationEngine()
eng.rootContext().setContextProperty("loraBridge", bridge)
eng.addImportPath(OUT + "/qml")
import shutil
shutil.copy(os.path.join(OUT, "qml", "LoraControlHud.qml"), os.path.dirname(qml))
eng.load(QUrl.fromLocalFile(qml))
assert eng.rootObjects(), "QML failed to load"
win = eng.rootObjects()[0]
bridge.install_on(win)
spin(300)

# ---------------------------------------------------------------- 1. nothing connected: keys pass through, no packets
QTest.keyClick(win, Qt.Key.Key_Up)
check("no USB: arrow key is NOT swallowed / nothing sent", not got)
check("health (no usb) = warn", bridge.health_check()["status"] == "warn", bridge.health_check())

# ---------------------------------------------------------------- 2. USB attached, LoRa not linked yet
bridge.attach_device(cli, "FAKE-ESP32")
esp_say("=== ESP32 LoRa Ground Station V2 ===", "Self-diagnosis PASSED. LoRa module OK.", "TX -> HELLO:123123")
spin(150)
check("status usb after attach", bridge.status == "usb", bridge.status)
QTest.keyPress(win, Qt.Key.Key_Up); spin(30)
check("USB only: ARROW UP press is not sent (stale-packet guard)", not any(g.startswith("KEYS:U1") for g in got), got)
QTest.keyRelease(win, Qt.Key.Key_Up); spin(30)
QTest.keyClick(win, Qt.Key.Key_1); spin(30)
check("USB only: key 1 does not fire BTN:E", "BTN:E" not in got, got)
check("health (usb only) = warn/NO LORA", bridge.health_check()["chip"] == "NO LORA", bridge.health_check())

# ---------------------------------------------------------------- 3. LoRa link comes up
esp_say("RX <- ACK:123123", "*** LINK ESTABLISHED ***")
spin(200)
check("status lora", bridge.status == "lora", bridge.status)
check("idle packet pushed on link-up", got and got[-1] == "KEYS:U0D0L0R0S0", got)
check("health (linked) = ok", bridge.health_check()["status"] == "ok", bridge.health_check())
got.clear()

# ---------------------------------------------------------------- 4. motor keys: edges only
QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
check("UP press -> KEYS:U1D0L0R0S0", got[-1:] == ["KEYS:U1D0L0R0S0"], got)
QTest.keyPress(win, Qt.Key.Key_Left); spin(40)
check("LEFT press -> KEYS:U1D0L1R0S0", got[-1:] == ["KEYS:U1D0L1R0S0"], got)
n = len(got)
for _ in range(5):                                                         # auto-repeat of UP must not send anything
    ev = QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_Up, Qt.KeyboardModifier.NoModifier, "", True, 1)
    QCoreApplication.sendEvent(win, ev)
spin(40)
check("auto-repeat sends nothing", len(got) == n, got)
check("keys map reflects held keys", bridge.keys["Up"] and bridge.keys["Left"] and not bridge.keys["Down"], bridge.keys)
QTest.keyPress(win, Qt.Key.Key_Space); spin(40)
check("SPACE press -> S1", got[-1:] == ["KEYS:U1D0L1R0S1"], got)
QTest.keyRelease(win, Qt.Key.Key_Up); spin(40)
check("UP release -> U0", got[-1:] == ["KEYS:U0D0L1R0S1"], got)
QTest.keyPress(win, Qt.Key.Key_Down); QTest.keyPress(win, Qt.Key.Key_Right); spin(40)
check("DOWN + RIGHT combine", got[-1:] == ["KEYS:U0D1L1R1S1"], got)
# window loses focus -> everything released with one idle packet
QCoreApplication.sendEvent(win, QEvent(QEvent.Type.WindowDeactivate)); spin(40)
check("focus loss releases all keys (idle packet)", got[-1:] == ["KEYS:U0D0L0R0S0"] and not any(bridge.keys.values()), (got, bridge.keys))
for k in (Qt.Key.Key_Left, Qt.Key.Key_Space, Qt.Key.Key_Down, Qt.Key.Key_Right):
    QTest.keyRelease(win, k)
spin(40)
got.clear()

# ---------------------------------------------------------------- 5. Ctrl+Up belongs to the horizon shortcut
QTest.keyPress(win, Qt.Key.Key_Up, Qt.KeyboardModifier.ControlModifier); spin(30)
QTest.keyRelease(win, Qt.Key.Key_Up, Qt.KeyboardModifier.ControlModifier); spin(30)
check("Ctrl+Up is ignored by the bridge", not got, got)

# ---------------------------------------------------------------- 6. solenoids: one-shot + ack
QTest.keyClick(win, Qt.Key.Key_1); spin(40)
check("key 1 -> BTN:E", got[-1:] == ["BTN:E"], got)
check("state pending", bridge.solenoidStates["E"] == "pending", bridge.solenoidStates)
esp_say("STM_BTN_ACK:E:OK"); spin(60)
check("ack ok", bridge.solenoidStates["E"] == "ok", bridge.solenoidStates)
QTest.keyClick(win, Qt.Key.Key_2); spin(30)
QTest.keyClick(win, Qt.Key.Key_3); spin(30)
QTest.keyClick(win, Qt.Key.Key_4); spin(30)
check("keys 2,3,4 -> BTN:M BTN:VU BTN:VD", got[-3:] == ["BTN:M", "BTN:VU", "BTN:VD"], got)
esp_say("STM_BTN_ACK:M:REJECTED"); spin(60)
check("ack rejected", bridge.solenoidStates["M"] == "rejected", bridge.solenoidStates)
got.clear()
for _ in range(4):                                                         # held digit fires once
    QCoreApplication.sendEvent(win, QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_1, Qt.KeyboardModifier.NoModifier, "1", True, 1))
spin(30)
check("held digit (auto-repeat) does not re-fire", "BTN:E" not in got, got)

# ---------------------------------------------------------------- 7. pot feedback
esp_say("STM_ACK:276552:T=4.3,B=3.5,S=48.0"); spin(80)
check("feedback parsed", abs(bridge.throttlePct - 4.3) < 1e-6 and abs(bridge.steeringPct - 48.0) < 1e-6 and bridge.feedbackFresh,
      (bridge.throttlePct, bridge.steeringPct))
esp_say("HB:STM:T=10.0,B=0.0,S=50.0"); spin(60)
check("feedback from heartbeat", abs(bridge.throttlePct - 10.0) < 1e-6)

# ---------------------------------------------------------------- 8. typing in a text field must not drive the boat
ti = win.findChild(object, "ti")
ti.forceActiveFocus(); spin(50)
got.clear()
QTest.keyClick(win, Qt.Key.Key_Space); QTest.keyClick(win, Qt.Key.Key_1); spin(40)
check("text field focused: Space / 1 are typed, not sent", not got and ti.property("text") == " 1", (got, ti.property("text")))
ti.setProperty("focus", False)
win.contentItem().forceActiveFocus(); spin(40)

# ---------------------------------------------------------------- 9. link lost while a key is held
QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
check("UP held", bridge.keys["Up"])
esp_say("", "=== LINK LOST ===", "Starting Handshake..."); spin(100)
check("link lost -> status usb, keys cleared", bridge.status == "usb" and not bridge.keys["Up"], (bridge.status, bridge.keys))
got.clear()
QTest.keyRelease(win, Qt.Key.Key_Up); QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
check("link down: new UP press is not sent", not any(g.startswith("KEYS:U1") for g in got), got)
QTest.keyRelease(win, Qt.Key.Key_Up)
# link returns: an idle packet resets the ESP32's remembered key state
esp_say("*** LINK ESTABLISHED ***"); spin(100)
check("relink -> idle packet again", got[-1:] == ["KEYS:U0D0L0R0S0"], got)

# ---------------------------------------------------------------- 10. ESP32 reboot is treated as link loss; HELLO as well
esp_say("=== ESP32 LoRa Ground Station V2 ==="); spin(60)
check("ESP32 boot banner drops the link", bridge.status == "usb", bridge.status)
esp_say("*** LINK ESTABLISHED ***"); spin(60)
esp_say("TX -> HELLO:123123"); spin(60)
check("HELLO while 'linked' drops the link", bridge.status == "usb", bridge.status)
esp_say("*** LINK ESTABLISHED ***"); spin(60)

# ---------------------------------------------------------------- 11. disconnect flushes idle while a key is held
QTest.keyPress(win, Qt.Key.Key_Up); spin(40)
got.clear()
bridge.disconnectPort(); spin(100)
check("disconnect with key held flushes idle packet", got[-1:] == ["KEYS:U0D0L0R0S0"], got)
check("status disconnected", bridge.status == "disconnected")
QTest.keyRelease(win, Qt.Key.Key_Up)

# ---------------------------------------------------------------- 12. screenshot of the hud (linked state) for a visual check
srv2 = QTcpServer(); srv2.listen(QHostAddress.SpecialAddress.LocalHost, 0)
c2 = QTcpSocket(); c2.connectToHost(QHostAddress.SpecialAddress.LocalHost, srv2.serverPort())
c2.waitForConnected(2000); srv2.waitForNewConnection(2000)
e2 = srv2.nextPendingConnection()
bridge.attach_device(c2, "COM5")
e2.write(b"*** LINK ESTABLISHED ***\r\nSTM_ACK:1:T=22.0,B=0.0,S=62.0\r\n"); e2.flush(); spin(150)
QTest.keyPress(win, Qt.Key.Key_Up); QTest.keyPress(win, Qt.Key.Key_Left); QTest.keyClick(win, Qt.Key.Key_1); spin(120)
img = win.grabWindow()
shot = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hud_linked.png")
img.save(shot)
print("screenshot", shot, img.width(), img.height())

bad = [n for n, ok in results if not ok]
print("\n%d/%d passed" % (len(results) - len(bad), len(results)))
sys.exit(1 if bad else 0)
