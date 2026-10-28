import io
import os
import struct
from pathlib import Path

from PySide6.QtCore import QBuffer, QByteArray, QRectF
from PySide6.QtGui import QColor, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "ui" / "assets" / "logo.svg"
OUT = ROOT / "assets" / "app_icon.ico"
OUT_PNG = ROOT / "assets" / "app_icon.png"


def render_qimg(size: int) -> QImage:
    r = QSvgRenderer(QByteArray(open(LOGO, "rb").read()))
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(QColor(0, 0, 0, 0))
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    r.render(p, QRectF(0, 0, size, size))
    p.end()
    return img


def frame_png(size: int) -> bytes:
    qimg = render_qimg(size)
    buf = QBuffer()
    buf.open(QBuffer.ReadWrite)
    qimg.save(buf, "PNG")
    data = bytes(buf.data())
    buf.close()
    return data


def bmp_frame_data(size: int) -> bytes:
    """32bit BGRA DIB (V3) + AND mask, top-down。"""
    img = Image.open(io.BytesIO(frame_png(size))).convert("RGBA")
    w = h = size
    raw = img.tobytes("raw", "BGRA")
    dib = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0,
                      w * 4 * h, 0, 0, 0, 0)
    dib += raw
    mask_stride = ((w + 31) // 32) * 4
    dib += b"\x00" * (mask_stride * h)
    return dib


def main():
    sizes = [16, 32, 48, 64, 128, 256]
    pngs = {s: frame_png(s) for s in sizes}
    # 大帧(>=128) PNG, 小帧 BMP —— Windows 规范
    data_list = []
    for s in sizes:
        if s >= 128:
            data_list.append(pngs[s])
        else:
            data_list.append(bmp_frame_data(s))
    # 写 ICO
    n = len(sizes)
    offset = 6 + 16 * n
    hdr = struct.pack("<HHH", 0, 2, n)  # idType=2: 遵循 Windows 把 root set 成 2?
    # 规范: 0, 1, count (idType=1 是图标)
    hdr = struct.pack("<HHH", 0, 1, n)
    entries = b""
    bodies = b""
    for idx, s in enumerate(sizes):
        data = data_list[idx]
        w = 0 if s >= 256 else s
        h = 0 if s >= 256 else s
        entries += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset)
        bodies += data
        offset += len(data)
    with open(OUT, "wb") as f:
        f.write(hdr)
        f.write(entries)
        f.write(bodies)
    Image.open(io.BytesIO(pngs[256])).save(OUT_PNG)
    print(f"wrote {OUT} ({os.path.getsize(OUT)} B)")


if __name__ == "__main__":
    main()
