//
//  NP3LUTRenderer.swift
//  Z30Control
//
//  v1.0.27：把 .NP3 配方的色彩参数烤成 3D LUT（32³，CIColorCube），
//  再套到图库照片上。渲染数学与 Tests/test_v127_np3.py 里的 Python 版
//  是同一套（常量一一对应），已在测试色卡上交叉验证过方向：
//  绿色 chroma -45 → 绿色 visibly 降饱和；中间调 hue 42 → 偏暖；
//  对比 40 → 整体反差上升。
//
//  必须说清楚：这是近似渲染，不是尼康官方算法。NP3 给的是参数，
//  尼康机内那套色彩管线是私有的，所以 App 里渲出来的只能接近
//  相机直出，不能 100% 一样。
//  锐化（sharpning / midRangeSharpning）和清晰度（clarity）这次不渲染，
//  只做色彩部分——锐化是空间域操作，进不了 3D LUT。
//

import Foundation
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// NP3 色彩数学（纯函数，与 Python 测试版同一套常量）
public enum NP3ColorMath {
    /// 黑场/白场每单位对应的归一化偏移
    public static let levelScale = 0.001
    /// Color Blender 单色影响的半宽（度）
    public static let blenderHalfWidthDeg = 45.0
    /// Color Blender brightness 每单位对应的亮度偏移
    public static let blenderBrightnessScale = 0.25
    /// Color Grading chroma 给灰色加的饱和量系数
    public static let gradingSatAdd = 0.3
    /// Color Grading brightness 每单位对应的亮度偏移
    public static let gradingBrightnessScale = 0.25
    /// 8 色基准色相（度）：红橙黄绿青蓝紫品红
    public static let blenderBaseHues: [Double] = [0, 30, 60, 120, 180, 240, 270, 300]

    public static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        min(max(v, lo), hi)
    }

    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    /// 最短有向角差（度，[-180, 180)）
    public static func angleDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a + 180).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d - 180
    }

    public static func rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        let d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = l <= 0.5 ? d / max(mx + mn, 1e-9) : d / max(2 - mx - mn, 1e-9)
        var h: Double
        if mx == r {
            h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h = (h * 60).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    public static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        let hh = (h.truncatingRemainder(dividingBy: 360) / 60)
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let seg = Int(hh) % 6
        switch seg {
        case 0: return (c + m, x + m, m)
        case 1: return (x + m, c + m, m)
        case 2: return (m, c + m, x + m)
        case 3: return (m, x + m, c + m)
        case 4: return (x + m, m, c + m)
        default: return (c + m, m, x + m)
        }
    }

    /// 单像素完整管线：色调（曲线或对比/色阶）→ 饱和 → Color Blender → Color Grading
    public static func adjustPixel(r: Double, g: Double, b: Double, control: NP3PictureControl) -> (r: Double, g: Double, b: Double) {
        var rr = r, gg = g, bb = b

        // 1. 色调：有自定义曲线就用 257 点原始表（逐通道），没有就用对比/色阶近似
        if let tc = control.toneCurve {
            func curve(_ v: Double) -> Double {
                let idx = clamp(v * 256, 0, 256)
                let lo = min(Int(idx), 256)
                let hi = min(lo + 1, 256)
                let f = idx - Double(lo)
                return Double(tc.raw[lo]) / 32767 * (1 - f)
                    + Double(tc.raw[hi]) / 32767 * f
            }
            rr = curve(rr); gg = curve(gg); bb = curve(bb)
        } else {
            func tone(_ v: Double) -> Double {
                let bp = max(0, Double(-control.blackLevel) * levelScale)
                let wp = 1 - Double(control.whiteLevel) * levelScale
                var t = clamp((v - bp) / max(wp - bp, 1e-6))
                t = clamp(0.5 + (t - 0.5) * (1 + Double(control.contrast) / 100))
                let hw = smoothstep(0.5, 1.0, t)
                t = clamp(t + Double(control.highlights) / 100 * hw * (1 - t))
                let sw = 1 - smoothstep(0.0, 0.5, t)
                t = clamp(t + Double(control.shadows) / 100 * sw * t)
                return t
            }
            rr = tone(rr); gg = tone(gg); bb = tone(bb)
        }

        // 2. 饱和：绕亮度轴缩放
        let luma = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb
        let satF = 1 + Double(control.saturation) / 100
        rr = clamp(luma + (rr - luma) * satF)
        gg = clamp(luma + (gg - luma) * satF)
        bb = clamp(luma + (bb - luma) * satF)

        // 3. Color Blender（HSL 空间，8 色三角权重）
        var hsl = rgbToHSL(r: rr, g: gg, b: bb)
        let blender = [
            control.colorBlender.red, control.colorBlender.orange,
            control.colorBlender.yellow, control.colorBlender.green,
            control.colorBlender.cyan, control.colorBlender.blue,
            control.colorBlender.purple, control.colorBlender.magenta,
        ]
        var hueShift = 0.0, chromaSum = 0.0, brightSum = 0.0
        for (i, v) in blender.enumerated() {
            let d = abs(angleDelta(from: blenderBaseHues[i], to: hsl.h))
            let w = max(0, 1 - d / blenderHalfWidthDeg)
            hueShift += w * Double(v.hue)
            chromaSum += w * Double(v.chroma)
            brightSum += w * Double(v.brightness)
        }
        hsl.h = (hsl.h + hueShift).truncatingRemainder(dividingBy: 360)
        if hsl.h < 0 { hsl.h += 360 }
        hsl.s = clamp(hsl.s * (1 + chromaSum / 100))
        hsl.l = clamp(hsl.l + brightSum / 100 * blenderBrightnessScale)
        (rr, gg, bb) = hslToRGB(h: hsl.h, s: hsl.s, l: hsl.l)

        // 4. Color Grading（按亮度分区，向目标色相 tint）
        hsl = rgbToHSL(r: rr, g: gg, b: bb)
        let g = control.colorGrading
        let lo = 0.5 - 0.2 * (0.5 + Double(g.blending) / 100)
        let hi = 0.5 + 0.2 * (0.5 + Double(g.blending) / 100)
        let mid = 0.5 + Double(g.balance) / 100 * 0.2
        let wSh = 1 - smoothstep(lo, mid, hsl.l)
        let wHi = smoothstep(mid, hi, hsl.l)
        let wMid = max(0, 1 - wSh - wHi)
        for (w, z) in [(wSh, g.shadows), (wMid, g.midTone), (wHi, g.highlights)] {
            guard z.chroma != 0 || z.brightness != 0 else { continue }
            hsl.h += w * Double(z.chroma) / 100 * angleDelta(from: hsl.h, to: Double(z.hue))
            hsl.s = clamp(hsl.s + w * Double(z.chroma) / 100 * gradingSatAdd * (1 - hsl.s))
            hsl.l = clamp(hsl.l + w * Double(z.brightness) / 100 * gradingBrightnessScale)
        }
        hsl.h = hsl.h.truncatingRemainder(dividingBy: 360)
        if hsl.h < 0 { hsl.h += 360 }
        (rr, gg, bb) = hslToRGB(h: hsl.h, s: hsl.s, l: hsl.l)
        return (clamp(rr), clamp(gg), clamp(bb))
    }
}

/// NP3 → 3D LUT 烘焙 + CIColorCube 套用
public final class NP3LUTRenderer {
    public static let shared = NP3LUTRenderer()

    /// LUT 维度（32³ = 32768个体素，RGBA float）
    public let cubeDimension = 32

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// 把配方参数烤成 CIColorCube 用的 cube data（R 最快，RGBA float）
    public func bakeCubeData(control: NP3PictureControl) -> Data {
        let n = cubeDimension
        var floats: [Float] = []
        floats.reserveCapacity(n * n * n * 4)
        for b in 0 ..< n {
            for g in 0 ..< n {
                for r in 0 ..< n {
                    let p = NP3ColorMath.adjustPixel(
                        r: Double(r) / Double(n - 1),
                        g: Double(g) / Double(n - 1),
                        b: Double(b) / Double(n - 1),
                        control: control
                    )
                    floats.append(contentsOf: [Float(p.r), Float(p.g), Float(p.b), 1.0])
                }
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    #if canImport(UIKit)
    /// 把配方套到一张图上（返回新图；失败返回 nil，调用方用原图兜底）
    public func apply(control: NP3PictureControl, to image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(bakeCubeData(control: control), forKey: "inputCubeData")
        guard let out = filter.outputImage,
              let cg = ciContext.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 渲好的图压成 JPEG（存相册用）
    public func jpegData(of image: UIImage, quality: CGFloat = 0.92) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
    #endif
}
