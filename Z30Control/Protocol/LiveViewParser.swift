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

    /// 帧像素尺寸（从 JPEG SOF 段解析；解析不到为 .zero）。
    /// v1.0.20：让取景页把相机实际发来的取景分辨率显示出来——
    /// 尼康 PTP 取景帧本身只有几百像素，手机满屏放大几倍看必然糊，
    /// 这是相机发来的上限，不是 App 压坏的。
    public var pixelSize: CGSize = .zero

    /// 增强后的图（降噪+锐化，见 LiveViewStreamService）。有它时优先用它。
    public var enhancedImage: UIImage? = nil

    #if canImport(UIKit)
    /// 快捷解码为 UIImage
    public var image: UIImage? {
        if let enhanced = enhancedImage { return enhanced }
        return UIImage(data: jpegData)
    }
    #endif

    public init(jpegData: Data, horizonRoll: Float, horizonPitch: Float, isInFocus: Bool, focusRect: CGRect?, timestamp: TimeInterval, pixelSize: CGSize = .zero, enhancedImage: UIImage? = nil) {
        self.jpegData = jpegData
        self.horizonRoll = horizonRoll
        self.horizonPitch = horizonPitch
        self.isInFocus = isInFocus
        self.focusRect = focusRect
        self.timestamp = timestamp
        self.pixelSize = pixelSize
        self.enhancedImage = enhancedImage
    }
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
        // 真机 LiveView 帧通常数十 KB；阈值放宽到 64 字节，避免小帧被误判
        //（之前 >128 会把模拟器 116 字节的测试帧也丢掉）
        guard rawPayload.count > 64 else { return nil }
        
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
            timestamp: Date().timeIntervalSince1970,
            pixelSize: Self.parseJPEGSize(jpegData) ?? .zero
        )
    }

    /// 从 JPEG 里读 SOF0/SOF2 段的宽高（取景帧实际像素尺寸）。
    /// 走法：SOI 后逐段跳（段长含自身 2 字节），遇到 0xC0/0xC2 读
    /// 精度(1B)+高(U16BE)+宽(U16BE)；遇到 SOS(0xDA)/EOI 停。
    public static func parseJPEGSize(_ data: Data) -> CGSize? {
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 3 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            if marker == 0xD8 || marker == 0x01 { i += 2; continue } // SOI/填充
            if marker == 0xD9 || marker == 0xDA { return nil } // EOI/SOS：帧头区已过
            if marker == 0xC0 || marker == 0xC2 {
                guard i + 9 < b.count else { return nil }
                let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                guard w > 0, h > 0 else { return nil }
                return CGSize(width: w, height: h)
            }
            let segLen = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard segLen >= 2 else { return nil }
            i += 2 + segLen
        }
        return nil
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
