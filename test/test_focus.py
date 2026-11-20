import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.abspath(sys.argv[1]))
from PySide6.QtCore import QObject, Qt, QUrl, QPoint
from PySide6.QtGui import QGuiApplication
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
cli.waitForConnected(2000); srv.waitForNewConnection(2000); esp = srv.nextPendingConnection()
got = []
esp.readyRead.connect(lambda: got.append(bytes(esp.readAll())))
eng = QQmlApplicationEngine(); eng.rootContext().setContextProperty("loraBridge", bridge); eng.addImportPath(HERE)
eng.load(QUrl.fromLocalFile(os.path.join(HERE, "win.qml")))
win = eng.rootObjects()[0]; bridge.install_on(win)
panel = win.findChild(QObject, "panel")
def spin(ms=80): QTest.qWait(ms)
bridge.attach_device(cli, "FAKE"); esp.write(b"*** LINK ESTABLISHED ***\r\n"); esp.flush(); spin(300)
def up():
    got.clear(); QTest.keyPress(win, Qt.Key.Key_Up); spin(60); ok = any(b"KEYS:U1" in g for g in got); QTest.keyRelease(win, Qt.Key.Key_Up); spin(60); return ok
def state(tag):
    fi = win.activeFocusItem()
    print("%-34s tab=%s open=%s motor=%s typing=%s focus=%s  UP_WORKS=%s" % (tag, panel.property("tab"), panel.property("open"), bridge.motorEnabled, bridge._typing(), fi.metaObject().className() if fi else None, up()))
panel.setProperty("tab", 0); spin(100); state("connections tab")
panel.setProperty("tab", 1); spin(200)
# click into the terminal input box
inp = win.findChild(QObject, "termInput")
print("termInput found:", inp is not None)
QTest.mouseClick(win, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(500, 947)); spin(150)
state("terminal tab, input clicked")
panel.setProperty("tab", 0); spin(200); state("back to connections tab")
panel.setProperty("tab", 1); spin(200); QTest.mouseClick(win, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(500, 947)); spin(150)
panel.setProperty("open", False); spin(300); state("panel CLOSED after clicking input")
