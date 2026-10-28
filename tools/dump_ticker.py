"""Ticker 诊断：打印 track 宽度 / 半宽 / 各 item 宽度 / x，验证回绕点。"""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_here)
if _root not in sys.path:
    sys.path.insert(0, _root)

from PySide6.QtCore import QUrl, QTimer, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem

out_path = os.path.join(os.environ.get("TEMP", "."), "ticker_dump.txt")
lines = []

app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.addImportPath(os.path.join(_root, "ui"))
engine.load(QUrl.fromLocalFile(os.path.join(_root, "ui", "main.qml")))
win = engine.rootObjects()[0]
win.show()


def find(obj, name, acc):
    if not isinstance(obj, QObject):
        return
    if obj.objectName() == name:
        acc.append(obj)
    for c in obj.children():
        find(c, name, acc)


def snap(tag):
    acc = []
    find(win, "tickerTrack", acc)
    if not acc:
        lines.append("tickerTrack not found")
        return
    tr = acc[0]
    if isinstance(tr, QQuickItem):
        widths = [round(k.width(), 1) for k in tr.childItems()]
        w, x = tr.width(), tr.x()
    else:
        return
    lines.append(f"[{tag}] track.width={w:.1f} x={x:.1f} half={w/2:.1f}")
    lines.append(f"       items({len(widths)})={[v for v in widths if v > 0]}")


def finish():
    snap("t3000")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    app.quit()


QTimer.singleShot(3000, finish)
sys.exit(app.exec())
