"""协议层单测：游标组装 / 上传分块 / 通知解析 / 识别码过滤（无硬件依赖）。

运行：python -m unittest discover tests  （或 python tests/test_protocol.py）
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core import protocol as P


class TestMagic(unittest.TestCase):
    def test_ident_magic(self):
        # 固件 BLE_FEATURE_MAGIC = 0x50555350UL，LE 落盘字节序 = "PSUP"
        self.assertEqual(P.FEATURE_MAGIC, b"PSUP")

    def test_adv_uuid16(self):
        self.assertEqual(P.uuid16(0xFFE0), "0000ffe0-0000-1000-8000-00805f9b34fb")

    def test_adv_svc_data(self):
        # 固件广播 AD：0xE0 0xFF 'A' 'P'（uuid16 LE + payload）
        ad = bytes([0xE0, 0xFF]) + P.ADV_SVC_DATA
        self.assertEqual(ad[:2], b"\xe0\xff")
        self.assertEqual(P.ADV_SVC_DATA, b"AP")


class TestListCursor(unittest.TestCase):
    def test_chunk_assembly(self):
        # 模拟设备端 list：每读 ≤500B，读到空段结束
        names = ["roleA", "roleB", "roleC", "roleD" * 50]
        payload = ("\n".join(names) + "\n").encode("utf-8")
        chunks = [payload[i:i + 500] for i in range(0, len(payload), 500)] + [b""]

        got = []
        for c in chunks:
            if not c:
                break
            got.append(c.decode("utf-8", "replace"))
        lines = [x for x in "".join(got).split("\n") if x]
        self.assertEqual(lines, names)


class TestUpload(unittest.TestCase):
    def test_chunk_sizes(self):
        self.assertEqual(P.chunk_sizes(1000, 500), [500, 500])
        self.assertEqual(P.chunk_sizes(1200, 500), [500, 500, 200])
        self.assertEqual(sum(P.chunk_sizes(4096 * 1024, 497)), 4096 * 1024)

    def test_validate_ok(self):
        self.assertIsNone(P.validate_upload("roleA", "loop.mjpeg", 12345))

    def test_validate_bad(self):
        self.assertIsNotNone(P.validate_upload("a/b", "loop.mjpeg", 10))   # 路径注入
        self.assertIsNotNone(P.validate_upload("roleA", "evil.txt", 10))     # 白名单外
        self.assertIsNotNone(P.validate_upload("roleA", "loop.mjpeg", 0))    # 大小 0
        self.assertIsNotNone(P.validate_upload("roleA", "loop.mjpeg", 5 * 1024 * 1024))  # 超 4MB
        self.assertIsNotNone(P.validate_upload("roleA:1", "loop.mjpeg", 10))  # 冒号

    def test_parse_prog(self):
        self.assertEqual(P.parse_prog(b"PROG:42"), 42)
        self.assertEqual(P.parse_prog(b"PROG:100"), 100)
        self.assertIsNone(P.parse_prog(b"OK"))
        self.assertIsNone(P.parse_prog(b"PROG:abc"))


if __name__ == "__main__":
    unittest.main()