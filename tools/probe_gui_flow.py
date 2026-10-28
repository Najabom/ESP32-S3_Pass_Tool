"""probe_gui_flow.py —— 完整模拟 GUI 连接后的读取顺序，定位 uid/motto/uname 读取失败点。

顺序：ident → version → list(全段) → current → loglevel → devname → uid → motto → uname
"""
import asyncio
import sys

from bleak import BleakClient, BleakScanner
from core import protocol as P


async def main():
    keyword = sys.argv[1] if len(sys.argv) > 1 else "Passenger"
    dev = None
    async with BleakScanner() as s:
        for _ in range(12):
            for d in s.discovered_devices:
                if keyword in (d.name or ""):
                    dev = d
                    break
            if dev:
                break
            await asyncio.sleep(0.5)
    if not dev:
        print("[flow] NOT FOUND")
        return
    print(f"[flow] found {dev.name} {dev.address}")

    async with BleakClient(dev.address, timeout=15) as c:
        print("[flow] connected")
        # 1. ident
        print(f"[flow] ident   = {bytes(await c.read_gatt_char(P.CHR_IDENT))!r}")
        # 2. version
        print(f"[flow] version = {bytes(await c.read_gatt_char(P.CHR_SWREV))!r}")
        # 3. list 全段（分段游标）
        data = b""
        try:
            while True:
                seg = await c.read_gatt_char(P.CHR_LIST)
                if not seg:
                    break
                data += seg
                if len(seg) < 500:
                    break
            print(f"[flow] list    = {len(data)} bytes, head={data[:80]!r}")
        except Exception as e:
            print(f"[flow] list    FAILED: {type(e).__name__}: {e}")
        # 4. current
        try:
            print(f"[flow] current = {bytes(await c.read_gatt_char(P.CHR_CURRENT))!r}")
        except Exception as e:
            print(f"[flow] current FAILED: {type(e).__name__}: {e}")
        # 5. loglevel
        try:
            print(f"[flow] loglevel= {bytes(await c.read_gatt_char(P.CHR_LOGLEVEL))!r}")
        except Exception as e:
            print(f"[flow] loglevel FAILED: {type(e).__name__}: {e}")
        # 6. devname / uid / motto / uname
        for label, uuid in (("devname", P.CHR_BTNAME), ("uid", P.CHR_UID),
                            ("motto", P.CHR_MOTTO), ("uname", P.CHR_UNAME)):
            try:
                d = await c.read_gatt_char(uuid)
                print(f"[flow] {label:8s} = {bytes(d)!r}")
            except Exception as e:
                print(f"[flow] {label:8s} FAILED: {type(e).__name__}: {e}")


asyncio.run(main())
