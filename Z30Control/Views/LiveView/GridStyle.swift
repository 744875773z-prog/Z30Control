import SwiftUI

// MARK: - 取景网格样式（v1.0.25）
// Yuan 2026-11-21 23:38：网格就这一种太单一了，都加上去，点网格可以
// 选择这几个网格或者是无网格。8 个选项：无网格 + 7 种网格。
enum GridStyle: String, CaseIterable {
    case none
    case thirds
    case thirdsDiagonals
    case phiGrid
    case phiSpiral
    case squareFrame
    case centerCross
    case symmetricFourths

    var displayName: String {
        switch self {
        case .none: return "无网格"
        case .thirds: return "三等分"
        case .thirdsDiagonals: return "三等分 + 对角线"
        case .phiGrid: return "黄金比例"
        case .phiSpiral: return "黄金螺旋"
        case .squareFrame: return "1:1 方形框"
        case .centerCross: return "中心十字"
        case .symmetricFourths: return "对称四分格"
        }
    }

    static let defaultsKey = "z30.gridStyle"
    static let `default`: GridStyle = .thirds

    static func load() -> GridStyle {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let style = GridStyle(rawValue: raw) else {
            return .default
        }
        return style
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    // MARK: - 画线

    static func path(for style: GridStyle, in size: CGSize) -> Path {
        var path = Path()
        let w = size.width
        let h = size.height
        switch style {
        case .none:
            break
        case .thirds:
            addThirds(&path, w: w, h: h)
        case .thirdsDiagonals:
            addThirds(&path, w: w, h: h)
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: w, y: h))
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
        case .phiGrid:
            // 黄金比例线：0.382 / 0.618
            let phi: CGFloat = 0.618
            path.move(to: CGPoint(x: w * (1 - phi), y: 0))
            path.addLine(to: CGPoint(x: w * (1 - phi), y: h))
            path.move(to: CGPoint(x: w * phi, y: 0))
            path.addLine(to: CGPoint(x: w * phi, y: h))
            path.move(to: CGPoint(x: 0, y: h * (1 - phi)))
            path.addLine(to: CGPoint(x: w, y: h * (1 - phi)))
            path.move(to: CGPoint(x: 0, y: h * phi))
            path.addLine(to: CGPoint(x: w, y: h * phi))
        case .phiSpiral:
            // 黄金螺旋（斐波那契方块剥离法，和预览图 v2 的 4 号同一套算法）
            let pts = phiSpiralPoints(in: size)
            guard pts.count > 1 else { break }
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
        case .squareFrame:
            // 1:1 方形框：以短边为边长，居中
            let side = min(w, h)
            let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2,
                              width: side, height: side)
            path.addRect(rect)
        case .centerCross:
            path.move(to: CGPoint(x: w / 2, y: 0))
            path.addLine(to: CGPoint(x: w / 2, y: h))
            path.move(to: CGPoint(x: 0, y: h / 2))
            path.addLine(to: CGPoint(x: w, y: h / 2))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: w, y: h))
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
            // 中心圆
            let r: CGFloat = 24
            path.addEllipse(in: CGRect(x: w / 2 - r, y: h / 2 - r,
                                       width: r * 2, height: r * 2))
        case .symmetricFourths:
            for f in [0.25, 0.5, 0.75] {
                path.move(to: CGPoint(x: w * f, y: 0))
                path.addLine(to: CGPoint(x: w * f, y: h))
                path.move(to: CGPoint(x: 0, y: h * f))
                path.addLine(to: CGPoint(x: w, y: h * f))
            }
        }
        return path
    }

    private static func addThirds(_ path: inout Path, w: CGFloat, h: CGFloat) {
        path.move(to: CGPoint(x: w / 3, y: 0))
        path.addLine(to: CGPoint(x: w / 3, y: h))
        path.move(to: CGPoint(x: 2 * w / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        path.move(to: CGPoint(x: 0, y: h / 3))
        path.addLine(to: CGPoint(x: w, y: h / 3))
        path.move(to: CGPoint(x: 0, y: 2 * h / 3))
        path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
    }

    // MARK: - 黄金螺旋（斐波那契方块剥离法）

    /// 黄金矩形按 1:φ 居中贴合画面，剥方块：左 → 上 → 右 → 下，顺时针。
    /// 每段弧：圆心是本方块的内侧角（入口点 + r × unit(上一圆心 − 入口点)），
    /// 弧从入口点扫到对角点，扫过的角度每次 +90°。
    /// 第一版预览图画错过：居中的参数螺旋，看着像个圈——那条不是这个。
    static func phiSpiralPoints(in size: CGSize) -> [CGPoint] {
        let phi: CGFloat = (1 + sqrt(5)) / 2
        var rect = goldenRect(in: size)
        var points: [CGPoint] = []
        var prevCenter: CGPoint? = nil

        // 剥方块的顺序固定：左 → 上 → 右 → 下，顺时针循环。
        // 黄金矩形一开始是横的，每剥一个就换方向，方块边长 = 当前矩形的短边。
        for step in 0..<16 {
            let w = rect.width
            let h = rect.height
            guard w > 0.5, h > 0.5 else { break }
            let side = min(w, h)
            var square: CGRect
            var entry: CGPoint
            switch step % 4 {
            case 0: // 左：方块在左，弧从左下角进、右上角出
                square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                entry = CGPoint(x: square.minX, y: square.maxY)
            case 1: // 上：方块在上，弧从左上角进、右下角出
                square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                entry = CGPoint(x: square.minX, y: square.minY)
            case 2: // 右：方块在右，弧从右上角进、左下角出
                square = CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
                entry = CGPoint(x: square.maxX, y: square.minY)
            default: // 下：方块在下，弧从右下角进、左上角出
                square = CGRect(x: rect.minX, y: rect.maxY - side, width: side, height: side)
                entry = CGPoint(x: square.maxX, y: square.maxY)
            }
            // 出点是方块里和入口对角的那个角
            let exit = CGPoint(x: square.minX + square.maxX - entry.x,
                               y: square.minY + square.maxY - entry.y)
            // 弧线圆心：第一段是第一个方块的内侧角（左方块的右下角）；
            // 之后 = 入口 + 边长 × unit(上一圆心 − 入口)，总落在方块内侧角上
            let center: CGPoint
            if let prev = prevCenter {
                let dx = prev.x - entry.x
                let dy = prev.y - entry.y
                let len = sqrt(dx * dx + dy * dy)
                center = CGPoint(x: entry.x + side * dx / len,
                                 y: entry.y + side * dy / len)
            } else {
                center = CGPoint(x: square.maxX, y: square.maxY)
            }
            prevCenter = center
            // 弧的起止角（入口 → 出口），顺时针每段 +90°，归一化保证递增
            var thStart = atan2(entry.y - center.y, entry.x - center.x)
            var thEnd = atan2(exit.y - center.y, exit.x - center.x)
            while thEnd < thStart { thEnd += 2 * .pi }
            // 采点
            let steps = 24
            for i in 0...steps {
                let th = thStart + (thEnd - thStart) * CGFloat(i) / CGFloat(steps)
                points.append(CGPoint(x: center.x + side * cos(th),
                                      y: center.y + side * sin(th)))
            }
            // 剥掉这个方块，剩下的矩形继续
            rect = remainingRect(afterPeeling: square, from: rect, dir: step % 4)
        }
        return points
    }

    private static func goldenRect(in size: CGSize) -> CGRect {
        let phi: CGFloat = (1 + sqrt(5)) / 2
        let w = size.width
        let h = size.height
        // 黄金矩形按 1:φ 居中贴合画面
        var rw = w
        var rh = w / phi
        if rh > h {
            rh = h
            rw = h * phi
        }
        return CGRect(x: (w - rw) / 2, y: (h - rh) / 2, width: rw, height: rh)
    }

    private static func remainingRect(afterPeeling square: CGRect, from rect: CGRect, dir: Int) -> CGRect {
        switch dir {
        case 0: // 左
            return CGRect(x: square.maxX, y: rect.minY,
                          width: rect.maxX - square.maxX, height: rect.height)
        case 2: // 右
            return CGRect(x: rect.minX, y: rect.minY,
                          width: square.minX - rect.minX, height: rect.height)
        case 1: // 上
            return CGRect(x: rect.minX, y: square.maxY,
                          width: rect.width, height: rect.maxY - square.maxY)
        default: // 下
            return CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: square.minY - rect.minY)
        }
    }
}
