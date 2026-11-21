"""v1.0.24 回归：上面参数全删掉，拍照键居中。

Yuan 2026-11-21 20:43 发截图（红圈）：顶部整块参数还没删掉——
状态条（未连相机/满屏/线连指引）+ 快门/光圈/ISO + 模式/白平衡/
测光/±EV + 收起；底部快门键不在正中央（被右边两个键顶偏）。

修：
1. portraitProHUD 顶部整块全删：topConnectionBanner、
   coreThreeParamsHUD、expandedSpecsStrip、modeDisplayText、
   isShowingExpandedParams、toggleLiveViewForActiveTransport、
   liveViewStreamLabel（帧分辨率仍解析+上报，只是不再显示）。
   顶部留空。未连接空状态（USB-C 直连 / Wi-Fi 热点两个入口）还在，
   线连指引从那里进。
2. 快门居中：底部 deck 改成三组等宽（左 DISP+满屏 / 中快门 /
   右网格+增强），快门落在屏幕正中央。满屏/完整切换从顶部挪到
   左组，功能没删。
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 快门居中镜像：三组等宽 ---
def shutter_center(deck_w, left_w, right_w, shutter_w):
    # 三组各占 deck_w/3；快门在中组内居中；两侧内容必须塞得进各自 1/3
    group = deck_w / 3
    center = group + group / 2
    fits = left_w <= group and right_w <= group
    clearance = (deck_w - shutter_w) / 2  # 快门两侧各剩多少
    return center, fits, clearance


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

    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")

    print("== 源码：顶部参数全删了 ==")
    for gone in ["topConnectionBanner", "coreThreeParamsHUD",
                 "expandedSpecsStrip", "isShowingExpandedParams",
                 "modeDisplayText", "toggleLiveViewForActiveTransport",
                 "liveViewStreamLabel"]:
        check(f"没有 {gone}", gone not in live)
    check("portraitProHUD 里不再提顶部参数",
          "topConnectionBanner" not in live and "coreThreeParamsHUD" not in live)

    print("== 源码：功能没丢 ==")
    check("满屏/完整切换还在（挪到底部）",
          "isFillScreen.toggle()" in live and "满屏" in live and "完整" in live)
    check("未连接空状态还在（两个连接入口）",
          "disconnectedEmptyState" in live and "USB-C 直连" in live)
    check("快门还在", "triggerShutterCapture()" in live)
    check("DISP、网格、增强都在",
          '"DISP"' in live and "isShowingGrid.toggle()" in live
          and "isEnhanceEnabled.toggle()" in live)
    check("三等分线不动", "compositionGridOverlay" in live)

    print("== 源码：快门居中结构 ==")
    check("左组靠左", ".frame(maxWidth: .infinity, alignment: .leading)" in live)
    check("快门组居中", ".frame(maxWidth: .infinity, alignment: .center)" in live)
    check("右组靠右", ".frame(maxWidth: .infinity, alignment: .trailing)" in live)

    print("== 纯逻辑：快门居中 ==")
    # iPhone 16 Pro Max 竖屏：deck 宽 = 390 - 16*2 = 358
    # 左组 DISP+满屏 = 48*2+12 = 108；右组 网格+增强 = 48*2+12 = 108；快门 66
    center, fits, clearance = shutter_center(358, 108, 108, 66)
    check("快门中心 = 屏幕正中央 179", abs(center - 179) < 0.01, f"got={center:.1f}")
    check("两侧内容塞得进各自 1/3", fits)
    check("快门两侧各剩 146pt，大于单侧 108pt", clearance >= 108, f"got={clearance:.0f}")
    # 旧结构复核：6 个子项（DISP/Spacer/快门/Spacer/网格/增强），5 个 20pt 间距
    # 固定宽 48+66+48+48=210，两个 Spacer 各分 (358-210-100)/2=24
    # 快门左缘 = 48+20+24=92，中心 = 92+33=125，确实偏左
    spacer_each = (358 - (48 + 66 + 48 + 48) - 5 * 20) / 2
    old_center = 48 + 20 + spacer_each + 33
    check("旧结构快门确实偏左（中心约 125，不是 179）",
          abs(old_center - 125) < 1 and old_center < 179, f"got={old_center:.0f}")

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
