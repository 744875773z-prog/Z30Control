//
//  LiveViewStreamService.swift
//  Z30Control
//
//  实时取景流调度、FPS 监控与渲染管道管理
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public final class LiveViewStreamService: ObservableObject {
    
    public static let shared = LiveViewStreamService()
    
    @Published public var currentFrame: LiveViewFrame?
    @Published public var currentFPS: Int = 30
    @Published public var activeFilter: LUTFilter? = LUTFilter.builtinPresets.first
    @Published public var isLUTEnabled: Bool = true
    @Published public var isFocusPeakingEnabled: Bool = false
    @Published public var isZebraEnabled: Bool = false
    @Published public var isHistogramVisible: Bool = true
    @Published public var isWaveformVisible: Bool = false
    
    // 模拟直方图数据分布 (0 ~ 255 的归一化曲线点)
    @Published public var histogramPoints: [Float] = []
    
    private var frameCounter: Int = 0
    private var lastFpsTimestamp: TimeInterval = 0
    // v1.0.6：滤镜在后台串行跑，只取最新一帧；忙时丢帧，保流畅
    private let lutQueue = DispatchQueue(label: "com.z30control.lut", qos: .userInitiated)
    private var lutFiltering = false
    
    private init() {
        generateMockHistogramData()
    }
    
    public func updateFrame(_ frame: LiveViewFrame) {
        // v1.0.6：选了滤镜，取景画面要实时变。之前 activeFilter/isLUTEnabled 只改了状态，
        // 没有任何地方把 LUT 画到帧上，所以选滤镜屏幕毫无变化。
        if isLUTEnabled, let filter = activeFilter, let rawImage = frame.image {
            guard !lutFiltering else { return } // 忙：丢掉这帧，下一帧再滤
            lutFiltering = true
            lutQueue.async { [weak self] in
                let filtered = LUTProcessor.shared.applyLUT(to: rawImage, filter: filter)
                let jpeg = filtered.jpegData(compressionQuality: 0.85) ?? frame.jpegData
                let filteredFrame = LiveViewFrame(jpegData: jpeg, horizonRoll: frame.horizonRoll, horizonPitch: frame.horizonPitch, isInFocus: frame.isInFocus, focusRect: frame.focusRect, timestamp: frame.timestamp)
                DispatchQueue.main.async {
                    self?.lutFiltering = false
                    self?.publishFrame(filteredFrame)
                }
            }
            return
        }
        publishFrame(frame)
    }

    private func publishFrame(_ frame: LiveViewFrame) {
        self.currentFrame = frame
        
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
