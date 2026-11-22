"""v1.0.33 回归：取景页左侧滤镜条改成两级钻取 + 字转 90°。

用户 2026-11-22 19:28 对着 v1.0.32 纠正：分组要点开才进，不要一屏
全摊开占屏；字也要顺时针转 90°（跟框一个方向），横握手机时才横着读。
上次把“汉字横着写”理解成竖屏坐标里的横排，错了，这次按转 90° 改。

检查点：
1. 顶部横条彻底没了；竖条是 ScrollView(.vertical)，仍在取景页最左边。
2. 竖条在 portraitProHUD 里 HStack 第一位（最左边）；底栏单独在下面
   一行占满宽（快门仍在屏幕正中央，v1.0.24 的要求）；清屏时藏起来。
3. 分组还在：11 组、121 套，组顺序不变；「原图」仍是第一级第一个。
4. 芯片是白色窄条：白底黑字、圆角 6、宽 30pt、选中变蓝底白字；
   容器全透明（竖条那段里没有任何 .background 黑底）；
   中文顺时针转 90°（railChip 里有 rotationEffect(.degrees(90))，
   且没有横排的 .lineLimit(2)）。
5. 最长中文名 13 个字，芯片高按字数算（13pt/字 + 16pt 留白），
   转 90° 后字不会顶出白框。
6. 点选行为没变：点芯片实时预览、点「原图」清除、离页清掉；
   预览只改显示，不写相机（渲染器/取景流里仍无写槽代码）。
7. 版本 1.0.33 / build 34 两处一致；iOS 14 护栏。
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
      ".background(" not in rail.split("private func railChip")[0])
check("竖条里没有 Color.black.opacity(0.55) 的黑底条",
      "Color.black.opacity(0.55)" not in rail.split("private func railChip")[0])

# ---------------------------------------------------------------- 2. 最左边 + 底栏满宽
check("竖条在 portraitProHUD 里", "previewFilterRail" in hud)
check("竖条在 HStack 第一位（最左边）",
      hud.find("previewFilterRail") < hud.find("disconnectedEmptyState"))
check("底栏在竖条下面、单独一行占满宽",
      hud.find("portraitBottomControlDeck") > hud.find("previewFilterRail")
      and "HStack(alignment: .top, spacing: 0)" in hud)
check("底栏还是满宽横向内边距 16（快门居中）",
      ".padding(.horizontal, 16)" in hud)
check("竖条贴顶部安全区（刘海/灵动岛下面）",
      "previewFilterRail\n" in VIEW and "topSafeInset(geo)" in hud)
check("清屏时竖条藏起来",
      "if !isCleanScreen {\n                        previewFilterRail" in VIEW)

# ---------------------------------------------------------------- 3. 分组还在
groups = re.findall(r'PictCtrlPresetGroup\(title: "([^"]+)"', PRESETS)
check("还是 11 组", len(groups) == 11, "、".join(groups))
check("第一级按组排（ForEach groups）", "ForEach(PictCtrlPresets.groups)" in rail)
check("组名是竖条芯片（railChip 传 group.title）",
      "railChip(title: group.title" in rail)
check("组里芯片按组内顺序（第二级 ForEach group.presets）",
      "ForEach(group.presets)" in rail)
check("「原图」仍是第一级第一个芯片",
      rail.find('previewChip(id: nil, title: "原图")')
      < rail.find("ForEach(PictCtrlPresets.groups)"))
check("还是 121 套", PRESETS.count("PictCtrlPreset(id:") == 121)
check("芯片上显示中文名", "title: preset.displayName" in rail)

# ---------------------------------------------------------------- 4. 白窄芯片 + 字转 90° + 透明容器
check("芯片白底（未选中 Color.white）",
      ".background(selected ? NikonTheme.accentBlue : Color.white)" in rail)
check("芯片黑字（未选中 .black）",
      ".foregroundColor(selected ? .white : .black)" in rail)
check("选中芯片蓝底白字高亮", "selected ? NikonTheme.accentBlue" in rail)
check("芯片是小方块圆角 6，不是大药丸 14",
      ".cornerRadius(6)" in rail and ".cornerRadius(14)" not in rail)
check("芯片窄而高：宽 30pt，高随字数走",
      ".frame(width: 30, height: railChipHeight(for: title))" in rail)
check("竖条宽 42 贴左边缘", ".frame(width: 42)" in rail)
check("芯片文字顺时针转 90°（跟框一个方向）",
      "rotationEffect(.degrees(90))" in rail)
check("芯片是单行字（没有横排的两行）", ".lineLimit(2)" not in rail)
check("旧的深色药丸芯片没了（white.opacity(0.15) 底）",
      "Color.white.opacity(0.15)" not in rail)

# ---------------------------------------------------------------- 5. 最长名字转 90° 后放得下
names = re.findall(r'displayName: "([^"]+)"', PRESETS)
longest = max(names, key=len)
check("最长中文名 13 个字，芯片高按 13pt/字 + 16pt 留白算",
      len(longest) <= 14 and "CGFloat(title.count) * 13 + 16" in rail,
      f"最长是「{longest}」（{len(longest)} 字）")
check("芯片定宽防换行（fixedSize 横向）",
      ".fixedSize(horizontal: true, vertical: false)" in rail)

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
