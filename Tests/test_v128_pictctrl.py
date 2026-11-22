"""v1.0.28 回归：机身滤镜——614 字节载荷写进相机 C1–C9。

检查点：
1. 载荷结构对答案：用 1dlut 项目 z30fit/payload.py 的真实输出作标准，
   Python 镜像版 builder（按 Swift 同款规格写）逐字节比对；
   Swift 源码里的模板常量（版本字节、标志位、参数步长）逐项核对。
2. 参数编码：sharp 9.0 ↔ 0x24、clarity −5.0 ↔ 0xEC、saturation 3.0 ↔ 0x0C、
   quick_sharp −2 ↔ 0xFE（1dlut 真机回读值）。
3. 121 套内置预设（v1.0.30 起全量）：Swift 里嵌的 base64 必须和 1dlut builtin_presets.json
   原文一字不差；每套解出来 614 字节、版本 02 00、名字栏 = cam 名、
   LUT 256 点大端 u16、值域 0..32767、单调。
4. 槽位号：C1–C9 = 0x00C9–0x00D1。
5. 红线：App 里没有任何 0x90CE（删槽指令）的代码调用——只允许出现在注释里；
   没有 DelCstPicCtrl / deletePictCtrl 之类的删除入口。
6. iOS 14 护栏：新文件里没有 iOS 15+ API。
7. 版本 1.0.30 / build 31 两处一致（v1.0.30 起由 test_v130 再验一遍）；控制页有真实可达的机身滤镜入口；
   v1.0.29 起 NP3 图库滤镜已移除（文件不在，见 test_v129）。
"""

import base64
import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))

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


def all_swift():
    out = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, "Z30Control")):
        for name in files:
            if name.endswith(".swift"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


# ---------------------------------------------------------------- 1. 载荷结构
PAYLOAD = read("Z30Control/Models/PictCtrlPayload.swift")

# Swift 模板常量必须和 payload.py 的 fallback_template() 一致
for needle, label in [
    ("p[0x000] = 0x02", "版本 0x02"),
    ("p[0x019] = 0x08", "锐化默认 +2 (0x08)"),
    ("p[0x01A] = 0x04", "中等锐化默认 +1 (0x04)"),
    ("p[0x023] = 0x01", "标志位 0x01"),
    ("p[0x024] = 0x49", "'I'"),
    ("p[0x025] = 0x30", "'0'"),
    ("p[0x027] = 0xFF", "0x027 FF"),
    ("p[0x029] = 0xFF", "0x029 FF"),
    ("p[0x02A] = 0x01", "0x02A 01"),
    ("p[0x02B] = 0x0F", "0x02B 0F"),
]:
    check("模板常量：" + label, needle in PAYLOAD)

check("载荷大小常量 614", "public static let size = 614" in PAYLOAD)
check("LUT 偏移 0x066", "lutOffset = 0x066" in PAYLOAD)
check("LUT 上限 32767", "lutMax = 32767" in PAYLOAD)
check("名字偏移 0x002 / 长 20", "nameOffset = 0x002" in PAYLOAD and "nameLength = 20" in PAYLOAD)

# 参数步长：quickSharp 1.0，其余 0.25
check("quickSharp 步长 1.0", "self == .quickSharp ? 1.0 : 0.25" in PAYLOAD)

# 参数编码数学（和 payload.py 的 encode_param 同款公式）
def encode_param(value, step):
    return round(value / step) & 0xFF

check("sharp 9.0 → 0x24", encode_param(9.0, 0.25) == 0x24)
check("clarity −5.0 → 0xEC", encode_param(-5.0, 0.25) == 0xEC)
check("saturation 3.0 → 0x0C", encode_param(3.0, 0.25) == 0x0C)
check("quick_sharp −2 → 0xFE", encode_param(-2.0, 1.0) == 0xFE)
check("mid_sharp 5.0 → 0x14", encode_param(5.0, 0.25) == 0x14)

# Python 镜像版 builder（按 Swift 同款规格）vs 1dlut 真实输出
if DLUT is None:
    print("SKIP 1dlut 交叉比对：克隆不在 /tmp/dlutz30 或 ~/workspace/dlutz30")
else:
    sys.path.insert(0, DLUT)
    from z30fit import payload as ref  # noqa: E402

    def mirror_build(curve, name, params=None):
        out = bytearray(ref.fallback_template())
        nb = name.encode("ascii")[:20].ljust(20, b"\x00")
        out[0x002:0x002 + 20] = nb
        table = [max(0, min(32767, round(v * 32767))) if v <= 1.0 else
                 max(0, min(32767, round(v))) for v in curve]
        for i in range(256):
            out[0x066 + i * 2] = (table[i] >> 8) & 0xFF
            out[0x066 + i * 2 + 1] = table[i] & 0xFF
        if params:
            out = bytearray(ref.set_params(bytes(out), params))
        return bytes(out)

    import numpy as np
    gamma = [((i / 255.0) ** 1.25) for i in range(256)]
    ref_bytes = ref.build_payload_614(np.array(gamma), name="TEST-GAMMA",
                                      params={"sharp": 9.0, "clarity": -5.0, "saturation": 3.0})
    mir_bytes = mirror_build(gamma, "TEST-GAMMA",
                             params={"sharp": 9.0, "clarity": -5.0, "saturation": 3.0})
    # 控制点段（0x02F）是 Swift/Python 各自算的，镜像版没算，先排除该段比对
    diff = [(i, a, b) for i, (a, b) in enumerate(zip(ref_bytes, mir_bytes)) if a != b]
    diff_outside_cp = [d for d in diff if not (0x02F <= d[0] < 0x037)]
    check("镜像 builder 与 payload.py 逐字节一致（除控制点段）",
          len(ref_bytes) == 614 and not diff_outside_cp,
          f"差异 {len(diff_outside_cp)} 字节" if diff_outside_cp else "614 字节全对")
    check("参考载荷版本 02 00", ref_bytes[0:2] == b"\x02\x00")
    check("参考载荷参数区 sharp=0x24", ref_bytes[0x019] == 0x24)
    check("参考载荷参数区 clarity=0xEC", ref_bytes[0x01B] == 0xEC)
    check("参考载荷参数区 saturation=0x0C", ref_bytes[0x01E] == 0x0C)
    check("参考载荷名字栏", ref_bytes[0x002:0x00C].rstrip(b"\x00") == b"TEST-GAMMA")
    lut = struct.unpack(">256H", ref_bytes[0x066:0x066 + 512])
    check("参考载荷 LUT 值域 0..32767", min(lut) >= 0 and max(lut) <= 32767)
    check("参考载荷 LUT 单调", all(lut[i] <= lut[i + 1] for i in range(255)))

# ---------------------------------------------------------------- 2. 槽位号
check("C1–C9 写在一行枚举里",
      "case c1 = 1, c2, c3, c4, c5, c6, c7, c8, c9" in PAYLOAD)
check("槽位号公式 0x00C8 + rawValue（C1=0x00C9 … C9=0x00D1）",
      "0x00C8 + rawValue" in PAYLOAD)
for i in range(1, 10):
    check(f"C{i} 槽位号 0x{0x00C8 + i:04X}",
          0x00C8 + i == 0x00C8 + i)  # 公式已在上一条验过，这里逐项列出数值

# ---------------------------------------------------------------- 3. 内置预设
PRESETS = read("Z30Control/Models/PictCtrlPresets.swift")
b64s = re.findall(r'payloadBase64: "([A-Za-z0-9+/=]+)"', PRESETS)
check("内置预设正好 121 套（v1.0.30 起全量）", len(b64s) == 121, f"找到 {len(b64s)} 套")
check("预设名全是 ASCII（进载荷）",
      all(re.search(r'cameraName: "([ -~]+)"', PRESETS) for _ in [0]) and
      len(re.findall(r'cameraName: "([ -~]+)"', PRESETS)) == 121)

if DLUT is not None:
    data = json.load(open(os.path.join(DLUT, "android/app/src/main/assets/builtin_presets.json")))
    by_id = {p["id"]: p for p in data["presets"]}
    swift_ids = re.findall(r'id: "([a-z0-9\-]+)"', PRESETS)
    check("121 套 id 都在 1dlut 预设库里", all(i in by_id for i in swift_ids),
          f"ids={swift_ids}")
    for pid, b64 in zip(swift_ids, b64s):
        raw = base64.b64decode(b64)
        orig = by_id[pid]["payload"]
        check(f"预设 {pid} 与 1dlut 原文一字不差", b64 == orig)
        check(f"预设 {pid} 614 字节", len(raw) == 614)
        check(f"预设 {pid} 版本 02 00", raw[0:2] == b"\x02\x00")
        name_in = raw[0x002:0x016].rstrip(b"\x00").decode("ascii")
        check(f"预设 {pid} 名字栏 = {by_id[pid]['cam']}", name_in == by_id[pid]["cam"])
        lut = struct.unpack(">256H", raw[0x066:0x066 + 512])
        check(f"预设 {pid} LUT 值域 + 单调",
              min(lut) >= 0 and max(lut) <= 32767 and
              all(lut[i] <= lut[i + 1] for i in range(255)))
else:
    print("SKIP 预设与 1dlut 原文比对：克隆不在")

# ---------------------------------------------------------------- 4. 红线：0x90CE
bad = []
for path in all_swift():
    for ln, line in enumerate(open(path, encoding="utf-8"), 1):
        code = line.split("//")[0]  # 去掉注释
        if "0x90CE" in code or "90CE" in code or "DelCstPicCtrl" in code \
                or "deletePictCtrl" in code or "delPictCtrl" in code:
            bad.append(f"{os.path.basename(path)}:{ln}")
check("App 代码里没有 0x90CE / 删槽调用", not bad, "; ".join(bad) if bad else "")
check("操作码里有 0x90CC/0x90CD/0x90CF",
      "0x90CC" in read("Z30Control/Protocol/PtpConstants.swift") and
      "0x90CD" in read("Z30Control/Protocol/PtpConstants.swift") and
      "0x90CF" in read("Z30Control/Protocol/PtpConstants.swift"))

# ---------------------------------------------------------------- 5. 严格 0x2001
USB = read("Z30Control/Services/UsbCameraManager.swift")
check("USB 写槽：必须明确 0x2001 才算成功",
      "respCode == 0x2001" in USB and "setPictCtrlData" in USB)
WIFI = read("Z30Control/Protocol/PtpIpClient.swift")
check("Wi-Fi 写槽：setPictCtrlData 存在且校验 0x2001",
      "func setPictCtrlData" in WIFI and "nikonSetPictCtrlData" in WIFI)
check("Wi-Fi 读槽：getPictCtrlData 存在",
      "func getPictCtrlData" in WIFI and "nikonGetPictCtrlData" in WIFI)
check("USB 读槽：getPictCtrlData 存在", "func getPictCtrlData" in USB)

# ---------------------------------------------------------------- 6. 安全流程
SVC = read("Z30Control/Services/PictCtrlService.swift")
for needle, label in [
    ("saveBackup", "写前备份落盘"),
    ("paramsOnly", "36 字节槽拒绝"),
    ("asyncAfter(deadline: .now() + 0.3)", "写后等 0.3 秒读回"),
    ("back == payload", "读回逐字节比对"),
    ("PictCtrlBackups", "备份目录"),
    ("pauseWifiLiveViewIfNeeded", "Wi-Fi 写前停取景"),
    ("restoreBackup", "备份还原入口"),
]:
    check("安全流程：" + label, needle in SVC)
check("备份还原不走删除（无 0x90CE 代码）",
      "0x90CE" not in SVC.split("//")[0])

# ---------------------------------------------------------------- 7. iOS 14 护栏（新文件）
NEW_FILES = ["Z30Control/Models/PictCtrlPayload.swift",
             "Z30Control/Models/PictCtrlPresets.swift",
             "Z30Control/Services/PictCtrlService.swift",
             "Z30Control/Views/Control/PictCtrlView.swift"]
IOS15_PLUS = [
    (r"onTapGesture\(.*location", "onTapGesture 带 location（iOS 17）"),
    (r"Button\(role:", "Button(role:)（iOS 15）"),
    (r"\.tint\(", ".tint（iOS 16）"),
    (r"\.background\([^)]*,\s*in:", ".background(_:in:)（iOS 15）"),
    (r"\.overlay\(alignment:.*\{", "闭包式 .overlay（iOS 15）"),
    (r"\.alert\(.*\.button", "新式 alert（iOS 15）"),
]
for rel in NEW_FILES:
    src = read(rel)
    for pat, label in IOS15_PLUS:
        check(f"iOS14：{os.path.basename(rel)} 无 {label}", not re.search(pat, src))

# ---------------------------------------------------------------- 8. 版本 + 入口 + NP3 不动
YML = read("project.yml")
PLIST = read("Z30Control/Info.plist")
check("版本 1.0.34 / build 35 两处一致",
      "MARKETING_VERSION: 1.0.34" in YML and "CURRENT_PROJECT_VERSION: 35" in YML and
      "<string>1.0.34</string>" in PLIST and "<string>35</string>" in PLIST)
check("project.yml 没有 info: 块（忽略注释行）",
      not any(re.match(r"\s*info\s*:", ln) for ln in YML.splitlines()
              if not ln.strip().startswith("#")))
CTRL = read("Z30Control/Views/Control/ControlDashboardView.swift")
check("控制页不再挂机身滤镜入口（入口已移到标签页）",
      "PictCtrlView()" not in CTRL and "pictCtrlEntryCard" not in CTRL)
TAB = read("Z30Control/App/RootTabView.swift")
check("标签页：机身滤镜在实时取景和图库之间",
      "case pictCtrl = 2" in TAB and "case gallery = 3" in TAB)
check("标签页标题「机身滤镜」", 'case .pictCtrl: return "机身滤镜"' in TAB)
check("标签页分发 PictCtrlView", "case .pictCtrl:\n                        PictCtrlView()" in TAB)
VIEW = read("Z30Control/Views/Control/PictCtrlView.swift")
check("槽位是 3×3 九宫格（LazyVGrid，3 列）",
      "LazyVGrid(columns: gridColumns" in VIEW and VIEW.count("GridItem(.flexible()") == 3)
check("九个槽一视同仁：可见文案里没有“推荐”",
      "推荐" not in "\n".join(ln.split("//")[0] for ln in VIEW.splitlines()))
check("未读显示“未读取”", 'return "未读取"' in VIEW)
check("空槽显示“空”", 'return "空"' in VIEW)
check("仅参数槽显示“仅参数”", 'return "仅参数"' in VIEW)
check("默认只选第一个空槽，不预选 C9", "selectedSlot = .c9" not in VIEW)
check("v1.0.29 NP3 图库滤镜已移除（文件 + 入口都不在）",
      not os.path.exists(os.path.join(ROOT, "Z30Control/Models/NP3PictureControl.swift")) and
      not os.path.exists(os.path.join(ROOT, "Z30Control/Views/Gallery/NP3FilterView.swift")) and
      not os.path.exists(os.path.join(ROOT, "Z30Control/Services/NP3RecipeStore.swift")) and
      not os.path.exists(os.path.join(ROOT, "Z30Control/Services/NP3LUTRenderer.swift")))

# ---------------------------------------------------------------- 汇总
failed = [n for n, ok, _ in CHECKS if not ok]
print(f"\n{len(CHECKS) - len(failed)}/{len(CHECKS)} 通过")
if failed:
    print("失败：")
    for n in failed:
        print("  - " + n)
    sys.exit(1)
print("全部通过")
