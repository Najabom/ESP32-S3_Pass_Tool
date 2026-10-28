# PassDeck 通行证控制台

**V1.0** · ESP32-S3 桌面通行证设备的 Windows PC 配套工具

PassDeck 通过 BLE 连接通行证设备，完成角色管理、名片编辑、素材制作、SD 卡文件传输、
交换记录查看和固件烧录。界面使用 PySide6 + QML，业务逻辑全部在 Python 侧，QML 不含
硬件操作。

> 设备端固件与硬件资料：[ESP32-S3_Pass](https://github.com/Najabom/ESP32-S3_Pass)

## 功能

| 页面 | 功能 |
|---|---|
| 状态监控 | 连接状态、固件版本、设备信息、实时传输速率 |
| 设备连接 | 扫描/连接、角色切换、UID/寄语/用户名、设备名、日志级别、热重载、时间同步、企划隔离、本机头像 |
| 文件制作 | 视频/GIF → `loop.mjpeg` / `intro.mjpeg`（240×320 MJPEG）；图片 → `portrait.bin`（64×64 RGB565）；3:4 画面裁剪 |
| 文件传输 | 角色素材上传/下载、整包传输、文件夹导入、角色删除、固件烧录 |
| 名片记录 | 读取设备 SD 卡交换记录、头像/立绘预览、相遇次数与时间 |
| 关于 | 版本与使用提示 |

- 设备识别不依赖设备名：广播 Service Data `0xFFE0` + `"AP"`，连接后读 `0xFFF5` 校验 `"PSUP"`。
- 上传白名单：`loop.mjpeg` / `intro.mjpeg` / `portrait.bin` / `ui_text.txt` / `self.bin`。
- 单次上传总量 ≤ 4 MB，视频文件 ≤ 3 MB，角色名 ≤ 48 UTF-8 字节。
- 连接后自动写入 PC 当前 Unix 时间，校准设备墙钟。
- 固件烧录内置 esptool，发布包自带 `firmware_v1.0_merged.bin`，无需另装 Python。

## 环境要求

- Windows 10/11（x64）
- Python 3.10+（开发测试使用 3.14）
- 支持 BLE 的蓝牙适配器
- 素材制作需要 `ffmpeg` / `ffprobe`（放入 `PATH`，或设置 `FFMPEG_PATH`）

## 安装与运行

```bat
python -m pip install -r requirements.txt
python app\app.py
```

也可以双击 `run.bat`。程序启动后：

1. 设备端打开蓝牙广播（设备菜单「蓝牙」页，或 SD 卡 `config/bt.txt` 写 `enable=1` 后重启）。
2. 在「设备连接」页点击「扫描」，选择设备并连接。
3. 连接成功后可切换角色、修改名片、上传素材或读取交换记录。

Windows 系统自带的蓝牙配对会在数秒后断开自定义 BLE 外设，这是系统行为；请始终通过
PassDeck 连接，不要先在 Windows 设置里配对。

## 素材与 SD 卡

设备从 SD 卡读取角色目录：

```text
/sdcard/
  <角色名>/
    loop.mjpeg       必需，240×320 MJPEG 原始流
    intro.mjpeg      可选，开机/切换角色时播放
    portrait.bin     可选，64×64 RGB565 小端，8192 B
    ui_text.txt      可选，leftcol / sub_text / op_name
  config/
    current.txt      当前角色名
    ip.txt           企划隔离配置（每行一个标识，留空=全通）
    bt.txt           设备名与广播开关
    fonts/           SD 卡中文字库（role_name_16.bin / role_name_30.bin）
    nvs_backup.txt   设备自动生成的 NVS 快照
```

「文件制作」页调用 ffmpeg 生成 MJPEG 和 RGB565 头像，可直接上传到设备。

## 固件烧录

发布包内的 `firmware/firmware_v1.0_merged.bin` 为 16 MB 整片镜像。烧录有两种模式：

- **保留设备设置**（默认）：只写应用分区 `0x10000`，NVS、校准、分区表和 SD 卡内容不变。
- **整片写入**：从 `0x0` 写入 bootloader、分区表和 app，NVS 会被重置；若 SD 卡存在
  `config/nvs_backup.txt`，设备启动后会自动回填关键设置。

烧录时不要断电或拔线，完成后设备自动重启。

## 从源码打包

```bat
python -m pip install -r requirements-dev.txt
```

将固件镜像放到 `firmware/firmware_v1.0_merged.bin`（该文件不进入 Git），或设置
`PASSDECK_FIRMWARE` 指向镜像路径，然后：

```bat
python build_exe.py
```

产物在 `dist/PassDeck/`，包含 Qt/PySide6 运行时、esptool、UI 资源和固件镜像。发布 zip
时请把 `dist/PassDeck/` 整个目录打包。

## 测试

```bat
python -m unittest discover tests
```

单元测试不依赖蓝牙硬件，覆盖协议识别码、游标分块、上传参数校验和进度解析。

## 项目结构

```text
ESP32-S3_Pass_Tool/
  app/
    app.py            PySide6/QML 入口与烧录自测钩子
    backend.py        QML ↔ core 桥接（Signal/Slot，BLE 在后台线程）
  core/
    protocol.py       BLE 应用协议（UUID / 识别码 / 尺寸 / 约束）
    passdeck_ble.py   bleak 客户端（扫描过滤 / 连接校验 / 游标读写 / 上传）
    worker.py         专用事件循环线程任务执行器
    filemaker.py      ffmpeg 素材转换
    blob_parse.py     名片 blob 解析与 RGB565 预览
  ui/
    main.qml          主窗口与导航
    pages/            6 个功能页
    components/       玻璃面板、霓虹按钮、图表等
    Theme/            设计令牌
  assets/             应用图标
  tests/              mock 单测
  tools/              图标/布局/冒烟等开发脚本
  build_exe.py        PyInstaller onedir 打包
```

界面设计规范见 [DESIGN_SPEC.md](DESIGN_SPEC.md)，QML 与 Backend 的接口约定见
[INTEGRATION.md](INTEGRATION.md)。

## BLE 协议摘要

| 服务 | 特性 | 用途 | 协议 |
|---|---|---|---|
| 0x180A | 0x2A28 | 固件版本 | 只读 |
| 0xFFE0 | 0xFFE1 | `current.txt` | 读写 ≤47 B，写后热重载 |
| | 0xFFE2 | `ui_text.txt` | 只写 ≤128 B |
| | 0xFFE3 | `ip.txt` | 只写 ≤256 B |
| | 0xFFE4 | 日志级别 | 读写 |
| | 0xFFE5 | 热重载 | 只写 |
| | 0xFFE6 / 0xFFE7 / 0xFFE8 | uid / motto / uname | 只写 ≤20 / ≤64 / ≤64 B |
| | 0xFFE9 | 时间 | 4 B LE Unix 秒，可附 2 B LE 时区 |
| | 0xFFEA | 设备名 | 读写 ≤15 B |
| | 0xFFEE | 清空交换记录 | 只写 |
| 0xFFF0 | 0xFFF1 | 角色列表 | 只读游标，≤500 B/段 |
| | 0xFFF2 | 文件读取 | 写 `PATH:` 打开，读分段 |
| | 0xFFF3 | 文件上传 | START → 块 ≤500 B → END |
| | 0xFFF4 | 上传状态 | 通知 `OK` / `PROG:n` / `DONE` / `ERR:*` |
| | 0xFFF5 | 设备识别码 | 只读 `"PSUP"` |
| | 0xFFF6 | 删除角色 | 只写角色名 |

## 已知限制

- 设备端角色列表为连接内缓存，刷新列表需要重新连接。
- 名片交换通过 ESP-NOW 完成，PC 不参与交换过程，只读取设备保存的记录。
- 上传白名单和大小限制由固件强制，PC 端预校验只用于提前提示。
- 本工具使用 Windows 系统字体（Microsoft YaHei UI），不随包分发字体文件。

## 许可证

本项目以 **GNU General Public License v3.0** 发布，详见 [LICENSE](LICENSE)。
第三方组件（PySide6/Qt、bleak、esptool、PyInstaller、Python 等）的许可证与声明见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES](LICENSES/)。

本项目为独立的个人工具，不隶属于任何游戏、公司或商业组织；相关名称与素材由使用者自行提供，
版权归其各自权利人所有。
