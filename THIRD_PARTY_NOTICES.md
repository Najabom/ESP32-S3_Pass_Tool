# 第三方组件与许可证声明

PassDeck 通行证控制台（本仓库）以 GNU General Public License v3.0 发布。Windows
发布包由 PyInstaller 打包，包含下列第三方组件。各组件的版权归其作者所有，完整许可证
文本见 [LICENSES](LICENSES/) 目录。

## 运行时组件

| 组件 | 版本 | 许可证 | 许可证文本 |
|---|---|---|---|
| PySide6 / shiboken6 | 6.11.1 | LGPL-3.0（另可选 GPL-3.0 或商业许可） | `LGPL-3.0.txt`、`Qt-LGPL-3.0.txt` |
| Qt | 6.11.1 | LGPL-3.0 / GPL-3.0 / 商业许可 | `LGPL-3.0.txt`、`Qt-LGPL-3.0.txt` |
| Python | 3.14 | PSF-2.0 | `PSF-2.0.txt` |
| bleak | 3.0.2 | MIT | `MIT-bleak.txt` |
| esptool | 5.4.0 | GPL-2.0-or-later | `esptool-GPL-2.0-or-later.txt` |
| esp-pylib | 1.1.4 | Apache-2.0 | `esp-pylib-Apache-2.0.txt` |
| pyserial | 3.5 | BSD-3-Clause | `BSD-3-Clause-pyserial.txt` |
| bitstring | 4.4.0 | MIT | `MIT-bitstring.txt` |
| cryptography | 50.0.1 | Apache-2.0 OR BSD-3-Clause | `Apache-2.0-cryptography.txt`、`BSD-3-Clause-cryptography.txt` |
| reedsolo | 1.7.0 | Unlicense OR MIT-0 | `MIT-0-reedsolo.txt` |
| intelhex | 2.3.0 | BSD-3-Clause | `BSD-intelhex.txt` |
| rich | 15.0.0 | MIT | `MIT-rich.txt` |
| rich-click | 1.9.9 | MIT | `MIT-rich-click.txt` |
| click | 8.4.2 | BSD-3-Clause | `BSD-3-Clause-click.txt` |
| markdown-it-py | 4.2.0 | MIT | `MIT-markdown-it-py.txt` |
| markdown-it | - | MIT | `MIT-markdown-it.txt` |
| mdurl | 0.1.2 | MIT | `MIT-mdurl.txt` |
| Pygments | 2.20.0 | BSD-2-Clause | `BSD-2-Clause-Pygments.txt` |
| colorama | 0.4.6 | BSD-3-Clause | `BSD-3-Clause-colorama.txt` |
| typing-extensions | 4.15.0 | PSF-2.0 | `PSF-2.0-typing-extensions.txt` |
| cffi | 2.0.0 | MIT | `MIT-cffi.txt` |
| pycparser | 3.0 | BSD-3-Clause | `BSD-3-Clause-pycparser.txt` |
| PyYAML | 6.0.3 | MIT | `MIT-PyYAML.txt` |
| winrt-* | 3.2.1 | MIT | `MIT-winrt.txt` |

## 构建与开发工具

这些组件用于构建发布包或开发脚本，通常不随最终用户程序运行。

| 组件 | 版本 | 许可证 | 许可证文本 |
|---|---|---|---|
| PyInstaller | 6.22.0 | GPL-2.0-or-later，含 bootloader 例外 | `PyInstaller.txt` |
| pyinstaller-hooks-contrib | 2026.6 | GPL-2.0-or-later（运行钩子为 Apache-2.0） | `PyInstaller-hooks.txt` |
| altgraph | 0.17.5 | MIT | `MIT-altgraph.txt` |
| pefile | 2024.8.26 | MIT | `MIT-pefile.txt` |
| Pillow | 12.2.0 | HPND | `Pillow.txt` |

## Qt / PySide6 说明

Qt 与 PySide6 的版权归 The Qt Company Ltd. 及其贡献者所有。本程序按 LGPL-3.0 使用
Qt/PySide6 动态库；本仓库整体按 GPL-3.0 发布。发布包中的 Qt 库保持可替换形式，完整
LGPL-3.0 文本见 `LICENSES/LGPL-3.0.txt`。Qt 源码与许可证信息：<https://www.qt.io/licensing>。

## esptool 说明

固件烧录功能通过 esptool 实现。esptool 以 GPL-2.0-or-later 发布；完整文本见
`LICENSES/esptool-GPL-2.0-or-later.txt`。本仓库整体同样以 GPL-3.0 发布，满足其
copyleft 要求。

## Python 说明

Windows 发布包内含 Python 运行时。Python 由 Python Software Foundation 以 PSF-2.0
许可发布；完整文本见 `LICENSES/PSF-2.0.txt`。Python 内附的 OpenSSL、zlib、libffi 等
组件适用各自的许可证，详见 Python 发行版中的 `LICENSE.txt`。

## 字体

本程序不随包分发字体文件，界面使用 Windows 系统字体（Microsoft YaHei UI）与等宽
系统字体。系统字体的使用受最终用户操作系统许可约束。
