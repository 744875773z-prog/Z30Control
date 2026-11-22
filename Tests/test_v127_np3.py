"""v1.0.28 回归：导入 .NP3 文件，在图库照片上当滤镜套用。

三件事：
1. 解析器逐字段对答案：用 ssssota deserialize.ts 的同一套偏移/公式
   （Python 移植）解析 Tests/fixtures/Modern-Chrome-Std.NP3，
   与 NP3-Modern-Chrome-Std-parsed.json 逐字段比对。
2. 渲染数学交叉验证：同一套渲染数学（numpy 版）跑在合成色卡上，
   方向要和 2026-11-22 验证的 demo 图一致——绿降、偏暖、对比升
   （demo 实测：绿块 G-R 165.5→111.5，std 73.8→82.0）。
   另外检查 Swift 里的常量和 Python 版一一对应，防止两边写漂了。
3. iOS 14 护栏：新文件里没有 iOS 15+ API；App 包里不内置任何 .NP3
   （版权原因，只做用户自己导入）；版本 1.0.28 / build 29 两处一致；
   滤镜入口从详情页真实可达。
"""

import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))

FIXTURES = os.path.join(ROOT, "Tests", "fixtures")
NP3_PATH = os.path.join(FIXTURES, "Modern-Chrome-Std.NP3")
REF_PATH = os.path.join(FIXTURES, "NP3-Modern-Chrome-Std-parsed.json")


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


# ---------------------------------------------------------------- 解析器
# 与 ssssota offset.ts / deserialize.ts 同一套偏移与公式
O_NAME = 0x18
O_SHARP = 0x52
O_MID = 0xF2
O_CLAR = 0x5C
O_CON = 0x110
O_HI = 0x11A
O_SH = 0x124
O_WL = 0x12E
O_BL = 0x138
O_SAT = 0x142
BLENDER = {"red": 0x14C, "orange": 0x14F, "yellow": 0x152, "green": 0x155,
           "cyan": 0x158, "blue": 0x15B, "purple": 0x15E, "magenta": 0x161}
GRADING = {"highlights": 0x170, "midTone": 0x174, "shadows": 0x178}
O_BLEND = 0x180
O_BAL = 0x182
O_CFA = 0x185
O_CFB = 0x186
O_TCF = 0x187
O_TC_RAW = 0x1CC
O_TC_PTS = 0x194
BASE_LENGTH = 392
TONE_CURVE_EXT_LEN = 586


def parse_np3(buf):
    def s8(b):
        return b - 0x80
    # comment chunk (deserialize.ts readCommentChunk)
    has_flag = buf[O_CFA] == 1 and buf[O_CFB] == 1
    chunk = None
    if has_flag and len(buf) >= BASE_LENGTH + 4 + 4:
        plen = struct.unpack(">I", buf[BASE_LENGTH:BASE_LENGTH + 4])[0]
        if plen != 0 and plen % 2 == 0:
            pend = BASE_LENGTH + 4 + plen
            if pend + 4 <= len(buf):
                payload = buf[BASE_LENGTH + 4:pend]
                term = payload.index(0)
                if all(b == 0 for b in payload[term:]):
                    chunk = (plen, struct.unpack(">I", buf[pend:pend + 4])[0])
    # tone curve start (deserialize.ts getToneCurveStart)
    tc = None
    if chunk is not None:
        if chunk[1] == 2:
            start = BASE_LENGTH + 4 + chunk[0] + 4
            if len(buf) >= start + TONE_CURVE_EXT_LEN:
                tc = start
    else:
        if len(buf) >= BASE_LENGTH + TONE_CURVE_EXT_LEN and buf[O_TCF] == 0x02:
            tc = BASE_LENGTH
    if tc is not None:
        delta = tc - BASE_LENGTH
        raw = [struct.unpack(">H", buf[O_TC_RAW + delta + i * 2:
                                       O_TC_RAW + delta + i * 2 + 2])[0]
               for i in range(257)]
        npts = buf[O_TC_PTS + delta]
        pts = [{"x": buf[O_TC_PTS + delta + 1 + i * 2],
                "y": buf[O_TC_PTS + delta + 2 + i * 2]} for i in range(npts)]
        tone_curve = {"raw": raw, "points": pts}
    else:
        tone_curve = None
    has_tc = tone_curve is not None
    payload = buf[BASE_LENGTH + 4:BASE_LENGTH + 4 + chunk[0]] if chunk else b""
    comment = payload[:payload.index(0)].decode("utf-8") if chunk else None
    got = {
        "name": buf[O_NAME:O_NAME + 19].split(b"\x00")[0].decode(),
        "sharpning": (buf[O_SHARP] - 0x80) / 4,
        "midRangeSharpning": (buf[O_MID] - 0x80) / 4,
        "clarity": (buf[O_CLAR] - 0x80) / 4,
        "contrast": 0 if has_tc else s8(buf[O_CON]),
        "highlights": 0 if has_tc else s8(buf[O_HI]),
        "shadows": 0 if has_tc else s8(buf[O_SH]),
        "whiteLevel": 0 if has_tc else s8(buf[O_WL]),
        "blackLevel": 0 if has_tc else s8(buf[O_BL]),
        "saturation": s8(buf[O_SAT]),
        "colorBlender": {k: {"hue": s8(buf[o]), "chroma": s8(buf[o + 1]),
                             "brightness": s8(buf[o + 2])} for k, o in BLENDER.items()},
        "colorGrading": {k: {"hue": ((buf[o] & 0x0F) << 8) + buf[o + 1],
                             "chroma": s8(buf[o + 2]), "brightness": s8(buf[o + 3])}
                         for k, o in GRADING.items()},
        "comment": comment,
    }
    got["colorGrading"]["blending"] = s8(buf[O_BLEND])
    got["colorGrading"]["balance"] = s8(buf[O_BAL])
    got["toneCurve"] = tone_curve
    return got


# ---------------------------------------------------------------- 渲染数学
# 与 Swift NP3ColorMath 同一套常量（见 NP3LUTRenderer.swift）
LEVEL_SCALE = 0.001
BLENDER_HALF_WIDTH_DEG = 45.0
BLENDER_BRIGHTNESS_SCALE = 0.25
GRADING_SAT_ADD = 0.3
GRADING_BRIGHTNESS_SCALE = 0.25
BASE_HUES = [0, 30, 60, 120, 180, 240, 270, 300]


def render_chart(chart, c):
    import numpy as np

    def smoothstep(a, b, x):
        t = np.clip((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3 - 2 * t)

    def rgb_to_hsl(rgb):
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        mx = rgb.max(axis=-1)
        mn = rgb.min(axis=-1)
        l = (mx + mn) / 2
        d = mx - mn
        s = np.where(d == 0, 0.0, np.where(l <= 0.5, d / np.maximum(mx + mn, 1e-9),
                                          d / np.maximum(2 - mx - mn, 1e-9)))
        h = np.zeros_like(l)
        mask = d != 0
        hh = np.zeros_like(mx[mask])
        mm = mx[mask]
        dd = d[mask]
        rr, gg, bb = r[mask], g[mask], b[mask]
        sel = mm == rr
        hh[sel] = ((gg[sel] - bb[sel]) / np.maximum(dd[sel], 1e-9)) % 6
        sel = mm == gg
        hh[sel] = (bb[sel] - rr[sel]) / np.maximum(dd[sel], 1e-9) + 2
        sel = mm == bb
        hh[sel] = (rr[sel] - gg[sel]) / np.maximum(dd[sel], 1e-9) + 4
        h[mask] = (hh * 60) % 360
        return np.stack([h, s, l], axis=-1)

    def hsl_to_rgb(hsl):
        h, s, l = hsl[..., 0] / 60.0, hsl[..., 1], hsl[..., 2]
        cc = (1 - np.abs(2 * l - 1)) * s
        x = cc * (1 - np.abs(h % 2 - 1))
        m = l - cc / 2
        z = np.zeros_like(h)
        rgb = np.zeros(hsl.shape)
        seg = (h % 6).astype(int)
        for i, v in enumerate([(cc, x, z), (x, cc, z), (z, cc, x),
                               (z, x, cc), (x, z, cc), (cc, z, x)]):
            sel = seg == i
            rgb[sel] = np.stack([v[0][sel], v[1][sel], v[2][sel]], axis=-1)
        return rgb + m[..., None]

    def ang_diff(a, b):
        return (b - a + 180) % 360 - 180

    out = chart.copy()
    tc = c.get("toneCurve")
    if tc is not None:
        raw = np.asarray(tc["raw"], dtype=float) / 32767.0
        idx = np.clip(out * 256.0, 0, 256)
        lo = np.clip(np.floor(idx).astype(int), 0, 256)
        hi = np.clip(lo + 1, 0, 256)
        f = idx - lo
        out = raw[lo] * (1 - f)[..., None] + raw[hi] * f[..., None]
    else:
        bp = max(0.0, -c["blackLevel"] * LEVEL_SCALE)
        wp = 1.0 - c["whiteLevel"] * LEVEL_SCALE
        out = np.clip((out - bp) / max(wp - bp, 1e-6), 0, 1)
        out = np.clip(0.5 + (out - 0.5) * (1 + c["contrast"] / 100.0), 0, 1)
        hw = smoothstep(0.5, 1.0, out)
        out = np.clip(out + (c["highlights"] / 100.0) * hw * (1 - out), 0, 1)
        sw = 1 - smoothstep(0.0, 0.5, out)
        out = np.clip(out + (c["shadows"] / 100.0) * sw * out, 0, 1)
    luma = out @ np.array([0.2126, 0.7152, 0.0722])
    out = np.clip(luma[..., None] + (out - luma[..., None]) * (1 + c["saturation"] / 100.0), 0, 1)
    hsl = rgb_to_hsl(out)
    H, S, L = hsl[..., 0], hsl[..., 1], hsl[..., 2]
    keys = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta"]
    hue_shift = np.zeros_like(H)
    chroma_sum = np.zeros_like(H)
    bright_sum = np.zeros_like(H)
    for k, center in zip(keys, BASE_HUES):
        v = c["colorBlender"][k]
        d = np.abs(ang_diff(center, H))
        w = np.clip(1 - d / BLENDER_HALF_WIDTH_DEG, 0, 1)
        hue_shift += w * v["hue"]
        chroma_sum += w * v["chroma"]
        bright_sum += w * v["brightness"]
    H = (H + hue_shift) % 360
    S = np.clip(S * (1 + chroma_sum / 100.0), 0, 1)
    L = np.clip(L + bright_sum / 100.0 * BLENDER_BRIGHTNESS_SCALE, 0, 1)
    out = hsl_to_rgb(np.stack([H, S, L], axis=-1))
    hsl = rgb_to_hsl(out)
    H, S, L = hsl[..., 0], hsl[..., 1], hsl[..., 2]
    g = c["colorGrading"]
    lo = 0.5 - 0.2 * (0.5 + g["blending"] / 100.0)
    hi = 0.5 + 0.2 * (0.5 + g["blending"] / 100.0)
    mid = 0.5 + g["balance"] / 100.0 * 0.2
    w_sh = 1 - smoothstep(lo, mid, L)
    w_hi = smoothstep(mid, hi, L)
    w_mid = np.clip(1 - w_sh - w_hi, 0, 1)
    for w, z in [(w_sh, g["shadows"]), (w_mid, g["midTone"]), (w_hi, g["highlights"])]:
        if z["chroma"] == 0 and z["brightness"] == 0:
            continue
        H = H + w * (z["chroma"] / 100.0) * ang_diff(H, z["hue"])
        S = np.clip(S + w * (z["chroma"] / 100.0) * GRADING_SAT_ADD * (1 - S), 0, 1)
        L = np.clip(L + w * (z["brightness"] / 100.0) * GRADING_BRIGHTNESS_SCALE, 0, 1)
    return np.clip(hsl_to_rgb(np.stack([H % 360, S, L], axis=-1)), 0, 1)


def make_chart():
    import numpy as np
    W, Hh = 640, 460
    img = np.zeros((Hh, W, 3))
    xs = np.linspace(0, 1, W)
    top = np.zeros((int(Hh * 0.55), W, 3))
    top[..., 0] = 0.55 + 0.25 * xs
    top[..., 1] = 0.70 + 0.05 * xs
    top[..., 2] = 0.90
    img[:top.shape[0]] = top
    patches = [(1, 0, 0), (1, 0.5, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1),
               (0.6, 0, 1), (1, 0, 1), (0.85, 0.75, 0.65), (0.5, 0.35, 0.25),
               (0.2, 0.5, 0.3), (0.85, 0.65, 0.3)]
    y0, y1 = int(Hh * 0.60), int(Hh * 0.80)
    for i, col in enumerate(patches):
        img[y0:y1, int(i * W / 12):int((i + 1) * W / 12)] = col
    y0, y1 = int(Hh * 0.85), Hh
    for i in range(12):
        v = i / 11.0
        img[y0:y1, int(i * W / 12):int((i + 1) * W / 12)] = (v, v, v)
    return img


def run():
    passed = failed = 0

    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name} {detail}")

    print("== 解析器逐字段对答案（Modern Chrome Std）==")
    buf = open(NP3_PATH, "rb").read()
    ref = json.load(open(REF_PATH))
    check("文件 426 字节，头是 NCP",
          len(buf) == 426 and buf[:3] == b"NCP")
    got = parse_np3(buf)
    mismatches = []
    for k in ["name", "sharpning", "midRangeSharpning", "clarity", "contrast",
              "highlights", "shadows", "whiteLevel", "blackLevel", "saturation",
              "comment"]:
        if got[k] != ref[k]:
            mismatches.append((k, got[k], ref[k]))
    for c in BLENDER:
        for f in ["hue", "chroma", "brightness"]:
            if got["colorBlender"][c][f] != ref["colorBlender"][c][f]:
                mismatches.append((f"blender.{c}.{f}", got["colorBlender"][c][f],
                                   ref["colorBlender"][c][f]))
    for z in ["highlights", "midTone", "shadows"]:
        for f in ["hue", "chroma", "brightness"]:
            if got["colorGrading"][z][f] != ref["colorGrading"][z][f]:
                mismatches.append((f"grading.{z}.{f}", got["colorGrading"][z][f],
                                   ref["colorGrading"][z][f]))
    for f in ["blending", "balance"]:
        if got["colorGrading"][f] != ref["colorGrading"][f]:
            mismatches.append((f"grading.{f}", got["colorGrading"][f],
                               ref["colorGrading"][f]))
    check("全部参数字段与标准答案一致", not mismatches, str(mismatches[:5]))
    check("这个配方没有自定义色调曲线（toneCurve 为空）",
          got["toneCurve"] is None and "toneCurve" not in ref)
    check("关键参数：绿色 chroma -45、中间调 hue 42、对比 40",
          got["colorBlender"]["green"]["chroma"] == -45
          and got["colorGrading"]["midTone"]["hue"] == 42
          and got["contrast"] == 40)

    print("== 渲染数学交叉验证（合成色卡，方向与 demo 图一致）==")
    import numpy as np
    chart = make_chart()
    after = render_chart(chart, ref)
    W = chart.shape[1]
    g0 = chart[int(460 * 0.60):int(460 * 0.80), int(3 * W / 12):int(4 * W / 12)]
    g1 = after[int(460 * 0.60):int(460 * 0.80), int(3 * W / 12):int(4 * W / 12)]
    gr_before = float((g0[..., 1] - g0[..., 0]).mean() * 255)
    gr_after = float((g1[..., 1] - g1[..., 0]).mean() * 255)
    check("绿块 G-R 大幅下降（demo：165.5→111.5）",
          gr_after < gr_before - 50, f"{gr_before:.1f}→{gr_after:.1f}")
    check("整体反差上升（demo std：73.8→82.0）",
          float(after.std()) > float(chart.std()),
          f"{float(chart.std() * 255):.1f}→{float(after.std() * 255):.1f}")
    m0 = chart[int(460 * 0.85):460, int(5 * W / 12):int(6 * W / 12)]
    m1 = after[int(460 * 0.85):460, int(5 * W / 12):int(6 * W / 12)]
    rb0 = float((m0[..., 0] - m0[..., 2]).mean() * 255)
    rb1 = float((m1[..., 0] - m1[..., 2]).mean() * 255)
    check("中间灰偏暖（R-B 上升）", rb1 > rb0, f"{rb0:.1f}→{rb1:.1f}")
    b0 = chart[int(460 * 0.60):int(460 * 0.80), int(5 * W / 12):int(6 * W / 12)]
    b1 = after[int(460 * 0.60):int(460 * 0.80), int(5 * W / 12):int(6 * W / 12)]
    check("蓝块色相 -32：向青偏移（B 通道仍主导、G 上升）",
          float(b1[..., 1].mean()) > float(b0[..., 1].mean())
          and float(b1[..., 2].mean()) > float(b1[..., 0].mean()))

    print("== Swift 与 Python 渲染常量一一对应 ==")
    renderer = read("Z30Control/Services/NP3LUTRenderer.swift")
    for const in ["levelScale = 0.001", "blenderHalfWidthDeg = 45.0",
                  "blenderBrightnessScale = 0.25", "gradingSatAdd = 0.3",
                  "gradingBrightnessScale = 0.25",
                  "[0, 30, 60, 120, 180, 240, 270, 300]",
                  "32767", "cubeDimension = 32"]:
        check(f"Swift 里有 {const}", const in renderer)
    check("色调曲线用 257 点原始表逐通道", "tc.raw[lo]" in renderer and "tc.raw[hi]" in renderer)
    check("锐化/清晰度注明了这次不渲染",
          "锐化" in renderer and "不渲染" in renderer)

    print("== Swift 解析器偏移与原库一致 ==")
    parser = read("Z30Control/Models/NP3PictureControl.swift")
    for off in ["0x18", "0x52", "0xf2", "0x5c", "0x110", "0x11a", "0x124",
                "0x12e", "0x138", "0x142", "0x14c", "0x14f", "0x152", "0x155",
                "0x158", "0x15b", "0x15e", "0x161", "0x170", "0x174", "0x178",
                "0x180", "0x182", "0x185", "0x186", "0x187", "0x1cc", "0x194"]:
        check(f"偏移 {off} 在", off in parser)
    check("校验文件头 NCP（0x4E 0x43 0x50）",
          "0x4e" in parser and "0x43" in parser and "0x50" in parser)
    check("有色调曲线时对比等 5 项按原库返回 0",
          "hasTC ? 0 : s8(offsetContrast)" in parser)

    print("== 版本 1.0.28 / build 29 ==")
    yml = read("project.yml")
    plist = read("Z30Control/Info.plist")
    check("两处版本一致",
          "MARKETING_VERSION: 1.0.28" in yml
          and "CURRENT_PROJECT_VERSION: 29" in yml
          and "<string>1.0.28</string>" in plist
          and "<string>29</string>" in plist)
    check("部署目标还是 14.0", 'deploymentTarget: "14.0"' in yml)

    print("== 入口真实可达 + 保存路径复用 ==")
    gallery = read("Z30Control/Views/Gallery/CameraGalleryView.swift")
    check("详情页有“滤镜”按钮", "滤镜（导入 .NP3 配方）" in gallery)
    check("按钮点开 NP3FilterView（带原图）",
          "NP3FilterView(item: item, originalImage: sourceImage)" in gallery)
    check("按钮只在原图下得来时可点", ".disabled(fullImage == nil)" in gallery)
    media = read("Z30Control/Services/MediaSyncService.swift")
    check("保存滤镜版复用相册写入路径",
          "saveFilteredImageData" in media
          and "saveDataToPhotosOrFiles(data, filename: filename" in media)
    view = read("Z30Control/Views/Gallery/NP3FilterView.swift")
    check("滤镜页有导入/保存/原图三项",
          "导入 .NP3 文件" in view and "保存滤镜版" in view
          and "原图（不套滤镜）" in view)
    check("解析失败给人话提示", "导入失败" in view and "localizedDescription" in view)
    check("配方可删除", ".onDelete(perform: deleteRecipes)" in view)

    print("== 不内置配方 + iOS 14 护栏 ==")
    np3_in_app = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, "Z30Control")):
        for name in files:
            if name.lower().endswith(".np3"):
                np3_in_app.append(name)
    check("App 包里没有任何 .NP3 文件", not np3_in_app, str(np3_in_app))
    new_files = [
        read("Z30Control/Models/NP3PictureControl.swift"),
        read("Z30Control/Services/NP3LUTRenderer.swift"),
        read("Z30Control/Services/NP3RecipeStore.swift"),
        read("Z30Control/Views/Gallery/NP3FilterView.swift"),
    ]
    new_src = "\n".join(new_files)
    check("新文件里没有 confirmationDialog", ".confirmationDialog(" not in new_src)
    for banned in ["PhotosPicker", "ShareLink", "presentationDetents",
                   "AsyncImage", "refreshable", "searchable", "swipeActions",
                   "scrollContentBackground", ".formatted(", "AttributedString",
                   "AnyLayout", "ViewThatFits", "GridRow", "LabeledContent",
                   "Gauge(", ".tint(", "role: .cancel", "role: .destructive",
                   "in: RoundedRectangle", "in: Capsule",
                   ".overlay(alignment:", ".fileImporter(",
                   ".alert(\"", "NavigationStack", "coordinateSpace"]:
        check(f"没有 {banned}", banned not in new_src)
    check("文件选择走 UIDocumentPickerViewController（iOS 14 就有）",
          "UIDocumentPickerViewController" in new_src
          and "forOpeningContentTypes" in new_src)
    check("只接受 .np3 后缀", 'UTType(filenameExtension: "np3")' in new_src)
    check("老式 Alert（iOS 14 写法）", "Alert(" in new_src)
    check("3D LUT 用 CIColorCube（iOS 5 就有）",
          '"CIColorCube"' in renderer and "inputCubeDimension" in renderer)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
