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
    
    private init() {
        generateMockHistogramData()
    }
    
    public func updateFrame(_ frame: LiveViewFrame) {
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
