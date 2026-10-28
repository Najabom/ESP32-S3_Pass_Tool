"""probe_uid.py —— 直连设备读取名片三个特征，验证固件 READ 是否工作。

用法: python probe_uid.py [设备名关键字]   (默认 PASS-II-)
输出: 每个特征的原始字节 + 解码串 + GATT 错误信息
"""
import asyncio
import sys

from bleak import BleakClient, BleakScanner
from core import protocol as P


async def main():
    keyword = sys.argv[1] if len(sys.argv) > 1 else "PASS-II-"
    print(f"[probe] scanning for '{keyword}' ...")
    dev = None
    all_devs = []
    async with BleakScanner() as s:
        for _ in range(12):
            for d in s.discovered_devices:
                nm = d.name or ""
                all_devs.append(nm)
                if keyword in nm:
                    dev = d
                    break
            if dev:
                break
            await asyncio.sleep(0.5)
    if not dev:
        print("[probe] NOT FOUND. all devices seen:", sorted(set(all_devs)))
        return
    print(f"[probe] found {dev.name} {dev.address}")

    async with BleakClient(dev.address, timeout=15) as c:
        print(f"[probe] connected, services: {len(c.services.services)}")
        for label, uuid in (("uid", P.CHR_UID), ("motto", P.CHR_MOTTO), ("uname", P.CHR_UNAME)):
            try:
                data = await c.read_gatt_char(uuid)
                print(f"[probe] {label:6s} raw={bytes(data)!r} text={data.decode('utf-8', 'replace')!r}")
            except Exception as e:
                print(f"[probe] {label:6s} READ FAILED: {type(e).__name__}: {e}")
        try:
            data = await c.read_gatt_char(P.CHR_IDENT)
            print(f"[probe] ident raw={bytes(data)!r}")
        except Exception as e:
            print(f"[probe] ident  READ FAILED: {type(e).__name__}: {e}")


asyncio.run(main())
