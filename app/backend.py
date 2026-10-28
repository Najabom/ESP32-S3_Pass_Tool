"""PySide6 桥接层：QML 界面 ↔ core 后台任务（Signal/Slot 全部线程安全）。"""

import os
import subprocess
import sys
import tempfile
import threading
import time

from PySide6.QtCore import QObject, Signal, Slot

from core.worker import Worker


def _nq(s):
    """弯引号转直引号（显示归一化，与固件 op_text_display 一致）：
    U+2018/2019 → '，U+201C/201D → "。非字符串原样返回。"""
    if not isinstance(s, str):
        return s
    return s.translate({0x2018: "'", 0x2019: "'", 0x201C: '"', 0x201D: '"'})


def _exc_text(e):
    """异常文案：空消息回退类型名，避免 toast/log 无详情。"""
    s = str(e)
    return s or type(e).__name__


class Backend(QObject):
    """暴露给 QML 的上下文对象（contextProperty "backend"）。"""

    # ---- 信号 ----
    scanDone = Signal(list)                 # [display, ...] 候选设备
    scanIdle = Signal()                      # 扫描异常路径复位 scanning（成功路径由 scanDone 复位）
    connState = Signal(bool, str)           # connected, 信息（版本/设备名）
    logMessage = Signal(str, str)           # level, text
    roleList = Signal(list)             # [角色名, ...]
    roleFilesReady = Signal(str, "QVariantList")  # 角色名, [(文件名, 大小|None), ...]
    uiTextReady = Signal(str, str, str, str)   # 角色名, leftcol, sub_text, op_name（无文件=全部 ""）
    ipcfgReady = Signal(str)                # 企划配置原文（多行；空 = 全通）
    currentRole = Signal(str)
    loglevelChanged = Signal(str)
    uploadProgress = Signal(int)            # 0..100
    downloadProgress = Signal(int)          # 0..100
    transferFile = Signal(int, int, str)    # 每文件开始: (序号1起, 总数, 文件名)
    transferStats = Signal(float, float, float, str)  # speed KB/s, done B, total B, "up"/"down"
    transferActive = Signal(bool)           # 传输进行中
    transferDone = Signal(bool, str)        # 传输会话结束 (ok, 消息)——完成/失败/停止
    toastMessage = Signal(str, int)         # 轻提示（右上角 Toast）：文本, 停留 ms
    stagedReady = Signal(str, int, int, 'QVariantList')  # 新建角色素材暂存就绪：名称, 文件数, 总字节, 路径列表
    comPorts = Signal('QVariantList')        # 串口扫描结果（有线烧录用）
    flashLog = Signal(str, int)              # esptool 行输出: (文本, 进度%或-1)
    flashDone = Signal(bool, str)            # 烧录结束: (ok, 消息)
    profileLoaded = Signal(str, str, str, str)  # devname, uid, motto, uname（连接后异步回填）
    cardsLoaded = Signal("QVariantList")    # 名片记录 [{seq,up,mac,uname,name,uid,motto,...}, ...]
    cardsFailed = Signal(str)               # 名片读取失败（原因），QML 显示而非误报空列表
    makeDone = Signal(bool, str, str, int)       # 素材制作完成 ok, message, 输出路径, 大小字节
    makeEstimate = Signal(int)                   # 素材预估大小（字节，-1=无法预估）
    sourceProbed = Signal(int, int, bool, int)   # 源尺寸 w, h, ffmpeg 可用, 时长秒
    cardMediaReady = Signal(str, str, str)  # 名片素材就绪 mac12hex, portraitPNG, avatarPNG（空=无）
    selfAvatarReady = Signal(str)           # 本机头像热载入完成（png 路径）

    def __init__(self, parent=None):
        super().__init__(parent)
        self._w = Worker(log=self._emit_log, on_lost=self._on_ble_lost)
        self._scan_items = []               # [(address, display)]
        self._version = ""
        self._connected = False
        self._upload_done = False
        self._upload_err = None
        self._t_last = 0.0          # 上次进度时间戳（速率计算）
        self._b_last = 0            # 上次进度字节
        self._transferring = False
        self._cancel = threading.Event()   # 停止上传/下载
        self._cfg_warned = False    # 连接时配置读取失败 toast 去重

    def _on_ble_lost(self):
        """设备主动掉线（BLE 线程回调）：更新状态、清空数据并通知 UI。"""
        if not self._connected:
            return
        self._connected = False
        self.connState.emit(False, "连接丢失")
        self.toastMessage.emit("设备连接已断开", 2600)
        # 清空设备相关数据（角色列表 / 名片记录），让 UI 回到未连接态
        self.roleList.emit([])
        # cards 不清空：��Ƭ��¼�����϶ϣ���UI �������Ĵ��Ѷ��ģ�
        # 解决读卡期间 BLE 闪断竞态清空的问题。
        self._emit_log("warn", "设备连接已丢失")

    # ------------------------------------------------------------------
    # 生命周期
    # ------------------------------------------------------------------
    def start(self):
        self._w.start()
        self._emit_log("info", "后台已启动，等待扫描设备")

    def stop(self):
        self._w.submit(self._w.do_disconnect())
        self._w.stop()

    def _emit_log(self, level, text):
        self.logMessage.emit(level, text)

    @Slot(str)
    def toast(self, msg: str):
        """QML 端轻提示（Toast 弹窗 + 日志台 warn 通道）。"""
        self.toastMessage.emit(msg, 2600)
        self._emit_log("warn", msg)

    @Slot(str, int)
    def toastFor(self, msg: str, ms: int):
        """带停留时长的轻提示（如推荐拔卡引导 10s）。"""
        self.toastMessage.emit(msg, max(800, int(ms)))
        self._emit_log("warn", msg)

    # ------------------------------------------------------------------
    # 固件烧录（有线 COM 口，esptool 子进程；与 BLE 传输互不冲突）
    # ------------------------------------------------------------------
    @Slot()
    def scanComPorts(self):
        """枚举可用串口（pyserial，esptool 依赖自带）。"""
        def _run():
            ports = []
            try:
                from serial.tools import list_ports
                for p in list_ports.comports():
                    ports.append(p.device)
            except Exception as e:
                self._emit_log("warn", f"串口枚举失败: {_exc_text(e)}")
            self.comPorts.emit(ports)
        threading.Thread(target=_run, daemon=True).start()

    @Slot(str, str, bool)
    def flashFirmware(self, port: str, bin_path: str, keep_settings: bool = True):
        """esptool 烧录。keep_settings=True（默认）：从 merged 镜像切出应用
        分区（0x10000 起 12MB 内、去尾部 0xFF 填充）只写 0x10000——
        NVS(0x9000)/校准/分区表均不触碰，设备设置原样保留。
        keep_settings=False：整片 merged 写 0x0（含分区表，NVS 被重置）。
        流式解析 "Writing at ... (NN%)" 驱动进度。"""
        if not bin_path or not os.path.isfile(bin_path):
            self.toast("固件文件不存在")
            return

        APP_OFF = 0x10000      # factory 分区偏移（与设备 partitions.csv 一致）
        APP_MAX = 0xC00000     # factory 分区大小 12MB
        def _slice_app(src, dst):
            """merged 是 0x0 起整片镜像（尾 0xFF 填充到 16MB）：
            取 [APP_OFF, APP_OFF+APP_MAX) 并从尾部剥掉 0xFF 填充。"""
            with open(src, "rb") as f:
                f.seek(APP_OFF)
                data = f.read(APP_MAX)
            end = len(data)
            while end > 0 and data[end - 1] == 0xFF:
                end -= 1
            if end == 0:
                raise ValueError("镜像应用区为空（文件不是 merged 整片镜像？）")
            with open(dst, "wb") as f:
                f.write(data[:end])
            return end

        def _run():
            if keep_settings:
                self._emit_log("info",
                               f"保留设置模式：仅写应用分区 0x{APP_OFF:x}（NVS/分区表不动）")
            else:
                self._emit_log("warn",
                               "全量模式：整片镜像写入，设备 NVS（UI选项/档案/校准）将被重置")
            self._emit_log("info", f"开始烧录: {bin_path} @ {port}")
            tmp = None
            try:
                if keep_settings:
                    import tempfile
                    tmp = os.path.join(tempfile.gettempdir(), "passdeck_app_slice.bin")
                    n = _slice_app(bin_path, tmp)
                    self._emit_log("info", f"应用分区切片 {n} B → 0x{APP_OFF:x}")
                target = tmp if keep_settings else bin_path
                addr = "0x%x" % APP_OFF if keep_settings else "0x0"
                # 进程内直调 esptool（打包 exe 自带，无需本机 Python；v5.4 起
                # 进度行格式 "Writing at 0x…  NN.N%"，无括号）
                args = ["--chip", "esp32s3", "--port", port,
                        "--baud", "921600",
                        "--before", "default-reset", "--after", "hard-reset",
                        "write_flash", addr, target]
                import io
                import re as _re
                last_pct = -1
                _pct_re = _re.compile(r"(\d+(?:\.\d+)?)%")

                def _feed(chunk):
                    nonlocal last_pct
                    for ln in chunk.splitlines():
                        ln = ln.strip()
                        if not ln:
                            continue
                        pct = -1
                        m = _pct_re.search(ln)
                        if m:
                            p = int(float(m.group(1)))
                            if p > last_pct:
                                last_pct = p
                                pct = p
                        self.flashLog.emit(ln[:200], pct)

                class _Tee(io.TextIOBase):
                    def writable(self):
                        return True

                    def write(self, s):
                        _feed(s)
                        return len(s)

                rfd, wfd = os.pipe()

                def _pump():
                    try:
                        while True:
                            b = os.read(rfd, 4096)
                            if not b:
                                break
                            _feed(b.decode("utf-8", "replace"))
                    except OSError:
                        pass

                pump = threading.Thread(target=_pump, daemon=True)
                pump.start()
                try:
                    save_out, save_err = os.dup(1), os.dup(2)
                except OSError:
                    save_out = save_err = -1
                if save_out >= 0:
                    os.dup2(wfd, 1)
                    os.dup2(wfd, 2)
                os.close(wfd)
                rc = 0
                try:
                    import contextlib
                    import esptool
                    with contextlib.redirect_stdout(_Tee()), \
                            contextlib.redirect_stderr(_Tee()):
                        esptool.main(args)
                except SystemExit as sx:
                    rc = int(sx.code) if isinstance(sx.code, int) else \
                        (0 if sx.code is None else 1)
                except Exception as ex:
                    if save_out >= 0:
                        os.dup2(save_out, 1)
                        os.dup2(save_err, 2)
                        os.close(save_out)
                        os.close(save_err)
                    try:
                        os.close(rfd)
                    except OSError:
                        pass
                    self.flashDone.emit(False, f"esptool 异常: {_exc_text(ex)}")
                    return
                if save_out >= 0:
                    os.dup2(save_out, 1)
                    os.dup2(save_err, 2)
                    os.close(save_out)
                    os.close(save_err)
                pump.join(1.5)
                try:
                    os.close(rfd)
                except OSError:
                    pass
                if rc == 0:
                    self.flashDone.emit(True, "烧录成功，设备即将重启" +
                                        ("（已保留设备设置）" if keep_settings else "（全量写入，设置已重置）"))
                else:
                    self.flashDone.emit(False, f"烧录失败（esptool rc={rc}）——检查串口是否被监视器占用/重新插拔")
            except Exception as ex:
                self.flashDone.emit(False, f"烧录异常: {_exc_text(ex)}")
            finally:
                if tmp and os.path.isfile(tmp):
                    try:
                        os.remove(tmp)
                    except OSError:
                        pass
        threading.Thread(target=_run, daemon=True).start()
    # 扫描 / 连接
    # ------------------------------------------------------------------
    @Slot()
    def startScan(self):
        def _run():
            async def _scan():
                devs = await self._w.do_scan()
                items = [(d.address, d.display) for d in devs]
                self._scan_items = items
                self.scanDone.emit([d for _, d in items])
                self._emit_log("info", f"扫描完成：发现 {len(items)} 台本族设备")

            try:
                fut = self._w.submit(_scan())
                exact = fut
            except Exception as e:
                self._emit_log("error", f"扫描失败: {e}")
                self.toast(f"扫描失败：{e}")
            else:
                def _scan_deadline(f):
                    try:
                        exc = f.exception()
                        if exc is not None:
                            self._emit_log("error", f"扫描失败: {exc}")
                            self.toast(f"扫描失败：{exc}")
                    except Exception:
                        pass
                    finally:
                        # 异常路径不 emit scanDone：QML 需显式复位 scanning
                        try:
                            self.scanIdle.emit()
                        except Exception:
                            pass
                exact.add_done_callback(_scan_deadline)

        threading.Thread(target=_run, daemon=True).start()

    @Slot(int)
    def connectDevice(self, index: int):
        # 纯 BLE 列表：index 指向扫描候选项
        if not (0 <= index < len(self._scan_items)):
            self._emit_log("warn", "请先选择设备")
            self.toast("请先扫描并选择设备")
            return
        self._connect_ble(index)

    def _connect_ble(self, index: int):
        address = self._scan_items[index][0]

        def _run():
            async def _conn():
                self._cfg_warned = False
                ok, err = await self._w.do_connect(address)
                if not ok:
                    self._connected = False
                    self.connState.emit(False, err)
                    self._emit_log("error", f"连接失败: {err}")
                    return
                self._connected = True
                try:
                    ver = await self._w.do_read_version()
                except Exception:
                    ver = "?"
                self._version = ver
                self.connState.emit(True, f"{address}  ({ver})")
                self._emit_log("info", f"已连接 {address}（识别码验证通过，时间已同步）")
                # 本机头像热载入（独立线程排队读 :self:，不阻塞后续连接流程）
                threading.Thread(target=self._load_self_avatar, daemon=True).start()
                self.refreshRoles()
                try:
                    cur = await self._w.do_read_current()
                    if cur:
                        self.currentRole.emit(_nq(cur))
                        self._emit_log("info", f"当前角色: {cur}")
                except Exception:
                    pass
                try:
                    lv = await self._w.do_read_loglevel()
                    self.loglevelChanged.emit(lv)
                except Exception:
                    pass
                # 异步读取设备配置（在 worker 线程串行 await，避免 QML 同步阻塞）
                async def _safe(fn):
                    try:
                        return await fn()
                    except Exception as e:
                        self._emit_log("warn", f"读取配置失败: {e}")
                        if not self._cfg_warned:
                            self._cfg_warned = True
                            self.toast(f"读取设备配置部分失败：{e}")
                        return ""
                devname = await _safe(self._w.do_read_device_name)
                uid = await _safe(self._w.do_read_uid)
                motto = await _safe(self._w.do_read_motto)
                uname = await _safe(self._w.do_read_uname)
                self._emit_log("info", f"配置回填: 设备名={devname or '(空)'} UID={uid or '(空)'} 寄语={motto or '(空)'} 用户名={uname or '(空)'}")
                self.profileLoaded.emit(devname, uid, motto, uname)

            try:
                fut = self._w.submit(_conn())
                exact = fut
            except Exception as e:
                self._emit_log("error", f"连接失败: {e}")
                self.toast(f"连接失败：{e}")
            else:
                def _conn_deadline(f):
                    try:
                        exc = f.exception()
                        if exc is not None:
                            self._emit_log("error", f"连接失败: {exc}")
                            self.toast(f"连接失败：{exc}")
                    except Exception:
                        pass
                exact.add_done_callback(_conn_deadline)

        threading.Thread(target=_run, daemon=True).start()

    def _load_self_avatar(self):
        """连接后热载入本机头像（self.bin → png），失败静默（无头像属正常）。"""
        try:
            fut = self._w.submit(self._w.do_read_self())
            path = fut.result(timeout=30)
            self.selfAvatarReady.emit(path)
        except Exception as e:
            self._emit_log("warn", f"本机头像读取失败: {e}")

    @Slot()
    def disconnectDevice(self):
        def _run():
            # 立即回 UI（不被 BLE 后台阻塞）：清状态/清数据/通知界面
            self._connected = False
            self.connState.emit(False, "已断开")
            self.roleList.emit([])
            self.cardsLoaded.emit([])
            try:
                fut = self._w.submit(self._w.do_disconnect())
                fut.result(timeout=15)
            except Exception as e:
                self._emit_log("warn", f"断开清理异常: {e}")

        threading.Thread(target=_run, daemon=True).start()

    # ------------------------------------------------------------------
    # 配置
    # ------------------------------------------------------------------
    @Slot()
    def refreshRoles(self):
        if not getattr(self, "_connected", False):
            self.toast("设备未连接，无法读取角色列表")
            return

        def _run():
            import time
            for attempt in range(2):
                try:
                    fut = self._w.submit(self._w.do_refresh_roles())
                    names = fut.result(timeout=30)
                    self.roleList.emit([_nq(x) for x in names])
                    return
                except Exception as e:
                    if attempt == 0:
                        # 设备刚写完大文件，LIST 可能卡一次；稍候重试一轮
                        self._emit_log("warn", f"读取角色列表失败(第1次)，重试: {e}")
                        time.sleep(2)
                        continue
                    self._emit_log("error", f"读取角色列表失败: {e}")
                    self.toast(f"读取角色列表失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def probeRoleFiles(self, name: str):
        """查询角色目录素材清单：[(文件名, 大小|None), ...]。触发 roleFilesReady。"""
        if not getattr(self, "_connected", False):
            self.toast("设备未连接，无法读取素材清单")
            return

        def _run():
            try:
                fut = self._w.submit(self._w.do_stat_files(name))
                files = fut.result(timeout=40)
                self.roleFilesReady.emit(name, [list(x) for x in files])
            except Exception as e:
                self._emit_log("error", f"读取素材清单失败: {e}")
                self.toast(f"读取素材清单失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def readUiText(self, name: str):
        """读角色 ui_text.txt（leftcol/sub_text/op_name）回填编辑框。触发 uiTextReady。"""
        if not getattr(self, "_connected", False):
            return

        def _run():
            try:
                fut = self._w.submit(self._w.do_read_ui_text(name))
                lc, sub, op = fut.result(timeout=30)
                self.uiTextReady.emit(name, lc, sub, op)
            except Exception as e:
                self._emit_log("error", f"读取界面文本失败: {e}")
                # 不回填空值（防误覆盖角色文本），仅提示
                self.toast(f"读取「{name}」界面文本失败，编辑框未更新：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def selectRole(self, name: str):
        # 切换 CD：5 秒内不允许再次切换（固件热重载期间切换易失败/掉线）
        now = time.monotonic()
        if now - getattr(self, "_last_switch", 0.0) < 5.0:
            self.toast("角色切换过快，请 5 秒后再试")
            return
        self._last_switch = now

        def _run():
            try:
                self._w.submit(self._w.do_select_role(name)).result(timeout=15)
                self.currentRole.emit(name)
            except Exception as e:
                self._emit_log("error", f"切换角色失败: {e}")
                self.toast(f"切换「{name}」失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def saveUiText(self, text: str):
        # 0xFFE2 原始整文本写入【当前角色】ui_text.txt（无模板头；常规编辑走 uploadUiText）
        self._run_simple(self._w.do_write_ui_text(text))

    @Slot(str)
    def saveIpcfg(self, text: str):
        """写入设备企划配置（ip.txt，每行一个企划标识；空串=全通）。"""
        self._run_simple(self._w.do_write_ipcfg(text), ok="企划配置已保存（约 10s 生效）")

    @Slot()
    def readIpcfg(self):
        """读回设备企划配置并刷新 UI（连接就绪/手动刷新时调用）。"""
        def _run():
            try:
                text = self._w.submit(self._w.do_read_ipcfg()).result(timeout=30)
                self.ipcfgReady.emit(text)
            except Exception as e:
                self._emit_log("warn", f"读回企划配置失败: {e}")
        threading.Thread(target=_run, daemon=True).start()

    @Slot()
    def deleteIpcfg(self):
        """删除设备企划配置 = 写入空行（全通，不隔离）。"""
        self._run_simple(self._w.do_clear_ipcfg(), ok="企划配置已删除（恢复全通）")

    @Slot()
    def triggerReload(self):
        self._run_simple(self._w.do_reload(), ok="已触发热重载")

    @Slot()
    def syncTime(self):
        def _run():
            try:
                tz = int(time.localtime().tm_gmtoff or 0) // 60
                self._w.submit(self._w.do_sync_time(tz)).result(timeout=15)
                self._emit_log("info", f"已同步 PC 时间（UTC{tz:+d} 分钟偏移，绝对对齐）")
            except Exception as e:
                msg = str(e)
                # 设备返回 ATT 错误 14：写入被拒（如 SD 忙/队列满），提示重试
                if "14" in msg and "GATT" in msg.upper():
                    self._emit_log("warn", "设备暂时拒绝校时（忙），可稍后重试")
                    self.toast("设备忙，校时未完成，请重试")
                else:
                    self._emit_log("error", f"操作失败: {e}")
                    self.toast(f"操作失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def setUid(self, uid: str):
        self._run_simple(self._w.do_set_uid(uid), ok="UID 已更新")

    @Slot(str)
    def setMotto(self, motto: str):
        self._run_simple(self._w.do_set_motto(motto), ok="寄语已更新")

    @Slot(str)
    def setUname(self, uname: str):
        self._run_simple(self._w.do_set_uname(uname), ok="用户名已更新")

    @Slot(str, str, str)
    def saveCard(self, uid: str, motto: str, uname: str):
        """一次保存全部名片字段（串行写三个特征，单条完成提示）。"""

        def _run():
            try:
                self._w.submit(self._w.do_set_uid(uid)).result(timeout=15)
                self._w.submit(self._w.do_set_motto(motto)).result(timeout=15)
                self._w.submit(self._w.do_set_uname(uname)).result(timeout=15)
                self._emit_log("info", "名片配置已保存")
                # 保存成功后重新读取回填 UI（QML 输入框显示最新值）
                try:
                    devname = self._w.submit(self._w.do_read_device_name).result(timeout=10)
                    rid = self._w.submit(self._w.do_read_uid).result(timeout=10)
                    rm = self._w.submit(self._w.do_read_motto).result(timeout=10)
                    ru = self._w.submit(self._w.do_read_uname).result(timeout=10)
                    self.profileLoaded.emit(devname, rid, rm, ru)
                except Exception as e:
                    self._emit_log("warn", f"名片回读失败: {e}")
                self.toast("名片配置已保存")
            except Exception as e:
                self._emit_log("error", f"名片保存失败: {e}")
                self.toast(f"名片保存失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    @Slot()
    def readCards(self):
        """读取设备 SD 卡名片记录（cards.txt）并广播 cardsLoaded。
        未连接静默跳过（不弹空列表）；读取失败发 cardsFailed（避免误报「暂无名片」）。"""
        if not self._w.connected or self._w._client is None:
            return
        def _run():
            try:
                cards = self._w.submit(self._w.do_read_cards()).result(timeout=300)
                for c in cards:
                    if isinstance(c, dict) and "name" in c:
                        c["name"] = _nq(c["name"])
                        c["uname"] = _nq(c.get("uname", ""))
                self.cardsLoaded.emit(cards)
            except Exception as e:
                self._emit_log("error", f"读取名片记录失败: {e}")
                self.cardsFailed.emit(str(e))
        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def setDeviceName(self, name: str):
        self._run_simple(self._w.do_write_device_name(name),
                         ok=f"设备名 -> {name}")

    @Slot(str)
    def deleteRole(self, name: str):
        """删除角色目录（BLE 异步删；延迟刷新列表等删除落盘）。"""
        def _run():
            try:
                self._w.submit(self._w.do_delete_role(name)).result(timeout=15)
                self._emit_log("info", f"已删除角色: {name}")
                self.toast(f"已删除角色「{name}」")
                time.sleep(1.5)
                self.refreshRoles()
            except Exception as e:
                self._emit_log("error", f"删除角色失败: {e}")
                self.toast(f"删除角色失败: {e}")
        threading.Thread(target=_run, daemon=True).start()

    @Slot(result=str)
    def readDeviceName(self):
        try:
            return self._w.submit(self._w.do_read_device_name()).result(timeout=10)
        except Exception as e:
            self._emit_log("warn", f"读取设备名失败: {e}")
            self.toast(f"读取设备名失败：{e}")
            return "PASS-II-XXXX"

    @Slot(result=str)
    def readUid(self):
        try:
            return self._w.submit(self._w.do_read_uid()).result(timeout=10)
        except Exception as e:
            self._emit_log("warn", f"读取 UID 失败: {e}")
            self.toast(f"读取 UID 失败：{e}")
            return ""

    @Slot(result=str)
    def readMotto(self):
        try:
            return self._w.submit(self._w.do_read_motto()).result(timeout=10)
        except Exception as e:
            self._emit_log("warn", f"读取寄语失败: {e}")
            self.toast(f"读取寄语失败：{e}")
            return ""

    @Slot(result=str)
    def readUname(self):
        try:
            return self._w.submit(self._w.do_read_uname()).result(timeout=10)
        except Exception as e:
            self._emit_log("warn", f"读取用户名失败: {e}")
            self.toast(f"读取用户名失败：{e}")
            return ""

    def _run_simple(self, coro, ok=None):
        def _run():
            try:
                self._w.submit(coro).result(timeout=15)
                if ok:
                    self._emit_log("info", ok)
            except Exception as e:
                self._emit_log("error", f"操作失败: {e}")
                self.toast(f"操作失败：{e}")

        threading.Thread(target=_run, daemon=True).start()

    # ------------------------------------------------------------------
    # 文件传输
    # ------------------------------------------------------------------
    _UPL_FILES = ("loop.mjpeg", "intro.mjpeg", "portrait.bin", "ui_text.txt")
    _MAX_VID = 3 * 1024 * 1024   # loop/intro 单文件上限（设备 RAM 限制）

    def _check_size(self, files):
        """按白名单预检：返回 (ok_files, oversize_desc)。loop/intro 超 3MB 剔除。"""
        import os
        ok, over = [], []
        for p, fn in files:
            if fn in ("loop.mjpeg", "intro.mjpeg"):
                sz = os.path.getsize(p)
                if sz > self._MAX_VID:
                    over.append(f"{fn} {sz / 1048576:.1f}MB")
                    continue
            ok.append((p, fn))
        return ok, over

    def stageImport(self, name: str, files: list):
        """新建角色第一步：解析白名单素材并暂存，等用户点「开始上传」再传。"""
        import os
        files = [(p, fn) for p, fn in files if fn in self._UPL_FILES]
        if not files:
            self._emit_log("warn", "所选内容不含白名单素材（loop.mjpeg / intro.mjpeg / portrait.bin）")
            self.toast("没有可导入的素材文件")
            return
        files, over = self._check_size(files)
        if over:
            self.toast("文件过大：" + "、".join(over) + " 超过 3MB 上限，已剔除")
            self._emit_log("warn", "文件过大（超 3MB 上限，设备内存限制）: " + "、".join(over))
            if not files:
                return
        self._staged = {"name": name, "files": files}
        total = sum(os.path.getsize(p) for p, _ in files)
        self.stagedReady.emit(name, len(files), total, [p for p, _ in files])
        self._emit_log("info", f"已就绪 {len(files)} 个素材（{total} B），点击「开始上传」传输")

    @Slot()
    def startStagedUpload(self):
        st = getattr(self, "_staged", None)
        if not st or self._transferring:
            return
        self._batch_upload_thread(st["name"], st["files"])

    @Slot(str, str)
    def uploadAll(self, local_dir: str, rolename: str):
        """整目录上传：源目录内全部白名单素材逐个上传到目标角色。"""
        import os
        local_dir = self._to_local(local_dir)
        if not os.path.isdir(local_dir):
            self.toast("本地目录不存在")
            return
        files = [(os.path.join(local_dir, fn), fn) for fn in self._UPL_FILES
                 if os.path.isfile(os.path.join(local_dir, fn))]
        if not files:
            self.toast("目录中没有可上传的白名单素材")
            return
        files, over = self._check_size(files)
        if over:
            self.toast("文件过大：" + "、".join(over) + " 超过 3MB 上限，已剔除")
            self._emit_log("warn", "文件过大（超 3MB 上限，设备内存限制）: " + "、".join(over))
            if not files:
                return
        self._batch_upload_thread(rolename, files)

    def _batch_upload_thread(self, name: str, files: list):
        if self._transferring:
            self.toast("已有上传/下载进行中，请先停止或等待完成")
            print("[guard] busy-ignore: upload-batch", flush=True)
            return
        self._cancel.clear()
        self.toast(f"开始上传「{name}」（{len(files)} 个文件）…")

        def _run():
            self._upload_done = False
            self._upload_err = None
            self._transferring = True
            self.transferActive.emit(True)
            ok, fail = 0, []
            total_n = len(files)
            try:
                for i, (p, fn) in enumerate(files, 1):
                    if self._cancel.is_set():
                        break
                    self._upload_err = None
                    self._t_last = 0.0
                    self._b_last = 0
                    self.uploadProgress.emit(0)
                    self.transferStats.emit(0.0, 0.0, float(os.path.getsize(p)), "up")
                    self.transferFile.emit(i, total_n, fn)
                    try:
                        fut = self._w.submit(
                            self._w.do_upload(p, name, fn,
                                              progress=self._on_up_progress,
                                              status=self._on_up_status,
                                              cancel=self._cancel))
                        fut.result(timeout=900)
                        if self._upload_err:
                            raise RuntimeError(self._upload_err)
                        ok += 1
                    except Exception as e:
                        # 单文件失败不中断整批：记录并继续下一个
                        self._emit_log("warn", f"文件 {fn} 上传失败: {_exc_text(e)}")
                        fail.append(f"{fn}: {_exc_text(e)}")
                        continue
                if self._cancel.is_set():
                    self.transferDone.emit(False, "上传已停止")
                elif fail:
                    self.transferDone.emit(ok > 0,
                                           f"角色「{name}」上传 {ok} 成功 / {len(fail)} 失败（{'; '.join(fail)}）")
                else:
                    self.transferDone.emit(True, f"角色「{name}」导入完成（{ok} 个文件）")
            except Exception as e:
                self._emit_log("error", f"角色上传失败: {_exc_text(e)}")
                self.transferDone.emit(False, _exc_text(e))
            finally:
                self._transferring = False
                self.transferActive.emit(False)
                self._staged = None
                # do_upload 已等设备端 REBUILD 完成（LIST:OK 通知），可直接刷新
                self.refreshRoles()

        threading.Thread(target=_run, daemon=True).start()

    @staticmethod
    def _dl_dir(rolename: str = "") -> str:
        """下载根目录：<程序根（exe 所在目录 / 仓库根）>/Downloads[/角色名]。
        角色名子目录按需创建。"""
        import os
        import sys
        if getattr(sys, "frozen", False):
            base = os.path.dirname(sys.executable)
        else:
            base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        d = os.path.join(base, "Downloads")
        if rolename:
            d = os.path.join(d, rolename)
        os.makedirs(d, exist_ok=True)
        return d

    @staticmethod
    def _to_local(p) -> str:
        from urllib.parse import unquote
        if hasattr(p, "toLocalFile"):
            p = p.toLocalFile()
        s = str(p)
        if s.startswith("file:///"):
            s = s[len("file:///"):]
        elif s.startswith("file://"):
            s = s[len("file://"):]
        return unquote(s).replace("/", "\\")

    @Slot(str, str)
    def importRoleFolder(self, name: str, folder: str):
        import os
        folder = self._to_local(folder)
        files = []
        for fn in os.listdir(folder):
            if fn in self._UPL_FILES:
                files.append((os.path.join(folder, fn), fn))
        self.stageImport(name, files)

    @Slot(str, str, str)
    def uploadFile(self, local_path: str, rolename: str, filename: str):
        import os
        lp = self._to_local(local_path)
        if filename in ("loop.mjpeg", "intro.mjpeg") and os.path.isfile(lp):
            sz = os.path.getsize(lp)
            if sz > self._MAX_VID:
                self.toast(f"文件过大：{filename} {sz / 1048576:.1f}MB 超过 3MB 上限（设备内存限制）")
                self._emit_log("warn", f"文件过大: {filename} {sz} B 超过 3MB 上限，已拒绝上传")
                return
        if self._transferring:
            self.toast("已有上传/下载进行中，请先停止或等待完成")
            print("[guard] busy-ignore: uploadFile", flush=True)
            return
        self._cancel.clear()
        def _run():
            self._upload_done = False
            self._upload_err = None
            self._t_last = 0.0
            self._b_last = 0
            self._transferring = True
            self.transferActive.emit(True)
            try:
                self.uploadProgress.emit(0)
                self.transferFile.emit(1, 1, filename)
                fut = self._w.submit(
                    self._w.do_upload(lp, rolename, filename,
                                      progress=self._on_up_progress,
                                      status=self._on_up_status,
                                      cancel=self._cancel))
                fut.result(timeout=900)
                if self._upload_err:
                    self.transferDone.emit(False, self._upload_err)
                else:
                    self.transferDone.emit(True, f"上传完成: {rolename}/{filename}")
            except Exception as e:
                self._emit_log("error", f"上传失败: {_exc_text(e)}")
                self.transferDone.emit(False, _exc_text(e))
            finally:
                self._transferring = False
                self.transferActive.emit(False)
                # do_upload 已等设备端 REBUILD 完成（LIST:OK 通知），可直接刷新
                self.refreshRoles()

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str, str, str, str)
    def uploadUiText(self, rolename: str, leftcol: str, sub_text: str, op_name: str):
        """界面文本编辑：生成 <角色>/ui_text.txt 并上传。leftcol≤13 码点、
        sub_text≤40 码点（设备字库仅 ASCII）；op_name 可中文。**留空的行 =
        该元素不显示**（不再有内置默认文案）。"""
        import os
        import tempfile

        def _cplimit(s: str, n: int) -> str:
            out, cp = [], 0
            for ch in s:
                if cp >= n:
                    break
                out.append(ch)
                cp += 1
            return "".join(out)

        lc = _cplimit(leftcol.strip(), 13)
        st = _cplimit(sub_text.strip(), 40)
        op = _cplimit(op_name.strip(), 60)
        # 恒写三键（空值行 = 该元素不显示）；UTF-8（op_name 支持中文）
        tmp = os.path.join(tempfile.gettempdir(), "passdeck_ui_text.txt")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("# ========== 角色文本配置（本角色 ui_text.txt） ==========\n")
            f.write("# 键=值；删除值 = 界面不显示该元素\n")
            f.write("leftcol=" + lc + "\n")
            f.write("sub_text=" + st + "\n")
            f.write("op_name=" + op + "\n")
        self.uploadFile(tmp, rolename, "ui_text.txt")

    @Slot(str)
    def uploadSelfAvatar(self, local_path: str):
        """本机名片头像：任意图片 → 64x64 RGB565 LE → 上传固件（cardstore self.bin，
        覆盖发卡时的头像段，未设则发卡用内置默认图）。"""
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QImage
        src = self._to_local(local_path)
        img = QImage(src)
        if img.isNull():
            self.toast("图片读取失败")
            return
        img = img.scaled(64, 64, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        canvas = QImage(64, 64, QImage.Format_RGB16)
        canvas.fill(Qt.black)
        from PySide6.QtGui import QPainter
        with QPainter(canvas) as p:
            # 居中贴图，黑边补足非正方形
            p.drawImage(max(0, (64 - img.width()) // 2),
                        max(0, (64 - img.height()) // 2), img)
        raw = bytes(canvas.bits())
        size = len(raw)
        if size != 8192:
            self.toast("头像编码异常（非 8192 字节）")
            return
        tmp = os.path.join(tempfile.gettempdir(), "passdeck_self.bin")
        with open(tmp, "wb") as f:
            f.write(raw)
        self._emit_log("info", f"头像已缩放为 64x64 RGB565（{size} B）")
        self.uploadFile(tmp, "self", "self.bin")

    @Slot(str)
    def downloadAll(self, rolename: str):
        """打包下载：目标角色全部白名单素材 → <程序根>/Downloads/<角色名>/。"""
        if self._transferring:
            self.toast("已有上传/下载进行中，请先停止或等待完成")
            print("[guard] busy-ignore: download-batch", flush=True)
            return
        self._cancel.clear()
        self.toast(f"开始下载「{rolename}」全部素材…")
        dest = self._dl_dir(rolename)

        def _run():
            self._transferring = True
            self.transferActive.emit(True)
            ok, skip, fail = 0, 0, []
            want = self._UPL_FILES
            total_n = len(want)
            try:
                for i, fn in enumerate(want, 1):
                    if self._cancel.is_set():
                        break
                    self._t_last = 0.0
                    self._b_last = 0
                    self.downloadProgress.emit(0)
                    self.transferFile.emit(i, total_n, fn)
                    try:
                        fut = self._w.submit(self._w.do_download(
                            "/sdcard/" + rolename + "/" + fn,
                            os.path.join(dest, fn),
                            progress=self._on_dl_progress,
                            cancel=self._cancel))
                        fut.result(timeout=900)
                        ok += 1
                    except FileNotFoundError:
                        skip += 1          # 该素材设备上不存在，跳过
                        self._emit_log("warn", f"跳过（设备无此素材）: {fn}")
                    except Exception as e:
                        fail.append(f"{fn}: {_exc_text(e)}")
                        self._emit_log("error", f"下载失败 {fn}: {_exc_text(e)}")
                if self._cancel.is_set():
                    self.transferDone.emit(False, "下载已停止")
                elif fail:
                    self.transferDone.emit(ok > 0,
                                           f"下载 {ok} 成功 / {len(fail)} 失败（{'; '.join(fail)}）")
                else:
                    note = f"，{skip} 个素材设备上没有" if skip else ""
                    self.transferDone.emit(ok > 0, f"已下载 {ok} 个素材 → {dest}{note}")
            except Exception as e:
                self._emit_log("error", f"批量下载失败: {_exc_text(e)}")
                self.transferDone.emit(False, _exc_text(e))
            finally:
                self._transferring = False
                self.transferActive.emit(False)

        threading.Thread(target=_run, daemon=True).start()

    @Slot()
    def cancelTransfer(self):
        """停止正在进行的上传/下载（进度回调处抛异常中断）。"""
        self._cancel.set()
        self._emit_log("warn", "已请求停止传输…")

    def _calc_speed(self, done, total, direction):
        """进度线程内：全程平均 KB/s（单点差分会把瞬时抖动/队列积压算进速度，
        显示值与真实落盘速率偏差大）。"""
        import time
        now = time.monotonic()
        speed = 0.0
        if self._t_last > 0 and now > self._t_last and done >= self._b_last:
            speed = done / (now - self._t_last) / 1024.0
        if self._t_last <= 0:
            self._t_last = now   # 传输起点基准（首个进度点）
        self._b_last = done
        self.transferStats.emit(max(0.0, speed), float(done),
                                float(total) if total else 0.0, direction)

    def _on_up_progress(self, done, total):
        if self._cancel.is_set():
            raise RuntimeError("已取消上传")
        if total:
            self.uploadProgress.emit(int(done * 100 / total))
            self._calc_speed(done, total, "up")

    def _on_up_status(self, data: bytes):
        """BLE 线程内：解析设备状态通知 OK/PROG/DONE/ERR。"""
        if data.startswith(b"OK"):
            self._emit_log("info", "设备：上传已就绪 (OK)")
        elif data.startswith(b"PROG:"):
            try:
                pct = int(data[5:])
                self.uploadProgress.emit(pct)
            except ValueError:
                pass
        elif data.startswith(b"DONE"):
            self._emit_log("info", "设备：上传完成 (DONE)")
        elif data.startswith(b"ERR:"):
            self._upload_err = data.decode("ascii", "replace")
            self._emit_log("error", f"设备：{self._upload_err}")
            self._upload_done = True

    @Slot(str, str)
    def downloadFile(self, remote_path: str, label: str):
        """单个文件下载 → <程序根>/Downloads/<角色名>/<文件名>（角色名取自
        remote_path /sdcard/<角色>/<文件>）。"""
        import os
        parts = [p for p in remote_path.split("/") if p and p != "sdcard"]
        if len(parts) < 2:
            self.toast("下载路径无效：" + remote_path)
            return
        dest = os.path.join(self._dl_dir(parts[0]), parts[-1])
        if self._transferring:
            self.toast("已有上传/下载进行中，请先停止或等待完成")
            print("[guard] busy-ignore: downloadFile", flush=True)
            return
        self._cancel.clear()
        def _run():
            self._t_last = 0.0
            self._b_last = 0
            self._transferring = True
            self.transferActive.emit(True)
            try:
                self.downloadProgress.emit(0)
                self.transferFile.emit(1, 1, parts[-1])
                fut = self._w.submit(
                    self._w.do_download(remote_path, dest,
                                        progress=self._on_dl_progress,
                                        cancel=self._cancel))
                n = fut.result(timeout=900)
                self.transferDone.emit(True, f"已下载 {label} ({n} B) → {dest}（单文件，未选\"全部\"则到此为止）")
            except FileNotFoundError:
                self._emit_log("warn", f"设备无此素材，跳过: {label}")
                self.transferDone.emit(False, f"设备无此素材，已跳过: {label}")
            except Exception as e:
                self._emit_log("error", f"下载 {label} 失败: {_exc_text(e)}")
                self.transferDone.emit(False, _exc_text(e))
            finally:
                self._transferring = False
                self.transferActive.emit(False)

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def readCardMedia(self, mac12: str):
        """下载 /sdcard/cards/card_<mac12>.bin → 解析 blob → portrait/avatar 转 PNG。"""
        mac12 = mac12.lower()
        if not mac12:
            return
        def _run():
            tmp = os.path.join(tempfile.gettempdir(), "passdeck_media")
            try:
                os.makedirs(tmp, exist_ok=True)
                binp = os.path.join(tmp, mac12 + ".bin")
                fut = self._w.submit(
                    self._w.do_download("/sdcard/cards/card_" + mac12 + ".bin",
                                        binp, None))
                fut.result(timeout=60)
                if not os.path.exists(binp) or os.path.getsize(binp) == 0:
                    self._emit_log("warn", f"名片素材 {mac12}: bin 下载为空")
                    self.cardMediaReady.emit(mac12, "", "")
                    return
                with open(binp, "rb") as f:
                    data = f.read()
                from core.blob_parse import parse_card_blob, rgb565_to_png
                info = parse_card_blob(data)
                if not info:
                    self._emit_log("warn", f"名片 {mac12} blob 解析失败 (len={len(data)})")
                    self.cardMediaReady.emit(mac12, "", "")
                    return
                pp = ap = ""
                if info["portrait_len"]:
                    pp = os.path.join(tmp, mac12 + "_p.png")
                    if not rgb565_to_png(info["portrait"], pp):
                        pp = ""
                if info["avatar_len"]:
                    ap = os.path.join(tmp, mac12 + "_a.png")
                    if not rgb565_to_png(info["avatar"], ap):
                        ap = ""
                # Windows 路径 → file:// URL 字符串（QML Image.source 直接可用）
                def _url(p):
                    if not p:
                        return ""
                    u = p.replace("\\", "/")
                    return "file:///" + u if not u.startswith("/") else "file://" + u
                pp = _url(pp)
                ap = _url(ap)
                self._emit_log("info", f"名片素材就绪: {mac12} (portrait={info['portrait_len']} avatar={info['avatar_len']})")
                self.cardMediaReady.emit(mac12, pp, ap)
            except Exception as e:
                self._emit_log("warn", f"名片素材读取失败 {mac12}: {e}")
                self.cardMediaReady.emit(mac12, "", "")

        threading.Thread(target=_run, daemon=True).start()

    def _on_dl_progress(self, done, total):
        # 下载已带文件总大小（STAT: 查询）；进度百分比
        if self._cancel.is_set():
            raise RuntimeError("已取消下载")
        pct = int(done * 100 / max(1, total)) if total else -1
        self.downloadProgress.emit(pct)
        self._calc_speed(done, total or 0, "down")

    @Slot(str, str, str, str, str, str, str, str, str, str, int)
    def estimateMake(self, src: str, outtype: str, fps: str, quality: str,
                     position: str, start_end: str, crop_x: str = "0",
                     crop_y: str = "0", crop_w: str = "0", crop_h: str = "0",
                     rotate: int = 0):
        """设置即预估（不生成）：采样推算大小 → makeEstimate。参数同 makeFile。"""
        if not src or outtype == "portrait.bin":
            return

        def _run():
            try:
                from core import filemaker
                crop = None
                if int(crop_w or 0) > 0:
                    crop = (int(crop_x or 0), int(crop_y or 0),
                            int(crop_w or 0), int(crop_h or 0))
                se = start_end.split(",")
                est = filemaker.estimate_mjpeg_size(
                    src, fps=int(fps) if fps else 10,
                    quality=int(quality) if quality else 3,
                    position=position,
                    start=se[0].strip(),
                    end=se[1].strip() if len(se) > 1 else None,
                    crop=crop, rotate=int(rotate) % 4)
                self.makeEstimate.emit(int(est) if est is not None else -1)
            except Exception as e:
                self._emit_log("warn", f"预估计算失败: {e}")
                self.makeEstimate.emit(-1)

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str, str, str, str, str, str, str, str, str, str, str, int)
    def makeFile(self, src: str, outtype: str, fps: str, quality: str,
                 position: str, start_end: str, crop_x: str = "0",
                 crop_y: str = "0", crop_w: str = "0", crop_h: str = "0",
                 out_dir: str = "", rotate: int = 0):
        """ffmpeg 素材制作（文件制作页）。outtype 形如 loop.mjpeg / portrait.bin。
        rotate: 顺时针 90° 次数 0-3（裁剪坐标按旋转后空间）。"""
        if not src:
            self.toast("请先选择源文件")
            return
        out = os.path.join(out_dir or os.path.dirname(src), outtype)
        crop = None
        if int(crop_w or 0) > 0:
            crop = (int(crop_x or 0), int(crop_y or 0),
                    int(crop_w or 0), int(crop_h or 0))

        def _run():
            est = -1
            try:
                if outtype == "loop.mjpeg":
                    from core import filemaker
                    est = filemaker.estimate_mjpeg_size(
                        src, fps=int(fps) if fps else 10,
                        quality=int(quality) if quality else 3,
                        position=position, start=start_end.split(",")[0].strip(),
                        end=start_end.split(",")[1].strip() if len(start_end.split(",")) > 1 else None,
                        crop=crop, rotate=int(rotate) % 4)
                if est is not None:
                    self.makeEstimate.emit(int(est))
                if est is not None and est > 3 * 1024 * 1024:
                    self.makeDone.emit(False, f"预估大小 {est // 1024} KB 超过 3MB 上限（设备内存限制），请降低码率/时长", "", 0)
                    return
            except Exception:
                pass
            self._emit_log("info", f"正在转换 {os.path.basename(src)} -> {outtype} …")
            try:
                fut = self._w.submit(
                    self._w.do_make_file(
                        src, out, outtype,
                        int(fps) if fps else 10,
                        int(quality) if quality else 3,
                        position, start_end, crop, int(rotate) % 4))
                ok, msg = fut.result(timeout=1800)
                size = os.path.getsize(out) if ok else 0
                self.makeDone.emit(ok, msg, out if ok else "", size)
                self._emit_log("info" if ok else "error",
                               f"素材制作{('完成' if ok else '失败')}: {msg}")
            except Exception as e:
                self._emit_log("error", f"素材制作异常: {e}")
                self.makeDone.emit(False, str(e), "", 0)

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str)
    def probeSource(self, src: str):
        """异步探测源文件尺寸/时长/ffmpeg 可用性 → sourceProbed(w, h, ffOk, dur)。"""
        if not src:
            self.sourceProbed.emit(0, 0, False, 0)
            return

        def _run():
            try:
                from core import filemaker
                dims = filemaker.probe_dims(src)
                dur = filemaker.probe_duration(src)
                ff = bool(filemaker.find_tool("ffmpeg"))
                self.sourceProbed.emit(dims[0] if dims else 0,
                                       dims[1] if dims else 0, ff,
                                       int(dur or 0))
            except Exception as e:
                self._emit_log("warn", f"源探测失败: {e}")
                self.sourceProbed.emit(0, 0, False, 0)

        threading.Thread(target=_run, daemon=True).start()

    @Slot(str, result=str)
    def extractFrame(self, src: str):
        """视频抽一帧预览（ffmpeg 1 秒处抽帧存 %TEMP%\\passdeck_frames\\）。失败返 ""。"""
        if not src:
            return ""
        try:
            from core import filemaker
            ffmpeg = filemaker.find_tool("ffmpeg")
            if not ffmpeg:
                return ""
            d = os.path.join(tempfile.gettempdir(), "passdeck_frames")
            os.makedirs(d, exist_ok=True)
            out = os.path.join(d, os.path.basename(src) + "_preview.png")
            cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
                   "-ss", "1", "-i", src, "-frames:v", "1", out]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if r.returncode != 0 or not os.path.isfile(out):
                return ""
            return out
        except Exception:
            return ""