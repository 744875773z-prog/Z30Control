//
//  LiveViewParser.swift
//  Z30Control
//
//  尼康 LiveView 实时取景数据包高效解析器
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 实时取景帧元数据与图像载荷
public struct LiveViewFrame {
    /// 纯净的 JPEG 图像二进制数据
    public let jpegData: Data
    
    /// 电子水平仪翻滚角度 (度数, -180 ~ +180)
    public let horizonRoll: Float
    
    /// 电子水平仪俯仰角度
    public let horizonPitch: Float
    
    /// 是否合焦 (Focus Confirmation)
    public let isInFocus: Bool
    
    /// 对焦点屏幕相对归一化矩形 (0.0~1.0)
    public let focusRect: CGRect?
    
    /// 抓取时间戳
    public let timestamp: TimeInterval
}

/// 尼康 LiveView 帧解析器
public final class LiveViewParser {
    
    // JPEG 标准起始标识 (SOI) 与结束标识 (EOI)
    private static let jpegSOI: [UInt8] = [0xFF, 0xD8]
    private static let jpegEOI: [UInt8] = [0xFF, 0xD9]
    
    /// 解析从尼康相机接收到的 LiveView 二进制数据载荷
    /// - Parameter rawPayload: 相机返回的包含尼康私有头部与 JPEG 的原始数据
    /// - Returns: 解析成功的 LiveViewFrame，若校验失败返回 nil
    public static func parse(rawPayload: Data) -> LiveViewFrame? {
        guard rawPayload.count > 128 else { return nil }
        
        let bytes = [UInt8](rawPayload)
        
        // 1. 高速检索 JPEG 起始标记 0xFF 0xD8
        guard let startIndex = findSequence(sequence: jpegSOI, in: bytes) else {
            return nil
        }
        
        // 2. 检索 JPEG 结束标记 0xFF 0xD9
        guard let endIndex = findSequence(sequence: jpegEOI, in: bytes, startingFrom: startIndex + 2) else {
            return nil
        }
        
        // 提取纯净 JPEG 数据
        let jpegEndIndex = endIndex + 2
        guard jpegEndIndex <= bytes.count else { return nil }
        let jpegData = rawPayload.subdata(in: startIndex..<jpegEndIndex)
        
        // 3. 解析尼康特有的头部元数据 (通常位于 JPEG 数据之前的 64~128 字节区域)
        var rollAngle: Float = 0.0
        var pitchAngle: Float = 0.0
        var inFocus = false
        var focusBox: CGRect? = nil
        
        if startIndex >= 32 {
            // 提取对焦状态标志 (示例偏移位置，通常在头部的固定偏移)
            inFocus = bytes[20] == 0x01
            
            // 提取简化的水平仪数值 (若存在)
            if startIndex >= 48 {
                let rollRaw = Int16(bytes[32]) | (Int16(bytes[33]) << 8)
                rollAngle = Float(rollRaw) / 10.0
            }
            
            // 归一化对焦框位置
            focusBox = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        }
        
        return LiveViewFrame(
            jpegData: jpegData,
            horizonRoll: rollAngle,
            horizonPitch: pitchAngle,
            isInFocus: inFocus,
            focusRect: focusBox,
            timestamp: Date().timeIntervalSince1970
        )
    }
    
    /// 二进制序列查找算法
    private static func findSequence(sequence: [UInt8], in buffer: [UInt8], startingFrom: Int = 0) -> Int? {
        guard buffer.count >= sequence.count, startingFrom <= buffer.count - sequence.count else {
            return nil
        }
        
        let targetLength = sequence.count
        for i in startingFrom...(buffer.count - targetLength) {
            var match = true
            for j in 0..<targetLength {
                if buffer[i + j] != sequence[j] {
                    match = false
                    break
                }
            }
            if match {
                return i
            }
        }
        return nil
    }
}
