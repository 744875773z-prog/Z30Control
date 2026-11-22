"""v1.0.29 回归：图库删除失效修复 + NP3 图库滤镜移除。

背景：用户在真机上试 v1.0.28，机身滤镜写槽成功（"效果不错"），但报告
图库删除失效，并要求取消图库里的 NP3 加滤镜功能。

1. 删除失效的原因（代码上能确认的唯一问题）：
   v1.0.28 的 diff 里 CameraGalleryView.swift、MediaSyncService.swift、
   两边的 deleteObject（0x100B）一个字节都没动过——删除的 PTP 代码本身
   没坏。坏的是 UI：同一个 VStack 上挂了三个 .alert(isPresented:)（保存
   结果 / 删除确认 / 删除结果），SwiftUI 一个 View 只认其中一个 alert，
   删除确认框被盖掉，点"删除"后什么都不弹，看着像删除失效。
   修法：一个 enum 状态 GalleryAlert + 单个 .alert(item:)，三种提示共用
   一个入口。本文件守住：图库页非注释行里只有一个 .alert 修饰符，且是
   .alert(item: $activeAlert)；删除确认分支里调 deleteSelected()。
2. 删除链路守住：图库"删除"按钮 → deleteSelected() → syncService.deleteItems
   → deleteOne → 两边 deleteObject；USB 和 Wi-Fi 的 deleteObject 都是
   0x100B（DeleteObject），响应 0x2001 算成功。
3. NP3 图库滤镜移除：NP3FilterView / NP3RecipeStore / NP3LUTRenderer /
   NP3PictureControl 四个文件 + test_v127_np3.py 都不在了；Swift 源码里
   再无 "NP3" 字样；详情页的"滤镜（导入 .NP3 配方）"入口没了；
   saveFilteredImageData 没了。
4. 机身滤镜不动：PictCtrl 四件套还在，121 套内置预设还在，0x90CE 仍无处可寻。
5. 版本 1.0.30 / build 31 两处一致；部署目标还是 14.0；改动文件无 iOS 15+ API。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" — " + detail) if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def code_lines(src):
    """去掉 // 注释行，剩下的才是真正会编译的代码。"""
    return [ln for ln in src.splitlines() if not ln.strip().startswith("//")]


def all_swift():
    out = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, "Z30Control")):
        for name in files:
            if name.endswith(".swift"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


GALLERY = read("Z30Control/Views/Gallery/CameraGalleryView.swift")
GALLERY_CODE = "\n".join(code_lines(GALLERY))
SYNC = read("Z30Control/Services/MediaSyncService.swift")
USB = read("Z30Control/Services/UsbCameraManager.swift")
PTPIP = read("Z30Control/Protocol/PtpIpClient.swift")
CONST = read("Z30Control/Protocol/PtpConstants.swift")

print("== 1. 删除入口：按钮 → 确认框 → deleteSelected → deleteItems ==")
check("图库有“删除”按钮，点它挂删除确认",
      'Button("删除")' in GALLERY and "activeAlert = .deleteConfirm(count:" in GALLERY)
check("删除确认框是 GalleryAlert 的一个分支",
      "case .deleteConfirm" in GALLERY and "primaryButton: .destructive" in GALLERY)
check("删除确认框的确认动作调 deleteSelected()",
      "deleteSelected()" in GALLERY)
check("deleteSelected 调 syncService.deleteItems",
      "syncService.deleteItems(items, progress:" in GALLERY)
check("deleteItems 串行删（deleteItemsResolved → deleteOne）",
      "deleteItemsResolved(items, progress:" in SYNC and "deleteOne(item)" in SYNC)
check("deleteOne：USB 走 UsbCameraManager.deleteObject，Wi-Fi 走 ptpClient.deleteObject",
      "UsbCameraManager.shared.deleteObject(handle: handle" in SYNC
      and "ptpClient.deleteObject(handle: handle)" in SYNC)

print("== 2. 删除走的是 0x100B（DeleteObject），两边都是 ==")
check("PtpConstants：deleteObject = 0x100B",
      re.search(r"case\s+deleteObject\s*=\s*0x100B", CONST) is not None)
check("USB：NikonPTPOpCode.deleteObject = 0x100B",
      re.search(r"case\s+deleteObject\s*=\s*0x100B", USB) is not None)
check("USB：deleteObject 用 deleteObject 操作码发命令",
      "buildPTPCommandPacket(opCode: NikonPTPOpCode.deleteObject.rawValue" in USB)
check("USB：deleteObject 响应 0x2001 算成功",
      "respCode == nil || respCode == 0x2001" in USB)
check("Wi-Fi：deleteObject 用 PtpOperationCode.deleteObject 发命令",
      "opCode: PtpOperationCode.deleteObject.rawValue" in PTPIP)
check("Wi-Fi：deleteObject 响应 0x2001 算成功",
      "code == PtpResponseCode.ok.rawValue" in PTPIP)

print("== 3. 单 alert 守住：一个 View 只挂一个 alert ==")
alert_mods = re.findall(r"\.alert\((?:isPresented|item):", GALLERY_CODE)
check("图库页代码里只有一个 .alert 修饰符（注释不算）",
      len(alert_mods) == 1, f"实际 {len(alert_mods)} 个：{alert_mods}")
check("唯一的 alert 是 .alert(item: $activeAlert)",
      ".alert(item: $activeAlert)" in GALLERY_CODE)
check("没有残留的 .alert(isPresented:)",
      ".alert(isPresented:" not in GALLERY_CODE)
check("三种提示都在同一个 alert 里（保存结果 / 删除确认 / 删除结果）",
      "case .saveResult" in GALLERY and "case .deleteConfirm" in GALLERY
      and "case .deleteResult" in GALLERY)
check("没有残留的旧 alert 状态",
      "showDeleteConfirm" not in GALLERY and "showBatchResult" not in GALLERY
      and "showBatchDeleteResult" not in GALLERY)

print("== 4. NP3 图库滤镜已移除 ==")
for rel in ("Z30Control/Models/NP3PictureControl.swift",
            "Z30Control/Services/NP3LUTRenderer.swift",
            "Z30Control/Services/NP3RecipeStore.swift",
            "Z30Control/Views/Gallery/NP3FilterView.swift",
            "Tests/test_v127_np3.py"):
    check(f"文件已删：{os.path.basename(rel)}",
          not os.path.exists(os.path.join(ROOT, rel)))
np3_left = [p for p in all_swift() if "NP3" in open(p, encoding="utf-8").read()]
check("Swift 源码里再无 NP3 字样", not np3_left,
      ("残留：" + ", ".join(os.path.basename(p) for p in np3_left)) if np3_left else "")
check("详情页没有“滤镜（导入 .NP3 配方）”入口",
      "滤镜（导入" not in GALLERY and "NP3FilterView" not in GALLERY)
check("saveFilteredImageData 已删（只被 NP3 滤镜用过）",
      "saveFilteredImageData" not in SYNC)

print("== 5. 机身滤镜不动 ==")
for rel in ("Z30Control/Models/PictCtrlPayload.swift",
            "Z30Control/Models/PictCtrlPresets.swift",
            "Z30Control/Services/PictCtrlService.swift",
            "Z30Control/Views/Control/PictCtrlView.swift"):
    check(f"机身滤镜文件还在：{os.path.basename(rel)}",
          os.path.exists(os.path.join(ROOT, rel)))
PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
check("121 套内置预设还在", PRESETS.count('payloadBase64: "') == 121)
check("机身滤镜 tab 还在取景和图库之间",
      "case pictCtrl = 2" in read("Z30Control/App/RootTabView.swift")
      and "case gallery = 3" in read("Z30Control/App/RootTabView.swift"))
all_src = "\n".join(open(p, encoding="utf-8").read() for p in all_swift())
code_src = "\n".join("\n".join(code_lines(open(p, encoding="utf-8").read()))
                     for p in all_swift())
check("仍无 0x90CE 删槽代码（注释除外）",
      "0x90CE" not in code_src and "DelCstPicCtrl" not in code_src
      and "deletePictCtrl" not in code_src)

print("== 6. 版本 + iOS 14 护栏 ==")
yml = read("project.yml")
plist = read("Z30Control/Info.plist")
check("版本 1.0.31 / build 32 两处一致",
      "MARKETING_VERSION: 1.0.31" in yml
      and "CURRENT_PROJECT_VERSION: 32" in yml
      and "<string>1.0.31</string>" in plist
      and "<string>32</string>" in plist)
check("部署目标还是 14.0", 'deploymentTarget: "14.0"' in yml)
check("project.yml 没有 info: 块（忽略注释行）",
      not any(re.match(r"\s*info\s*:", ln) for ln in yml.splitlines()
              if not ln.strip().startswith("#")))
for pat, label in [
    (r"confirmationDialog\(", "confirmationDialog（iOS 15）"),
    (r"Button\(role:", "Button(role:)（iOS 15）"),
    (r"\.tint\(", ".tint（iOS 16）"),
    (r"\.background\([^)]*,\s*in:", ".background(_:in:)（iOS 15）"),
    (r"onTapGesture\(.*location", "带位置的 onTapGesture（iOS 17）"),
    (r"\.overlay\(alignment:.*\{", "闭包式 .overlay（iOS 15）"),
    (r"\.alert\(.*\.button", "新式 alert（iOS 15）"),
]:
    check(f"iOS14：图库页无 {label}", not re.search(pat, GALLERY_CODE))

# ---------------------------------------------------------------- 汇总
failed = [n for n, ok, _ in CHECKS if not ok]
print(f"\n{len(CHECKS) - len(failed)}/{len(CHECKS)} 通过")
if failed:
    print("失败：")
    for n in failed:
        print("  - " + n)
    sys.exit(1)
print("全部通过")
