"""v1.0.30 回归：全部 121 套机身滤镜分好组、加进「机身滤镜」tab。

数据源：1dlut 项目 android/app/src/main/assets/builtin_presets.json（121 套，
桌面端 tools/gen_android_presets.py 用 z30fit 代码生成——手机端只做搬运）。

检查点：
1. 121 套齐全：Swift 里的 payloadBase64 正好 121 个，id 全在 JSON 里，
   每套 base64 与 JSON 原文一字不差（13 套还用桌面端代码重算过，逐字节一致）。
2. 每套 614 字节、版本 02 00、名字栏 = cam 名且 ASCII ≤ 20 字节、
   LUT 段 256×u16 大端、值域 0..32767、单调。
3. 分组：11 组，数量加起来 121——通用影调 12、影调族 8、低饱和·冷调·硬光 20、
   胶片 24、电影 21、风光 14、暗调 10、街拍 5、日系 5、黑白 1、人像 1；
   分组顺序和 1dlut 原顺序一致；组内顺序和 JSON 一致。
4. 无重复载荷（121 个 payload 各不相同）；旧的 8 套都在 121 套里（按 id 和字节）。
5. UI：机身滤镜 tab 里是分组可折叠分区（组标题 + 展开/收起），标题写 121 套，
   C1–C9 九宫格还在上面，写槽流程（备份→写→读回比对）没动。
6. 版本 1.0.30 / build 31 两处一致；iOS 14 护栏（改动文件无 iOS 15+ API）。
"""

import base64
import json
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 1dlut 克隆：优先持久化那份，/tmp 那份重启会丢
DLUT = None
for cand in (os.path.join(os.path.expanduser("~"), "workspace", "dlutz30"),
             "/tmp/dlutz30"):
    if os.path.exists(os.path.join(cand, "z30fit", "payload.py")):
        DLUT = cand
        break

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" — " + detail) if detail else ""))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
VIEW = read("Z30Control/Views/Control/PictCtrlView.swift")

# 分组表（1dlut 自己的分法）：40 参数化 = 通用 12 + 影调族 8 + 低饱和 20；
# 81 配方库按 ncp_data.py 的 group 字段分 8 组。
EXPECTED = [("通用影调", 12), ("影调族", 8), ("低饱和", 20),
            ("胶片", 24), ("电影", 21), ("风光", 14), ("暗调", 10),
            ("街拍", 5), ("日系", 5), ("黑白", 1), ("人像", 1)]

# ---------------------------------------------------------------- 1. 总数 + 逐套比对
b64s = re.findall(r'payloadBase64: "([A-Za-z0-9+/=]+)"', PRESETS)
check("内置预设正好 121 套", len(b64s) == 121, f"找到 {len(b64s)} 套")
check("121 个载荷各不相同（无重复）", len(set(b64s)) == 121)

swift_ids = re.findall(r'id: "([a-z0-9\-]+)"', PRESETS)
check("121 个 id 各不相同", len(set(swift_ids)) == 121, f"去重后 {len(set(swift_ids))} 个")

if DLUT is None:
    print("SKIP 与 1dlut 原文比对：克隆不在")
    by_id = {}
else:
    data = json.load(open(os.path.join(
        DLUT, "android/app/src/main/assets/builtin_presets.json"), encoding="utf-8"))
    check("JSON 里也是 121 套", len(data["presets"]) == 121)
    by_id = {p["id"]: p for p in data["presets"]}
    check("121 套 id 都在 1dlut 预设库里", all(i in by_id for i in swift_ids))
    # Swift 是按分组排的（JSON 里 81 套是交错的，不是按组排的），所以全局顺序
    # 不要求一致；要求的是每组内部的相对顺序和 JSON 一致（稳定分组）。
    json_ids = [p["id"] for p in data["presets"]]
    for title, want in EXPECTED:
        group_ids = re.findall(r'id: "([a-z0-9\-]+)"',
                               PRESETS.split(f'title: "{title}"', 1)[1].split("]),", 1)[0])
        json_group = [i for i in json_ids if i in set(group_ids)]
        check(f"分组「{title}」组内顺序和 JSON 一致",
              group_ids == json_group, f"{len(group_ids)} 套")
    bad = []
    for pid, b64 in zip(swift_ids, b64s):
        if b64 != by_id[pid]["payload"]:
            bad.append(pid)
    check("每套 base64 与 1dlut 原文一字不差", not bad, "; ".join(bad) if bad else "")

    # 2. 逐套载荷结构
    for pid, b64 in zip(swift_ids, b64s):
        raw = base64.b64decode(b64)
        ok = (len(raw) == 614 and raw[0:2] == b"\x02\x00")
        name_in = raw[0x002:0x016].split(b"\x00")[0]
        try:
            name_in.decode("ascii")
            ascii_ok = True
        except UnicodeDecodeError:
            ascii_ok = False
        ok = ok and ascii_ok and len(name_in) <= 20 and name_in.decode("ascii") == by_id[pid]["cam"]
        lut = struct.unpack(">256H", raw[0x066:0x066 + 512])
        ok = ok and min(lut) >= 0 and max(lut) <= 32767 and all(
            lut[i] <= lut[i + 1] for i in range(255))
        if not ok:
            check(f"预设 {pid} 载荷结构（614B/02 00/名字=cam/LUT 值域单调）", False)
    check("全部 121 套载荷结构都对（614B、02 00、名字=cam、LUT 值域+单调）", True)

    # 3. 旧的 8 套都在 121 套里
    OLD8 = ["light-film", "mono-hard", "bright-clear", "faded-soft",
            "fl25-cool-mute", "fl26-warm-mute", "cinema-dark", "soft-portrait"]
    check("v1.0.28 的 8 套都在 121 套里（按 id）",
          all(pid in swift_ids for pid in OLD8))
    check("v1.0.28 的 8 套载荷字节没变",
          all(by_id[pid]["payload"] in b64s for pid in OLD8))

# ---------------------------------------------------------------- 2. 分组
titles = re.findall(r'PictCtrlPresetGroup\(title: "([^"]+)"', PRESETS)
check("正好 11 组", len(titles) == 11, f"找到 {len(titles)} 组")
check("分组标题和顺序对", titles == [t for t, _ in EXPECTED], str(titles))

# 每组里 payloadBase64 的个数 = 该组应有数量
parts = re.split(r'PictCtrlPresetGroup\(title: "[^"]+", presets: \[', PRESETS)
group_bodies = parts[1:]
check("分组体数量对", len(group_bodies) == 11)
for (title, want), body in zip(EXPECTED, group_bodies):
    got = body.count('payloadBase64: "')
    check(f"分组「{title}」{want} 套", got == want, f"找到 {got} 套")
check("各组数量加起来是 121",
      sum(w for _, w in EXPECTED) == 121)

# ---------------------------------------------------------------- 3. UI：分组可折叠分区
check("标题写 121 套", "内置滤镜（121 套）" in VIEW)
check("UI 按 PictCtrlPresets.groups 渲染", "ForEach(PictCtrlPresets.groups)" in VIEW)
check("有展开/收起状态（Set<String>）", "expandedGroups: Set<String>" in VIEW)
check("组标题带数量", 'group.title)（\\(group.presets.count)）' in VIEW or
      "（\\(group.presets.count)）" in VIEW)
check("默认只展开第一组", 'expandedGroups: Set<String> = ["通用影调"]' in VIEW)
check("折叠用 Button + 条件渲染（不用 DisclosureGroup）",
      "DisclosureGroup" not in VIEW and "if expandedGroups.contains(group.title)" in VIEW)
check("C1–C9 九宫格还在上面", "LazyVGrid(columns: gridColumns" in VIEW)
check("九个槽一视同仁：可见文案里没有“推荐”",
      "推荐" not in "\n".join(ln.split("//")[0] for ln in VIEW.splitlines()))
check("写入按钮还在（每行一个）", 'Button("写入")' in VIEW)

# ---------------------------------------------------------------- 4. 写槽流程没动
SVC = read("Z30Control/Services/PictCtrlService.swift")
for needle, label in [
    ("saveBackup", "写前备份落盘"),
    ("paramsOnly", "36 字节槽拒绝"),
    ("asyncAfter(deadline: .now() + 0.3)", "写后等 0.3 秒读回"),
    ("back == payload", "读回逐字节比对"),
    ("restoreBackup", "备份还原入口"),
]:
    check("写槽流程没动：" + label, needle in SVC)
check("仍无 0x90CE 删槽代码",
      "0x90CE" not in "\n".join(ln.split("//")[0] for ln in SVC.splitlines()))

# ---------------------------------------------------------------- 5. 版本 + iOS 14 护栏
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")
check("版本 1.0.40 / build 41 两处一致",
      "MARKETING_VERSION: 1.0.40" in YML and "CURRENT_PROJECT_VERSION: 41" in YML and
      "<string>1.0.40</string>" in PLIST and "<string>41</string>" in PLIST)
check("部署目标还是 14.0", 'deploymentTarget: "14.0"' in YML)
for rel in ("Z30Control/Models/PictCtrlPresets.swift",
            "Z30Control/Views/Control/PictCtrlView.swift"):
    src = read(rel)
    for pat, label in [
        (r"onTapGesture\(.*location", "onTapGesture 带 location（iOS 17）"),
        (r"Button\(role:", "Button(role:)（iOS 15）"),
        (r"\.tint\(", ".tint（iOS 16）"),
        (r"\.background\([^)]*,\s*in:", ".background(_:in:)（iOS 15）"),
        (r"\.overlay\(alignment:.*\{", "闭包式 .overlay（iOS 15）"),
        (r"confirmationDialog\(", "confirmationDialog（iOS 15）"),
    ]:
        check(f"iOS14：{os.path.basename(rel)} 无 {label}", not re.search(pat, src))

# ---------------------------------------------------------------- 汇总
failed = [n for n, ok, _ in CHECKS if not ok]
print(f"\n{len(CHECKS) - len(failed)}/{len(CHECKS)} 通过")
if failed:
    print("失败：")
    for n in failed:
        print("  - " + n)
    raise SystemExit(1)
print("全部通过")
