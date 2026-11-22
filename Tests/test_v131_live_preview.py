"""v1.0.31 回归：实时取景页滤镜实时预览（v1.0.32 最左侧竖条；
v1.0.34 组内联展开 + 磨砂玻璃 + 顶到最上方）。

功能：取景页最左侧一条竖向可滚动的滤镜条，平时是「原图」+ 11 个
组名，点组在该组上方展开组内预设（121 套齐全，按机身滤镜 tab 的 11 组
顺序），点选后取景画面实时套上该滤镜的样子；点「原图」恢复原样。
只做手机端预览，绝不影响相机、不写槽位、不改保存的照片。

渲染：预设 614 字节载荷里 +0x066 的 256 点 1D LUT（u16 大端，
0..32767）烘成 32³ CIColorCube——1D 曲线逐通道独立，cube 在
(r,g,b) 处的值就是 (lut[r], lut[g], lut[b])。饱和度（0x1E，
0.25/级）用 CIColorControls 一并加上：系数 = 1 + 值×0.1。
cube 按预设缓存，不每帧重算；预览叠加在降噪+锐化之后；
只消费最新帧（忙时丢帧）。

检查点：
1. LUT→CIColorCube 生成正确（Python 镜像 Swift 的算法）：
   中性预设的 cube 是单位阵（黑点 stays 黑、白点 stays 白）；
   全部 121 套逐通道独立；32³ 尺寸 = 32*32*32*4 个 float。
2. 饱和度映射：系数 = 1 + 值×0.1，全套在 0.7..1.3 内。
3. 滤镜条组内联展开：平时「原图」+ 11 组，点组在该组上方展开预设，
   「原图」能清除预览。
4. 预览路径不调用任何写槽代码、不碰保存的照片。
5. 预览在增强之后、只消费最新帧、不经过 JPEG 重压。
6. 机身滤镜 tab、图库删除修复、NP3 已移除的状态没动。
7. 版本 1.0.40 / build 41 两处一致；iOS 14 护栏。
"""

import base64
import math
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" — " + detail) if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
RENDERER = read("Z30Control/Services/LivePreviewRenderer.swift")
STREAM = read("Z30Control/Services/LiveViewStreamService.swift")
VIEW = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")

DIM = 32
LUT_MAX = 32767


def round_half_away(x):
    # Swift .rounded()：半值远离零；i/31*255 除端点外没有恰好 x.5 的情况，
    # 这里仍按 half-away 写，和 Swift 一致。
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def lut_value(lut, grid):
    idx = round_half_away(grid / 31.0 * 255.0)
    return lut[idx] / LUT_MAX


def build_cube(lut):
    # 镜像 LivePreviewRenderer.cubeData：R 最快、然后 G、最后 B，
    # 索引 ((b*32+g)*32+r)，每个点 4 个 float（RGBA）。
    out = [0.0] * (32 * 32 * 32 * 4)
    for b in range(32):
        for g in range(32):
            for r in range(32):
                base = ((b * 32 + g) * 32 + r) * 4
                out[base + 0] = lut_value(lut, r)
                out[base + 1] = lut_value(lut, g)
                out[base + 2] = lut_value(lut, b)
                out[base + 3] = 1.0
    return out


# ---------------------------------------------------------------- 1. cube 数学
b64s = re.findall(r'payloadBase64: "([A-Za-z0-9+/=]+)"', PRESETS)
ids = re.findall(r'id: "([a-z0-9\-]+)"', PRESETS)
check("预设仍是 121 套", len(b64s) == 121, f"找到 {len(b64s)} 套")

luts = {}
for pid, b in zip(ids, b64s):
    raw = base64.b64decode(b)
    luts[pid] = struct.unpack(">256H", raw[0x066:0x066 + 512])

neutral = build_cube(luts["neutral"])
# 32 点网格从 256 点 LUT 采样，量化误差上限 0.5/255 + 0.5/32767 ≈ 0.002，
# 所以单位阵只要求到 0.005——不是逐点精确，是采样精度内的单位阵。
ident_ok = True
max_err = 0.0
for b in range(32):
    for g in range(32):
        for r in range(32):
            base = ((b * 32 + g) * 32 + r) * 4
            want = (r / 31.0, g / 31.0, b / 31.0, 1.0)
            got = tuple(neutral[base:base + 4])
            max_err = max(max_err, max(abs(a - c) for a, c in zip(got, want)))
            if any(abs(a - c) > 0.005 for a, c in zip(got, want)):
                ident_ok = False
                break
check("中性预设的 cube 是单位阵（黑点 stays 黑、白点 stays 白，采样误差内）",
      ident_ok, f"最大偏差 {max_err:.5f}")

# 全部 121 套逐通道独立：抽查对角线 + 两端 + 确定性伪随机点
bad = []
for pid, lut in luts.items():
    cube = build_cube(lut)
    pts = [(i, i, i) for i in range(32)]
    pts += [(0, 0, 0), (31, 31, 31), (0, 31, 0), (31, 0, 31)]
    seed = 12345
    for _ in range(200):
        seed = (seed * 1103515245 + 12345) % (1 << 31)
        pts.append((seed % 32, (seed >> 5) % 32, (seed >> 10) % 32))
    for (r, g, b) in pts:
        base = ((b * 32 + g) * 32 + r) * 4
        want = (lut_value(lut, r), lut_value(lut, g), lut_value(lut, b), 1.0)
        got = tuple(cube[base:base + 4])
        if any(abs(a - c) > 1e-6 for a, c in zip(got, want)):
            bad.append(pid)
            break
check("全部 121 套 cube 逐通道独立", not bad, "; ".join(bad) if bad else "")
check("cube 尺寸 = 32³×4 个 float", len(neutral) == 32 * 32 * 32 * 4,
      f"{len(neutral)} 个")
check("Swift 里 cube 字节数 = 32³×4×4",
      "32 * 32 * 32 * 4 * 4" in RENDERER)

# ---------------------------------------------------------------- 2. 饱和度映射
def sat_factor(raw_byte):
    v = raw_byte if raw_byte < 128 else raw_byte - 256
    return max(0.0, min(2.0, 1.0 + (v * 0.25) * 0.1))

factors = {}
for pid, b in zip(ids, b64s):
    raw = base64.b64decode(b)
    factors[pid] = sat_factor(raw[0x1E])
check("饱和度系数全套在 0.7..1.3 内",
      all(0.7 <= f <= 1.3 for f in factors.values()),
      f"最小 {min(factors.values()):.2f} 最大 {max(factors.values()):.2f}")
check("FL25 低饱和冷调（饱和 -2.0）系数是 0.8",
      abs(factors["fl25-cool-mute"] - 0.8) < 1e-9)
check("Swift 里饱和度映射 = 1 + 值×0.1 且钳在 0..2",
      "1.0 + value * 0.1" in RENDERER and "max(0.0, min(2.0" in RENDERER)

# ---------------------------------------------------------------- 3. 渲染器源码
for needle, label in [
    ("CIColorCube", "用 CIColorCube 渲染"),
    ('"inputCubeDimension"', "传 inputCubeDimension"),
    ("cubeDimension = 32", "cube 维度 32"),
    ("NSCache", "cube 按预设缓存"),
    ("totalCostLimit", "缓存有上限"),
    ("CIColorControls", "饱和度用 CIColorControls"),
    ("kCIInputSaturationKey", "饱和度键正确"),
]:
    check("渲染器：" + label, needle in RENDERER)
ib = RENDERER.find("for b in")
ig = RENDERER.find("for g in")
ir = RENDERER.find("for r in")
check("cube 排布 R 最快、然后 G、最后 B（循环顺序 b→g→r）",
      0 <= ib < ig < ir)
check("渲染失败返回 nil（调用方用原图）",
      "-> UIImage?" in RENDERER and "return nil" in RENDERER)

# ---------------------------------------------------------------- 4. 取景流：预览分支
check("取景流有 previewPreset 状态（nil = 原图）",
      "previewPreset: PictCtrlPreset? = nil" in STREAM)
m = re.search(r"if let preset = previewPreset.*?(?=\n        // v1\.0\.6)", STREAM,
              re.DOTALL)
check("updateFrame 里有预览分支", m is not None)
if m:
    branch = m.group(0)
    check("预览先增强、再套 cube（叠加在降噪+锐化之后）",
          branch.find("enhanceLiveViewImage") < branch.find("applyPreview"))
    check("预览分支忙时丢帧（只消费最新帧）",
          "guard !frameFiltering else { return }" in branch)
    check("预览结果进 enhancedImage（不经过 JPEG 重压）",
          "out.enhancedImage = img" in branch and
          "jpegData(compressionQuality" not in branch)
    for needle, label in [
        ("0x90CD", "0x90CD 写槽"),
        ("setPictCtrlData", "写槽函数"),
        ("writeSlot", "写槽流程"),
        ("saveBackup", "备份流程"),
        ("PHPhotoLibrary", "相册写入"),
        ("MediaSyncService", "图库同步服务"),
    ]:
        check("预览分支不碰：" + label, needle not in branch)
for needle, label in [
    ("0x90CD", "0x90CD 写槽"),
    ("setPictCtrlData", "写槽函数"),
    ("writeSlot", "写槽流程"),
]:
    check("渲染器文件里没有：" + label, needle not in RENDERER)

# ---------------------------------------------------------------- 5. 取景页左侧两级滤镜条
# v1.0.34：「原图」+ 11 组名，点组在该组上方内联展开；字顺时针转 90°。
# （横向 ScrollView 在文件别处还有一个，是参数选择器，不是滤镜条。）
rail_seg = VIEW[VIEW.find("private var previewFilterRail"):
                VIEW.find("// MARK: - 横屏专业相机两翼透明 OSD 布局")]
check("滤镜条是竖向 ScrollView", "ScrollView(.vertical" in rail_seg)
check("滤镜竖条里没有横向 ScrollView", "ScrollView(.horizontal" not in rail_seg)
check("滤镜条从 11 组排平（flatMap 保持组顺序）",
      "PictCtrlPresets.groups.flatMap" in VIEW)
check("滤镜条第一个芯片是「原图」", 'previewChip(id: nil, title: "原图")' in VIEW)
check("芯片上显示中文名", "title: preset.displayName" in VIEW)
check("点「原图」清除预览（nil 经 flatMap 得到 nil）",
      "streamService.previewPreset = id.flatMap" in VIEW)
check("离开取景页清掉预览选择",
      "streamService.previewPreset = nil" in VIEW)
# v1.0.32：条从顶部横条改成最左侧竖条、仍在竖屏 HUD 里、底栏上面
hud = VIEW.split("private var portraitProHUD", 1)[1]
check("滤镜竖条在 portraitProHUD 里", "previewFilterRail" in hud)
check("滤镜竖条在底栏上面（先出现）",
      hud.find("previewFilterRail") < hud.find("portraitBottomControlDeck"))
check("清屏时滤镜条藏起来", "if !isCleanScreen {\n                        previewFilterRail" in VIEW)
check("滤镜条顶到最上方（不要 topSafeInset 留白）", "topSafeInset(geo)" not in VIEW)
check("选中芯片高亮（磨砂底上盖半透明蓝）",
      "NikonTheme.accentBlue.opacity(0.8)" in VIEW)
check("没有加标语和说明文字",
      "实时显示滤镜" not in VIEW and "点这里" not in VIEW)

# ---------------------------------------------------------------- 6. 其他状态没动
PICT = read("Z30Control/Views/Control/PictCtrlView.swift")
check("机身滤镜 tab 还是 121 套", "内置滤镜（121 套）" in PICT)
check("图库删除修复还在（单 alert）",
      "GalleryAlert" in read("Z30Control/Views/Gallery/CameraGalleryView.swift")
      or ".alert(item:" in read("Z30Control/Views/Gallery/CameraGalleryView.swift"))
swift_src = ""
for dp, _, fns in os.walk(os.path.join(ROOT, "Z30Control")):
    for fn in fns:
        if fn.endswith(".swift"):
            swift_src += read(os.path.join(dp, fn))
check("全仓 Swift 源码里仍无 NP3",
      "NP3" not in "\n".join(ln.split("//")[0] for ln in swift_src.splitlines()))

# ---------------------------------------------------------------- 7. 版本 + iOS 14 护栏
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")
check("版本 1.0.40 / build 41 两处一致",
      "MARKETING_VERSION: 1.0.40" in YML and "CURRENT_PROJECT_VERSION: 41" in YML and
      "<string>1.0.40</string>" in PLIST and "<string>41</string>" in PLIST)
check("部署目标还是 14.0", 'deploymentTarget: "14.0"' in YML)
for rel, src in [
    ("LivePreviewRenderer.swift", RENDERER),
    ("LiveViewStreamService.swift", STREAM),
    ("LiveViewMonitorView.swift", VIEW),
]:
    for pat, label in [
        (r"onTapGesture\(.*location", "onTapGesture 带 location（iOS 17）"),
        (r"Button\(role:", "Button(role:)（iOS 15）"),
        (r"\.tint\(", ".tint（iOS 16）"),
        (r"\.background\([^)]*,\s*in:", ".background(_:in:)（iOS 15）"),
        (r"\.overlay\(alignment:.*\{", "闭包式 .overlay（iOS 15）"),
        (r"confirmationDialog\(", "confirmationDialog（iOS 15）"),
    ]:
        check(f"iOS14：{rel} 无 {label}", not re.search(pat, src))

# ---------------------------------------------------------------- 汇总
failed = [n for n, ok, _ in CHECKS if not ok]
print(f"\n{len(CHECKS) - len(failed)}/{len(CHECKS)} 通过")
if failed:
    print("失败：")
    for n in failed:
        print("  - " + n)
    raise SystemExit(1)
print("全部通过")
