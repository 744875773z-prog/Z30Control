"""v1.0.22 回归：底栏在原来位置不变，只有中间取景的地方默认是横屏。

之前两版都理解偏了：v1.0.19 整页强制横屏（底栏没了），v1.0.21
横屏也显示底栏（底栏收窄居中，位置变了）。用户要的是：整页锁定
竖屏，底栏在原来位置不动，只有中间取景画面在页内转 90°——手机
横过来拿（顶朝左），画面正过来铺满；底栏、参数条、快门键都在
竖屏原位置，不动也不消失。系统方向锁定也不用开了，App 自己锁竖屏。

修：
1. 取景页 onAppear 改 lockPortrait（新增 portraitOnly 开关，
   AppDelegate 返回 .portrait），离页恢复。
2. liveViewImage：帧先按（高×宽）铺满/完整，再顺时针转 90°，
   外框裁回竖屏尺寸。
3. 点按对焦坐标跟着转：屏上点 (nx, ny) 对应帧上 (ny, 1-nx)。
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 点按对焦坐标镜像（画面顺时针转 90°）---
def tap_to_focus(nx, ny):
    # 屏上点 (nx, ny) -> 帧上 (ny, 1-nx)：帧左上角转到了屏右上角
    return (ny, 1 - nx)


# --- 转后铺满/完整尺寸镜像 ---
def rotated_fill(container_w, container_h, img_w, img_h):
    # 帧先按（高×宽）铺满：scale = max(容器宽/帧高，容器高/帧宽）
    # 转 90° 后：沿容器高方向占 帧宽*scale，沿容器宽方向占 帧高*scale，
    # 外框裁回容器尺寸；可见的是帧高方向的中间一段。
    scale = max(container_w / img_h, container_h / img_w)
    along_h = img_w * scale
    along_w = img_h * scale
    visible_fraction = container_w / along_w
    return scale, along_h, along_w, visible_fraction


def rotated_fit(container_w, container_h, img_w, img_h):
    scale = min(container_w / img_h, container_h / img_w)
    # 转 90° 后：宽 = 帧高*scale，高 = 帧宽*scale，居中
    w = img_h * scale
    h = img_w * scale
    top_margin = (container_h - h) / 2
    return w, h, top_margin


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
    lock = read("Z30Control/App/OrientationLock.swift")
    root = read("Z30Control/App/RootTabView.swift")

    print("== 源码：整页锁定竖屏 ==")
    check("取景页进页锁竖屏", "OrientationLock.lockPortrait()" in live)
    check("取景页不再强制横屏", "lockLandscape()" not in live)
    check("lockPortrait 存在", "func lockPortrait()" in lock)
    check("portraitOnly 开关存在", "portraitOnly" in lock)
    check("AppDelegate 竖屏锁返回 .portrait",
          "if OrientationLock.portraitOnly { return .portrait }" in lock)
    check("离页清掉两个开关",
          "unlockToPortrait()" in live and "portraitOnly = false" in lock)

    print("== 源码：只有画面转 90° ==")
    check("满屏和完整都转 90°", live.count("rotationEffect(.degrees(90))") >= 2)
    check("帧先按（高×宽）铺",
          "frame(width: size.height, height: size.width)" in live)
    check("外框裁回竖屏尺寸",
          ".frame(width: size.width, height: size.height)" in live)
    check("点按对焦坐标跟着转",
          "setTouchFocus(x: normY, y: 1 - normX)" in live)
    check("底栏还在（横屏竖屏都显示）", "if !isLandscape" not in root)

    print("== 纯逻辑：点按对焦坐标 ==")
    check("屏左上 (0,0) -> 帧 (0,1)", tap_to_focus(0, 0) == (0, 1))
    check("屏右下 (1,1) -> 帧 (1,0)", tap_to_focus(1, 1) == (1, 0))
    check("中心点不动", tap_to_focus(0.5, 0.5) == (0.5, 0.5))
    check("屏右上 (1,0) -> 帧左上 (0,0)", tap_to_focus(1, 0) == (0, 0))
    check("(0.25,0.75) -> (0.75,0.75)",
          tap_to_focus(0.25, 0.75) == (0.75, 0.75))

    print("== 纯逻辑：转后铺满/完整 ==")
    scale, along_h, along_w, vis = rotated_fill(390, 774, 640, 424)
    check("满屏放大倍数约 1.21", abs(scale - 1.209) < 0.01, f"got={scale:.3f}")
    check("满屏沿竖边铺满 774", abs(along_h - 774) < 1, f"got={along_h:.1f}")
    check("满屏只看到帧高方向中间约 76%",
          abs(vis - 0.76) < 0.01, f"got={vis:.3f}")
    w, h, top = rotated_fit(390, 774, 640, 424)
    check("完整模式整帧可见（竖着看 390×589）",
          abs(w - 390) < 1 and abs(h - 589) < 2, f"got={w:.0f}x{h:.0f}")
    check("完整模式上下各留约 92pt", abs(top - 92) < 2, f"got={top:.1f}")

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
