"""v1.0.38：取景页滤镜竖条展开方式改成网格，一次全显、不滚动。

v1.0.37 的横向展开（竖条右侧第二列）已由网格取代：单列 12 个放不下，
通用影调的轻胶片被截在底栏处、滑不到底。v1.0.38 改成网格——竖条右侧
紧贴着的网格，一列放不下就自动多列，按列填，全部一次全显、没有
ScrollView；v1.0.37 的对齐机制（RailGroupTopKey + railGroupTops +
expandedColumnTopPadding）随第二列一起删了——网格顶对齐，不用跟被点
分组的可见位置对齐。详见 test_v138（网格排版验算）。

检查点：
1. 竖条不动：仍在最左边缘、顶到顶，原图 + 11 个组名。
2. 网格在竖条右侧（同一 HStack、alignment .top、spacing 0，紧贴），
   不是插进同一列；竖条里不再有 ForEach(group.presets)。
3. 分组位置不动：点组只改 railExpandedGroupTitle，竖条内容不变。
4. 对齐机制没了：网格顶对齐，不用跟被点分组对齐；换组时网格重建
   （id 随组变），不用滚动。
5. 点预设触发预览；再点该分组收起；点别的分组换一个网格；一次只展开一组。
6. 选中态：选中的预设变蓝，它所在的组在竖条里标蓝。
7. 文字仍顺时针转 90°；芯片仍是磨砂玻璃 + 白字；DISP 时竖条和网格
   一起藏起来。
8. 版本 1.0.41 / build 42 两处一致；iOS 14 护栏。
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" — " + detail) if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


VIEW = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")

# 各段切片：竖条本体、网格、芯片函数、竖屏布局。
hud_start = VIEW.find("private var portraitProHUD")
hud_end = VIEW.find("private func bottomSafeInset")
HUD = VIEW[hud_start:hud_end]
rail_start = VIEW.find("private var previewFilterRail")
rail_end = VIEW.find("private struct PreviewGridLayout")
RAIL = VIEW[rail_start:rail_end]
grid_start = VIEW.find("private func previewExpandedGrid")
grid_end = VIEW.find("/// 磨砂玻璃背景", grid_start)
GRID = VIEW[grid_start:grid_end]
chip_start = VIEW.find("private func railChip(")
chip_end = VIEW.find("/// 芯片高 = 字数", chip_start)
CHIP = VIEW[chip_start:chip_end]

# ---------------------------------------------------------------- 1. 竖条不动：最左边缘、顶到顶
check("竖条仍在 HStack 里、后面有 Spacer 撑满宽（贴最左边缘）",
      "previewFilterRail" in HUD and "Spacer()" in HUD
      and HUD.find("previewFilterRail") < HUD.find("Spacer()"))
check("竖条仍顶到最上方（没有 topSafeInset 的留白用法）",
      ".padding(.top, topSafeInset" not in VIEW)
check("竖条宽度仍是 42pt（窄条，不挡画面）",
      ".frame(width: 42)" in RAIL)

# ---------------------------------------------------------------- 2. 网格在竖条右侧，不是插进同一列
check("有网格 previewExpandedGrid",
      "private func previewExpandedGrid(" in VIEW)
check("网格紧贴在竖条右侧（同一 HStack，竖条之后、Spacer 之前）",
      "previewExpandedGrid(" in HUD
      and HUD.find("previewFilterRail\n") < HUD.find("previewExpandedGrid(")
      < HUD.find("Spacer()")
      and "HStack(alignment: .top, spacing: 0)" in HUD)
check("竖条本体里不再有组内预设（不插进同一列）",
      "ForEach(group.presets)" not in RAIL)
check("网格里才是组内预设（按列填，切片 ForEach group.presets[start..<end]）",
      "ForEach(group.presets[start..<end])" in GRID)
check("旧的第二列没了（previewExpandedColumn）",
      "previewExpandedColumn" not in VIEW)
check("旧的内联展开没了（ScrollViewReader / scrollTo / 定位 id）",
      "ScrollViewReader" not in RAIL
      and "scrollTo" not in RAIL
      and "rail-group-" not in VIEW)

# ---------------------------------------------------------------- 3. 分组位置不动
check("竖条里还是只显示原图 + 11 个组名",
      'previewChip(id: nil, title: "原图")' in RAIL
      and "ForEach(PictCtrlPresets.groups)" in RAIL
      and "railChip(title: group.title" in RAIL)
check("点组只改展开状态（toggle，不插内容）",
      "let expanding = railExpandedGroupTitle != group.title" in RAIL
      and "railExpandedGroupTitle = expanding ? group.title : nil" in RAIL)
check("有展开状态 railExpandedGroupTitle（nil = 全部收起）",
      "@State private var railExpandedGroupTitle: String? = nil" in VIEW)

# ---------------------------------------------------------------- 4. 对齐机制没了：网格顶对齐，不用跟被点分组对齐
# v1.0.37 的对齐机制（RailGroupTopKey + railGroupTops +
# expandedColumnTopPadding）随第二列一起删了——注释里提旧名不算
# （test_v138 §2 同款处理）。网格在 HStack 里 alignment .top，
# 顶对齐；换组时 id 变了整个网格重建，不用滚动（网格里没有 ScrollView）。
clean_view = VIEW.replace(
    "制（RailGroupTopKey + railGroupTops）随第二列一起删了", "")
check("对齐机制没了（RailGroupTopKey / railGroupTops / expandedColumnTopPadding）",
      "RailGroupTopKey" not in clean_view
      and "railGroupTops" not in clean_view
      and "expandedColumnTopPadding" not in clean_view)
check("换组时网格重建（id 随组变），不用滚动",
      '.id("preview-grid-\\(title)")' in GRID
      and "ScrollView" not in GRID)

# ---------------------------------------------------------------- 5. 点选 / 收起 / 换组 / 一次只展开一组
check("网格里的预设芯片点选触发预览（previewChip 带统一高和字号）",
      "previewChip(" in GRID
      and "id: preset.id, title: preset.displayName" in GRID)
check("点预设立即应用预览（streamService.previewPreset = …flatMap…）",
      "streamService.previewPreset = id.flatMap" in VIEW)
check("选中态两处都有标记（预设变蓝、所在组也变蓝）",
      "selectedPresetGroupTitle" in VIEW
      and "selected: selectedPresetGroupTitle == group.title" in VIEW
      and "selectedPreviewPresetID == id" in VIEW)

# ---------------------------------------------------------------- 6. 字转 90° + 磨砂玻璃 + DISP 一起藏
check("字仍顺时针转 90°（跟框一个方向）",
      ".rotationEffect(.degrees(90))" in CHIP)
check("网格芯片跟竖条同款（磨砂玻璃底、白字）",
      "FrostedGlassView(style: .systemUltraThinMaterialDark)" in CHIP
      and ".foregroundColor(.white)" in CHIP)
check("没用 SwiftUI iOS 15 才有的 Material（只用 UIBlurEffect 包装）",
      ".ultraThinMaterial" not in VIEW
      and ".thinMaterial" not in VIEW)
check("DISP 清屏时网格和竖条一起藏（都在 !isCleanScreen 块里）",
      HUD.find("if !isCleanScreen") < HUD.find("previewExpandedGrid(")
      < HUD.find("portraitBottomControlDeck"))

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
