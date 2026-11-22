"""v1.0.32 回归：取景页滤镜条从顶部横条改成最左边竖条。

用户 2026-11-22 19:14 对着 v1.0.31 截图反馈：横着拍，顶部黑底横条
挡画面；改成：竖条贴取景页最左边，11 组照旧（组名 + 组里芯片），
中文横着写不转，白色小方块芯片，不要黑底条。

检查点：
1. 顶部横条彻底没了（previewFilterStrip 定义、横向 ScrollView、黑底条
   都不在滤镜条里）；竖条是 ScrollView(.vertical)。
2. 竖条在取景页最左边：portraitProHUD 里 HStack 第一位就是它，
   底栏单独在下面一行占满宽（快门仍在屏幕正中央，v1.0.24 的要求）。
3. 分组还在：11 组、121 套，组名 + 组里芯片，组顺序不变；「原图」仍是第一个。
4. 芯片是白色小方块：白底黑字、圆角 6、固定宽，选中变蓝底白字；
   容器全透明（竖条那段里没有任何 .background 黑底）；
   中文横着写（竖条 + 芯片那段里没有 rotationEffect）。
5. 最长中文名 12 个字，两行能放下（芯片 92pt、12pt 字，一行约 7 个字）。
6. 点选行为没变：点芯片实时预览、点「原图」清除、离页清掉；
   预览只改显示，不写相机（渲染器/取景流里仍无写槽代码）。
7. 版本 1.0.32 / build 33 两处一致；iOS 14 护栏。
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
STREAM = read("Z30Control/Services/LiveViewStreamService.swift")

# 竖条 + 芯片这段（从 rail 定义起到 chip 函数结束），断言都圈在这里面，
# 文件别处还有黑底徽标/DISP 按钮/横向参数选择器，那些是别的控件、要留着。
rail_start = VIEW.find("private var previewFilterRail")
chip_end = VIEW.find("// MARK: - 横屏专业相机两翼透明 OSD 布局")
rail = VIEW[rail_start:chip_end]
hud = VIEW.split("private var portraitProHUD", 1)[1].split(
    "private func bottomSafeInset", 1)[0]

# ---------------------------------------------------------------- 1. 横条没了，竖条来了
check("顶部横条定义没了", "previewFilterStrip" not in VIEW)
check("滤镜条是竖向 ScrollView",
      "ScrollView(.vertical, showsIndicators: false)" in rail)
check("竖条里没有横向 ScrollView", "ScrollView(.horizontal" not in rail)
check("竖条容器没有任何黑底 .background",
      ".background(" not in rail.split("private func previewChip")[0])
check("竖条里没有 Color.black.opacity(0.55) 的黑底条",
      "Color.black.opacity(0.55)" not in rail.split("private func previewChip")[0])

# ---------------------------------------------------------------- 2. 最左边 + 底栏满宽
check("竖条在 portraitProHUD 里", "previewFilterRail" in hud)
check("竖条在 HStack 第一位（最左边）",
      hud.find("previewFilterRail") < hud.find("disconnectedEmptyState"))
check("底栏在竖条下面、单独一行占满宽",
      hud.find("portraitBottomControlDeck") > hud.find("previewFilterRail")
      and "HStack(spacing: 0, alignment: .top)" in hud)
check("底栏还是满宽横向内边距 16（快门居中）",
      ".padding(.horizontal, 16)" in hud)
check("竖条贴顶部安全区（刘海/灵动岛下面）",
      "previewFilterRail\n" in VIEW and "topSafeInset(geo)" in hud)
check("清屏时竖条藏起来",
      "if !isCleanScreen {\n                        previewFilterRail" in VIEW)

# ---------------------------------------------------------------- 3. 分组还在
groups = re.findall(r'PictCtrlPresetGroup\(title: "([^"]+)"', PRESETS)
check("还是 11 组", len(groups) == 11, "、".join(groups))
check("竖条按组排（ForEach groups）", "ForEach(PictCtrlPresets.groups)" in rail)
check("组名显示出来", "Text(group.title)" in rail)
check("组里芯片按组内顺序", "ForEach(group.presets)" in rail)
check("「原图」仍是竖条第一个芯片",
      rail.find('previewChip(id: nil, title: "原图")')
      < rail.find("ForEach(PictCtrlPresets.groups)"))
check("还是 121 套", PRESETS.count("PictCtrlPreset(id:") == 121)
check("芯片上显示中文名", "title: preset.displayName" in rail)

# ---------------------------------------------------------------- 4. 白芯片 + 横字 + 透明容器
check("芯片白底（未选中 Color.white）",
      ".background(selected ? NikonTheme.accentBlue : Color.white)" in rail)
check("芯片黑字（未选中 .black）",
      ".foregroundColor(selected ? .white : .black)" in rail)
check("选中芯片蓝底白字高亮", "selected ? NikonTheme.accentBlue" in rail)
check("芯片是小方块圆角 6，不是大药丸 14",
      ".cornerRadius(6)" in rail and ".cornerRadius(14)" not in rail)
check("芯片固定宽 92，排成整齐一列", ".frame(width: 92)" in rail)
check("竖条固定宽 104 贴左边缘", ".frame(width: 104)" in rail)
check("竖条 + 芯片里没有 rotationEffect（中文横着写，不转）",
      "rotationEffect" not in rail)
check("旧的深色药丸芯片没了（white.opacity(0.15) 底）",
      "Color.white.opacity(0.15)" not in rail)

# ---------------------------------------------------------------- 5. 最长名字两行放得下
names = re.findall(r'displayName: "([^"]+)"', PRESETS)
longest = max(names, key=len)
check("最长中文名 12 个字，两行能放下（92pt、12pt 字，一行约 7 字）",
      len(longest) <= 14, f"最长是「{longest}」（{len(longest)} 字）")
check("芯片允许换两行", ".lineLimit(2)" in rail)

# ---------------------------------------------------------------- 6. 点选行为没变，预览只改显示
check("点「原图」清除预览（nil 经 flatMap 得到 nil）",
      "streamService.previewPreset = id.flatMap" in rail)
check("离开取景页清掉预览选择",
      "streamService.previewPreset = nil" in VIEW)
check("取景流仍有 previewPreset 状态（nil = 原图）",
      "previewPreset: PictCtrlPreset? = nil" in STREAM)
for needle, label in [
    ("0x90CD", "0x90CD 写槽"),
    ("setPictCtrlData", "写槽函数"),
    ("writeSlot", "写槽流程"),
]:
    check("渲染器文件里没有：" + label, needle not in RENDERER)

# ---------------------------------------------------------------- 7. 版本 + iOS 14 护栏
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")
check("版本 1.0.32 / build 33 两处一致",
      "MARKETING_VERSION: 1.0.32" in YML and "CURRENT_PROJECT_VERSION: 33" in YML and
      "<string>1.0.32</string>" in PLIST and "<string>33</string>" in PLIST)
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
