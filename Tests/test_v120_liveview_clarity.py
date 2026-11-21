"""v1.0.20 回归：取景画面模糊、噪点高。

根因（v1.0.19 回退，实话实说）：
v1.0.19 删了滤镜条，却没关滤镜默认——LiveViewStreamService 默认
isLUTEnabled = true、activeFilter = PORTRA 400，于是每帧都先过一遍
暖调胶片滤镜，再以 JPEG 0.85 重压一遍才显示。用户在 v1.0.18 里
点过「原片 (Off)」，所以 v1.0.19 的取景反而比 v1.0.18 更糊。
再加上相机 PTP 取景帧本身只有几百像素，手机满屏放大几倍看必然糊，
暗光下（ISO 1250、1/10s）传感器噪点也被一起放大。

修：
1. 滤镜默认关（isLUTEnabled = false、activeFilter = nil），取景原片直出。
2. 取景帧轻量增强（CINoiseReduction 降噪 + CIUnsharpMask 轻锐化，
   默认开，取景页可关），结果存在 enhancedImage 里，不经过 JPEG 重压。
3. 帧分辨率从 JPEG SOF 段解析出来，取景页显示在取景按钮/左翼上，
   让相机发来的上限看得见。

这里验源码接线 + SOF 解析镜像 + 对模拟器的真实取景帧（8×8 测试帧）。
"""

import os, sys, threading, struct, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))
sys.path.insert(0, os.path.join(ROOT, "Simulator"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- SOF 解析镜像（LiveViewParser.parseJPEGSize）---
def parse_jpeg_size(data):
    b = data
    if len(b) <= 4 or b[0] != 0xFF or b[1] != 0xD8:
        return None
    i = 2
    while i + 3 < len(b):
        if b[i] != 0xFF:
            return None
        marker = b[i + 1]
        if marker in (0xD8, 0x01):
            i += 2
            continue
        if marker in (0xD9, 0xDA):
            return None
        if marker in (0xC0, 0xC2):
            if i + 9 >= len(b):
                return None
            h = (b[i + 5] << 8) | b[i + 6]
            w = (b[i + 7] << 8) | b[i + 8]
            if w <= 0 or h <= 0:
                return None
            return (w, h)
        seg_len = (b[i + 2] << 8) | b[i + 3]
        if seg_len < 2:
            return None
        i += 2 + seg_len
    return None


def make_jpeg(w, h, sof_marker=0xC0):
    data = b"\xff\xd8"
    app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    data += app0
    sof = (b"\xff" + bytes([sof_marker]) + struct.pack(">H", 17) + bytes([8])
           + struct.pack(">HH", h, w)
           + bytes([3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]))
    return data + sof


def run():
    passed = failed = 0

    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name} {detail}")

    svc = read("Z30Control/Services/LiveViewStreamService.swift")
    parser = read("Z30Control/Protocol/LiveViewParser.swift")
    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")

    print("== 源码：滤镜默认关（v1.0.19 回退的修复）==")
    check("isLUTEnabled 默认 false", "isLUTEnabled: Bool = false" in svc)
    check("activeFilter 默认 nil", "activeFilter: LUTFilter? = nil" in svc)
    check("不再默认 PORTRA 400", "builtinPresets.first" not in svc)
    check("LUT 分支还在（能力保留），但默认走不到",
          "if isLUTEnabled, let filter = activeFilter" in svc)

    print("== 源码：轻量增强 ==")
    check("增强默认开", "isEnhanceEnabled: Bool = true" in svc)
    check("降噪 + 轻锐化", "CINoiseReduction" in svc and "CIUnsharpMask" in svc)
    check("增强结果不走 JPEG 重压（存在 enhancedImage 里）",
          "enhancedImage" in svc and "enhancedImage" in parser)
    check("增强走后台串行，忙时丢帧",
          "frameFilterQueue" in svc and "frameFiltering" in svc)
    check("增强参数保守（降噪 0.02 / 锐化 0.5）",
          '"inputNoiseLevel"' in svc and "0.02" in svc
          and '"inputIntensity"' in svc and "0.5" in svc)

    print("== 源码：帧分辨率 ==")
    check("parseJPEGSize 存在（读 SOF0/SOF2）",
          "func parseJPEGSize" in parser and "0xC0" in parser and "0xC2" in parser)
    check("LiveViewFrame 带 pixelSize", "pixelSize: CGSize" in parser)
    check("parse() 回填 pixelSize", "pixelSize: Self.parseJPEGSize(jpegData)" in parser)
    check("流服务上报 currentFrameSize",
          "currentFrameSize: CGSize" in svc and "currentFrameSize = frame.pixelSize" in svc)
    check("取景按钮显示分辨率", "liveViewStreamLabel" in live)
    check("横屏左翼也显示分辨率",
          "streamService.currentFrameSize" in live)
    check("增强开关在取景页（竖屏+横屏两处）",
          live.count("streamService.isEnhanceEnabled.toggle()") >= 2)

    print("== 纯逻辑：SOF 解析 ==")
    check("640×424 的 SOF0 解析对", parse_jpeg_size(make_jpeg(640, 424)) == (640, 424))
    check("SOF2 也解析", parse_jpeg_size(make_jpeg(1024, 680, 0xC2)) == (1024, 680))
    check("没有 SOF 返回空", parse_jpeg_size(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9") is None)
    check("不是 JPEG 返回空", parse_jpeg_size(b"\x00\x01\x02\x03\x04\x05") is None)

    print("== 模拟器：真实取景帧 ==")
    from z30_simulator import NikonZ30Simulator, TEST_JPEG
    from test_fixed_flow import (FixedClient, PKT_INIT_CMD_REQ,
                                 PKT_INIT_EVENT_REQ)
    sim = NikonZ30Simulator(host="127.0.0.1", port=15740)
    t = threading.Thread(target=sim.start, daemon=True)
    t.start()
    time.sleep(0.5)
    check("模拟器测试帧 8×8", parse_jpeg_size(TEST_JPEG) == (8, 8),
          f"got={parse_jpeg_size(TEST_JPEG)}")
    import uuid as _uuid
    c = FixedClient()
    guid = _uuid.uuid4().bytes
    name = ("Z30 Pro Controller\x00").encode("utf-16le")
    pkt = struct.pack("<II", 4 + 4 + 16 + len(name) + 4, PKT_INIT_CMD_REQ) \
        + guid + name + struct.pack("<I", 0x00010000)
    c.cmd.sendall(pkt)
    ack = c.cmd_reader.read_packet()
    conn_num = struct.unpack("<I", ack[8:12])[0]
    c.evt.sendall(struct.pack("<III", 12, PKT_INIT_EVENT_REQ, conn_num))
    c.evt_reader.read_packet()
    c.cmd_no_data(0x1002, [1])
    check("开启取景 0x9201 -> OK", c.cmd_no_data(0x9201, []) == 0x2001)
    payload, code = c.data_request(0x9203, [])
    check("取回取景帧 0x9203 -> OK", code == 0x2001 and len(payload) > 64,
          f"code={code:#x} len={len(payload)}")
    start = payload.find(b"\xff\xd8")
    check("帧里有 JPEG", start >= 0)
    size = parse_jpeg_size(payload[start:]) if start >= 0 else None
    check("帧内 JPEG 解析出 8×8", size == (8, 8), f"got={size}")
    c.cmd_no_data(0x1003, [])

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
