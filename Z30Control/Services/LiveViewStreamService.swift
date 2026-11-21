//
//  LiveViewStreamService.swift
//  Z30Control
//
//  实时取景流调度、FPS 监控与渲染管道管理
//

import Foundation
import Combine
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

public final class LiveViewStreamService: ObservableObject {

    public static let shared = LiveViewStreamService()

    @Published public var currentFrame: LiveViewFrame?
    @Published public var currentFPS: Int = 30
    // v1.0.20：滤镜默认关。v1.0.19 删了滤镜条却没关默认，结果每帧都过
    // PORTRA 400 还重压一遍 JPEG 0.85——比 v1.0.18（用户点过原片关掉）
    // 还糊。滤镜条已删，取景页不再有地方能打开它，默认就该是原片直出。
    @Published public var activeFilter: LUTFilter? = nil
    @Published public var isLUTEnabled: Bool = false
    // v1.0.20：取景帧轻量增强（降噪+锐化，默认开，取景页可关）。
    // 只做显示层增强，不改相机设置、不动原图。
    @Published public var isEnhanceEnabled: Bool = true
    // 当前取景帧的实际像素尺寸（相机发来的那帧多大，见 LiveViewParser）。
    @Published public var currentFrameSize: CGSize = .zero
    @Published public var isFocusPeakingEnabled: Bool = false
    @Published public var isZebraEnabled: Bool = false
    @Published public var isHistogramVisible: Bool = true
    @Published public var isWaveformVisible: Bool = false

    // 模拟直方图数据分布 (0 ~ 255 的归一化曲线点)
    @Published public var histogramPoints: [Float] = []

    private var frameCounter: Int = 0
    private var lastFpsTimestamp: TimeInterval = 0
    // v1.0.6：滤镜在后台串行跑，只取最新一帧；忙时丢帧，保流畅
    private let frameFilterQueue = DispatchQueue(label: "com.z30control.framefilter", qos: .userInitiated)
    private var frameFiltering = false
    // 增强用的共享 CI 上下文（每帧新建上下文很贵）。
    private static let enhanceContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private init() {
        generateMockHistogramData()
    }
    
    public func updateFrame(_ frame: LiveViewFrame) {
        // v1.0.6：选了滤镜，取景画面要实时变。之前 activeFilter/isLUTEnabled 只改了状态，
        // 没有任何地方把 LUT 画到帧上，所以选滤镜屏幕毫无变化。
        if isLUTEnabled, let filter = activeFilter, let rawImage = frame.image {
            guard !frameFiltering else { return } // 忙：丢掉这帧，下一帧再滤
            frameFiltering = true
            frameFilterQueue.async { [weak self] in
                let filtered = LUTProcessor.shared.applyLUT(to: rawImage, filter: filter)
                let jpeg = filtered.jpegData(compressionQuality: 0.85) ?? frame.jpegData
                let filteredFrame = LiveViewFrame(jpegData: jpeg, horizonRoll: frame.horizonRoll, horizonPitch: frame.horizonPitch, isInFocus: frame.isInFocus, focusRect: frame.focusRect, timestamp: frame.timestamp, pixelSize: frame.pixelSize)
                DispatchQueue.main.async {
                    self?.frameFiltering = false
                    self?.publishFrame(filteredFrame)
                }
            }
            return
        }
        // v1.0.20：轻量增强（先降噪再轻锐化），只改显示的这帧，不动原图。
        // 后台串行跑，忙时丢帧保流畅；增强结果存在 enhancedImage 里，不经过
        // JPEG 重压（上面 LUT 分支的 0.85 重压正是画面变糊的帮凶之一）。
        if isEnhanceEnabled, let rawImage = frame.image {
            guard !frameFiltering else { return } // 忙：丢掉这帧，下一帧再滤
            frameFiltering = true
            frameFilterQueue.async { [weak self] in
                let enhanced = Self.enhanceLiveViewImage(rawImage)
                var out = frame
                out.enhancedImage = enhanced
                DispatchQueue.main.async {
                    self?.frameFiltering = false
                    self?.publishFrame(out)
                }
            }
            return
        }
        publishFrame(frame)
    }

    /// 轻量取景增强：CINoiseReduction 降噪（轻手）+ CIUnsharpMask 轻锐化。
    /// 参数都取保守值——取景帧本身只有几百像素，重手会把噪点锐成颗粒。
    private static func enhanceLiveViewImage(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        var out: CIImage? = CIImage(cgImage: cg)
        if let input = out, let denoise = CIFilter(name: "CINoiseReduction") {
            denoise.setValue(input, forKey: kCIInputImageKey)
            denoise.setValue(0.02, forKey: "inputNoiseLevel")
            denoise.setValue(0.4, forKey: "inputSharpness")
            out = denoise.outputImage
        }
        if let input = out, let sharpen = CIFilter(name: "CIUnsharpMask") {
            sharpen.setValue(input, forKey: kCIInputImageKey)
            sharpen.setValue(1.5, forKey: "inputRadius")
            sharpen.setValue(0.5, forKey: "inputIntensity")
            out = sharpen.outputImage
        }
        guard let result = out, let outCG = enhanceContext.createCGImage(result, from: result.extent) else {
            return image
        }
        return UIImage(cgImage: outCG)
    }

    private func publishFrame(_ frame: LiveViewFrame) {
        self.currentFrame = frame
        if frame.pixelSize != .zero, frame.pixelSize != currentFrameSize {
            self.currentFrameSize = frame.pixelSize
        }
        
        // 计算真实 FPS
        frameCounter += 1
        let now = Date().timeIntervalSince1970
        if now - lastFpsTimestamp >= 1.0 {
            currentFPS = frameCounter
            frameCounter = 0
            lastFpsTimestamp = now
        }
    }
    
    public func setFilter(_ filter: LUTFilter?) {
        self.activeFilter = filter
    }
    
    public func toggleLUT() {
        isLUTEnabled.toggle()
    }
    
    private func generateMockHistogramData() {
        // 生成具有典型曝光分布的测试曲线
        var points: [Float] = []
        for i in 0..<30 {
            let x = Float(i) / 30.0
            let y = exp(-pow(x - 0.35, 2) / 0.04) * 0.8 + 0.1
            points.append(y)
        }
        self.histogramPoints = points
    }
}
