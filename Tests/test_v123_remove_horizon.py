"""v1.0.23 回归：去掉取景页的绿色横线+圆圈（电子水平仪）。

Yuan 2026-11-21 20:29 发截图：第一张上电子水平仪那条绿色横线+
中间圆圈压在“未检测到相机信号”文字上，要去掉。第二张展示的是
中间这块区域——他准备以后在这里加滤镜，滤镜要分类，所以现在
不搞，只先把水平仪去掉，位置留空。

修：删掉 cameraViewport 里 horizonLevelIndicator 的调用和它的定义。
三等分线（compositionGridOverlay）不动，点按对焦绿框不动。
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


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

    print("== 源码：水平仪已去掉 ==")
    check("没有 horizonLevelIndicator 的调用", "horizonLevelIndicator" not in live)
    check("没有水平仪的定义", "private var horizonLevelIndicator" not in live)
    check("没有绿色横线+圆圈的残留",
          "Circle().stroke(NikonTheme.readyGreen" not in live)

    print("== 源码：其他的不动 ==")
    check("三等分线还在", "compositionGridOverlay" in live)
    check("三等分线还按开关显示",
          "if isShowingGrid && !isCleanScreen" in live)
    check("点按对焦绿框还在", "touchFocusPosition" in live)
    check("取景画面还在（转 90°）", "rotationEffect(.degrees(90))" in live)
    check("取景页还是锁竖屏", "OrientationLock.lockPortrait()" in live)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
