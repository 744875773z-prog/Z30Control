"""v1.0.21 回归：取景页底栏要留着，只有画面横过来。

之前：RootTabView 横屏下自动隐藏底栏（if !isLandscape），而取景页
v1.0.19 起进页强制横屏——结果一进取景页底栏就没了，只能点返回回
控制页，图库也去不了。用户要的是：底栏依旧存在，只有画面横过来。

修：底栏横屏竖屏都显示（仍在 VStack 流内，页面内容不被盖住）；
横屏时底栏收窄到 420pt 居中（宽屏上三个键拉满屏太散）；取景页
继续强制横屏（不用再开系统方向锁定），离开取景页恢复竖屏。
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 底栏可见性镜像 ---
def tab_bar_visible(is_landscape):
    # v1.0.21 起：横屏竖屏都显示，不再按方向隐藏
    return True


def tab_bar_width(available_width):
    # v1.0.21 起：横屏收窄封顶 420pt 居中；竖屏不受影响
    return min(available_width, 420)


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

    root = read("Z30Control/App/RootTabView.swift")
    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
    lock = read("Z30Control/App/OrientationLock.swift")

    print("== 源码：底栏不再按横屏隐藏 ==")
    check("没有按横屏隐藏底栏的条件", "if !isLandscape" not in root)
    check("底栏直接在 VStack 流里", "pureWhiteBlueTabBar(bottomInset: bottomSafeArea)" in root)
    check("底栏仍在流内（不是 overlay）",
          "底栏仍在 VStack 流内" in root)
    check("三个页签还在（控制/实时取景/图库）",
          "case control" in root and "case liveView" in root and "case gallery" in root)
    check("横屏时底栏收窄到 420pt 居中", ".frame(maxWidth: 420)" in root)

    print("== 源码：取景页还是强制横屏 ==")
    # v1.0.22 起：取景页改锁竖屏（画面在页内转 90°），底栏原位置不动
    check("进取景页锁定竖屏（v1.0.22 起）", "OrientationLock.lockPortrait()" in live)
    check("离页恢复竖屏", "OrientationLock.unlockToPortrait()" in live)
    check("OrientationLock 还在",
          "func lockLandscape()" in lock and "func unlockToPortrait()" in lock)

    print("== 纯逻辑：底栏可见性与宽度 ==")
    check("竖屏显示底栏", tab_bar_visible(False) is True)
    check("横屏也显示底栏", tab_bar_visible(True) is True)
    check("竖屏 390pt 宽不受收窄影响", tab_bar_width(390) == 390)
    check("横屏 844pt 宽封顶 420pt", tab_bar_width(844) == 420)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
