"""通行证设备 BLE 应用协议层（与固件 src/nfc/ble_gatt.c 约定逐条对齐）。

识别不依赖设备名：
  - 扫描阶段：广播 16-bit Service Data（UUID 0xFFE0, payload "AP"）
  - 连接阶段：读 0xFFF5 返回 4B "PSUP"
两者均为预埋在程序内部的固定识别码。
"""

# ---------------------------------------------------------------------------
# 设备族识别码（与固件 BLE_FEATURE_MAGIC / 广播 svc_data 一致，勿改）
# ---------------------------------------------------------------------------
FEATURE_MAGIC = b"PSUP"          # GATT 0xFFF5 只读返回（LE 字节序 "PSUP"）
ADV_SVC_UUID16 = 0xFFE0          # 广播 Service Data UUID（16-bit）
ADV_SVC_DATA = b"AP"             # 广播 Service Data payload

# ---------------------------------------------------------------------------
# UUID（16-bit 简写 → 完整 128-bit 字符串，bleak 使用）
# ---------------------------------------------------------------------------
_UUID16_TMPL = "0000%04x-0000-1000-8000-00805f9b34fb"


def uuid16(u: int) -> str:
    return _UUID16_TMPL % u


# 设备信息 0x180A
SVC_DEVINFO = uuid16(0x180A)
CHR_SWREV = uuid16(0x2A28)                  # 软件版本（只读）
# 设置服务 0xFFE0
SVC_SETTINGS = uuid16(0xFFE0)
CHR_CURRENT = uuid16(0xFFE1)                # current.txt（读写，写后热重载）
CHR_UITEXT = uuid16(0xFFE2)                 # 当前角色 ui_text.txt（只写 ≤128B，原样替换无模板头）
CHR_IPCFG = uuid16(0xFFE3)                  # ip.txt（只写 ≤256B）
CHR_LOGLEVEL = uuid16(0xFFE4)               # 日志级别（读写）
CHR_RELOAD = uuid16(0xFFE5)                 # 热重载（只写）
CHR_UID = uuid16(0xFFE6)                    # 名片 uid（只写 ≤20B）
CHR_MOTTO = uuid16(0xFFE7)                  # 名片 motto（只写 ≤64B UTF-8）
CHR_UNAME = uuid16(0xFFE8)                  # 名片 uname（只写 ≤64B UTF-8）
CHR_TIME = uuid16(0xFFE9)                   # unix 秒（只写 4B LE；6B = +tz int16 LE）
CHR_BTNAME = uuid16(0xFFEA)                 # 设备名（读写 ≤15B；写后设备重写 bt.txt 并重开广播）
CHR_CARDCLR = uuid16(0xFFEE)                # 清空交换历史（只写任意字节；删 cards.txt+cards/ 并清冷却 NVS）
# SD 服务 0xFFF0
SVC_SD = uuid16(0xFFF0)
CHR_LIST = uuid16(0xFFF1)                   # 角色目录列表（只读，游标分段）
CHR_READFILE = uuid16(0xFFF2)               # 文件读取（写 PATH: 打开，读分段）
CHR_UPLOAD = uuid16(0xFFF3)                 # 素材上传（只写）
CHR_UPLSTATUS = uuid16(0xFFF4)              # 上传状态（通知）
CHR_IDENT = uuid16(0xFFF5)                  # 设备识别码（只读 "PSUP"）
CHR_DEL = uuid16(0xFFF6)                    # 删除角色（只写；角色名，禁系统目录）

# ---------------------------------------------------------------------------
# 尺寸与协议常量（与固件一致）
# ---------------------------------------------------------------------------
CFG_CURRENT_MAX = 47         # current.txt 写入上限
CFG_UITEXT_MAX = 128
CFG_IPCFG_MAX = 256
CFG_UID_MAX = 20
CFG_MOTTO_MAX = 64
CFG_UNAME_MAX = 64
RD_CHUNK_MAX = 500           # list / readfile 单段上限
UPL_TOTAL_MAX = 4 * 1024 * 1024
UPL_TIMEOUT_S = 30           # 设备端无数据超时

LOG_LEVELS = ("warn", "info", "debug", "error", "verbose")

# 可上传的素材文件（白名单，与固件 upl_validate 一致）
UPLOADABLE_FILES = ("loop.mjpeg", "intro.mjpeg", "portrait.bin", "ui_text.txt", "self.bin")

# readfile 打开失败时设备返回的标记（8 字节）
ERR_OPEN = b"ERR:open"

# 上传状态通知前缀
NOTIF_OK = b"OK"
NOTIF_DONE = b"DONE"
NOTIF_PROG = b"PROG:"
NOTIF_ERR = b"ERR:"

# ---------------------------------------------------------------------------
# 纯逻辑工具（可单测，不依赖 bleak）
# ---------------------------------------------------------------------------


def parse_prog(notif: bytes):
    """解析通知 PROG:n → 0..100；非进度通知返回 None。"""
    if notif.startswith(NOTIF_PROG):
        try:
            return int(notif[len(NOTIF_PROG):])
        except ValueError:
            return None
    return None


def chunk_sizes(total: int, chunk: int):
    """上传分块尺寸序列（测试/进度计算用）。"""
    sizes = []
    left = total
    while left > 0:
        n = min(chunk, left)
        sizes.append(n)
        left -= n
    return sizes


def validate_upload(rolename: str, filename: str, size: int):
    """上传参数预校验：与固件 upl_validate 同规则。返回错误串或 None。"""
    if not rolename or "/" in rolename or ":" in rolename or len(rolename.encode("utf-8")) > 48:
        return "角色名不合法（禁 / 与 :，UTF-8 ≤48 字节 ≈ 16 个汉字）"
    if filename not in UPLOADABLE_FILES:
        return "文件不在白名单（loop.mjpeg / intro.mjpeg / portrait.bin / ui_text.txt / self.bin）"
    if size <= 0 or size > UPL_TOTAL_MAX:
        return f"大小越界（1 ~ {UPL_TOTAL_MAX} B）"
    # 视频素材 3MB 上限（设备 PSRAM 缓冲预留不足；intro.mjpeg 3.06MB 老素材仍可传）
    if filename in ("loop.mjpeg", "intro.mjpeg") and size > 3 * 1024 * 1024:
        return (f"{filename} 大小 {size // 1024}KB 超过 3MB 上限（设备内存限制），"
                "请降低码率/时长或降低分辨率")
    return None