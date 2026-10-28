"""布局诊断：加载 main.qml，导出对象树几何信息（文本/坐标/尺寸）到文件。"""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_here)
if _root not in sys.path:
    sys.path.insert(0, _root)

from PySide6.QtCore import QUrl, QTimer, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("TEMP", "."), "qml_dump.txt")

app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.addImportPath(os.path.join(_root, "ui"))
engine.load(QUrl.fromLocalFile(os.path.join(_root, "ui", "main.qml")))
win = engine.rootObjects()[0]
win.show()

lines = []


def walk(obj, depth=0):
    if not isinstance(obj, QObject):
        return
    meta = obj.metaObject()
    cls = meta.className()
    pad = "  " * depth
    extra = ""
    for prop in ("x", "y", "width", "height", "visible", "text", "opacity"):
        idx = meta.indexOfProperty(prop)
        if idx >= 0:
            val = obj.property(prop)
            extra += f" {prop}={val}"
    lines.append(f"{pad}{cls}: {extra}")
    for child in obj.children():
        walk(child, depth + 1)


def dump():
    walk(win)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("dumped:", out)
    app.quit()


QTimer.singleShot(1200, dump)
sys.exit(app.exec())
