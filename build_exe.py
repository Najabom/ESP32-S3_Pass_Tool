"""PyInstaller 打包脚本：python build_exe.py（需已 pip install -r requirements-dev.txt）。"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FW_NAME = "firmware_v1.0_merged.bin"


def main():
    if not shutil.which("pyinstaller"):
        sys.exit("未安装 PyInstaller：pip install -r requirements-dev.txt")

    fw_src = Path(os.environ.get("PASSDECK_FIRMWARE") or ROOT / "firmware" / FW_NAME)
    if not fw_src.is_file():
        sys.exit(
            f"缺少固件镜像：{fw_src}\n"
            f"请从 ESP32-S3_Pass 的 Releases 下载 {FW_NAME} 放到 firmware/ 目录，"
            "或设置环境变量 PASSDECK_FIRMWARE 指向该文件。"
        )

    dist = ROOT / "dist" / "PassDeck"
    if dist.exists():
        shutil.rmtree(dist)

    cmd = [
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--windowed",
        "--name", "PassDeck",
        "--icon", str(ROOT / "assets" / "app_icon.ico"),
        "--paths", str(ROOT),
        "--add-data", f"{ROOT / 'ui'};ui",
        "--add-data", f"{ROOT / 'assets'};assets",
        "--collect-all", "bleak",
        # 烧录链路：backend 函数内动态 import，PyInstaller 静态分析看不到；
        # esptool 5.4 运行时依赖 esp-pylib/rich_click/click/serial 等
        "--collect-all", "esptool",
        "--collect-all", "esp_pylib",
        "--collect-all", "rich_click",
        "--collect-submodules", "serial",
        "--collect-data", "yaml",
        str(ROOT / "app" / "app.py"),
    ]
    print("running:", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)

    # 出厂固件随包分发（GUI 默认定位 _internal/firmware/；--add-data 分号解析
    # 在部分 PyInstaller 版本不稳，直接拷贝更可靠）
    fw_dir = dist / "_internal" / "firmware"
    fw_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fw_src, fw_dir / FW_NAME)

    # 说明文档与许可证随包分发
    for name in ("README.md", "LICENSE", "THIRD_PARTY_NOTICES.md"):
        src = ROOT / name
        if src.is_file():
            shutil.copy2(src, dist / name)
    lic_dir = ROOT / "LICENSES"
    if lic_dir.is_dir():
        shutil.copytree(lic_dir, dist / "LICENSES", dirs_exist_ok=True)

    print(f"打包完成：{dist}")
    print("资源检查：")
    missing = []
    for rel in ("ui/main.qml", "ui/pages/DevicePage.qml", "ui/components/GlassPanel.qml",
                "ui/assets/ic_refresh.svg", f"firmware/{FW_NAME}"):
        p = dist / "_internal" / rel
        ok = p.exists()
        if not ok:
            missing.append(rel)
        print(("  OK  " if ok else "  MISS") + f" {rel}")
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        p = dist / name
        ok = p.exists()
        if not ok:
            missing.append(name)
        print(("  OK  " if ok else "  MISS") + f" {name}")
    if missing:
        sys.exit("打包缺少资源：" + ", ".join(missing))


if __name__ == "__main__":
    main()