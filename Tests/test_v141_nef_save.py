"""v1.0.41 回归：RAW（NEF）照片在图库里无法保存。

用户 2026-11-22 21:27 的问题：用 RAW 格式拍完照，在图库里无法保存。
根因（按代码查实）：MediaSyncService.saveDataToPhotosOrFiles 里 NEF 被
分流到 App 自己的文稿目录（Documents），没进系统相册；而且 Info.plist
里没有 UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace，所以存
在文稿目录的 NEF 在“文件”App 里也看不到。批量保存弹的还是“已存入手机
X 张”，用户去相册里找不到，就以为保存失败。
但手机本身是支持的：苹果官方“iOS 27 支持的相机 RAW 格式”列表里就有
Nikon Z30，系统相册能存、能显示 Z30 的 NEF。

修法：
1. NEF 改走系统相册：先写临时 .NEF 文件，用 PHAssetCreationRequest +
   addResource(with: .photo, fileURL:) 以 RAW 原样存进相册（JPEG 那条路
   不动）。成败以 performChanges 回调为准。
2. 兜底：相册写入失败才存到文稿目录，并给明确提示（批量保存结果里写
   明“已存到 App 文稿目录，在‘文件’App 里可以找到”）；Info.plist 加
   UIFileSharingEnabled 和 LSSupportsOpeningDocumentsInPlace。
3. 顺手改掉过时说法：saveDataToPhotosOrFiles 注释里“NEF 无法直接写入
   相册”按新行为改写；“保存到相册”按钮对 NEF 也名副其实了，不改文案。
   批量保存成功计数和“已存入手机 X 张”提示保持（成功 = 真进相册，或
   兜底走文稿目录 + 提示）。

检查点：
1. NEF 走相册 fileURL 通道，不再只进文稿目录。
2. 相册写入失败才走文稿目录兜底，且批量保存结果里有明确提示。
3. Info.plist 里两个文件共享键都在。
4. JPEG 保存路径不变；批量保存对 NEF 计成功。
5. 详情页不再留“NEF 无法写入相册”的旧说法。
6. 拍完存滤镜版不动（NEF 仍不支持滤镜版，那是另一回事）。
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


SYNC = read("Z30Control/Services/MediaSyncService.swift")
VIEW = read("Z30Control/Views/Gallery/CameraGalleryView.swift")
FCS = read("Z30Control/Services/FilteredCaptureService.swift")
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")

# ---------------------------------------------------------------- 1. NEF 走相册 fileURL 通道
check("NEF 有独立的进相册函数 saveNEFToPhotos",
      "func saveNEFToPhotos" in SYNC)
check("NEF 用 fileURL 通道加为 .photo 资源（RAW 原样进相册）",
      "addResource(with: .photo, fileURL: tempURL, options: nil)" in SYNC)
check("NEF 先写临时 .NEF 文件再交给相册",
      "temporaryDirectory" in SYNC
      and 'appendingPathExtension("NEF")' in SYNC
      and "try data.write(to: tempURL)" in SYNC)
check("临时文件在 performChanges 回调里删掉",
      "removeItem(at: tempURL)" in SYNC)
check("NEF 进相册成败以 performChanges 回调为准",
      "PHAssetCreationRequest.forAsset()" in SYNC
      and "completion(.photos)" in SYNC)
check("保存结果分三种：进相册 / 文稿目录兜底 / 彻底失败",
      "public enum PhotoSaveOutcome" in SYNC
      and "case photos" in SYNC
      and "case documents" in SYNC
      and "case failed" in SYNC)

# ---------------------------------------------------------------- 2. 文稿目录只是兜底 + 有明确提示
check("文稿目录只在相册拒收时走（saveToDocuments 兜底函数）",
      "func saveToDocuments" in SYNC
      and SYNC.count(".documentDirectory") == 1)
check("相册失败才调文稿目录兜底",
      "completion(self.saveToDocuments(data, filename: filename) ? .documents : .failed)" in SYNC)
check("单张保存透传保存结果（不吞 .documents）",
      "downloadAndSaveToPhotos(item: CameraMediaItem, completion: @escaping (PhotoSaveOutcome) -> Void)" in SYNC)
check("批量保存计文稿目录兜底张数",
      "completion(succeeded, documents, items.count)" in SYNC
      and "if outcome == .documents { documents += 1 }" in SYNC
      and "if outcome != .failed {" in SYNC)
check("批量保存结果提示写明文稿目录兜底、去“文件”App 找",
      "case saveResult(succeeded: Int, documents: Int, total: Int)" in VIEW
      and "已存到 App 文稿目录" in VIEW
      and "在“文件”App 里可以找到" in VIEW)
check("“已存入手机 X 张”提示保持（成功 = 进相册或兜底 + 提示）",
      "已存入手机" in VIEW)

# ---------------------------------------------------------------- 3. Info.plist 文件共享键
check("Info.plist 有 UIFileSharingEnabled = true",
      re.search(r"<key>UIFileSharingEnabled</key>\s*<true/>", PLIST) is not None)
check("Info.plist 有 LSSupportsOpeningDocumentsInPlace = true",
      re.search(r"<key>LSSupportsOpeningDocumentsInPlace</key>\s*<true/>", PLIST) is not None)

# ---------------------------------------------------------------- 4. JPEG 路径不变；批量保存对 NEF 计成功
check("JPEG/视频仍走 data 通道进相册（没动）",
      "req.addResource(with: isVideo ? .video : .photo, data: data, options: nil)" in SYNC)
check("批量保存：非失败都计成功",
      "if outcome != .failed {" in SYNC)
check("自动速传仍用同一条保存通道（结果非失败即成功）",
      "let ok = outcome != .failed" in SYNC)

# ---------------------------------------------------------------- 5. 旧说法清掉
check("全仓不再留“NEF 无法直接写入相册”的旧说法",
      "NEF 无法直接写入相册" not in SYNC
      and "NEF 无法写入相册" not in SYNC)
check("保存函数注释按新行为改写",
      "NEF 用 fileURL 通道以 RAW 原样存入" in SYNC)

# ---------------------------------------------------------------- 6. 拍完存滤镜版不动
check("滤镜版保存仍走同一条存相册通道（只认 .photos 为成功）",
      "saveImageDataToPhotos" in FCS
      and "completion(outcome == .photos)" in SYNC)
check("NEF 仍不支持滤镜版（另一回事，这版不动）",
      "notJPEG" in FCS)

# ---------------------------------------------------------------- 7. 版本 + iOS 14 护栏
check("版本 1.0.41 / build 42 两处一致",
      "MARKETING_VERSION: 1.0.41" in YML and "CURRENT_PROJECT_VERSION: 42" in YML and
      "<string>1.0.41</string>" in PLIST and "<string>42</string>" in PLIST)
for banned in ["onTapGesture", "Button(role:", ".tint(", ".background(_:in:",
                "ultraThinMaterial", ".coordinateSpace(.named"]:
    check("服务文件无 iOS 15+ API：%s" % banned, banned not in SYNC)
# 视图里原有的 .onTapGesture(count: 2)（详情页双击复位缩放）是 iOS 13 的老
# API，不禁；只禁 v126 那条带位置的 iOS 16/17 形式。
check("视图无带位置的 onTapGesture（iOS 16/17 才有）",
      "onTapGesture { location" not in VIEW
      and "onTapGesture(coordinateSpace:" not in VIEW)
for banned in ["Button(role:", ".tint(", ".background(_:in:",
                "ultraThinMaterial", ".coordinateSpace(.named"]:
    check("视图无 iOS 15+ API：%s" % banned, banned not in VIEW)
check("fileURL 通道是老 API（iOS 9+，iOS 14 能用）",
      "addResource(with: .photo, fileURL:" in SYNC)

print("")
failed = [c for c in CHECKS if not c[1]]
print("TOTAL %d passed, %d failed" % (len(CHECKS) - len(failed), len(failed)))
raise SystemExit(1 if failed else 0)
