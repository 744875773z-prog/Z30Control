//
//  LivePreviewRenderer.swift
//  Z30Control
//
//  v1.0.31：取景页滤镜实时预览——把机身滤镜的 614 字节载荷里
//  +0x066 的 256 点 1D LUT 烘成 32³ CIColorCube，只在手机屏幕上
//  显示，不写相机、不改保存的照片。
//  1D 曲线是逐通道独立作用的，cube 在 (r,g,b) 处的值就是
//  (lut[r], lut[g], lut[b])。饱和度（载荷 0x1E，0.25/级）用
//  CIColorControls 一并加上：系数 = 1 + 值×0.1（-3..+3 → 0.7..1.3），
//  这是近似映射，机身的饱和度刻度不是公开的。
//  cube 数据按预设 id 缓存（NSCache，上限 16MB ≈ 32 个 cube），
//  不每帧重算；取景帧只有几百像素，CIColorCube 在 GPU 上几乎免费。
//  CIColorCube 的数据排布：R 最快、然后 G、最后 B——
//  索引 ((b*32 + g)*32 + r)，每个点 4 个 float（RGBA）。
//  诚实说明：这是对机身出片的近似——机身管线是 LUT→白平衡增益，
//  之后还有逐通道整形（1dlut 项目实测 R 偏高约 11%、B 偏低），
//  手机预览不可能和机身直出逐点一致，只能用来挑风格。
//

import Foundation
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

public final class LivePreviewRenderer {
    public static let shared = LivePreviewRenderer()

    public static let cubeDimension = 32
    /// 一个 cube 的字节数：32³ × 4 float = 512KB。
    public static let cubeByteCount = 32 * 32 * 32 * 4 * 4

    private let cache = NSCache<NSString, NSData>()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    /// 预设 → 32³ CIColorCube 数据（Data 里是 32³×4 个 Float，RGBA）。
    /// nil = 载荷非法。结果按预设 id 缓存，不每帧重算。
    public func cubeData(for preset: PictCtrlPreset) -> Data? {
        if let hit = cache.object(forKey: preset.id as NSString) {
            return hit as Data
        }
        guard let payload = preset.payload,
              let lut = PictCtrlPayload.parseLUT(payload) else { return nil }
        var floats = [Float](repeating: 0, count: 32 * 32 * 32 * 4)
        for b in 0..<32 {
            for g in 0..<32 {
                for r in 0..<32 {
                    let base = ((b * 32 + g) * 32 + r) * 4
                    floats[base + 0] = Self.cubeValue(lut: lut, grid: r)
                    floats[base + 1] = Self.cubeValue(lut: lut, grid: g)
                    floats[base + 2] = Self.cubeValue(lut: lut, grid: b)
                    floats[base + 3] = 1.0
                }
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: preset.id as NSString, cost: data.count)
        return data
    }

    /// 网格点 i（0..31）→ LUT 值归一化到 0..1：输入强度 i/31 对应
    /// LUT 下标 round(i/31*255)，输出 lut[idx]/32767。
    public static func cubeValue(lut: [Int], grid: Int) -> Float {
        guard lut.count == 256, grid >= 0, grid < 32 else { return 0 }
        let idx = Int((Double(grid) / 31.0 * 255.0).rounded())
        return Float(lut[idx]) / Float(PictCtrlPayload.lutMax)
    }

    /// 载荷饱和度 → CIColorControls 系数（近似映射，见文件头注释）。
    public static func saturationFactor(for preset: PictCtrlPreset) -> Float {
        guard let payload = preset.payload,
              payload.count > Int(PictCtrlPayload.Param.saturation.rawValue) else { return 1.0 }
        let raw = payload[Int(PictCtrlPayload.Param.saturation.rawValue)]
        let value = PictCtrlPayload.decodeParam(raw, param: .saturation)
        return Float(max(0.0, min(2.0, 1.0 + value * 0.1)))
    }

    /// 把预览滤镜画到一帧上：先 CIColorCube，再 CIColorControls（饱和度）。
    /// 失败返回 nil，调用方用原图。
    public func applyPreview(to image: UIImage, preset: PictCtrlPreset) -> UIImage? {
        guard let cg = image.cgImage,
              let cube = cubeData(for: preset) else { return nil }
        var out: CIImage? = CIImage(cgImage: cg)
        if let input = out, let cubeFilter = CIFilter(name: "CIColorCube") {
            cubeFilter.setValue(input, forKey: kCIInputImageKey)
            cubeFilter.setValue(Self.cubeDimension, forKey: "inputCubeDimension")
            cubeFilter.setValue(cube, forKey: "inputCubeData")
            out = cubeFilter.outputImage
        }
        let sat = Self.saturationFactor(for: preset)
        if let input = out, sat != 1.0, let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(input, forKey: kCIInputImageKey)
            controls.setValue(sat, forKey: kCIInputSaturationKey)
            out = controls.outputImage
        }
        guard let result = out,
              let outCG = ciContext.createCGImage(result, from: result.extent) else { return nil }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
