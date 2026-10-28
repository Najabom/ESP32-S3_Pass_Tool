"""后台 BLE 任务执行器：专用事件循环线程，纯 Python（不依赖 Qt）。
用法：Worker.start() 后 submit(coro) 投递任务；任务间自动串行执行（BLE 客户端同一
会话），回调在 BLE 线程内触发。"""

import asyncio
import os
import tempfile
import threading

from .passdeck_ble import PassDeckClient, scan as ble_scan
from . import protocol as P
from . import filemaker
from . import blob_parse


class Worker:
    """BLE 客户端工作线程包装：submit(coro) 到专用事件循环。"""

    def __init__(self, log=None, on_lost=None):
        self._loop = None
        self._thread = None
        self._client = None
        self._address = None
        self.connected = False
        self._log = log or (lambda level, text: None)
        # 掉线感知回调（BLE 线程内触发；调用方自行保证线程安全）
        self._on_lost = on_lost
        # 手动断开时抑制掉线回调（close() 也会触发 disconnected_callback）
        self._suppress_lost = False

    def _handle_lost(self):
        if not self.connected or self._suppress_lost:
            return
        self.connected = False
        if self._on_lost:
            try:
                self._on_lost()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # 生命周期
    # ------------------------------------------------------------------
    def start(self):
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._loop.run_forever, daemon=True)
        self._thread.start()

    def stop(self):
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=2)

    def submit(self, coro):
        if not self._loop:
            raise RuntimeError("worker not started")
        return asyncio.run_coroutine_threadsafe(coro, self._loop)

    def _require(self):
        if not self._client:
            raise ConnectionError("未连接设备")

    # ------------------------------------------------------------------
    # 扫描 / 连接
    # ------------------------------------------------------------------
    async def do_scan(self):
        return await ble_scan(timeout=6.0)

    async def do_connect(self, address: str):
        if self._client:
            self._suppress_lost = True
            try:
                await self._client.close()
            finally:
                self._suppress_lost = False
            self._client = None
        c = PassDeckClient(address, on_lost=self._handle_lost)
        err = await c.connect()
        if err:
            self.connected = False
            return False, err
        self._client = c
        self._address = address
        self.connected = True
        return True, "ok"

    async def do_disconnect(self):
        if self._client:
            self._suppress_lost = True
            try:
                await self._client.close()
            finally:
                self._suppress_lost = False
            self._client = None
        self.connected = False
    # 设备信息 / 配置
    # ------------------------------------------------------------------
    async def do_read_version(self):
        self._require()
        return await self._client.read_version()

    async def do_read_current(self):
        self._require()
        return await self._client.read_current()

    async def do_select_role(self, rolename: str):
        self._require()
        await self._client.write_current(rolename)
        self._log("info", f"角色已切换: {rolename}（设备热重载中）")

    async def do_refresh_roles(self):
        self._require()
        return await self._client.list_roles()

    async def do_write_ui_text(self, text: str):
        self._require()
        # 0xFFE2：原样整文本写入【当前角色】ui_text.txt（设备侧写当前角色目录）
        await self._client.write_ui_text(text)
        self._log("info", "ui_text.txt 已写入（当前角色）")

    async def do_read_ipcfg(self):
        """读回企划配置原文（多行）；空 = 全通。"""
        self._require()
        raw = await self._client.read_ipcfg()
        lines = [ln.strip() for ln in raw.splitlines()
                 if ln.strip() and not ln.strip().startswith("#")]
        return "\n".join(lines)

    async def do_write_ipcfg(self, text: str):
        self._require()
        await self._client.write_ipcfg(text)
        self._log("info", "企划配置已写入 ip.txt（ESP-NOW 10s 内重载）")

    async def do_clear_ipcfg(self):
        """删除企划配置 = 写入空行（全通）。0 字节 BLE 写不可靠，发一个空行。"""
        self._require()
        await self._client.write_ipcfg("\n")
        self._log("info", "企划配置已删除（不隔离 = 全通）")

    async def do_read_loglevel(self):
        self._require()
        return await self._client.read_loglevel()

    async def do_write_loglevel(self, level: str):
        self._require()
        await self._client.write_loglevel(level)
        self._log("info", f"日志级别 -> {level}")

    async def do_reload(self):
        self._require()
        await self._client.trigger_reload()
        self._log("info", "已触发热重载")

    async def do_sync_time(self, tz_min: int | None = None):
        self._require()
        await self._client.sync_time(tz_min)
        self._log("info", "已同步 PC 时间到设备（绝对对齐）")

    async def do_set_uid(self, uid: str):
        self._require()
        await self._client.set_uid(uid)
        self._log("info", "名片 UID 已更新")

    async def do_set_motto(self, motto: str):
        self._require()
        await self._client.set_motto(motto)
        self._log("info", "名片寄语已更新")

    async def do_set_uname(self, uname: str):
        self._require()
        await self._client.set_uname(uname)
        self._log("info", "名片用户名已更新")

    async def do_read_uid(self):
        self._require()
        return await self._client.read_uid()

    async def do_read_motto(self):
        self._require()
        return await self._client.read_motto()

    async def do_read_uname(self):
        self._require()
        return await self._client.read_uname()

    async def do_read_device_name(self):
        self._require()
        return await self._client.read_device_name()

    async def do_write_device_name(self, name: str):
        self._require()
        await self._client.write_device_name(name)
        self._log("info", f"设备名 -> {name}（广播重开）")

    async def do_delete_role(self, name: str):
        """删除角色目录（固件异步删 /sdcard/<name>/ 并刷新列表缓存）。
        先订阅 status 再删（等 LIST:OK = 缓存重建完成才拉新列表，
        否则列表刷新读到旧缓存/空）。删除失败时 err 通知直接抛出。"""
        self._require()
        err_msgs = []
        list_ok = []

        def _notify(_handle, data):
            if data.startswith(b"ERR"):
                err_msgs.append(data.decode("utf-8", "replace"))
            elif data.startswith(b"LIST:OK"):
                list_ok.append(True)

        await self._client.subscribe_status(_notify)
        try:
            await self._client.delete_role(name)
            self._log("info", f"已请求删除角色: {name}")
            for i in range(60):
                if err_msgs:
                    raise RuntimeError(err_msgs[0])
                if list_ok:
                    break
                await asyncio.sleep(0.5)
            else:
                self._log("warn", "删除后 LIST:OK 未到（REBUILD 可能仍在进行）")
        finally:
            await self._client.unsubscribe_status()

    # ------------------------------------------------------------------
    # SD 文件
    # ------------------------------------------------------------------
    async def do_download(self, remote_path: str, save_path: str, progress=None, cancel=None):
        self._require()
        # portrait.bin 下载时自动转码为 jpg（本地免 bin 工具链）
        jpg_out = remote_path.endswith("portrait.bin")
        if jpg_out:
            save_path = save_path[:-4] + ".jpg" if save_path.lower().endswith(".bin") \
                else save_path + ".jpg"

        def _save(data):
            if jpg_out:
                if not blob_parse.rgb565_to_jpg(data, save_path, 64, 64):
                    raise RuntimeError("RGB565 → JPEG 转码失败")
            else:
                with open(save_path, "wb") as f:
                    f.write(data)

        def _prog(done, total):
            if progress:
                progress(done, total)

        data = await self._client.download_file(remote_path, _prog, cancel)
        _save(data)
        self._log("info", f"已下载 {remote_path} -> {save_path} ({len(data)} B)")
        return len(data)

    async def do_read_self(self) -> str:
        """读取本机头像：self.bin 特判（cardstore 分区）→ 转 PNG 存临时目录
        返回 file:// URL 字符串（QML Image.source 直接可用）。"""
        self._require()
        data = await self._client.download_file(":self:")
        if len(data) != 8192:
            raise ValueError(f"本机头像数据异常: {len(data)} B（期望 8192 B）")
        out = os.path.join(tempfile.gettempdir(), "passdeck_self.png")
        blob_parse.rgb565_to_png(data, out, w=64, h=64)
        self._log("info", f"本机头像已载入: {out}")
        url = out.replace("\\", "/")
        return "file:///" + url if not url.startswith("/") else "file://" + url

    async def do_stat_files(self, rolename: str):
        """列出角色目录实际存在的素材（4 白名单内）。返回 [(name,size)...]，
        不存在的文件（stat = 0xFFFFFFFF / 异常）不列入，避免假性 4096MB。"""
        self._require()
        files = ("loop.mjpeg", "intro.mjpeg", "portrait.bin", "ui_text.txt")
        out = []
        for fn in files:
            path = f"/sdcard/{rolename}/{fn}"
            try:
                size = await self._client.stat_file(path)
            except Exception as e:
                self._log("warn", f"stat {path} 失败: {e}")
                continue
            if size == 0xFFFFFFFF or size is None:
                self._log("warn", f"素材缺失（设备返回无此文件 0xFFFFFFFF）: {rolename}/{fn}")
                continue
            out.append((fn, size))
        self._log("info", f"角色素材清单 {rolename}: " + ", ".join(
            f"{n}={s}" for n, s in out) + f" （共 {len(out)} 项）")
        return out

    async def do_read_ui_text(self, rolename: str):
        """读角色 ui_text.txt 内容回填编辑框。返回 (leftcol, sub_text, op_name)。
        无文件（设备将自动生成模板）→ ("", "", "")。"""
        self._require()
        path = f"/sdcard/{rolename}/ui_text.txt"
        try:
            data = await self._client.download_file(path)
        except FileNotFoundError:
            self._log("info", f"界面文本 {rolename}: 无文件（下次加载自动生成模板）")
            return ("", "", "")
        text = data.decode("utf-8", "replace")
        lc = sub = op = ""
        for line in text.splitlines():
            line = line.strip("\r")
            if line.startswith("leftcol="):
                lc = line[len("leftcol="):]
            elif line.startswith("sub_text="):
                sub = line[len("sub_text="):]
            elif line.startswith("op_name="):
                op = line[len("op_name="):]
        self._log("info",
                  f"界面文本 {rolename}: leftcol='{lc}' sub_text='{sub}' op_name='{op}'")
        return (lc, sub, op)

    async def do_read_cards(self):
        """读取设备 /sdcard/cards.txt 名片记录，解析为字段 dict 列表。"""
        self._require()
        try:
            data = await self._client.download_file("/sdcard/cards.txt")
        except FileNotFoundError:
            return []
        except Exception as e:
            self._log("warn", f"读名片失败: {e}")
            raise

        text = data.decode("utf-8", "replace")
        cards = parse_cards(text)
        self._log("info", f"名片记录: {len(cards)} 条")
        return cards



    async def do_upload(self, local_path: str, rolename: str, filename: str,
                        progress=None, status=None, cancel=None):
        self._require()
        # portrait 目标允许直接选图片（jpg/png…，与下载端自动转码对称）：
        # 本端先经 ffmpeg 转 64x64 RGB565，再走原上传管线
        conv = None
        if filename == "portrait.bin" and os.path.splitext(local_path)[1].lower() in (
                ".jpg", ".jpeg", ".png", ".bmp", ".webp"):
            from . import filemaker
            tmp = os.path.join(os.path.dirname(os.path.abspath(local_path)),
                               "_portrait_conv.bin")
            try:
                ok, msg = filemaker.make_portrait(local_path, tmp)
                if not ok:
                    raise ValueError(msg)
                with open(tmp, "rb") as f:
                    conv = f.read()
            finally:
                if os.path.isfile(tmp):
                    os.remove(tmp)
            self._log("info", "portrait: 图片源已转 64x64 RGB565（" +
                      str(len(conv)) + " B）")
        size = len(conv) if conv is not None else os.path.getsize(local_path)
        err = P.validate_upload(rolename, filename, size)
        if err:
            raise ValueError(err)

        err_msgs = []
        done_flags = []
        list_ok = []

        def _notify(_handle, data: bytearray):
            s = bytes(data)
            if s.startswith(b"ERR") and not err_msgs:
                err_msgs.append(s.decode("utf-8", "replace"))
            elif s.startswith(b"DONE"):
                done_flags.append(True)
            elif s.startswith(b"LIST:OK"):
                list_ok.append(True)

        await self._client.subscribe_status(_notify)

        if conv is not None:
            data = conv
        else:
            with open(local_path, "rb") as f:
                data = f.read()
        total = len(data)
        await self._client.upload_start(rolename, filename, total)
        # 窗口化写入：3 块无响应 + 1 块响应（ACK 同步点，附加进度）
        win = 3
        acked = 0
        pending = 0
        chunk = 500
        for off in range(0, total, chunk):
            if cancel is not None and cancel.is_set():
                raise RuntimeError("已取消上传")
            b = data[off:off + chunk]
            pending += len(b)
            if win == 0 or len(b) < chunk:
                sync = (win == 0 or len(b) < chunk)
                await self._client.upload_write(b, response=sync)
                # 同步点：此 write 的 ACK 到达 = 窗口内前面 NO_RSP 块已被处理
                acked += pending
                pending = 0
                win = 3
            else:
                await self._client.upload_write(b, response=False)
                win -= 1
            if progress:
                progress(acked, total)

        # END 尾部（收尾标记：设备收到即开始落盘校验）
        await self._client.upload_end()

        stat_ok = False
        for i in range(240):
            if cancel is not None and cancel.is_set():
                raise RuntimeError("已取消上传")
            if err_msgs:
                raise RuntimeError(err_msgs[0])
            if done_flags:
                break
            if i % 20 == 19 and filename != "self.bin":
                try:
                    if await self._client.stat_file(f"/sdcard/{rolename}/{filename}") == size:
                        stat_ok = True
                        break
                except Exception:
                    pass
            await asyncio.sleep(0.5)
        else:
            # 设备端 DONE 通知可能被 BLE 丢（att write 竞态），兜底：
            # 直接 STAT 校验目标文件大小 == 期望（写入已落盘的证据）
            if filename == "self.bin":
                await self._client.unsubscribe_status()
                raise RuntimeError("设备端未确认写入完成（超时）")
            try:
                sz = await self._client.stat_file(f"/sdcard/{rolename}/{filename}")
            except Exception:
                sz = -1
            if sz == size:
                stat_ok = True
            else:
                await self._client.unsubscribe_status()
                raise RuntimeError("设备端未确认写入完成（超时）")
        if stat_ok:
            self._log("info", "DONE 通知丢失，STAT 核验通过")

        # 等 LIST:OK（REBUILD 完成通知）：列表缓存重建完才拉新列表，
        # 否则读缓存拿到旧列表（新文件名/删除不生效）
        for _ in range(60):
            if cancel is not None and cancel.is_set():
                await self._client.unsubscribe_status()
                raise RuntimeError("已取消上传")
            if err_msgs:
                await self._client.unsubscribe_status()
                raise RuntimeError(err_msgs[0])
            if list_ok:
                break
            await asyncio.sleep(0.5)
        else:
            self._log("warn", "LIST:OK 未到（REBUILD 可能仍在进行），拉列表稍后重试即可")

        await self._client.unsubscribe_status()
        self._log("info", f"上传完成: {rolename}/{filename} ({size} B)")

    async def do_make_file(self, src: str, out: str, outtype: str, fps: int,
                           quality: int, position: str, start_end: str,
                           crop=None, rotate: int = 0):
        """ffmpeg 素材转换。ffmpeg/ffprobe 为同步阻塞（可达数十分钟），必须放
        线程池执行，避免卡死承载 BLE 回调的事件循环。返回 (ok, msg)。"""
        if not os.path.isfile(src):
            return False, "源文件不存在"

        def _work():
            if outtype == "portrait.bin":
                return filemaker.make_portrait(src, out)
            start = end = None
            if start_end:
                parts = start_end.split(",")
                start = parts[0].strip() or None
                end = parts[1].strip() if len(parts) > 1 and parts[1].strip() else None
            # 3MB 上限：取样估算，超限拒绝生成（设备 PSRAM 预留不足）
            if outtype == "loop.mjpeg":
                est = filemaker.estimate_mjpeg_size(src, fps=fps, quality=quality,
                                                    position=position, start=start,
                                                    end=end, crop=crop, rotate=rotate)
                if est is not None and est > 3 * 1024 * 1024:
                    return False, (f"预计大小 {est // 1024} KB 超过 3MB 上限"
                                   f"（设备内存限制），请降低码率/时长")
            return filemaker.make_mjpeg(src, out, fps=fps, quality=quality,
                                        position=position, start=start,
                                        end=end, crop=crop, rotate=rotate)

        return await asyncio.to_thread(_work)

def parse_cards(text: str) -> list:
    """解析设备 cards.txt 文本 → 字段 dict 列表（backend readCards 复用）。

    数据行 = "#0001 | up=114s | mac=..."（卡序号也是 # 前缀），
    只有注释行（无 mac=）才跳过。若跳过 # 行会丢掉全部卡片。
    """
    cards = []
    for line in text.splitlines():
        line = line.strip()
        if not line or "mac=" not in line:
            continue
        fields = {}
        for part in line.split(" | "):
            p = part.strip()
            if p.startswith("#"):
                # 序号在行首 "#%04ld"，前导 # 剪掉后做数字解析
                seq_str = p[1:]
                # 该段可能同时含其他内容，但 card_log 格式为 "#NNNN" 独立段，安全。
                try:
                    fields["seq"] = int(seq_str)
                except ValueError:
                    pass
            elif p.startswith("up="):
                # 设备整文件重写（时间对齐/迁移）可能撕裂出乱码段（如 "up=8872#0203"），
                # 单段解析失败只跳过该段，不放弃整张卡。
                try:
                    fields["up"] = int(p[3:].rstrip("s"))
                except ValueError:
                    pass
            elif p.startswith("mac="):
                fields["mac"] = p[4:]
            elif p.startswith('uname="'):
                fields["uname"] = p[7:-1]
            elif p.startswith('name="'):
                fields["name"] = p[6:-1]
            elif p.startswith("ip="):
                fields["ip"] = p[3:]
            elif p.startswith("uid="):
                fields["uid"] = p[4:]
            elif p.startswith('motto="'):
                fields["motto"] = p[7:-1]
            elif p.startswith("avatar="):
                fields["avatar"] = p[7:]
            elif p.startswith("portrait="):
                fields["portrait"] = p[9:]
            elif p.startswith("stk="):
                fields["stk"] = p[4:]
        if "mac" in fields:
            cards.append(fields)
    return cards
