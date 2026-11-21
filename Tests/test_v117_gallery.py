"""v1.0.17 回归：图库缩略图、素材选项页、诊断行（v1.0.18 修订版）。

Yuan 2026-11-21 18:19-18:26 连报四个问题：
1. 图库 353 张只列文件名，全是占位图标——之前根本没人取过缩略图。
2. （v1.0.18 已删速传）原 -9934 根因：didAdd 下载时取景 20fps 还在抢
   PTP 通道；且 ICC 失败后复查那条路直接忽略结果。现在 didAdd 不再下载，
   拍后复查只把新文件插进图库；图库保存的下载仍先停帧再下。
3. 素材选项页：分享按钮只震一下什么都不干；下载失败时 completion
   永远不调，按钮“正在从相机下载…”转到天荒地老；时间比手机快 10
   分钟是相机时钟快（相机设定菜单校准），不是 App 算错。
4. 控制页电池下面挂着“诊断：0x1015 → 数据在 first…”看着像报错——
   其实是读成功的底层日志，每次读属性都往可见行里写。

这里验源码接线 + 模拟器 GetThumb + 纯逻辑镜像（暂停计数、诊断分级、
下载兜底链）。真机行为（缩略图是否显示、-9934 是否消失、分享是否
弹出）须由用户在相机上验证。
"""

import os, re, sys, threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 暂停计数镜像（UsbCameraManager pause/resume）---
class PauseCounter:
    def __init__(self, streaming=True):
        self.streaming = streaming
        self.count = 0
        self.paused = False

    def pause(self):
        if not self.streaming:
            return
        self.count += 1
        if self.count == 1:
            self.paused = True

    def resume(self):
        if self.count <= 0:
            return
        self.count -= 1
        if self.count == 0:
            self.paused = False


# --- 诊断分级镜像（ptpDiagnosticIsError）---
ERROR_MARKERS = ["失败", "被拒", "出错", "无数据", "未识别", "无应答", "超时",
                 "未见新照片", "没有新对象", "读卡句柄失败", "读句柄失败", "跳过"]


def is_error(text):
    return any(m in text for m in ERROR_MARKERS)


# --- 下载兜底链镜像（downloadOriginalData）---
def download_original_data(icc_ok, ptp_handle, ptp_ok):
    """icc_ok: ICC 下载是否成功；ptp_handle: 有无句柄；ptp_ok: PTP 取原图是否成功。
    返回 (成功与否, 走的路)。任何分支都必须有答复。"""
    if icc_ok:
        return True, "ICC"
    if ptp_handle is not None:
        return (True, "PTP") if ptp_ok else (False, "PTP")
    return False, "无路可走"


def run():
    passed = failed = 0

    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name}: {detail}")

    usb = read("Z30Control/Services/UsbCameraManager.swift")
    media = read("Z30Control/Services/MediaSyncService.swift")
    gallery = read("Z30Control/Views/Gallery/CameraGalleryView.swift")
    control = read("Z30Control/Views/Control/ControlDashboardView.swift")

    print("== 缩略图：GetThumb + 映射表 + 懒加载 ==")
    check("fetchThumbnailData 用 GetThumb 0x100A",
          "func fetchThumbnailData(handle: UInt32" in usb and "0x100A" in usb)
    check("文件名→句柄映射表存在", "filenameHandleMap" in media)
    check("映射表后台建表（最新 1000 个）",
          "fetchCardItemsViaPTP(limit: 1000)" in media)
    check("fetchCardItemsViaPTP 接受 limit 参数",
          "func fetchCardItemsViaPTP(limit: Int = 300" in usb)
    check("缩略图走缓存 + 在途去重",
          "thumbCache" in media and "thumbInFlight" in media)
    check("映射表未建好时请求挂起、建好后放掉",
          "thumbPending" in media)
    check("格子用 GalleryThumbImage", "GalleryThumbImage(item: item)" in gallery)
    check("列表也用 GalleryThumbImage",
          gallery.count("GalleryThumbImage(item: item)") >= 2)
    check("详情预览也取缩略图",
          "previewImage" in gallery and "thumbnail(for: item)" in gallery)

    print("== 速传已删：不再自动下载，拍后复查只插图库 ==")
    check("暂停改成计数式", "liveViewPauseCount" in usb)
    check("停取景时计数清零", "liveViewPauseCount = 0" in usb)
    check("didAdd 不再下载（只剩图库保存那一处 requestDownloadFile）",
          usb.count("requestDownloadFile") == 1)
    check("拍后复查插进图库（不再下载）",
          "insertNewCapturedFiles" in usb and "insertCapturedItem" in usb)
    check("图库保存下载前仍停帧",
          "func downloadUSBFile" in usb and "pauseLiveViewFetching()" in usb)
    check("没有速传重试/重扫（rescan 已删）",
          "rescanCardForNewPhotos" not in usb and "fetchNewCapturedFiles" not in usb)

    print("== 素材选项页：真分享 + 下载有答复 ==")
    check("downloadOriginalData 存在且任何路都调 completion",
          "func downloadOriginalData(item: CameraMediaItem" in media)
    check("下载收敛到 downloadOriginalData（旧的分支已删）",
          "downloadOriginalData(item: item)" in media
          and "ICC 目录的项目没有句柄，ICC 下不来就真的下不来" not in media)
    check("下载兜底查映射表", "filenameHandleMap[item.filename]" in media)
    check("分享调系统分享（UIActivityViewController）",
          "UIActivityViewController" in gallery)
    check("分享先把原图下到临时文件",
          "downloadOriginalData(item: item)" in gallery and "NSTemporaryDirectory()" in gallery)
    check("分享按钮不再是空震动",
          "之前这个按钮只震一下" in gallery)

    print("== 诊断行：只在真报错时显示 ==")
    check("ptpDiagnosticIsError 存在", "ptpDiagnosticIsError" in usb)
    check("控制页按 isError 显示",
          "if usbCamera.ptpDiagnosticIsError" in control)
    check("读属性成功不再写诊断行",
          "读成功是常态" in usb)
    check("没有速传页再显示诊断行（FastTransferView 已删）",
          not os.path.exists(os.path.join(ROOT, "Z30Control/Views/FastTransfer/FastTransferView.swift")))

    print("== 纯逻辑：暂停计数 ==")
    pc = PauseCounter()
    pc.pause(); pc.pause()
    check("两次暂停后仍停着", pc.paused and pc.count == 2)
    pc.resume()
    check("一次恢复后还停着（计数未归零）", pc.paused and pc.count == 1)
    pc.resume()
    check("两次恢复后才真正恢复", not pc.paused and pc.count == 0)
    pc.resume()
    check("多余的恢复是空操作", pc.count == 0 and not pc.paused)
    pc2 = PauseCounter(streaming=False)
    pc2.pause()
    check("没在取景时暂停是空操作", pc2.count == 0)

    print("== 纯逻辑：诊断分级 ==")
    check("成功日志不是错",
          not is_error("0x1015 → 数据在 first（裸数据）(first 1B / second 12B)，响应 0x2001"))
    check("下载失败是错", is_error("下载失败：未能完成操作。"))
    check("对焦被拒是错", is_error("对焦被拒 0x2008"))
    check("拍后复查跳过是错", is_error("拍后复查跳过：拍前卡快照没读到，只靠相机推送"))

    print("== 纯逻辑：下载兜底链 ==")
    check("ICC 成功走 ICC", download_original_data(True, None, False) == (True, "ICC"))
    check("ICC 失败 + 有句柄 + PTP 成功", download_original_data(False, 1234, True) == (True, "PTP"))
    check("ICC 失败 + 有句柄 + PTP 失败有答复",
          download_original_data(False, 1234, False) == (False, "PTP"))
    check("ICC 失败 + 没句柄也有答复（失败）",
          download_original_data(False, None, False) == (False, "无路可走"))

    print("== 模拟器：GetThumb 回 JPEG 小图 ==")
    import time as _time
    import struct as _struct
    import uuid as _uuid
    from test_fixed_flow import FixedClient, PKT_INIT_CMD_REQ, PKT_INIT_EVENT_REQ
    from z30_simulator import NikonZ30Simulator
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
    payload, code = c.data_request(0x1004)
    n = int.from_bytes(payload[0:4], "little")
    storages = [int.from_bytes(payload[4 + 4 * i:8 + 4 * i], "little") for i in range(n)]
    payload, code = c.data_request(0x1007, [storages[0], 0, 0])
    n = int.from_bytes(payload[0:4], "little")
    handles = [int.from_bytes(payload[4 + 4 * i:8 + 4 * i], "little") for i in range(n)]
    check("模拟器卡里有对象", len(handles) > 0, f"handles={handles}")
    thumb, tcode = c.data_request(0x100A, [handles[0]])
    check("GetThumb 回 0x2001", tcode == 0x2001, f"code=0x{tcode:04X}")
    check("GetThumb 回 JPEG（FF D8 开头）",
          len(thumb) > 2 and thumb[0] == 0xFF and thumb[1] == 0xD8,
          f"len={len(thumb)}")
    c.cmd_no_data(0x1003)

    print(f"\n通过 {passed} / {passed + failed}")
    return failed == 0


if __name__ == "__main__":
    sys.exit(0 if run() else 1)
