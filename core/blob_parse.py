"""名片 blob 解析（nfc_proto.h card_blob_hdr_t）与 RGB565 转 PNG。

blob 布局（packed，LE）：
  v5 (ver=5, HDR 236B)：magic "CRD1"(u32) ver(u8) name_len(u8) name[64] uid_len(u8) uid[20]
            motto_len(u8) motto[64] avatar_len(u16) sticker_cnt(u8)
            sticker_len[3](u16) ts(u32) uname_len(u8) uname[64] portrait_len(u16)
  v4 (ver=4, HDR 196B)：同上但 name[24]
  v3 (ver=3, HDR 104B 旧)：同上但 motto[20] uname[16]
  数据区：portrait(portrait_len) → avatar(avatar_len) → stickers(sticker_len...)
portrait/avatar 均为 64x64 RGB565 小端（8192B）。
"""

import struct

CARD_BLOB_MAGIC = 0x31445243          # "CRD1" LE
HDR_SIZE = 236                         # v5：name[64] + motto[64] + uname[64]
HDR_SIZE_LEGACY = 104                  # 旧 v3：motto[20] + uname[16]

# 各版本字段容量
_V3_MOTTO_N = 20
_V3_UNAME_N = 16
_V4_MOTTO_N = 64
_V4_UNAME_N = 64
_V4_NAME_N = 24                       # v4/v3 name=24；v5=64
_V5_NAME_N = 64

_VER_ALLOWED = (3, 4, 5)


def parse_card_blob(data):
    """解析 blob → dict（字段 + portrait/avatar/stickers 原始字节）。失败返 None。"""
    if len(data) < HDR_SIZE_LEGACY:
        return None
    if struct.unpack_from("<I", data, 0)[0] != CARD_BLOB_MAGIC:
        return None
    ver = data[4]
    if ver not in _VER_ALLOWED:
        return None
    if ver == 3:
        motto_n = _V3_MOTTO_N
        uname_n = _V3_UNAME_N
        name_n = _V4_NAME_N
    else:
        motto_n = _V4_MOTTO_N
        uname_n = _V4_UNAME_N
        name_n = _V5_NAME_N if ver >= 5 else _V4_NAME_N

    def _txt(buf):
        return buf.decode("utf-8", "replace").rstrip("\x00")

    name_len = data[5]
    name = _txt(data[6:6 + name_n][:name_len])
    off = 6 + name_n
    uid_len = data[off]
    uid = _txt(data[off + 1:off + 1 + 20][:uid_len])
    off += 1 + 20
    motto_len = data[off]
    motto = _txt(data[off + 1:off + 1 + motto_n][:motto_len])
    off += 1 + motto_n
    avatar_len, sticker_cnt = struct.unpack_from("<HB", data, off)
    off += 3
    sticker_len = list(struct.unpack_from("<HHH", data, off))
    off += 6
    ts = struct.unpack_from("<I", data, off)[0]
    off += 4
    uname_len = data[off]
    uname = _txt(data[off + 1:off + 1 + uname_n][:uname_len])
    off += 1 + uname_n
    portrait_len = struct.unpack_from("<H", data, off)[0]
    off += 2

    portrait = data[off:off + portrait_len] if portrait_len else b""
    off += portrait_len
    avatar = data[off:off + avatar_len] if avatar_len else b""
    off += avatar_len
    stickers = []
    for sl in sticker_len[:sticker_cnt]:
        stickers.append(data[off:off + sl])
        off += sl

    return {
        "name": name, "uid": uid, "motto": motto, "uname": uname,
        "avatar_len": avatar_len, "portrait_len": portrait_len,
        "sticker_cnt": sticker_cnt, "ts": ts,
        "portrait": portrait, "avatar": avatar, "stickers": stickers,
    }


def rgb565_to_png(rgb565, out_path, w=64, h=64):
    """RGB565 小端 → PNG 文件（LE 平台 Format_RGB16 直接映射）。返回是否成功。"""
    if len(rgb565) < w * h * 2:
        return False
    from PySide6.QtGui import QImage
    img = QImage(rgb565, w, h, w * 2, QImage.Format_RGB16).copy()
    return img.save(out_path)


def rgb565_to_jpg(rgb565, out_path, w=64, h=64, quality=92):
    """RGB565 小端 → JPEG 文件（下载 portrait.bin 时自动转码）。返回是否成功。"""
    if len(rgb565) < w * h * 2:
        return False
    from PySide6.QtGui import QImage
    img = QImage(rgb565, w, h, w * 2, QImage.Format_RGB16).copy()
    return img.save(out_path, "JPG", quality)
