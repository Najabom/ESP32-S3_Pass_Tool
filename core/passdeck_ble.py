"""通行证设备 BLE 客户端（bleak 异步封装）。

识别链：
  1. 扫描：Service Data（0xFFE0 == "AP"）过滤 → 候选列表
  2. 连接：读 0xFFF5 == "PSUP" 二次确认，不符即断开
  3. 连接成功后自动写 0xFFE9（PC 当前 unix 秒）校准设备墙钟
"""

import asyncio
import struct
import time

from bleak import BleakClient, BleakScanner
from bleak.backends.scanner import AdvertisementData

from . import protocol as P


class DeviceInfo:
    """扫描到的候选设备（已通过 Service Data 识别码过滤）。"""

    def __init__(self, address: str, name: str, rssi, adv: AdvertisementData):
        self.address = address
        self.name = name or address
        self.rssi = rssi
        self.adv = adv

    @property
    def display(self) -> str:
        return f"{self.name}  ({self.address})  {self.rssi} dBm"


def is_passdeck_adv(adv) -> bool:
    """扫描层识别：Service Data 0xFFE0 == b"AP"（不依赖设备名）。

    接受 bleak AdvertisementData 或 {uuid: bytes} dict（便于 mock 测试）。
    """
    if adv is None:
        return False
    sd = adv.service_data if hasattr(adv, "service_data") else adv
    if P.ADV_SVC_UUID16 in sd:
        return sd[P.ADV_SVC_UUID16] == P.ADV_SVC_DATA
    # 部分后端把 16-bit 展开为 128-bit 完整 UUID 字符串
    full = P.uuid16(P.ADV_SVC_UUID16)
    if full in sd:
        return sd[full] == P.ADV_SVC_DATA
    return False


async def scan(timeout: float = 6.0) -> list:
    """扫描并返回本族设备列表（Service Data 过滤）。"""
    found: dict[str, DeviceInfo] = {}

    def _cb(device, adv):
        if adv is None:
            return
        if is_passdeck_adv(adv):
            name = adv.local_name or device.name
            found[device.address] = DeviceInfo(device.address, name, adv.rssi, adv)

    scanner = BleakScanner(detection_callback=_cb, scanning_mode="active")
    await scanner.start()
    try:
        await asyncio.sleep(timeout)
    finally:
        await scanner.stop()
    return list(found.values())


class PassDeckClient:
    """已连接的设备会话。所有方法为协程，调用方负责放入事件循环。"""

    def __init__(self, address: str, on_lost=None):
        self._client = BleakClient(
            address, disconnected_callback=lambda _c: on_lost and on_lost())
        self._mtu = 23

    # ------------------------------------------------------------------
    # 连接生命周期
    # ------------------------------------------------------------------
    async def connect(self) -> str | None:
        """连接 + 识别码验证 + 自动时间同步。返回 None=成功，否则错误串。"""
        try:
            await self._client.connect()
            _ = self._client.services  # bleak 3.x：同步属性（内部解析服务表）
        except Exception as e:
            return f"连接失败: {e}"
        try:
            self._mtu = self._client.mtu_size or 23
        except Exception:
            self._mtu = 23
        # 二次确认：0xFFF5 识别码
        try:
            ident = await self._client.read_gatt_char(P.CHR_IDENT)
        except Exception as e:
            await self._safe_close()
            return f"识别码读取失败: {e}"
        if ident != P.FEATURE_MAGIC:
            await self._safe_close()
            return f"识别码不符（{ident!r} ≠ {P.FEATURE_MAGIC!r}），已断开"
        # 自动时间同步（含本机时区，失败不阻断连接）
        try:
            await self.sync_time(int(time.localtime().tm_gmtoff or 0) // 60)
        except Exception:
            pass
        return None

    async def _safe_close(self):
        try:
            await self._client.disconnect()
        except Exception:
            pass

    async def close(self):
        await self._safe_close()

    @property
    def mtu(self) -> int:
        return self._mtu

    @property
    def upload_chunk(self) -> int:
        """单块上传/读取上限：min(500, MTU-3)。"""
        return min(P.RD_CHUNK_MAX, max(20, self._mtu - 3))

    # ------------------------------------------------------------------
    # 设备信息 / 配置
    # ------------------------------------------------------------------
    async def read_version(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_SWREV)
        return data.decode("utf-8", "replace").strip()

    async def read_current(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_CURRENT)
        return data.decode("utf-8", "replace").strip()

    async def write_current(self, rolename: str) -> None:
        """写 current.txt（触发设备热重载）。≤47B。"""
        if len(rolename.encode("utf-8")) > P.CFG_CURRENT_MAX:
            raise ValueError(f"角色名超长（> {P.CFG_CURRENT_MAX} B）")
        await self._client.write_gatt_char(
            P.CHR_CURRENT, rolename.encode("utf-8"), response=True)

    async def write_ui_text(self, text: str) -> None:
        data = text.encode("utf-8")
        if len(data) > P.CFG_UITEXT_MAX:
            raise ValueError(f"ui_text 超长（> {P.CFG_UITEXT_MAX} B）")
        await self._client.write_gatt_char(P.CHR_UITEXT, data, response=True)

    async def read_ipcfg(self) -> str:
        """读回 /sdcard/config/ip.txt 原文；设备无文件 → b\"\"（= 全通）。"""
        data = await self._client.read_gatt_char(P.CHR_IPCFG)
        return data.decode("utf-8", "replace").strip()

    async def write_ipcfg(self, text: str) -> None:
        data = text.encode("utf-8")
        if len(data) > P.CFG_IPCFG_MAX:
            raise ValueError(f"ip.txt 超长（> {P.CFG_IPCFG_MAX} B）")
        await self._client.write_gatt_char(P.CHR_IPCFG, data, response=True)

    async def read_loglevel(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_LOGLEVEL)
        return data.decode("utf-8", "replace").strip()

    async def write_loglevel(self, level: str) -> None:
        if level not in P.LOG_LEVELS:
            raise ValueError(f"日志级别必须是 {P.LOG_LEVELS}")
        await self._client.write_gatt_char(
            P.CHR_LOGLEVEL, level.encode("utf-8"), response=True)

    async def trigger_reload(self) -> None:
        await self._client.write_gatt_char(P.CHR_RELOAD, b"1", response=True)

    async def sync_time(self, tz_min: int | None = None) -> None:
        """绝对对齐设备墙钟。4B=仅 unix；6B=unix+时区偏移分钟（int16 LE）。"""
        if tz_min is None:
            data = struct.pack("<I", int(time.time()))
        else:
            data = struct.pack("<Ih", int(time.time()), int(tz_min))
        await self._client.write_gatt_char(P.CHR_TIME, data, response=True)

    async def clear_exchange_history(self) -> None:
        """清空设备交换历史：删 /sdcard/cards.txt 与 cards/ 全部 bin + 清冷却记录。"""
        await self._client.write_gatt_char(P.CHR_CARDCLR, b"1", response=True)

    async def set_uid(self, uid: str) -> None:
        data = uid.encode("utf-8")
        if len(data) > P.CFG_UID_MAX:
            raise ValueError(f"UID 超长（> {P.CFG_UID_MAX} B）")
        await self._client.write_gatt_char(P.CHR_UID, data, response=True)

    async def read_uid(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_UID)
        return data.decode("utf-8", "replace").strip("\x00")

    async def set_motto(self, motto: str) -> None:
        data = motto.encode("utf-8")
        if len(data) > P.CFG_MOTTO_MAX:
            raise ValueError(f"寄语超长（> {P.CFG_MOTTO_MAX} B）")
        await self._client.write_gatt_char(P.CHR_MOTTO, data, response=True)

    async def read_motto(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_MOTTO)
        return data.decode("utf-8", "replace").strip("\x00")

    async def set_uname(self, uname: str) -> None:
        data = uname.encode("utf-8")
        if len(data) > P.CFG_UNAME_MAX:
            raise ValueError(f"用户名超长（> {P.CFG_UNAME_MAX} B）")
        await self._client.write_gatt_char(P.CHR_UNAME, data, response=True)

    async def read_uname(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_UNAME)
        return data.decode("utf-8", "replace").strip("\x00")

    async def read_device_name(self) -> str:
        data = await self._client.read_gatt_char(P.CHR_BTNAME)
        return data.decode("utf-8", "replace")

    async def delete_role(self, name: str) -> None:
        """删除角色目录（固件异步递归删 /sdcard/<name>/，禁删系统目录）。"""
        data = name.encode("utf-8")
        if not data or len(data) >= P.CFG_CURRENT_MAX:
            raise ValueError(f"角色名不合法（1~{P.CFG_CURRENT_MAX - 1} 字节）")
        await self._client.write_gatt_char(P.CHR_DEL, data, response=True)

    async def write_device_name(self, name: str) -> None:
        data = name.encode("utf-8")
        if not data or len(data) > 15:
            raise ValueError("设备名需 1~15 字节")
        if any(b < 0x20 for b in data):
            raise ValueError("设备名含控制字符")
        await self._client.write_gatt_char(P.CHR_BTNAME, data, response=True)

    async def list_roles(self) -> list:
        """角色目录列表：循环读 0xFFF1 至空段，按行拆分。"""
        names = []
        while True:
            data = await self._client.read_gatt_char(P.CHR_LIST)
            if not data:
                break
            names.append(data.decode("utf-8", "replace"))
        lines = []
        for part in names:
            lines.extend(part.split("\n"))
        return [x for x in lines if x]

    async def open_file(self, path: str) -> None:
        """打开 /sdcard/ 下文件（游标会话）。路径须以 /sdcard/ 开头。
        ":self:" 特判：cardstore 分区本机头像（SPIFFS 裸 RGB565）。"""
        if path != ":self:" and (not path.startswith("/sdcard/") or ".." in path):
            raise ValueError("路径必须以 /sdcard/ 开头且不含 ..")
        cmd = "PATH:" + path
        data = cmd.encode("utf-8")
        if len(data) > P.RD_CHUNK_MAX + 5:
            raise ValueError("路径过长")
        await self._client.write_gatt_char(P.CHR_READFILE, data, response=True)

    async def read_file_chunk(self) -> bytes:
        """读下一段（≤500B）。EOF 返回 b""；打开失败首段返回 b"ERR:open"。"""
        return await self._client.read_gatt_char(P.CHR_READFILE)

    async def stat_file(self, path: str) -> int:
        """查询 /sdcard/ 下文件大小（STAT: 命令，下个 READ 返回 4B LE）。
        文件不存在返回 0xFFFFFFFF。"""
        if path != ":self:" and (not path.startswith("/sdcard/") or ".." in path):
            raise ValueError("路径必须以 /sdcard/ 开头且不含 ..")
        cmd = "STAT:" + path
        await self._client.write_gatt_char(P.CHR_READFILE, cmd.encode("utf-8"), response=True)
        data = await self._client.read_gatt_char(P.CHR_READFILE)
        if len(data) != 4:
            raise FileNotFoundError(f"设备端无此文件: {path}")
        return int.from_bytes(data, "little")

    async def download_file(self, path: str, progress=None, cancel=None) -> bytes:
        """整文件下载（先查大小，再 readfile 游标循环）。
        progress(done, total) 可选——total 为文件实际大小。
        cancel(threading.Event) 可选——置位后中止（下个分片前检查）。"""
        import time as _t
        _t0 = _t.monotonic()
        size = await self.stat_file(path)
        if size == 0xFFFFFFFF:
            raise FileNotFoundError(f"设备端无此文件: {path}")
        await self.open_file(path)
        buf = bytearray()
        while True:
            if cancel is not None and cancel.is_set():
                raise RuntimeError("已取消下载")
            chunk = await self.read_file_chunk()
            if chunk == P.ERR_OPEN:
                raise FileNotFoundError(f"设备端打开失败: {path}")
            if not chunk:
                break
            buf += chunk
            if progress:
                progress(len(buf), size)
        return bytes(buf)

    # ------------------------------------------------------------------
    # 素材上传
    # ------------------------------------------------------------------
    async def subscribe_status(self, cb) -> None:
        await self._client.start_notify(P.CHR_UPLSTATUS, cb)

    async def unsubscribe_status(self) -> None:
        try:
            await self._client.stop_notify(P.CHR_UPLSTATUS)
        except Exception:
            pass

    async def upload_file(self, data: bytes, rolename: str, filename: str, progress=None, cancel=None) -> None:
        """整文件上传（窗口化：3 无响应 + 1 响应同步点，吞吐 ~4x）。
        cancel(threading.Event) 可选——置位后中止。"""
        await self.upload_start(rolename, filename, len(data))
        off = 0
        win = 0
        for ch in P.chunk_sizes(len(data), self.upload_chunk):
            if cancel is not None and cancel.is_set():
                raise RuntimeError("已取消上传")
            await self.upload_write(data[off:off + ch], response=(win == 3))
            win = 0 if win == 3 else win + 1
            off += ch
            if progress:
                progress(off, len(data))
        await self.upload_end()

    async def upload_start(self, rolename: str, filename: str, size: int) -> None:
        err = P.validate_upload(rolename, filename, size)
        if err:
            raise ValueError(err)
        cmd = f"START:{rolename}/{filename}:{size}".encode("utf-8")
        await self._client.write_gatt_char(P.CHR_UPLOAD, cmd, response=True)

    async def upload_write(self, data: bytes, response: bool = True) -> None:
        """数据块：response=True 做同步点；False 无响应写（吞吐）。
        设备端 START 时记录 size，END 后按累计校验兜底丢块。"""
        await self._client.write_gatt_char(P.CHR_UPLOAD, data, response=response)

    async def upload_end(self) -> None:
        # 无响应写：设备端 host 内 fclose 抢 SD 锁时 ACK 可能迟回，等它会卡住
        await self._client.write_gatt_char(P.CHR_UPLOAD, b"END", response=False)