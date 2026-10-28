"""冒烟截图：加载 main.qml，渲染后保存窗口截图（用于视觉验收）。"""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_here)
if _root not in sys.path:
    sys.path.insert(0, _root)

from PySide6.QtCore import QUrl, QTimer, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("TEMP", "."), "qml_shot.png")
page = int(sys.argv[2]) if len(sys.argv) > 2 else 0

app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.addImportPath(os.path.join(_root, "ui"))


class Stub(QObject):
    """backend 桩：让独立引擎能渲染完整 UI（截图用）"""
    pass


engine.rootContext().setContextProperty("backend", Stub())
engine.load(QUrl.fromLocalFile(os.path.join(_root, "ui", "main.qml")))
win = engine.rootObjects()[0]
win.show()
win.raise_()


def grab():
    if isinstance(win, QQuickWindow):
        win.setProperty("navIndex", page)
        win.grabWindow().save(out)
        print("saved:", out)
    app.quit()


QTimer.singleShot(1600, grab)
sys.exit(app.exec())
