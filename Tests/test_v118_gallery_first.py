"""v1.0.18 回归：速传删了，图库是唯一入口；拍完照直接进图库，选图批量保存/分享。

Yuan 2026-11-21 18:42 的决定：“直接舍弃速传，直接读取图库，拍完照
直接导入图库就行了，然后我在图库可以直接选择图片进行保存。”
背景：18:40 的截图里 v1.0.17 的详情页保存仍报“保存失败”（ICC 下载在
真机上还是不稳），18:39 的取景页拍摄条 11 张全是占位图（成片是 NEF，
UIImage 解不出来，速传条根本没法显示）。

改法：
1. 速传页签删了（3 个 Tab：控制/实时取景/图库），FastTransferView.swift 删文件。
2. didAdd 不再自动下载——新照片进 USB 目录后重建图库列表；App 快门
   拍后复查（2.5s/6s）查到的新对象直接插进图库，不再下载。
3. 不再自动存入手机相册（addCapturedPhoto 删了，里面的
   UIImageWriteToSavedPhotosAlbum 一并没了）。保存是用户在图库里的
   主动选择。
4. 图库多选：右上角“选择”，点格子/列表打勾，底部条“保存到相册”/
   “分享”/“取消”，批量保存一张一张串行下，失败的最后汇总报数。
5. 取景页“本次拍摄”条改从图库取本次拍摄的照片（文件名集合），缩略图
   走 GetThumb（NEF 也有内嵌 JPEG 预览），点一张进详情页保存/分享。
6. 快门成功不再等下载回显，直接弹“快门已触发，成片见图库”。

这里验源码接线 + 纯逻辑镜像（插入去重、批量进度、大小解析）+ 模拟器
GetObjectInfo 两种布局的大小解析。真机行为（拍完是否进图库、多选
保存是否成功）须由用户在相机上验证。
"""

import os, sys, threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 插入去重镜像（insertCapturedItem）---
def insert_item(items, filename):
    if any(i == filename for i in items):
        return items
    return [filename] + items


# --- 批量保存进度镜像（saveItems）---
def save_items(items, ok_flags):
    """items: 待保存文件名；ok_flags: 每张是否成功。返回 (progress 调用序列, 成功数, 总数)。"""
    progress = []
    succeeded = 0
    for i, name in enumerate(items):
        progress.append((i + 1, len(items)))
        if ok_flags[i]:
            succeeded += 1
    return progress, succeeded, len(items)


# --- ObjectInfo 大小解析镜像（parseObjectInfoSize）---
def parse_object_info_size(data, parse_ptp_string):
    if len(data) >= 53:
        name, _ = parse_ptp_string(data, 52)
        if name:
            return int.from_bytes(data[8:12], "little")
    return int.from_bytes(data[10:14], "little")


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
    tabs = read("Z30Control/App/RootTabView.swift")

    print("== 速传页签和文件都删了 ==")
    check("FastTransferView.swift 文件已删",
          not os.path.exists(os.path.join(ROOT, "Z30Control/Views/FastTransfer/FastTransferView.swift")))
    check("Tab 枚举里没有 fastTransfer",
          "fastTransfer" not in tabs)
    check("Tab 切换里没有 FastTransferView()",
          "FastTransferView()" not in tabs)
    check("只剩 3 个 Tab（控制/实时取景/图库）",
          "case gallery = 2" in tabs and "case control = 0" in tabs and "case liveView = 1" in tabs)

    print("== UsbCameraManager：不再自动下载/自动存相册 ==")
    check("sessionCapturedPhotos 已删", "sessionCapturedPhotos" not in usb)
    check("addCapturedPhoto 已删", "addCapturedPhoto" not in usb)
    check("lastCapturedPhoto/lastCapturedFilename 已删",
          "lastCapturedPhoto" not in usb and "lastCapturedFilename" not in usb)
    check("CapturedPhotoItem 已删", "CapturedPhotoItem" not in usb)
    check("rescanCardForNewPhotos 已删", "rescanCardForNewPhotos" not in usb)
    check("fetchNewCapturedFiles 已删", "fetchNewCapturedFiles" not in usb)
    check("不再自动存入手机相册", "UIImageWriteToSavedPhotosAlbum" not in usb)
    check("本次拍摄只记文件名集合", "sessionCapturedFilenames" in usb)
    check("didAdd 只记文件名 + 重建图库 + 刷新存储",
          "sessionCapturedFilenames.insert" in usb
          and "MediaSyncService.shared.refreshFromUSB()" in usb)
    check("拍后复查插进图库（insertNewCapturedFiles）",
          "insertNewCapturedFiles" in usb and "insertCapturedItem" in usb)
    check("大小解析按布局分流（parseObjectInfoSize）",
          "parseObjectInfoSize" in usb and "readPTPString(data, offset: 52)" in usb)

    print("== MediaSyncService：插入 + 批量保存/分享 ==")
    check("insertCapturedItem 存在", "func insertCapturedItem" in media)
    check("插入去重按文件名", "contains(where: { $0.filename == filename })" in media)
    check("插入放最前面", "fetchedItems.insert(item, at: 0)" in media
          and "mediaItems.insert(item, at: 0)" in media)
    check("插入的 id 和目录同一套（文件名哈希）",
          "UInt32(truncatingIfNeeded: filename.hashValue)" in media)
    check("saveItems 存在（串行 + 进度 + 汇总）",
          "func saveItems" in media and "progress(index + 1, items.count)" in media)
    check("downloadItemsData 存在（串行取原图）",
          "func downloadItemsData" in media)

    print("== 图库：多选 + 底部操作条 ==")
    check("多选状态存在", "isSelecting" in gallery and "selectedFilenames" in gallery)
    check("右上角有选择按钮", "多选开关" in gallery)
    check("点格子/列表多选时打勾、不多选时进详情",
          "func cellTapped" in gallery and "selectedItemForDetail = item" in gallery)
    check("格子多选打勾标记",
          "checkmark.circle.fill" in gallery and "circle" in gallery)
    check("底部条有保存到相册/分享/取消",
          "保存到相册" in gallery and '"分享"' in gallery and '"取消"' in gallery)
    check("批量保存走 saveItems", "syncService.saveItems" in gallery)
    check("批量分享走 downloadItemsData", "syncService.downloadItemsData" in gallery)
    check("批量结果有汇总提示", "showBatchResult" in gallery and "已存入手机" in gallery)
    check("多选分享用 ShareBatch", "ShareBatch" in gallery)
    check("GalleryThumbImage 模块内可见（供拍摄条用）",
          "struct GalleryThumbImage: View" in gallery and "private struct GalleryThumbImage" not in gallery)

    print("== 取景页：拍摄条改从图库取，点开进详情 ==")
    check("sessionItems 按文件名从图库取",
          "sessionCapturedFilenames.contains($0.filename)" in live)
    check("拍摄条用 GalleryThumbImage", "GalleryThumbImage(item: item)" in live)
    check("点拍摄条打开详情页", "selectedGalleryItem = item" in live
          and "PhotoExportSheet(item: item)" in live)
    check("快门成功直接弹提示（不再等下载回显）",
          "快门已触发" in live and "已触发，成片见图库" in live)
    check("旧文案已清（速传中/全屏回显并存入手机）",
          "速传中，完成后见图库" not in live
          and "全屏回显并存入手机" not in live
          and "已回传并存入相册" not in live
          and "拍立得速传" not in live)

    print("== 纯逻辑：插入去重 ==")
    items = insert_item([], "DSC_3047.JPG")
    check("空列表插入放最前", items == ["DSC_3047.JPG"])
    items = insert_item(items, "DSC_3048.JPG")
    check("新照片插最前", items == ["DSC_3048.JPG", "DSC_3047.JPG"])
    items2 = insert_item(items, "DSC_3047.JPG")
    check("重复文件名不重复插", items2 == items)

    print("== 纯逻辑：批量保存进度 ==")
    prog, ok, total = save_items(["A.JPG", "B.JPG", "C.JPG"], [True, False, True])
    check("进度一张一张报", prog == [(1, 3), (2, 3), (3, 3)])
    check("成功数汇总", (ok, total) == (2, 3))
    prog, ok, total = save_items([], [])
    check("空列表直接完成", (ok, total) == (0, 0))

    print("== 模拟器：两种 ObjectInfo 布局的大小解析 ==")
    from test_fixed_flow import (FixedClient, PKT_INIT_CMD_REQ,
                                 PKT_INIT_EVENT_REQ, parse_ptp_string,
                                 parse_sim_object_info,
                                 make_standard_object_info)
    from z30_simulator import NikonZ30Simulator
    import struct as _struct
    import time as _time
    import uuid as _uuid
    # 标准布局（真机用的）：大小在偏移 8
    std = make_standard_object_info()
    check("标准布局大小在偏移 8（5432100）",
          parse_object_info_size(std, parse_ptp_string) == 5432100,
          f"got={parse_object_info_size(std, parse_ptp_string)}")
    # 模拟器简化布局：大小在偏移 10
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
    payload, code = c.data_request(0x1008, [1001])
    check("模拟器 GetObjectInfo 回 0x2001", code == 0x2001, f"code=0x{code:04X}")
    check("模拟器布局大小在偏移 10（和解析器一致）",
          parse_object_info_size(payload, parse_ptp_string)
          == parse_sim_object_info(payload)["size"],
          f"size={parse_sim_object_info(payload)['size']}")
    c.cmd_no_data(0x1003)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
