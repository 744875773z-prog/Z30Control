"""v1.0.39 回归：拍完在手机上加滤镜存一份。

用户 2026-11-22 20:47 的问题：相机没开滤镜、取景页开了预览滤镜，
点快门保存的还是相机里没加滤镜的照片。原因：预览滤镜只改手机屏幕
显示（LivePreviewRenderer），从不写相机；快门是 InitiateCapture，
照片按相机自己的设置存到卡里。用户选的修法（20:51）：拍完在手机上
加滤镜存一份——取景页选了非“原图”预设时点快门，拍完自动把带滤镜
的版本存一份到系统相册，相机卡里还是原片。

功能（FilteredCaptureService，新文件）：
1. 触发：只在快门那一刻选了非“原图”预设时走；选“原图”什么都不做。
   快门那一刻把选中的预设记下来，后面就用这个预设渲染（中途换滤镜
   不影响这次）。
2. 取片：优先等 ObjectAdded 事件拿新对象句柄（Wi-Fi 走事件通道、
   USB 走拍后复查插进图库的通知），拿不到就轮询 GetObjectHandles，
   用拍前快照做差集认新照片；然后 GetObject 下全分辨率原图。
   USB 和 Wi-Fi 都要通。
3. 渲染：复用取景预览同一套烘焙（LivePreviewRenderer.applyPreview——
   1D LUT 烘 32³ CIColorCube + 饱和度），不抄一份数学；全分辨率，
   只在最后做一次最高质量 JPEG 编码（1.0）。
4. 保存：走图库批量保存同一条存相册通道（MediaSyncService）。
   NSPhotoLibraryAddUsageDescription 权限键在 Info.plist 里。
5. 反馈：存好 / 哪步失败了都给轻提示；不管成败都不动卡里原片。
6. 拍完的下载渲染全程不冻取景：下载渲染在后台串行队列上；USB 下原图
   那一下先停取景帧拉取（ICC 下载和取景抢 PTP 通道会报 -9934），
   下完恢复（计数式暂停，不会把拍后复查的暂停提前放掉）。

检查点：
1. 只有选了非原图预设点快门才触发；选原图不触发。
2. 快门时刻的预设被记下来用于渲染。
3. 取片用新对象句柄：ObjectAdded 事件快路 + 轮询差集兜底。
4. 渲染复用预览的烘焙函数，不抄一份；照片全分辨率、只编一次 JPEG。
5. 保存走系统相册通道；失败有提示；不动卡里原片（无删除代码）。
6. 下载渲染在后台队列，不冻取景；USB 下原图前后停/恢复取景。
7. 版本 1.0.41 / build 42 两处一致；iOS 14 护栏。
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" — " + detail) if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


SERVICE = read("Z30Control/Services/FilteredCaptureService.swift")
VIEW = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
SYNC = read("Z30Control/Services/MediaSyncService.swift")
USB = read("Z30Control/Services/UsbCameraManager.swift")
RENDERER = read("Z30Control/Services/LivePreviewRenderer.swift")
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")

# ---------------------------------------------------------------- 1. 触发：只在选了非原图时点快门
shutter_fn = VIEW.split("private func triggerShutterCapture()")[1].split(
    "/// v1.0.39：拍完在手机上加滤镜存一份")[0]
check("快门时刻记下选中的预设（在发快门之前）",
      "let shutterPreset = selectedPreviewPresetID.flatMap" in shutter_fn
      and shutter_fn.index("let shutterPreset") < shutter_fn.index("capturePhoto"))
check("选了预设才走滤镜版保存（USB 分支）",
      "if let preset = shutterPreset" in shutter_fn
      and "saveFilteredCopyAfterCapture(preset: preset, transport: .usb)" in shutter_fn)
check("选了预设才走滤镜版保存（Wi-Fi 分支）",
      "saveFilteredCopyAfterCapture(preset: preset, transport: .wifi)" in shutter_fn)
check("选原图（nil）不触发：shutterPreset 为 nil 时不调用保存",
      shutter_fn.count("saveFilteredCopyAfterCapture") == 2
      and "if let preset = shutterPreset" in shutter_fn)
check("保存入口按通路传基线：USB 传拍前快照，Wi-Fi 传 nil",
      "usbCamera.preCaptureHandleSnapshot" in VIEW
      and "(transport == .usb) ? usbCamera.preCaptureHandleSnapshot : nil" in VIEW)

# ---------------------------------------------------------------- 2. 取片：事件快路 + 轮询差集
check("服务注册 ObjectAdded 观察者（事件快路）",
      "addObjectAddedObserver" in SERVICE)
check("服务轮询 GetObjectHandles，用基线差集认新照片",
      "pollTick" in SERVICE
      and "filter({ !baseline.contains($0) }).max()" in SERVICE)
check("轮询有超时兜底（20 秒没找到就报失败，不一直等）",
      "waitTimeout" in SERVICE and "20" in SERVICE
      and ".failed(.notFound)" in SERVICE)
check("Wi-Fi 事件通道通知观察者（handlePtpEvent 里 0x4002）",
      "notifyObjectAdded(objectId)" in SYNC
      and "PtpEventCode.objectAdded.rawValue" in SYNC)
check("USB 拍后复查插进图库时通知观察者（insertCapturedItem 带句柄）",
      "if let handle = ptpHandle { self.notifyObjectAdded(handle) }" in SYNC)
check("USB 拍前快照对外可读（capturePhoto 发快门前记下的卡内句柄）",
      "preCaptureHandleSnapshot" in USB)
check("USB 轮询句柄有公开入口",
      "fetchAllObjectHandlesPublic" in USB)
check("USB 和 Wi-Fi 各走各的取原图路",
      "downloadRawObjectData(handle:" in SERVICE
      and "client.getObject(handle:" in SERVICE)

# ---------------------------------------------------------------- 3. 渲染：复用预览烘焙，全分辨率，一次编码
check("渲染复用取景预览同一套烘焙（LivePreviewRenderer.applyPreview）",
      "LivePreviewRenderer.shared.applyPreview(to:" in SERVICE)
check("服务里没有自己抄一份 cube 数学（不建 CIFilter、不算 cube 点）",
      "CIFilter" not in SERVICE
      and "cubeValue" not in SERVICE
      and "32 * 32 * 32" not in SERVICE
      and "cubeData(" not in SERVICE)
check("只做一次最高质量 JPEG 编码（1.0）",
      SERVICE.count("jpegData(compressionQuality: 1.0)") == 1)
check("照片全分辨率，不缩小（无 resize/降采样）",
      "resize" not in SERVICE.lower()
      and "downsampl" not in SERVICE.lower()
      and "scaledTo" not in SERVICE
      and "thumbnail" not in SERVICE.lower())
check("非 JPEG 原图（比如 NEF）不硬解，直接报不支持",
      "0xFF, data[1] == 0xD8" in SERVICE
      and ".notJPEG" in SERVICE)

# ---------------------------------------------------------------- 4. 保存：走系统相册通道；失败有提示；不动原片
check("保存走图库批量保存同一条存相册通道",
      "MediaSyncService.shared.saveImageDataToPhotos" in SERVICE
      and "saveImageDataToPhotos" in SYNC
      and "saveDataToPhotosOrFiles(data, filename: filename) { outcome in" in SYNC
      and "completion(outcome == .photos)" in SYNC)
check("相册保存权限键在 Info.plist 里",
      "NSPhotoLibraryAddUsageDescription" in PLIST)
check("存好给轻提示（滤镜版已存到相册）",
      '"滤镜版已存到相册"' in VIEW)
check("失败也给轻提示（滤镜版保存失败 + 原因）",
      '"滤镜版保存失败"' in VIEW and "err.message" in VIEW)
check("服务里没有任何删除卡内原片的代码",
      "deleteObject" not in SERVICE and "0x100B" not in SERVICE
      and "DeleteObject" not in SERVICE)

# ---------------------------------------------------------------- 5. 不冻取景：后台队列 + USB 下原图时停/恢复取景
check("下载渲染在服务自己的后台串行队列上，不走主线程",
      'DispatchQueue(label: "com.z30control.filteredcapture"' in SERVICE
      and "workQueue.async" in SERVICE)
check("完成回调才回主线程（只为弹提示）",
      "DispatchQueue.main.async { req.completion(outcome) }" in SERVICE)
check("USB 下原图前停取景帧拉取，下完恢复（防 -9934）",
      "pauseLiveViewFetching()" in SERVICE
      and "resumeLiveViewFetching()" in SERVICE)
check("多拍排队：一次只跑一个请求，按快门顺序排队",
      "pending" in SERVICE and "pump()" in SERVICE
      and "active == nil" in SERVICE)

# ---------------------------------------------------------------- 6. 版本 + iOS 14 护栏
check("版本 1.0.41 / build 42 两处一致",
      "MARKETING_VERSION: 1.0.41" in YML and "CURRENT_PROJECT_VERSION: 42" in YML and
      "<string>1.0.41</string>" in PLIST and "<string>42</string>" in PLIST)
for banned in ["onTapGesture", "Button(role:", ".tint(", ".background(_:in:",
                "ultraThinMaterial", ".coordinateSpace(.named"]:
    check("新服务无 iOS 15+ API：%s" % banned, banned not in SERVICE)

print("")
failed = [c for c in CHECKS if not c[1]]
print("TOTAL %d passed, %d failed" % (len(CHECKS) - len(failed), len(failed)))
raise SystemExit(1 if failed else 0)
