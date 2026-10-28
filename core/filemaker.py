"""PassDeck 素材制作 —— ffmpeg 转换核心（无 GUI 依赖，worker 线程调用）。

参考：ffmpeg MJPEG 原始流转换思路（旧 mjpeg_convert.py 同款流程）：
- 视频/GIF -> loop.mjpeg / intro.mjpeg（240x320 MJPEG 原始流）
- 任意图片 -> portrait.bin（64x64 小端 RGB565，8192B，与固件 CARD_PORTRAIT_SIZE 一致）
"""

import os
import re
import shutil
import subprocess
import tempfile

TARGET_W, TARGET_H = 240, 320
TARGET_RATIO = TARGET_W / TARGET_H          # 3:4 竖屏
PORTRAIT_W, PORTRAIT_H = 64, 64             # 角色头像 64x64 RGB565

COMMON_DIRS = [
    r"C:\ffmpeg\bin",
    r"C:\ffmpeg",
    r"C:\Program Files\ffmpeg\bin",
    r"C:\Program Files (x86)\ffmpeg\bin",
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Links"),
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "ffmpeg", "bin"),
    os.path.join(os.environ.get("USERPROFILE", ""), "ffmpeg", "bin"),
]

POSITIONS = ("center", "left", "right", "top", "bottom")


def find_tool(name):
    env = os.environ.get("FFMPEG_PATH")
    if env:
        p = os.path.join(env, name + ".exe") if os.path.isdir(env) else env
        if os.path.isfile(p):
            return p
    found = shutil.which(name)
    if found:
        return found
    for d in COMMON_DIRS:
        if d:
            p = os.path.join(d, name + ".exe")
            if os.path.isfile(p):
                return p
    return None


def ffmpeg_available():
    return find_tool("ffmpeg") is not None


def _probe(ffprobe, path):
    """返回 (w, h) 或 None（含 rotate 处理）。"""
    r = subprocess.run(
        [ffprobe, "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height:stream_tags=rotate",
         "-of", "csv=p=0:s=x", path],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=20)
    if r.returncode != 0:
        return None
    fields = r.stdout.strip().split(",")
    try:
        w, h = int(fields[0]), int(fields[1])
        rot = int(fields[2]) if len(fields) > 2 and fields[2] not in ("", "N/A") else 0
    except (ValueError, IndexError):
        return None
    if rot in (90, 270):
        w, h = h, w
    return w, h


def _probe_fallback(ffmpeg, path):
    r = subprocess.run([ffmpeg, "-i", path], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=20)
    m = re.search(r"Video:.*?(\d{2,5})x(\d{2,5})", r.stderr or "")
    if m:
        return int(m.group(1)), int(m.group(2))
    return None


def probe_dims(path):
    """返回 (w, h) 或 None。"""
    ffmpeg = find_tool("ffmpeg")
    if not ffmpeg:
        return None
    ffprobe = os.path.join(os.path.dirname(os.path.abspath(ffmpeg)), "ffprobe.exe")
    if not os.path.isfile(ffprobe):
        ffprobe = find_tool("ffprobe")
    dims = _probe(ffprobe, path) if ffprobe else None
    if not dims:
        dims = _probe_fallback(ffmpeg, path)
    return dims


def probe_duration(path):
    """返回时长（秒，float）或 None。"""
    ffprobe = find_tool("ffprobe")
    if not ffprobe:
        return None
    r = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=20)
    try:
        v = float((r.stdout or "").strip())
        return v if v > 0 else None
    except (ValueError, AttributeError):
        return None


def _round_even(v):
    v = int(round(v))
    return v - (v % 2)


_TIME_RE = re.compile(r"^\d+(?:\.\d+)?$|^\d+:\d{1,2}(?::\d{1,2}(?:\.\d+)?)?$")


def _to_seconds(t):
    if isinstance(t, (int, float)):
        return float(t)
    if not isinstance(t, str) or not t:
        return 0.0
    parts = [float(p) for p in t.split(":")]
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    return parts[0] * 3600 + parts[1] * 60 + parts[2]


def _compute_crop(iw, ih, position):
    ratio = iw / ih
    if abs(ratio - TARGET_RATIO) < 1e-6:
        return iw, ih, 0, 0
    if ratio > TARGET_RATIO:                      # 太宽：裁宽度
        cw = min(_round_even(ih * TARGET_RATIO), iw if iw % 2 == 0 else iw - 1)
        ch = ih
        max_x = iw - cw
        cx = {"left": 0, "right": max_x}.get(position, max_x // 2)
        return cw, ch, cx, 0
    ch = min(_round_even(iw / TARGET_RATIO), ih if ih % 2 == 0 else ih - 1)   # 太高：裁高度
    cw = iw
    max_y = ih - ch
    cy = {"top": 0, "bottom": max_y}.get(position, max_y // 2)
    return cw, ch, 0, cy


def _clamp_even(v, lo, hi):
    v = int(round(v))
    if v < lo:
        v = lo
    if v > hi:
        v = hi
    return v - (v % 2)


def compute_crop_rect(iw, ih, cx, cy, cw, ch):
    """显式裁剪矩形（源像素，QML 裁剪弹窗结果）：钳制 3:4 比例并偶数化。

    返回 (cw, ch, cx, cy)。cx/cy 为裁剪框左上角。
    """
    if cw <= 0 or ch <= 0:
        return _compute_crop(iw, ih, "center")
    # 钳制尺寸：不超过源
    cw = min(cw, iw)
    ch = min(ch, ih)
    # 强制 3:4（以宽为准调整高）
    ch = _clamp_even(cw * TARGET_H / TARGET_W, 1, ih)
    cw = _clamp_even(cw, 1, iw)
    if cw * TARGET_H / TARGET_W > ih:          # 高放不下：以高为准
        ch = _clamp_even(ih, 1, ih)
        cw = _clamp_even(ch * TARGET_W / TARGET_H, 1, iw)
    cx = _clamp_even(cx, 0, max(0, iw - cw))
    cy = _clamp_even(cy, 0, max(0, ih - ch))
    return cw, ch, cx, cy


def make_mjpeg(src, out_path, fps=10, quality=3, position="center",
               start=None, end=None, crop=None, rotate=0):
    """视频/GIF -> 240x320 MJPEG 原始流。返回 (ok, msg)。

    crop=(cx, cy, cw, ch) 显式源像素裁剪矩形（QML 裁剪弹窗结果，旋转后坐标系），
    优先于 position。rotate: 顺时针 90° 次数 0-3（先旋转后裁剪）。
    """
    if not os.path.isfile(src):
        return False, "源文件不存在"
    ffmpeg = find_tool("ffmpeg")
    if not ffmpeg:
        return False, "未找到 ffmpeg（请安装或设置 FFMPEG_PATH）"
    dims = probe_dims(src)
    if not dims:
        return False, "无法读取源视频尺寸"
    iw, ih = dims
    rot = int(rotate or 0) % 4
    # 旋转后的坐标系（90°/270° 宽高互换）
    rw, rh = (ih, iw) if rot % 2 == 1 else (iw, ih)
    if crop:
        cw, ch, cx, cy = compute_crop_rect(rw, rh, *crop)
    else:
        if position not in POSITIONS:
            position = "center"
        cw, ch, cx, cy = _compute_crop(rw, rh, position)
    trans = "".join(",transpose=1" for _ in range(rot))
    vf = f"{trans.lstrip(',')},crop={cw}:{ch}:{cx}:{cy},scale={TARGET_W}:{TARGET_H}"
    if not trans:
        vf = vf.lstrip(",")
    if src.lower().endswith(".gif"):
        vf += ",format=rgb24"
    if start and not _TIME_RE.match(start):
        return False, "开始时间格式应为 mm:ss / hh:mm:ss / 秒"
    if end and not _TIME_RE.match(end):
        return False, "结束时间格式应为 mm:ss / hh:mm:ss / 秒"
    duration = None
    if start and end and _to_seconds(end) <= _to_seconds(start):
        return False, "结束时间必须晚于开始时间"
    if end:
        d = _to_seconds(end) - (_to_seconds(start) if start else 0)
        if d > 0:
            duration = d          # ≤0 视为未指定（防单帧输出）

    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "warning"]
    if start:
        cmd += ["-ss", start]
    ext = os.path.splitext(src)[1].lower()
    is_img = ext in (".png", ".jpg", ".jpeg", ".bmp", ".webp")
    if is_img:
        cmd += ["-loop", "1", "-i", src]      # 图片 → 循环输入，输出动态多帧
    else:
        cmd += ["-i", src]
    cmd += ["-filter_complex", f"[0:v]{vf}"]
    # MJPEG 无码率控制：不钳位 q 值时 ffmpeg 对静帧/运动帧的输出大小差
    # 可达 30 倍，估算按采样比例放大时误差爆炸。
    # 用 -qmin/-qmax 把质量窗口锁死，估算失真来源只剩画面内容本身。
    _q = max(1, min(31, int(quality)))
    cmd += ["-an", "-c:v", "mjpeg", "-q:v", str(_q), "-qmin", str(_q), "-qmax", str(_q),
            "-r", str(fps)]
    if duration is None and is_img:
        duration = 5                          # 图片默认 5 秒动画（可被结束时间覆盖）
    if duration is not None:
        cmd += ["-t", str(duration)]
    cmd += ["-f", "mjpeg", out_path]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800,
                           encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return False, "转换超时（30 分钟）"
    if r.returncode != 0:
        tail = (r.stderr or "").strip().splitlines()
        return False, "ffmpeg 失败: " + (tail[-1] if tail else f"exit {r.returncode}")
    if not os.path.isfile(out_path):
        return False, "输出文件未生成"
    size = os.path.getsize(out_path)
    ext = os.path.splitext(src)[1].lower()
    if size < 2000 and ext not in (".png", ".jpg", ".jpeg", ".bmp", ".webp"):
        return False, "输出过小，请检查源视频是否有效"
    return True, f"生成成功 ({size//1024} KB)"


def estimate_mjpeg_size(src, fps=10, quality=3, position="center",
                        start=None, end=None, crop=None, rotate=0,
                        sample_secs=2.0):
    """多点采样推算 MJPEG 大小（B）。首/中/尾三点各 sample_secs/3 秒，
    取三处净码率的平均值乘总时长。比单点（只取样末尾）更能代表
    静态帧与动态帧交错的真实片段。估算失败返回 None（上层放行制作）。
    """
    dur = probe_duration(src)
    if not dur or dur <= 0:
        # 单张图片 ffprobe 无时长 → 与 make_mjpeg 一致按默认 5s 动画估算
        ext = os.path.splitext(src)[1].lower()
        if ext in (".png", ".jpg", ".jpeg", ".bmp", ".webp"):
            dur = 5.0
        else:
            return None
    t0 = _to_seconds(start) if start and _to_seconds(start) >= 0 else 0.0
    t_end = _to_seconds(end) if end and _to_seconds(end) and _to_seconds(end) <= dur else dur
    if t_end <= t0:
        t_end = dur
    span = t_end - t0
    if span <= 0:
        return None
    # 每点采样时长（总取样不超 sample_secs）
    s_per = max(0.3, min(sample_secs / 3.0, span - 0.1))
    # 三点采样窗口：首、尾、中间（窗口宽 s_per）
    wins = [(t0, t0 + s_per),
            (max(t0, (t0 + t_end) / 2 - s_per / 2), min(t_end, (t0 + t_end) / 2 + s_per / 2)),
            (t_end - s_per, t_end)]
    sizes = []
    for w_start, w_end in wins:
        if w_end - w_start < 0.2:
            continue
        _fdesc, samp = tempfile.mkstemp(suffix=".mjpeg")
        os.close(_fdesc)
        try:
            ok, _msg = make_mjpeg(src, samp, fps=fps, quality=quality,
                                  position=position, start=str(w_start),
                                  end=str(w_end),
                                  crop=crop, rotate=rotate)
            if not ok:
                continue
            sz = os.path.getsize(samp)
            if sz > 0:
                sizes.append(sz)
        finally:
            try:
                os.unlink(samp)
            except OSError:
                pass
    if not sizes:
        return None
    # 平均码率：各点 size / 各点采样时长，再乘总 span
    avg_size_per_second = 0.0
    for i, (w_start, w_end) in enumerate([w for w in wins if w[1] - w[0] >= 0.2]):
        if i < len(sizes):
            avg_size_per_second += sizes[i] / (w_end - w_start)
    if len(sizes) == 0:
        return None
    avg_size_per_second /= len(sizes)
    return int(avg_size_per_second * span)


def make_portrait(src, out_path):
    """任意图片 -> 64x64 小端 RGB565（8192B）。返回 (ok, msg)。"""
    if not os.path.isfile(src):
        return False, "源文件不存在"
    ffmpeg = find_tool("ffmpeg")
    if not ffmpeg:
        return False, "未找到 ffmpeg（请安装或设置 FFMPEG_PATH）"
    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "warning",
           "-i", src,
           "-frames:v", "1",
           "-vf", f"scale={PORTRAIT_W}:{PORTRAIT_H}:force_original_aspect_ratio=decrease,"
                  f"pad={PORTRAIT_W}:{PORTRAIT_H}:(ow-iw)/2:(oh-ih)/2,format=rgb565le",
           "-f", "rawvideo", out_path]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300,
                           encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return False, "转换超时（5 分钟）"
    if r.returncode != 0:
        tail = (r.stderr or "").strip().splitlines()
        return False, "ffmpeg 失败: " + (tail[-1] if tail else f"exit {r.returncode}")
    if not os.path.isfile(out_path) or os.path.getsize(out_path) != PORTRAIT_W * PORTRAIT_H * 2:
        return False, "输出尺寸不符（应为 64x64 RGB565）"
    return True, "生成成功 (64x64 RGB565, 8 KB)"
