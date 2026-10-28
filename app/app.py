"""PySide6/QML 入口：PassDeck 通行证控制台（PC 端蓝牙工具）。"""

import os
import sys

# 资源根：开发态=仓库根；PyInstaller 冻结态=_MEIPASS（onedir 的 _internal 目录，
# 所有 --add-data 注入点所在）
if getattr(sys, "frozen", False):
    _root = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
else:
    _here = os.path.dirname(os.path.abspath(__file__))
    _root = os.path.dirname(_here)
if _root not in sys.path:
    sys.path.insert(0, _root)

import ctypes
ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("PassDeck.PassDeck")

from PySide6.QtCore import QUrl, Qt, QTimer
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

from app.backend import Backend


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("PassDeck 通行证控制台")
    app.setOrganizationName("PassDeck")
    # 任务栏/窗口图标：优先取打包资源 assets/app_icon.ico，缺失则忽略
    _icon = os.path.join(_root, "assets", "app_icon.ico")
    if os.path.exists(_icon):
        app.setWindowIcon(QIcon(_icon))

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    ui_dir = os.path.join(_root, "ui")
    engine.addImportPath(ui_dir)
    qml_path = os.path.join(ui_dir, "main.qml")
    engine.load(QUrl.fromLocalFile(qml_path))
    if not engine.rootObjects():
        sys.exit("failed to load main.qml: " + qml_path)

    _win = engine.rootObjects()[0]
    from PySide6.QtQuick import QQuickWindow
    if isinstance(_win, QQuickWindow) and os.path.exists(_icon):
        _win.setIcon(QIcon(_icon))
    # Windows 任务栏图标：无边框窗口 Qt 有时不刷新 WM_SETICON，直接 Win32 窗口消息兜底
    try:
        import ctypes as _c
        _user32 = _c.windll.user32
        WM_SETICON = 0x0080
        ICON_SMALL = 0
        ICON_BIG = 1
        _hwnd = int(_win.winId())
        # 从 ico 提取大/小图标
        _large = _c.wintypes.HICON()
        _small = _c.wintypes.HICON()
        _c.windll.shell32.ExtractIconExW(_icon, 0, _c.byref(_large), _c.byref(_small), 1)
        if _large.value:
            _user32.SendMessageW(_hwnd, WM_SETICON, ICON_BIG, _large)
        if _small.value:
            _user32.SendMessageW(_hwnd, WM_SETICON, ICON_SMALL, _small)
    except Exception:
        pass
    backend.setParent(_win)
    backend.start()
    # 关闭程序（窗口 X/Alt-F4/退出）自动断开 BLE 会话
    app.aboutToQuit.connect(backend.stop)

    ft = os.environ.get("PASSDECK_FLASH_TEST")
    if ft:
        # 自测钩子：无 GUI 跑一遍「扫描→烧录（保留设置）→断开→退出」，
        # 结果写 PASSDECK_FLASH_OUT（默认 flash_selftest.txt）。
        # 用法：set PASSDECK_FLASH_TEST=COM5 && PassDeck.exe
        port = ft.strip()
        state = {"rc": None, "msg": ""}
        logbuf = []

        def _log(line, pct):
            logbuf.append(f"{pct:>3} {line}")

        def _done(ok, msg):
            state["rc"] = 0 if ok else 1
            state["msg"] = msg
            app.quit()

        backend.flashLog.connect(_log)
        backend.flashDone.connect(_done)

        def _fail(msg):
            state["rc"] = 1
            state["msg"] = msg
            app.quit()

        def _kick():
            def _on_ports(ps):
                if port not in ps:
                    _fail(f"SCAN-MISS ports={ps}")
                    return
                binp = os.environ.get("PASSDECK_FLASH_BIN") or os.path.join(
                    _root, "firmware", "firmware_v1.0_merged.bin")
                if not os.path.isfile(binp):
                    _fail("BIN-MISS " + binp)
                    return
                state["msg"] = f"SCAN-OK {ps}"
                backend.flashFirmware(port, binp, True)
            backend.comPorts.connect(_on_ports)
            backend.scanComPorts()

        QTimer.singleShot(300, _kick)
        QTimer.singleShot(300000, lambda: _fail("TIMEOUT"))
        app.exec()
        out = os.environ.get("PASSDECK_FLASH_OUT", "flash_selftest.txt")
        with open(out, "w", encoding="utf-8") as f:
            f.write(f"rc={state['rc']} msg={state['msg']}\n")
            f.write("\n".join(logbuf[-400:]))
        sys.exit(state["rc"] if state["rc"] is not None else 3)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()