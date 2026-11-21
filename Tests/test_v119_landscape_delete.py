"""v1.0.19 回归：取景器强制横屏、图库批量删机内照片、详情页看原图、
缩略图占位 bug、刚拍的照片被目录刷新冲掉。

Yuan 2026-11-21 19:22 三张截图 + 要求：
1. 图库上面几行一直是占位图（下面滚动后才出现的反而能显示），刚拍
   的照片也看不到；图不太清晰。根因两个：(a) 缩略图请求在映射表建好
   前挂起，重跑时被 thumbInFlight 挡住，completion 永远不调——上面
   先露出来的格子永久占位；(b) 拍后复查插进来的新照片，下一次目录
   刷新（ICC 目录投递慢、新文件还没进目录）就被整表替换冲掉。
   修：挂起前摘掉 inFlight + 第二个来取的排队等结果；刚拍的钉住，
   刷新后合并回最前面，直到进目录为止；GetThumb 下不来退回原图缩略图。
2. 点开一张图直接展示原图（之前详情页只显示 160px 小缩略图，糊）；
   详情页的保存/分享按钮取消，只在图库总页面多选里保存/分享。
   横/竖显示切换后固定住（旋转按钮，记下来，切页面也不变）。
3. 图库内批量删除机内照片（PTP DeleteObject 0x100B，串行删，先弹
   确认框，删完汇总）。删了就真没了。
4. 取景页：本次拍摄条不要了，AF-ON 不要了，滤镜条先删了；快门键下移
   到底栏上方一点（之前底栏 96pt 空一大截——底栏在 VStack 流里，
   取景页框底就是 TabBar 顶边，那 96pt 全是白空的）；取景器直接改成
   横的（进页强制横屏，离页恢复竖屏，不用再开系统方向锁定）。

这里验源码接线 + 纯逻辑镜像（钉住合并、串行删除、旋转循环）+
模拟器 DeleteObject 真删。真机行为（横屏转不转、删除真删假删）
须由用户在相机上验证——删之前请先确认卡里照片已备份。
"""

import os, sys, threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 钉住合并镜像（mergePinned）---
# 目录里没有的钉住照片补到最前面，且继续钉着；进目录的就不再钉住。
def merge_pinned(pinned, ordered):
    missing = [p for p in pinned if p not in ordered]
    return missing + ordered, missing


# --- 串行删除镜像（deleteItemsResolved）---
def delete_items(items, ok_flags):
    progress = []
    succeeded = 0
    for i, name in enumerate(items):
        progress.append((i + 1, len(items)))
        if ok_flags[i]:
            succeeded += 1
    return progress, succeeded, len(items)


# --- 旋转循环镜像（PhotoRotationStore.setRotation）---
def rotate(current):
    return (current + 90) % 360


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

    usb = read("Z30Control/Services/UsbCameraManager.swift")
    media = read("Z30Control/Services/MediaSyncService.swift")
    gallery = read("Z30Control/Views/Gallery/CameraGalleryView.swift")
    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
    wifi = read("Z30Control/Protocol/PtpIpClient.swift")
    app = read("Z30Control/App/Z30ControlApp.swift")
    orient_path = os.path.join(ROOT, "Z30Control/App/OrientationLock.swift")
    orient = read("Z30Control/App/OrientationLock.swift") if os.path.exists(orient_path) else ""

    print("== 取景器强制横屏 ==")
    check("OrientationLock.swift 存在", os.path.exists(orient_path))
    check("横屏开关 landscapeOnly", "static var landscapeOnly" in orient)
    check("锁横屏转 landscapeRight", "landscapeRight" in orient)
    check("解锁回竖屏 portrait", "unlockToPortrait" in orient and "UIInterfaceOrientation.portrait" in orient)
    check("AppDelegate 按开关给方向",
          "supportedInterfaceOrientationsFor" in orient
          and ".landscape" in orient and ".allButUpsideDown" in orient)
    check("App 入口挂了 AppDelegate",
          "@UIApplicationDelegateAdaptor(AppDelegate.self)" in app)
    # v1.0.22 起：取景页改锁竖屏（画面在页内转 90°），不再锁横屏
    check("进取景页锁竖屏（v1.0.22 起）", "OrientationLock.lockPortrait()" in live)
    check("离取景页恢复竖屏", "OrientationLock.unlockToPortrait()" in live)
    check("快门键贴底栏上方（96pt 空隙已清）",
          ".padding(.bottom, 12 + max(bottomSafeInset(geo) - 20, 0))" in live
          and ".padding(.bottom, 96 +" not in live)

    print("== 批量删除机内照片 ==")
    check("USB 有 DeleteObject 0x100B", "case deleteObject" in usb and "0x100B" in usb)
    check("USB deleteObject 发之前停取景帧",
          "func deleteObject(handle: UInt32" in usb and "pauseLiveViewFetching()" in usb)
    check("USB 删除按 0x2001 判成功", "respCode == nil || respCode == 0x2001" in usb)
    check("Wi-Fi 有 deleteObject", "func deleteObject(handle: UInt32" in wifi)
    check("Wi-Fi 删除用 PTP deleteObject 操作码",
          "PtpOperationCode.deleteObject.rawValue" in wifi)
    check("MediaSyncService 有 deleteItems（串行 + 进度 + 汇总）",
          "func deleteItems" in media and "progress(index + 1, items.count)" in media)
    check("删掉的从列表/缓存/钉住列表里去掉",
          "pinnedCapturedItems.removeAll" in media and "thumbCache.removeValue" in media)
    check("句柄不够时等映射表建好再删",
          "handleMapWaiters" in media)
    check("图库多选条有删除按钮 + 确认框",
          '"删除"' in gallery and "showDeleteConfirm" in gallery
          and "永久删除" in gallery)
    check("删除结果有汇总提示",
          "showBatchDeleteResult" in gallery and "已删除" in gallery)

    print("== 详情页直接看原图，保存/分享只在总页面 ==")
    check("详情页下原图显示",
          "fullImage" in gallery and "downloadOriginalData(item: item)" in gallery)
    check("NEF 原图解不出来退回缩略图",
          "退回小缩略图" in gallery)
    check("详情页没有保存按钮", "无损保存原图到系统相册" not in gallery)
    check("详情页没有分享按钮", "隔空投送 / 系统分享" not in gallery)
    check("详情页有旋转按钮（横/竖固定）",
          "旋转 90°" in gallery and "PhotoRotationStore" in gallery)
    check("旋转记下来（UserDefaults 按文件名）",
          "z30.photoRotation." in gallery)
    check("详情页能双指缩放",
          "MagnificationGesture" in gallery)

    print("== 缩略图占位 bug + 新照片被冲掉 ==")
    check("挂起的缩略图请求重跑不再被 inFlight 挡住",
          "thumbInFlight.remove(item.id)" in media
          and "thumbPending.append" in media)
    check("同一张图第二个来取的排队等结果",
          "thumbWaiters" in media)
    check("缩略图下不来退回原图缩略图",
          "downscaled" in gallery and "downloadOriginalData(item: item)" in gallery)
    check("刚拍的照片钉住（insertCapturedItem）",
          "pinnedCapturedItems.insert" in media)
    check("目录刷新合并钉住的照片（mergePinned）",
          "mergePinned(into:" in media)
    check("三处刷新都合并（USB 目录/PTP 列卡/Wi-Fi）",
          media.count("mergePinned(into") >= 4)

    print("== 纯逻辑：钉住合并 ==")
    merged, pinned = merge_pinned(["DSC_3051.JPG"], ["DSC_3050.JPG", "DSC_3049.JPG"])
    check("目录里没有的钉住照片补到最前面",
          merged == ["DSC_3051.JPG", "DSC_3050.JPG", "DSC_3049.JPG"])
    check("补进去后还钉着", pinned == ["DSC_3051.JPG"])
    merged, pinned = merge_pinned(["DSC_3051.JPG"], ["DSC_3051.JPG", "DSC_3050.JPG"])
    check("目录里已有的不再重复补", merged == ["DSC_3051.JPG", "DSC_3050.JPG"])
    check("进目录的就不再钉住", pinned == [])

    print("== 纯逻辑：串行删除 ==")
    prog, ok, total = delete_items(["A.JPG", "B.JPG", "C.JPG"], [True, True, False])
    check("进度一张一张报", prog == [(1, 3), (2, 3), (3, 3)])
    check("成功数汇总（失败的不算）", (ok, total) == (2, 3))

    print("== 纯逻辑：旋转循环 ==")
    check("0→90→180→270→0", [rotate(0), rotate(90), rotate(180), rotate(270)] == [90, 180, 270, 0])

    print("== 模拟器：DeleteObject 真删 ==")
    from test_fixed_flow import (FixedClient, PKT_INIT_CMD_REQ,
                                 PKT_INIT_EVENT_REQ)
    from z30_simulator import NikonZ30Simulator
    import struct as _struct
    import time as _time
    import uuid as _uuid
    sim = NikonZ30Simulator(host="127.0.0.1", port=15740)
    t = threading.Thread(target=sim.start, daemon=True)
    t.start()
    _time.sleep(0.5)
    c = FixedClient()
    guid = _uuid.uuid4().bytes
    name = ("Z30 Pro Controller\x00").encode("utf-16le")
    pkt = _struct.pack("<II", 4 + 4 + 16 + len(name) + 4, PKT_INIT_CMD_REQ) \
        + guid + name + _struct.pack("<I", 0x00010000)
    c.cmd.sendall(pkt)
    ack = c.cmd_reader.read_packet()
    conn_num = _struct.unpack("<I", ack[8:12])[0]
    c.evt.sendall(_struct.pack("<III", 12, PKT_INIT_EVENT_REQ, conn_num))
    c.evt_reader.read_packet()
    assert c.cmd_no_data(0x1002, [1]) == 0x2001

    def handles():
        payload, code = c.data_request(0x1007, [0x00010001])
        assert code == 0x2001
        n = _struct.unpack("<I", payload[:4])[0]
        return list(_struct.unpack(f"<{n}I", payload[4:4 + 4 * n]))

    before = handles()
    check("删之前卡里有 1002", 1002 in before, f"handles={before}")
    code = c.cmd_no_data(0x100B, [1002])
    check("DeleteObject 1002 回 0x2001", code == 0x2001, f"code=0x{code:04X}")
    after = handles()
    check("删之后 1002 不在句柄列表里", 1002 not in after, f"handles={after}")
    check("其他照片还在", 1001 in after and len(after) == len(before) - 1)
    code = c.cmd_no_data(0x100B, [1002])
    check("再删同一张回 0x2009（句柄不存在）", code == 0x2009, f"code=0x{code:04X}")
    c.cmd_no_data(0x1003)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
