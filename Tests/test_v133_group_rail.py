"""v1.0.33 回归：取景页左侧滤镜条两级钻取 + 字转 90°。

用户 2026-11-22 19:28 纠正 v1.0.32：“按组分好，然后点击组进行选择，
这个可以降低屏幕占用，而且汉字布局方式并不是我要的，把他们也旋转
90°”。上次把“汉字横着写”理解成竖屏坐标里的横排，错了——用户横着
握手机拍，框在页内顺时针转了 90°，字也要顺时针转 90° 才横着读。

检查点：
1. 第一级是 12 项：原图 + 11 个组名，不再一屏全展开 121 套。
2. 点组进入第二级，只显示该组的预设，数量与该组一致
   （胶片 24、电影 21、风光 14、暗调 10、街拍 5、日系 5、
   黑白 1、人像 1、通用影调 12、影调族 8、低饱和·冷调·硬光 20）。
3. 第二级顶部有返回入口「← 分组」，点它回到第一级。
4. 选中态两级都有标记：第二级里选中的预设芯片变蓝；第一级里
   它所在的组名也变蓝（selectedPresetGroupTitle）。
5. 所有芯片里的中文都顺时针转 90°（rotationEffect(.degrees(90))，
   跟框一个方向），不是横排。
6. 芯片窄而高（宽 30pt、高随字数走），白底白框、黑字，选中蓝底白字；
   容器全透明，不要黑底条。
7. 点选仍能触发预览（点预设立即应用、点原图清除）；预览只改显示，
   不写相机。
8. 版本 1.0.33 / build 34 两处一致；iOS 14 护栏。
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
    "通用影调": 12, "影调族": 8, "低饱和 · 冷调 · 硬光": 20,
    "胶片": 24, "电影": 21, "风光": 14, "暗调": 10,
    "街拍": 5, "日系": 5, "黑白": 1, "人像": 1,
}

# ---------------------------------------------------------------- 1. 第一级 12 项
check("有两级状态 railSelectedGroupTitle（nil = 第一级）",
      "@State private var railSelectedGroupTitle: String? = nil" in VIEW)
check("第一级有「原图」芯片", 'previewChip(id: nil, title: "原图")' in rail)
check("第一级按组排（ForEach groups）", "ForEach(PictCtrlPresets.groups)" in rail)
check("第一级组名是芯片（railChip 传 group.title）",
      "railChip(title: group.title" in rail)
check("第一级没有直接展开全部预设（else 分支里没有 ForEach group.presets）",
      rail.split("} else {", 1)[1].count("ForEach(group.presets)") == 0
      if "} else {" in rail else False)
check("模型里还是 11 组、121 套",
      len(model_groups) == 11 and sum(model_groups.values()) == 121,
      f"{len(model_groups)} 组、{sum(model_groups.values())} 套")

# ---------------------------------------------------------------- 2. 点组进第二级，数量与该组一致
check("点组进第二级（railSelectedGroupTitle = group.title）",
      "railSelectedGroupTitle = group.title" in rail)
check("第二级按组名反查该组",
      "PictCtrlPresets.groups.first(where: { $0.title == title })" in rail)
check("第二级只显示该组预设（ForEach group.presets）",
      "ForEach(group.presets)" in rail)
check("各组数量与模型一致",
      model_groups == EXPECTED,
      "、".join(f"{k}{v}" for k, v in model_groups.items()))
check("第二级芯片显示中文名", "title: preset.displayName" in rail)

# ---------------------------------------------------------------- 3. 返回入口
check("第二级顶部有返回入口「← 分组」", 'railChip(title: "← 分组"' in rail)
check("点返回回到第一级（railSelectedGroupTitle = nil）",
      "railSelectedGroupTitle = nil" in rail)

# ---------------------------------------------------------------- 4. 选中态两级都有标记
check("有选中预设所属组的反查（selectedPresetGroupTitle）",
      "private var selectedPresetGroupTitle: String?" in VIEW)
check("第一级组芯片按所属组标蓝",
      "selected: selectedPresetGroupTitle == group.title" in rail)
check("第二级预设芯片按选中 id 标蓝",
      "selectedPreviewPresetID == id" in rail)
check("标蓝是蓝底白字（accentBlue + .white）",
      ".background(selected ? NikonTheme.accentBlue : Color.white)" in rail
      and ".foregroundColor(selected ? .white : .black)" in rail)

# ---------------------------------------------------------------- 5. 字顺时针转 90°
check("芯片文字顺时针转 90°（跟框一个方向）",
      "rotationEffect(.degrees(90))" in rail)
check("芯片是单行字（没有横排的两行）", ".lineLimit(2)" not in rail)
check("芯片定宽防换行（fixedSize 横向）",
      ".fixedSize(horizontal: true, vertical: false)" in rail)

# ---------------------------------------------------------------- 6. 窄高白芯片 + 透明容器
check("芯片窄而高：宽 30pt，高随字数走",
      ".frame(width: 30, height: railChipHeight(for: title))" in rail)
check("芯片高按字数算（13pt/字 + 16pt 留白）",
      "CGFloat(title.count) * 13 + 16" in rail)
check("芯片白底（未选中 Color.white）",
      ".background(selected ? NikonTheme.accentBlue : Color.white)" in rail)
check("芯片圆角 6", ".cornerRadius(6)" in rail)
check("竖条宽 42 贴左边缘", ".frame(width: 42)" in rail)
check("竖条容器没有任何黑底 .background",
      ".background(" not in rail.split("private func railChip")[0])

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
check("版本 1.0.33 / build 34 两处一致",
      "MARKETING_VERSION: 1.0.33" in YML and "CURRENT_PROJECT_VERSION: 34" in YML and
      "<string>1.0.33</string>" in PLIST and "<string>34</string>" in PLIST)
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
