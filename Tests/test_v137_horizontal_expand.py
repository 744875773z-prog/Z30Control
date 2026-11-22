"""v1.0.37：取景页滤镜竖条展开方式改成横向。

用户 2026-11-22 20:16 对着 v1.0.36 实测纠正：“位置好了，你改完横向
展开我看看，展开位置现在还是不对”——竖条位置（最左边缘、顶到顶）
对了，不用动；问题是展开方式：v1.0.34–36 是把组内预设插进同一列、
出现在该组芯片上方（竖着堆在列里），插进去的预设把分组顶走，位置
老不对。改成横向展开：竖条右侧紧贴着出现第二列，只放该组的预设；
横着拍照时看过去，就是在分组上方横着展开的一排选项。

检查点：
1. 竖条不动：仍在最左边缘、顶到顶，原图 + 11 个组名。
2. 第二列在竖条右侧（同一 HStack、alignment .top、spacing 0，紧贴），
   不是插进同一列；竖条里不再有 ForEach(group.presets)。
3. 分组位置不动：点组只改 railExpandedGroupTitle，竖条内容不变。
4. 对齐：第二列第一个预设跟被点分组芯片顶部对齐——组芯片用
   GeometryReader + PreferenceKey 把可见 minY 传上来（竖条坐标系），
   第二列据此补顶部留白（minY - 4pt，两列都有 4pt 上边距）。
5. 点预设触发预览；再点该分组收起；点别的分组换一列；一次只展开一组。
6. 选中态：选中的预设变蓝，它所在的组在竖条里标蓝。
7. 文字仍顺时针转 90°；芯片仍是磨砂玻璃 + 白字；DISP 时竖条和第二列
   一起藏起来。
8. 版本 1.0.37 / build 38 两处一致；iOS 14 护栏。
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

# 各段切片：竖条本体、第二列、芯片函数、竖屏布局。
hud_start = VIEW.find("private var portraitProHUD")
hud_end = VIEW.find("private func bottomSafeInset")
HUD = VIEW[hud_start:hud_end]
rail_start = VIEW.find("private var previewFilterRail")
rail_end = VIEW.find("private struct RailGroupTopKey")
RAIL = VIEW[rail_start:rail_end]
col_start = VIEW.find("private var previewExpandedColumn")
col_end = VIEW.find("private func expandedColumnTopPadding")
COLUMN = VIEW[col_start:col_end]
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

# ---------------------------------------------------------------- 2. 第二列在竖条右侧，不是插进同一列
check("有第二列 previewExpandedColumn",
      "private var previewExpandedColumn: some View" in VIEW)
check("第二列紧贴在竖条右侧（同一 HStack，竖条之后、Spacer 之前）",
      "previewExpandedColumn\n" in HUD
      and HUD.find("previewFilterRail\n") < HUD.find("previewExpandedColumn\n")
      < HUD.find("Spacer()")
      and "HStack(alignment: .top, spacing: 0)" in HUD)
check("竖条本体里不再有组内预设（不插进同一列）",
      "ForEach(group.presets)" not in RAIL)
check("第二列里才是组内预设（ForEach group.presets）",
      "ForEach(group.presets)" in COLUMN)
check("第二列宽也是 42pt（跟竖条一样窄）",
      ".frame(width: 42)" in COLUMN)
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

# ---------------------------------------------------------------- 4. 对齐：第一预设跟被点分组顶部对齐
check("有对齐用的 PreferenceKey（RailGroupTopKey）",
      "private struct RailGroupTopKey: PreferenceKey" in VIEW)
check("组芯片用 GeometryReader 量可见 minY（竖条坐标系）",
      "GeometryReader" in RAIL
      and 'geo.frame(in: .named("previewRailSpace")).minY' in RAIL)
check("竖条声明了坐标系 previewRailSpace",
      '.coordinateSpace(name: "previewRailSpace")' in RAIL)
check("可见位置用 onPreferenceChange 接到 railGroupTops",
      ".onPreferenceChange(RailGroupTopKey.self)" in RAIL
      and "@State private var railGroupTops: [String: CGFloat] = [:]" in VIEW)
check("第二列按 minY - 4pt 补顶部留白（两列都有 4pt 上边距）",
      "private func expandedColumnTopPadding(for title: String) -> CGFloat" in VIEW
      and "max((railGroupTops[title] ?? 4) - 4, 0)" in VIEW
      and ".padding(.top, expandedColumnTopPadding(for: title))" in COLUMN)
check("换组时第二列重建、滚动回顶部（id 随组变）",
      '.id("preview-expand-\\(title)")' in COLUMN)

# ---------------------------------------------------------------- 5. 点选 / 收起 / 换组 / 一次只展开一组
check("第二列里的预设芯片点选触发预览（previewChip）",
      'previewChip(id: preset.id, title: preset.displayName)' in COLUMN)
check("点预设立即应用预览（streamService.previewPreset = …flatMap…）",
      "streamService.previewPreset = id.flatMap" in VIEW)
check("选中态两处都有标记（预设变蓝、所在组也变蓝）",
      "selectedPresetGroupTitle" in VIEW
      and "selected: selectedPresetGroupTitle == group.title" in VIEW
      and "selectedPreviewPresetID == id" in VIEW)

# ---------------------------------------------------------------- 6. 字转 90° + 磨砂玻璃 + DISP 一起藏
check("字仍顺时针转 90°（跟框一个方向）",
      ".rotationEffect(.degrees(90))" in CHIP)
check("第二列芯片跟竖条同款（磨砂玻璃底、白字）",
      "FrostedGlassView(style: .systemUltraThinMaterialDark)" in CHIP
      and ".foregroundColor(.white)" in CHIP)
check("没用 SwiftUI iOS 15 才有的 Material（只用 UIBlurEffect 包装）",
      ".ultraThinMaterial" not in VIEW
      and ".thinMaterial" not in VIEW)
check("DISP 清屏时第二列和竖条一起藏（都在 !isCleanScreen 块里）",
      HUD.find("if !isCleanScreen") < HUD.find("previewExpandedColumn\n")
      < HUD.find("portraitBottomControlDeck"))

# ---------------------------------------------------------------- 7. 版本 + iOS 14 护栏
check("版本 1.0.37 / build 38 两处一致",
      "MARKETING_VERSION: 1.0.37" in YML and "CURRENT_PROJECT_VERSION: 38" in YML and
      "<string>1.0.37</string>" in PLIST and "<string>38</string>" in PLIST)
check("iOS 14 护栏：没有 iOS 15+ 才有的 API（新式 alert / Button(role:) / .tint / 闭包 overlay）",
      "Button(role:" not in VIEW and ".tint(" not in VIEW
      and ".background(_:in:)" not in VIEW)

print()
passed = sum(1 for _, ok, _ in CHECKS if ok)
print(f"{passed}/{len(CHECKS)} checks passed")
raise SystemExit(0 if passed == len(CHECKS) else 1)
