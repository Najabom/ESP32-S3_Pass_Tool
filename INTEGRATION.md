# INTEGRATION.md —— 后端信号对接与运行说明

## 运行

```
run.bat                    # 或手动：
.venv313\Scripts\python.exe app\app.py
```

- 环境：PySide6 6.8.3 + bleak（GDIF venv 复用）
- 入口：`app/app.py` → 加载 `ui/main.qml`，注册 `backend` 上下文属性与 `ui/Theme` import 路径

## 架构

```
core/worker.py   纯逻辑层（bleak 扫描/连接/GATT 读写，独立线程）
app/backend.py   桥接层（QObject：Signal/Slot，线程安全队列转发）
ui/*.qml         界面层（QML，只读 backend 属性 + 响应 Signal）
```

后端零 QML 依赖；QML 零业务逻辑。

## Backend → QML 信号

| 信号 | 参数 | 用途 |
|---|---|---|
| `scanDone(list)` | 设备显示名列表 | DevicePage 设备列表 |
| `connState(bool, str)` | 已连接, 信息(版本/设备名) | 状态镜像、固件版本解析 `v(x.y.z)` |
| `roleList(list)` | 角色名列表 | 角色切换/传输目标 |
| `currentRole(str)` | 当前角色 | 当前角色高亮 |
| `loglevelChanged(str)` | 日志级别 | 日志级别下拉回显 |
| `uploadProgress(int)` / `downloadProgress(int)` | 0..100，<0 不确定态 | 进度条 |
| `transferStats(float,float,float,str)` | 速率KB/s, 已传B, 总B, "up"/"down" | 统计行 + 速率曲线 |
| `transferDone(bool, str)` | 成功, 消息 | 传输结束复位 |
| `transferActive(bool)` | 是否传输中 | — |
| `toastMessage(str)` | 提示文本 | 右上角 ToastHost |
| `logMessage(str, str)` | level(error/warn/info/debug), 文本 | 底部日志台 |

## QML → Backend 槽

| 槽 | 参数 | 动作 |
|---|---|---|
| `startScan()` | — | 开始 BLE 扫描（约 8s 自动结束） |
| `connectDevice(int)` | 列表索引 | 连接选中设备并拉取服务 |
| `disconnectDevice()` | — | 断开 |
| `refreshRoles()` | — | 重读角色目录（list 缓存刷新） |
| `selectRole(str)` | 角色名 | 写 current.txt 热重载 |
| `saveUiText(str)` | 文本 | 写 ui_text.txt |
| `saveIpcfg(str)` | 文本 | 写 ip.txt |
| `setLoglevel(str)` | verbose..error | 设置设备日志级别 |
| `triggerReload()` | — | 触发配置热重载 |
| `syncTime()` | — | 同步系统时间到设备 |
| `setUid/setMotto/setUname(str)` | 名片字段 | 写入设备名片 |
| `uploadFile(local, role, file)` | 本地路径, 角色, 远端文件名 | 上传素材（≤4MB 白名单） |
| `downloadFile(remote, save, label)` | 远端路径, 保存名, 标签 | 下载素材到本地 |
| `toast(str)` | 文本 | 弹 Toast（+日志台 warn） |

## QML 页面接入模式

页面通过 `Connections { target: backend; function onXxx(...) }` 镜像信号到本地
property，UI 绑定 property —— 避免直接绑定信号参数导致的重绑定循环。

## 注意事项

- Windows 原生蓝牙配对后数秒自动断开是系统对自定义 BLE 外设的固有行为，
  请始终通过本工具连接。
- 设备 list 服务有目录缓存，SD 卡目录变更后需断开重连或热重载刷新。
- 上传白名单为 `loop.mjpeg / intro.mjpeg / portrait.bin / ui_text.txt / self.bin`，单文件 ≤4MB。
