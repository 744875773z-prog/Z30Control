"""v1.0.36 回归：取景页滤镜竖条回到最左边缘 + 芯片换成真透的磨砂玻璃。

v1.0.37：展开方式改成横向第二列（见 test_v137）——组内预设不再插进
同一列，ScrollViewReader 滚回也不需要了；本套件的展开断言已同步改
成横向展开，其他检查点不变。

用户 2026-11-22 20:04 对着 v1.0.34 截图纠正：“除了顶到顶了，其他没有
符合的地方”——从截图看两处实锤：
1. 竖条跑到了屏幕正中间，不在最左侧。根因：v1.0.34 删空状态时把
   HStack 里撑宽的内容一起删了，只剩 42pt 宽的竖条，被默认居中的
   VStack 顶到了正中间。修法：HStack 里加 Spacer 撑满宽，竖条贴到
   最左边缘；顶到最上方不变。
2. 芯片看着是纯白底，不是玻璃。根因：v1.0.34 用的 systemMaterialLight
   太不透。修法：改成最透的 systemUltraThinMaterialDark（UIBlurEffect，
   iOS 13 就有，iOS 14 可用），深色取景画面透得出来才是真玻璃；
   未选中字改白字（黑字在深色玻璃上看不清）；再加一圈细白描边定住
   玻璃边缘；选中仍是半透明蓝盖层 + 白字。

另复核（只读代码 + 本测试断言，真机仍留给用户）：
3. 点组展开的逻辑还在（v1.0.37 改横向：预设在竖条右侧第二列，不再
   插进同一列；一次只展开一组，railExpandedGroupTitle 单值）。
4. 字仍顺时针转 90°（跟框一个方向）；顶到最上方不变；容器全透明，
   不要黑底条。
5. 版本 1.0.37 / build 38 两处一致；iOS 14 护栏。
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

# 竖条布局那段（portraitProHUD）与芯片函数体（railChip），断言圈在这里面。
hud_start = VIEW.find("private var portraitProHUD")
hud_end = VIEW.find("private func bottomSafeInset")
HUD = VIEW[hud_start:hud_end]
chip_start = VIEW.find("private func railChip(")
chip_end = VIEW.find("/// 芯片高 = 字数", chip_start)
CHIP = VIEW[chip_start:chip_end]

# ---------------------------------------------------------------- 1. 竖条贴最左边缘
check("HStack 里竖条后面有 Spacer 撑满宽（竖条贴最左边缘）",
      "previewFilterRail" in HUD and "Spacer()" in HUD
      and HUD.find("previewFilterRail") < HUD.find("Spacer()"))
check("竖条仍顶到最上方（没有 topSafeInset 的留白用法）",
      ".padding(.top, topSafeInset" not in VIEW)
check("竖条宽度仍是 42pt（窄条，不挡画面）",
      ".frame(width: 42)" in VIEW)

# ---------------------------------------------------------------- 2. 真透的磨砂玻璃
check("芯片用最透的 systemUltraThinMaterialDark（UIBlurEffect，iOS 14 可用）",
      "FrostedGlassView(style: .systemUltraThinMaterialDark)" in CHIP)
check("芯片函数体内已无不透的 systemMaterialLight",
      "systemMaterialLight" not in CHIP)
check("未选中字是白色（深色玻璃上黑字看不清）",
      ".foregroundColor(.white)" in CHIP
      and "selected ? .white : .black" not in CHIP)
check("芯片没有纯白实底（白只出现在细描边里）",
      "background(Color.white" not in CHIP
      and ".fill(Color.white)" not in CHIP)
check("有细白描边定住玻璃边缘",
      ".stroke(Color.white.opacity(0.35), lineWidth: 0.5)" in CHIP)
check("选中仍是半透明蓝盖层 + 白字",
      "NikonTheme.accentBlue.opacity(0.8)" in CHIP)
check("没用 SwiftUI iOS 15 才有的 Material（只用 UIBlurEffect 包装）",
      ".ultraThinMaterial" not in VIEW
      and ".thinMaterial" not in VIEW)

# ---------------------------------------------------------------- 3. 点组展开（逻辑复核，v1.0.37 改横向）
check("有展开状态 railExpandedGroupTitle（nil = 全部收起）",
      "@State private var railExpandedGroupTitle: String? = nil" in VIEW)
check("组内预设改到竖条右侧第二列，不再插进同一列（v1.0.37 横向展开）",
      "private var previewExpandedColumn" in VIEW
      and "ForEach(group.presets)" not in VIEW[VIEW.find("private var previewFilterRail"):VIEW.find("private struct RailGroupTopKey")]
      and "ForEach(group.presets)" in VIEW[VIEW.find("private var previewExpandedColumn"):])
check("点组切换展开/收起（一次只展开一组）",
      "let expanding = railExpandedGroupTitle != group.title" in VIEW
      and "railExpandedGroupTitle = expanding ? group.title : nil" in VIEW)
check("选中态两处都有标记（预设变蓝、所在组也变蓝）",
      "selectedPresetGroupTitle" in VIEW
      and "selected: selectedPresetGroupTitle == group.title" in VIEW)

# ---------------------------------------------------------------- 3b. 点组真的展开（v1.0.37：第二列对齐用 PreferenceKey）
# v1.0.34 的旧根因（预设插在组芯片上方、插入点在可视区外面）已随横向
# 展开消失：第二列第一个预设用 RailGroupTopKey 传上来的可见 minY 对齐
# 被点分组的顶部，详见 test_v137。
check("旧的 ScrollViewReader 滚回没了（横向展开不再需要）",
      "ScrollViewReader" not in VIEW
      and "scrollTo" not in VIEW
      and "rail-group-" not in VIEW)
check("第二列对齐用 PreferenceKey（RailGroupTopKey，详见 test_v137）",
      "private struct RailGroupTopKey: PreferenceKey" in VIEW
      and ".onPreferenceChange(RailGroupTopKey.self)" in VIEW)
check("展开带动画（变化看得见）",
      "withAnimation" in VIEW)
check("芯片点按区域是整个矩形（转 90° 的字别把热区带偏）",
      ".contentShape(Rectangle())" in CHIP)

# ---------------------------------------------------------------- 4. 其他不变
check("字仍顺时针转 90°（跟框一个方向）",
      ".rotationEffect(.degrees(90))" in CHIP)
check("容器全透明、不要黑底条",
      "Color.black" not in VIEW[VIEW.find("private var previewFilterRail"):VIEW.find("private struct FrostedGlassView")])
check("空状态整块仍是删掉的（取景页无未连接提示块）",
      "disconnectedEmptyState" not in VIEW)

# ---------------------------------------------------------------- 5. 版本 + iOS 14 护栏
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
