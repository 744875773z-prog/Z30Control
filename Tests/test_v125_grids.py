"""v1.0.25 回归：网格 8 选 1。

Yuan 2026-11-21 23:38：“都加上去，点击网格，然后可以选择这个几个
网格或者是无网格”。

修：
1. 新建 GridStyle.swift：无网格 + 7 种网格（三等分 / 三等分+对角线 /
   黄金比例 / 黄金螺旋 / 1:1 方形框 / 中心十字 / 对称四分格），选择存
   UserDefaults（z30.gridStyle），默认三等分（和之前默认开着的三等分线一致）。
2. 底栏和左翼的“网格”按钮不再开关，点开取景网格选择器（页内底部面板，
   和参数面板同一个做法；v1.0.26 从 confirmationDialog 换成面板，因为
   confirmationDialog 是 iOS 15 才有的，mini 5 的 14.2 用不了），
   当前选中的带 ✓，点一个立即生效并关闭。
3. compositionGridOverlay 按所选样式画线；无网格时不画。
4. 黄金螺旋按斐波那契方块画（从角上盘进来收在三分点附近），和预览图
   grid-options-preview-v2.png 里的 4 号同一套算法——第一版画错过一次
   （居中的参数螺旋，看着像个圈），这次的弧线圆心取方块内侧角。
"""

import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


PHI = (1 + math.sqrt(5)) / 2


# --- 黄金螺旋的 Python 镜像（和 GridStyle.phiSpiralPoints 同一套算法） ---
def golden_rect(w, h):
    rw, rh = w, w / PHI
    if rh > h:
        rh, rw = h, h * PHI
    return ((w - rw) / 2, (h - rh) / 2, rw, rh)


def phi_spiral_points(w, h, min_side=0.5):
    rx, ry, rw, rh = golden_rect(w, h)
    rect = [rx, ry, rw, rh]
    pts = []
    prev = None
    sweeps = []
    for step in range(40):
        x, y, rw, rh = rect
        if rw <= min_side or rh <= min_side:
            break
        side = min(rw, rh)
        if step % 4 == 0:  # 左：方块在左，弧从左下角进、右上角出
            sq = (x, y, side, side)
            entry = (x, y + side)
        elif step % 4 == 1:  # 上：方块在上，弧从左上角进、右下角出
            sq = (x, y, side, side)
            entry = (x, y)
        elif step % 4 == 2:  # 右：方块在右，弧从右上角进、左下角出
            sq = (x + rw - side, y, side, side)
            entry = (x + rw, y)
        else:  # 下：方块在下，弧从右下角进、左上角出
            sq = (x, y + rh - side, side, side)
            entry = (x + rw, y + rh)
        # 出点是方块里和入口对角的那个角
        ex = (2 * sq[0] + sq[2] - entry[0], 2 * sq[1] + sq[3] - entry[1])
        if prev is None:
            center = (sq[0] + sq[2], sq[1] + sq[3])
        else:
            dx, dy = prev[0] - entry[0], prev[1] - entry[1]
            ln = math.hypot(dx, dy)
            center = (entry[0] + side * dx / ln, entry[1] + side * dy / ln)
        prev = center
        th0 = math.atan2(entry[1] - center[1], entry[0] - center[0])
        th1 = math.atan2(ex[1] - center[1], ex[0] - center[0])
        while th1 < th0:
            th1 += 2 * math.pi
        sweeps.append(th1 - th0)
        for i in range(25):
            th = th0 + (th1 - th0) * i / 24
            pts.append((center[0] + side * math.cos(th),
                        center[1] + side * math.sin(th)))
        if step % 4 == 0:
            rect = [sq[0] + sq[2], y, x + rw - (sq[0] + sq[2]), rh]
        elif step % 4 == 2:
            rect = [x, y, sq[0] - x, rh]
        elif step % 4 == 1:
            rect = [x, sq[1] + sq[3], rw, y + rh - (sq[1] + sq[3])]
        else:
            rect = [x, y, rw, sq[1] - y]
    return pts, sweeps


def polyline_length(pts):
    return sum(math.hypot(pts[i + 1][0] - pts[i][0],
                          pts[i + 1][1] - pts[i][1])
               for i in range(len(pts) - 1))


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

    grid = read("Z30Control/Views/LiveView/GridStyle.swift")
    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")

    print("== 源码：GridStyle.swift ==")
    check("8 个 case 齐全",
          all(f"case {c}" in grid for c in
              ["none", "thirds", "thirdsDiagonals", "phiGrid",
               "phiSpiral", "squareFrame", "centerCross", "symmetricFourths"]))
    check("8 个中文名齐全",
          all(n in grid for n in
              ["无网格", "三等分", "三等分 + 对角线", "黄金比例", "黄金螺旋",
               "1:1 方形框", "中心十字", "对称四分格"]))
    check("默认三等分", 'static let `default`: GridStyle = .thirds' in grid)
    check("存 UserDefaults（z30.gridStyle）",
          'static let defaultsKey = "z30.gridStyle"' in grid
          and "func load()" in grid and "func save()" in grid)
    check("黄金比例线在 0.382 / 0.618",
          "0.618" in grid and "(1 - phi)" in grid)
    check("对称四分格在 1/4、1/2、3/4",
          "0.25, 0.5, 0.75" in grid)
    check("1:1 方形框以短边为边长居中",
          "let side = min(w, h)" in grid)
    check("中心十字有中心圆",
          "addEllipse" in grid)
    check("黄金螺旋按方块剥离法",
          "phiSpiralPoints" in grid and "while thEnd < thStart" in grid)

    print("== 源码：选择器（页内底部面板，iOS 14 也能用）==")
    check("不用 confirmationDialog（iOS 15 才有）",
          ".confirmationDialog(" not in live)
    check("网格选择面板在",
          "gridPickerPanel()" in live and "func gridPickerPanel" in live)
    check("面板在 body 里按开关显示",
          "if showingGridPicker && !isCleanScreen" in live)
    check("8 个选项全列出", "GridStyle.allCases" in live)
    check("当前选中带 ✓", 'Image(systemName: "checkmark")' in live)
    check("选完保存并关闭", "style.save()" in live
          and "showingGridPicker = false" in live)
    check("两处网格按钮都改成打开选择器",
          live.count("showingGridPicker = true") == 2,
          f"got={live.count('showingGridPicker = true')}")
    check("旧的 isShowingGrid 开关没了", "isShowingGrid" not in live)

    print("== 源码：叠加层按所选样式画 ==")
    check("无网格时不画", "gridStyle != .none" in live)
    check("按所选样式画线",
          "GridStyle.path(for: gridStyle, in: geo.size)" in live)

    print("== 纯逻辑：黄金矩形与螺旋 ==")
    # 3:2 取景框 300×200
    rx, ry, rw, rh = golden_rect(300, 200)
    check("黄金矩形长宽比 = φ",
          abs(rw / rh - PHI) < 0.001, f"ratio={rw / rh:.4f}")
    check("黄金矩形居中贴合画面",
          abs(rx) < 0.001 and abs(ry - (200 - rh) / 2) < 0.001)
    pts, sweeps = phi_spiral_points(300, 200)
    check("每段弧都正好扫 90°",
          all(abs(s - math.pi / 2) < 1e-9 for s in sweeps),
          f"sweeps={[round(math.degrees(s)) for s in sweeps]}")
    length = polyline_length(pts)
    check("螺旋总长在合理范围（≈761）",
          700 < length < 900, f"len={length:.1f}")
    check("螺旋全在画面里面",
          all(0 <= px <= 300 and 0 <= py <= 200 for px, py in pts))
    check("螺旋终点收在画面里面",
          0 <= pts[-1][0] <= 300 and 0 <= pts[-1][1] <= 200,
          f"end={pts[-1]}")
    # 螺旋要收进一个固定点（眼）：多剥几段，终点几乎不动
    pole_pts, _ = phi_spiral_points(300, 200, min_side=0.01)
    check("螺旋收进一个固定点（眼）",
          math.hypot(pts[-1][0] - pole_pts[-1][0],
                     pts[-1][1] - pole_pts[-1][1]) < 1.0,
          f"end={pts[-1]}, pole={pole_pts[-1]}")
    # 竖屏螺旋终点收在画面里面
    pts_v, _ = phi_spiral_points(200, 300)
    check("竖屏螺旋终点收在画面里面",
          0 <= pts_v[-1][0] <= 200 and 0 <= pts_v[-1][1] <= 300,
          f"end={pts_v[-1]}")

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
