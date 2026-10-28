# 固件镜像目录

发布包需要 `firmware_v1.0_merged.bin`。该二进制文件不进入 Git，请从
[ESP32-S3_Pass Releases](https://github.com/Najabom/ESP32-S3_Pass/releases) 下载后放到
本目录：

```text
firmware/
  firmware_v1.0_merged.bin
```

也可以设置环境变量 `PASSDECK_FIRMWARE` 指向任意位置的镜像，再运行 `python build_exe.py`。
