"""v1.0.38：取景页滤镜展开改成网格，一次全显、不滚动；第三组改名“低饱和”。

用户 2026-11-22 20:27 对着 v1.0.37 截图反馈两点：
1. 点了通用影调，第二列竖着排 12 个预设，轻胶片被截在底栏处、滑不到底。
   根因：单列 12 个芯片约 12×68 + 顶部对齐留白 ≈ 870pt，超出底栏上方
   约 770pt 的可视区；列里有 ScrollView 也没用——滑到底时最后一个芯片
   仍被底栏盖住（列框本身顶到了可视区底边之外）。
2. 第三个分组“低饱和 · 冷调 · 硬光”名字太长（竖条芯片 11 个字、159pt 高）。

改法：
1. 第二列改成网格（previewExpandedGrid）：一列放不下就自动多列，按列填
   （先填满第一列再填第二列，跟原来从上往下的顺序一致）；列数、芯片统一高、
   列距、字号全由 previewGridLayout 按可用区算出来，保证一次全显；网格里
   没有 ScrollView。v1.0.37 的对齐机制（RailGroupTopKey + railGroupTops +
   expandedColumnTopPadding）随第二列一起删了——网格顶对齐，不用跟被点
   分组的可见位置对齐。
2. 组名改短成“低饱和”（机身滤镜 tab 的分区分组标题跟着一起变，同一份数据）。
   注意 PictCtrlPresets.swift 头上写着“由脚本生成、不要手改”——重新生成会
   把组名打回原样，到时再改一次（代码里已留注释）。

检查点：
1. 网格在竖条右侧（同一 HStack，竖条之后、Spacer 之前）；竖条不动。
2. 单列 / 对齐机制全删了；网格里没有 ScrollView。
3. 排版函数存在且是纯函数式（列数、芯片统一高、列距、字号）；同组芯片等高。
4. 验算：把 Swift 的 previewGridLayout 原样抄成 Python，对 11 组 × 3 台机子
   （iPhone 16 Pro Max 440×956、390 宽 iPhone 390×844、iPad mini 5 768×1024）
   算一遍——宽、高都塞得进可用区（可用宽 = 屏宽 − 42 竖条 − 16 边距；
   可用高 = 屏高 − TabBar − 200 底栏预留），且字号不小于 8pt。
   另验 v1.0.37 的翻车现场：通用影调 12 个在旧单列里要 ≈870pt > 可视区。
5. 点选 / 收起 / 换组 / 一次只展开一组 / 选中态两处标记 / 字转 90° /
   磨砂玻璃 / DISP 一起藏，都没变。
6. 组名：“低饱和”在，旧长名不再是分组标题（注释里提旧名不算）。
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


VIEW = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")

hud_start = VIEW.find("private var portraitProHUD")
hud_end = VIEW.find("private func bottomSafeInset")
HUD = VIEW[hud_start:hud_end]
rail_start = VIEW.find("private var previewFilterRail")
rail_end = VIEW.find("private struct PreviewGridLayout")
RAIL = VIEW[rail_start:rail_end]
grid_start = VIEW.find("private func previewExpandedGrid")
grid_end = VIEW.find("/// 磨砂玻璃背景", grid_start)
GRID = VIEW[grid_start:grid_end]
chip_start = VIEW.find("private func filterChipButton(")
chip_end = VIEW.find("/// 芯片高 = 字数", chip_start)
CHIP = VIEW[chip_start:chip_end]

# ---------------------------------------------------------------- 1. 网格在竖条右侧，竖条不动
check("网格紧贴在竖条右侧（同一 HStack，竖条之后、Spacer 之前）",
      "previewExpandedGrid(" in HUD
      and HUD.find("previewFilterRail\n") < HUD.find("previewExpandedGrid(")
      < HUD.find("Spacer()")
      and "HStack(alignment: .top, spacing: 0)" in HUD)
check("竖条仍是 42pt 宽、原图 + 11 个组名",
      ".frame(width: 42)" in RAIL
      and 'previewChip(id: nil, title: "原图")' in RAIL
      and "ForEach(PictCtrlPresets.groups)" in RAIL)
check("网格拿到可用区（扣掉竖条 42pt 和底栏预留 200pt）",
      "availWidth: geo.size.width - 42 - 16" in HUD
      and "availHeight: geo.size.height - 200" in HUD)

# ---------------------------------------------------------------- 2. 单列 / 对齐机制全删，网格无滚动
check("旧的第二列没了（previewExpandedColumn）",
      "previewExpandedColumn" not in VIEW)
check("旧的对齐机制没了（RailGroupTopKey / railGroupTops / expandedColumnTopPadding）",
      "RailGroupTopKey" not in VIEW.replace(
          "制（RailGroupTopKey + railGroupTops）随第二列一起删了", "")
      and "railGroupTops" not in VIEW.replace(
          "制（RailGroupTopKey + railGroupTops）随第二列一起删了", "")
      and "expandedColumnTopPadding" not in VIEW)
check("网格里没有 ScrollView（一次全显，不用滚）",
      "ScrollView" not in GRID)
check("网格按列填（start..<end 切片，先填满一列再填下一列）",
      "group.presets[start..<end]" in GRID
      and "ForEach(0..<layout.columns" in GRID)
check("换组时网格重建（id 随组变）",
      '.id("preview-grid-\\(title)")' in GRID)

# ---------------------------------------------------------------- 3. 排版函数：纯函数、统一芯片高
check("有排版函数 previewGridLayout（列数、芯片高、列距、字号）",
      "private func previewGridLayout(" in VIEW
      and "private struct PreviewGridLayout" in VIEW
      and "columns" in VIEW and "chipHeight" in VIEW
      and "colPitch" in VIEW and "fontSize" in VIEW)
check("芯片统一高 = 最长名 ×（字号 + 1）+ 16（同组等高）",
      "CGFloat(maxNameLength) * (fontSize + 1) + 16" in VIEW)
check("字号从 12 往下试、列距从 42 往下收（先最大字号最宽列距）",
      "for fontSize in [12, 11, 10, 9, 8]" in VIEW
      and "for colPitch in [42, 36, 34, 30]" in VIEW)
check("网格芯片用统一高 + 排版算出的字号（不是按名字各算各的）",
      "height: layout.chipHeight, fontSize: layout.fontSize" in GRID)
check("竖条和网格共用一个芯片做法（filterChipButton）",
      "private func filterChipButton(" in VIEW
      and "private func railChip(title: String" in VIEW
      and "filterChipButton(" in VIEW)

# ---------------------------------------------------------------- 4. 验算：11 组 × 3 台机子，一次全显
# Swift 的 previewGridLayout 原样抄过来（行高 = 芯片高 + 6 间距；
# 网格另有顶部 4pt 留白，也算进去）。
def grid_layout(preset_count, max_name_len, avail_w, avail_h):
    spacing = 6
    for font_size in (12, 11, 10, 9, 8):
        chip_h = max_name_len * (font_size + 1) + 16
        rows = max(1, int((avail_h + spacing) // (chip_h + spacing)))
        columns = (preset_count + rows - 1) // rows
        for col_pitch in (42, 36, 34, 30):
            if columns * col_pitch <= avail_w:
                return columns, chip_h, col_pitch, font_size
    chip_h = max_name_len * 9 + 16
    rows = max(1, int((avail_h + spacing) // (chip_h + spacing)))
    return (preset_count + rows - 1) // rows, chip_h, 30, 8


# 各组（个数，最长名长）：从 PictCtrlPresets.swift 实测读出来，不手写。
groups = []
for m in re.finditer(
        r'PictCtrlPresetGroup\(title: "([^"]+)", presets: \[(.*?)\]\),',
        PRESETS, re.S):
    names = re.findall(r'displayName: "([^"]+)"', m.group(2))
    groups.append((m.group(1), len(names), max(len(n) for n in names)))
check("读到 11 组、121 套（验算用的分组表是源码实测，不是手写）",
      len(groups) == 11 and sum(c for _, c, _ in groups) == 121,
      f"{len(groups)} 组、{sum(c for _, c, _ in groups)} 套")

# （屏宽，屏高，TabBar 高）：16 Pro Max、390 宽 iPhone、mini 5。
DEVICES = [("iPhone 16 Pro Max 440×956", 440, 956, 83),
           ("390 宽 iPhone 390×844", 390, 844, 83),
           ("iPad mini 5 768×1024", 768, 1024, 49)]
worst = []
for dev_name, w, h, tab in DEVICES:
    avail_w = w - 42 - 16
    avail_h = h - tab - 200
    for title, count, max_len in groups:
        cols, chip_h, pitch, font = grid_layout(count, max_len, avail_w, avail_h)
        rows_used = (count + cols - 1) // cols
        total_w = cols * pitch
        total_h = rows_used * chip_h + (rows_used - 1) * 6 + 4  # +4 顶部留白
        fits = total_w <= avail_w and total_h <= avail_h and font >= 8
        worst.append((dev_name, title, cols, rows_used, font, total_w, total_h, fits))
        check(f"{dev_name}「{title}」{count} 个一次全显（{cols} 列×{rows_used} 行，{font}pt 字）",
              fits, f"宽 {total_w}/{avail_w}，高 {total_h}/{avail_h}")

# 胶片组（24 个、13 字名）是最大的一组，单拎出来看三台机子的排版。
for dev_name, title, cols, rows_used, font, total_w, total_h, fits in worst:
    if title == "胶片":
        print(f"    排版明细 {dev_name} 胶片组：{cols} 列 × {rows_used} 行，"
              f"{font}pt 字，宽 {total_w}pt，高 {total_h}pt")

# v1.0.37 翻车现场复算：通用影调 12 个在旧单列里要多高。
_, count, max_len = next(g for g in groups if g[0] == "通用影调")
old_single_col = count * (max_len * 13 + 16) + (count - 1) * 6 + 48  # 12 芯片 + 间距 + 对齐留白
check("旧单列确实放不下（通用影调 12 个单列约 870pt > 可视区）",
      old_single_col > 673, f"旧单列约 {old_single_col}pt，可用高 673pt（16PM）")

# ---------------------------------------------------------------- 5. 点选 / 收起 / 选中态 / 样式都没变
check("点组只改展开状态（toggle，不插内容）",
      "let expanding = railExpandedGroupTitle != group.title" in RAIL
      and "railExpandedGroupTitle = expanding ? group.title : nil" in RAIL)
check("有展开状态 railExpandedGroupTitle（nil = 全部收起）",
      "@State private var railExpandedGroupTitle: String? = nil" in VIEW)
check("网格里的预设芯片点选触发预览（previewChip 带统一高和字号）",
      "previewChip(" in GRID and "id: preset.id, title: preset.displayName" in GRID)
check("点预设立即应用预览（streamService.previewPreset = …flatMap…）",
      "streamService.previewPreset = id.flatMap" in VIEW)
check("选中态两处都有标记（预设变蓝、所在组也变蓝）",
      "selectedPresetGroupTitle" in VIEW
      and "selected: selectedPresetGroupTitle == group.title" in VIEW
      and "selectedPreviewPresetID == id" in VIEW)
check("字仍顺时针转 90°（跟框一个方向）",
      ".rotationEffect(.degrees(90))" in CHIP)
check("芯片仍是磨砂玻璃底、白字",
      "FrostedGlassView(style: .systemUltraThinMaterialDark)" in CHIP
      and ".foregroundColor(.white)" in CHIP)
check("没用 SwiftUI iOS 15 才有的 Material（只用 UIBlurEffect 包装）",
      ".ultraThinMaterial" not in VIEW and ".thinMaterial" not in VIEW)
check("DISP 清屏时网格和竖条一起藏（都在 !isCleanScreen 块里）",
      HUD.find("if !isCleanScreen") < HUD.find("previewExpandedGrid(")
      < HUD.find("portraitBottomControlDeck"))

# ---------------------------------------------------------------- 6. 组名改短
check("第三组改名“低饱和”",
      'PictCtrlPresetGroup(title: "低饱和"' in PRESETS)
check("旧长名不再是分组标题",
      'PictCtrlPresetGroup(title: "低饱和 · 冷调 · 硬光"' not in PRESETS)
check("11 组标题仍在（改名没丢组）",
      len(re.findall(r'PictCtrlPresetGroup\(title: "', PRESETS)) == 11)

# ---------------------------------------------------------------- 7. 版本 + iOS 14 护栏
check("版本 1.0.41 / build 42 两处一致",
      "MARKETING_VERSION: 1.0.41" in YML and "CURRENT_PROJECT_VERSION: 42" in YML and
      "<string>1.0.41</string>" in PLIST and "<string>42</string>" in PLIST)
check("iOS 14 护栏：没有 iOS 15+ 才有的 API（新式 alert / Button(role:) / .tint / 闭包 overlay）",
      "Button(role:" not in VIEW and ".tint(" not in VIEW
      and ".background(_:in:)" not in VIEW)

print()
passed = sum(1 for _, ok, _ in CHECKS if ok)
print(f"{passed}/{len(CHECKS)} checks passed")
raise SystemExit(0 if passed == len(CHECKS) else 1)
