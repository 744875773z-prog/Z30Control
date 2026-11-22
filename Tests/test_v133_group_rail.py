"""v1.0.34 回归：取景页左侧滤镜条改成组内联展开 + 磨砂玻璃 + 顶到最上方，
未连接的空状态整块删掉。

v1.0.38：展开方式改成网格一次全显（见 test_v138）——组内预设不再插进
同一列、也不再是竖条右侧单列；本套件的展开断言已同步改成网格展开，其他检查点不变。

用户 2026-11-22 19:40 对着 v1.0.33 截图圈改：
红圈（左侧竖条）：顶到最上方；背景不要白色了，改磨砂玻璃质感；
点组直接在该组上方展开组内选项选，不要两级钻取。
黄圈（中间“未检测到相机信号”空状态块）：整块不要了，连接入口
只留在「控制」页。

检查点：
1. 网格展开：平时只显示「原图」+ 11 个组名；点组在竖条右侧展开网格
   （数量与该组一致，一次全显不滚动），再点收起；一次只展开一组；没有
   「← 分组」返回入口（两级钻取没了）。
2. 选中态：展开的预设芯片变蓝；它所在的组名也变蓝
   （selectedPresetGroupTitle）。
3. 芯片磨砂玻璃底（UIVisualEffectView + UIBlurEffect），不是纯白；
   选中在磨砂底上盖半透明蓝，仍是蓝底白字；容器全透明，不要黑底条。
4. 竖条顶到最上方：不要 topSafeInset 的留白，topSafeInset 辅助函数也删了。
5. 空状态整块没了：取景页里没有“未检测到相机信号”、没有
   disconnectedEmptyState / connectOptionRow，没有线连指引和连接向导
   的入口；「控制」页的连接入口还在。
6. 字仍顺时针转 90°（跟框一个方向）；芯片窄而高（宽 30pt、高随字数走）。
7. 点选仍能触发预览（点预设立即应用、点原图清除）；预览只改显示，
   不写相机。
8. 版本 1.0.40 / build 41 两处一致；iOS 14 护栏。
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
CONTROL = read("Z30Control/Views/Control/ControlDashboardView.swift")
PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
RENDERER = read("Z30Control/Services/LivePreviewRenderer.swift")

# 竖条 + 芯片这段（从 rail 定义起到 chip 函数结束），断言都圈在这里面。
rail_start = VIEW.find("private var previewFilterRail")
chip_end = VIEW.find("// MARK: - 横屏专业相机两翼透明 OSD 布局")
rail = VIEW[rail_start:chip_end]

# 模型里的分组与数量（从 PictCtrlPresets.swift 里数，不是抄文档）。
chunks = PRESETS.split('PictCtrlPresetGroup(title: "')[1:]
model_groups = {}
for chunk in chunks:
    title = chunk.split('"', 1)[0]
    model_groups[title] = chunk.count("PictCtrlPreset(id:")
EXPECTED = {
    "通用影调": 12, "影调族": 8, "低饱和": 20,
    "胶片": 24, "电影": 21, "风光": 14, "暗调": 10,
    "街拍": 5, "日系": 5, "黑白": 1, "人像": 1,
}

# ---------------------------------------------------------------- 1. 组内联展开
check("有展开状态 railExpandedGroupTitle（nil = 全部收起）",
      "@State private var railExpandedGroupTitle: String? = nil" in VIEW)
check("两级钻取的状态没了（railSelectedGroupTitle）",
      "railSelectedGroupTitle" not in VIEW)
check("没有「← 分组」返回入口（两级钻取没了）",
      "← 分组" not in VIEW)
check("平时只显示「原图」+ 11 个组名",
      'previewChip(id: nil, title: "原图")' in rail
      and "ForEach(PictCtrlPresets.groups)" in rail)
groups_block = rail.split("ForEach(PictCtrlPresets.groups)", 1)[1]
railfunc = VIEW[rail_start:VIEW.find("private struct PreviewGridLayout")]
grid_block = VIEW[VIEW.find("private func previewExpandedGrid"):VIEW.find("/// 磨砂玻璃背景")]
check("组内预设改到竖条右侧网格，不再插进同一列（v1.0.38 网格一次全显）",
      "ForEach(group.presets)" not in railfunc
      and "ForEach(group.presets[start..<end])" in grid_block)
check("点组切换展开/收起（同组再点就收起）",
      "railExpandedGroupTitle = expanding ? group.title : nil" in VIEW
      and "let expanding = railExpandedGroupTitle != group.title" in VIEW)
check("模型里还是 11 组、121 套",
      len(model_groups) == 11 and sum(model_groups.values()) == 121,
      f"{len(model_groups)} 组、{sum(model_groups.values())} 套")
check("各组数量与模型一致",
      model_groups == EXPECTED,
      "、".join(f"{k}{v}" for k, v in model_groups.items()))
check("组里芯片显示中文名", "title: preset.displayName" in rail)

# ---------------------------------------------------------------- 2. 选中态两处都有标记
check("有选中预设所属组的反查（selectedPresetGroupTitle）",
      "private var selectedPresetGroupTitle: String?" in VIEW)
check("组芯片按所属组标蓝",
      "selected: selectedPresetGroupTitle == group.title" in rail)
check("预设芯片按选中 id 标蓝",
      "selectedPreviewPresetID == id" in rail)

# ---------------------------------------------------------------- 3. 磨砂玻璃底
check("有 FrostedGlassView（UIVisualEffectView 包装）",
      "private struct FrostedGlassView: UIViewRepresentable" in VIEW
      and "UIVisualEffectView(effect: UIBlurEffect(style: style))" in VIEW)
check("芯片底用磨砂玻璃（v1.0.36 改最透的 systemUltraThinMaterialDark）",
      "FrostedGlassView(style: .systemUltraThinMaterialDark)" in rail)
check("未选中不再是纯白底",
      ".background(selected ? NikonTheme.accentBlue : Color.white)" not in rail)
check("选中在磨砂底上盖半透明蓝（仍是蓝底白字）",
      "NikonTheme.accentBlue.opacity(0.8)" in rail
      and ".foregroundColor(.white)" in rail)
check("芯片圆角 6", ".cornerRadius(6)" in rail)
check("竖条宽 42 贴左边缘", ".frame(width: 42)" in rail)
check("竖条容器没有任何颜色底 .background（GeometryReader 量位置除外）",
      ".background(Color" not in rail.split("private func railChip")[0]
      and ".background(NikonTheme" not in rail.split("private func railChip")[0])

# ---------------------------------------------------------------- 4. 竖条顶到最上方
check("竖条不要 topSafeInset 的留白",
      ".padding(.top, topSafeInset(geo))" not in VIEW)
check("topSafeInset 辅助函数删了",
      "private func topSafeInset" not in VIEW)

# ---------------------------------------------------------------- 5. 空状态整块没了
for needle, label in [
    ("未检测到相机信号", "空状态标题"),
    ("disconnectedEmptyState", "空状态视图"),
    ("connectOptionRow", "连接入口行"),
    ("showingWiredHelp", "线连指引入口"),
    ("wiredConnectionGuidanceSheet", "线连指引页"),
    ("showingConnectionWizard", "连接向导入口"),
    ("USB-C 直连", "USB-C 直连卡片"),
    ("连接相机 Wi-Fi 热点", "Wi-Fi 热点卡片"),
]:
    check("取景页里没有：" + label, needle not in VIEW)
check("「控制」页的连接向导入口还在",
      "showingConnectionWizard" in CONTROL
      and "ConnectionWizardView()" in CONTROL)

# ---------------------------------------------------------------- 6. 字顺时针转 90° + 窄高芯片
check("芯片文字顺时针转 90°（跟框一个方向）",
      "rotationEffect(.degrees(90))" in rail)
check("芯片是单行字（没有横排的两行）", ".lineLimit(2)" not in rail)
check("芯片定宽防换行（fixedSize 横向）",
      ".fixedSize(horizontal: true, vertical: false)" in rail)
check("竖条芯片窄而高：宽 30pt，高随字数走（railChipHeight 经 filterChipButton）",
      "height: railChipHeight(for: title)" in rail
      and ".frame(width: 30, height: height)" in rail)
check("芯片高按字数算（13pt/字 + 16pt 留白）",
      "CGFloat(title.count) * 13 + 16" in rail)

# ---------------------------------------------------------------- 7. 点选触发预览，预览只改显示
check("点预设立即应用预览（streamService.previewPreset = …flatMap…）",
      "streamService.previewPreset = id.flatMap" in rail)
check("点「原图」清除预览", 'previewChip(id: nil, title: "原图")' in rail)
check("离开取景页清掉预览选择",
      "streamService.previewPreset = nil" in VIEW)
for needle, label in [
    ("0x90CD", "0x90CD 写槽"),
    ("setPictCtrlData", "写槽函数"),
    ("writeSlot", "写槽流程"),
]:
    check("渲染器文件里没有：" + label, needle not in RENDERER)

# ---------------------------------------------------------------- 8. 版本 + iOS 14 护栏
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")
check("版本 1.0.40 / build 41 两处一致",
      "MARKETING_VERSION: 1.0.40" in YML and "CURRENT_PROJECT_VERSION: 41" in YML and
      "<string>1.0.40</string>" in PLIST and "<string>41</string>" in PLIST)
check("部署目标还是 14.0", 'deploymentTarget: "14.0"' in YML)
for pat, label in [
    (r"onTapGesture\(.*location", "onTapGesture 带 location（iOS 17）"),
    (r"Button\(role:", "Button(role:)（iOS 15）"),
    (r"\.tint\(", ".tint（iOS 16）"),
    (r"\.background\([^)]*,\s*in:", ".background(_:in:)（iOS 15）"),
    (r"\.overlay\(alignment:.*\{", "闭包式 .overlay（iOS 15）"),
    (r"confirmationDialog\(", "confirmationDialog（iOS 15）"),
]:
    check(f"iOS14：LiveViewMonitorView 无 {label}", not re.search(pat, VIEW))

# ---------------------------------------------------------------- 汇总
failed = [n for n, ok, _ in CHECKS if not ok]
print(f"\n{len(CHECKS) - len(failed)}/{len(CHECKS)} 通过")
if failed:
    print("失败：")
    for n in failed:
        print("  - " + n)
    raise SystemExit(1)
print("全部通过")
