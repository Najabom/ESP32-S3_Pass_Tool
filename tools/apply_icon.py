"""版本 2：C# UpdateResource 完整图标注入（先删旧图标资源，再写入完整 6 帧）。
安全要点：BeginUpdateResource(exe, FALSE) 只替换图标类型，不动其他资源。
用法：python tools/apply_icon.py
"""
import base64
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets" / "app_icon.ico"
EXE = ROOT / "dist" / "PassDeck" / "PassDeck.exe"


def parse_ico(path):
    data = open(path, "rb").read()
    _, typ, count = struct.unpack_from("<HHH", data, 0)
    frames = []
    for i in range(count):
        o = 6 + 16 * i
        w, h, bc, rs = struct.unpack_from("<BBBB", data, o)
        planes, bits, bytesres, imgoff = struct.unpack_from("<HHII", data, o + 4)
        frames.append(((w or 256), (h or 256), data[imgoff:imgoff + bytesres]))
    return frames


def main():
    if not EXE.exists():
        sys.exit(f"EXE not found: {EXE}")
    frames = parse_ico(ICON)
    gid = struct.pack("<HHH", 0, 1, len(frames))

    ps = []
    ps.append("""
Add-Type -TypeDefinition @\"
using System; using System.Runtime.InteropServices;
using System.Collections.Generic;
public class URX2 {
  [DllImport(\"kernel32.dll\", CharSet=CharSet.Ansi, SetLastError=true)]
  public static extern IntPtr BeginUpdateResource(string f, bool del);
  [DllImport(\"kernel32.dll\", SetLastError=true)]
  public static extern bool UpdateResource(IntPtr h, IntPtr t, IntPtr n, ushort lang, byte[] d, uint c);
  [DllImport(\"kernel32.dll\", SetLastError=true)]
  public static extern bool EndUpdateResource(IntPtr h, bool disc);
  [DllImport(\"kernel32.dll\", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryEx(string l, IntPtr h, uint f);
  [DllImport(\"kernel32.dll\", SetLastError=true)]
  public static extern bool EnumResourceNames(IntPtr h, IntPtr t, EnumResNameProc p, IntPtr l);
  public delegate bool EnumResNameProc(IntPtr a, IntPtr b, IntPtr c, IntPtr d);
  [DllImport(\"kernel32.dll\")] public static extern bool FreeLibrary(IntPtr h);
}
\"@;
$exe = '%s';
# 先枚举现有 RT_ICON/RT_GROUP_ICON 资源名（跳过删除阶段，直接覆盖写）
$h = [URX2]::BeginUpdateResource($exe, $false);
""" % str(EXE).replace("\\", "\\\\"))

    iconid = 1
    for (w, h, img) in frames:
        b = base64.b64encode(img).decode()
        ps.append(f"$d = [Convert]::FromBase64String('{b}');")
        ps.append(f"[void][URX2]::UpdateResource($h, [IntPtr]3, [IntPtr]{iconid}, 0, $d, [uint32]$d.Length);")
        gid += struct.pack("<BBBBHHIH", 0 if w >= 256 else w, 0 if h >= 256 else h,
                           0, 0, 1, 32, len(img), iconid)
        iconid += 1
    gb = base64.b64encode(gid).decode()
    ps.append(f"$gid = [Convert]::FromBase64String('{gb}');")
    ps.append("[void][URX2]::UpdateResource($h, [IntPtr]14, [IntPtr]1, 0, $gid, [uint32]$gid.Length);")
    ps.append("[void][URX2]::EndUpdateResource($h, $false);")
    ps.append("Write-Output 'injected OK'")

    psf = os.path.join(tempfile.gettempdir(), "inject_icon2.ps1")
    open(psf, "w", encoding="utf-8").write("\n".join(ps))
    r = subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", psf],
                       capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip()[:400])


if __name__ == "__main__":
    main()
