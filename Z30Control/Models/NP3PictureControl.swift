//
//  NP3PictureControl.swift
//  Z30Control
//
//  v1.0.27：尼康 Flexible Color Picture Control（.NP3）文件解析。
//  格式依据：开源库 ssssota/nikon-flexible-color-picture-control
//  （TypeScript，MIT）的 deserialize.ts / offset.ts / types.ts / base.ts，
//  按其偏移与公式逐项移植，不凭空猜格式。
//  注意：这只是 Flexible 配方的格式；老式标准 Picture Control（.NCP 等）
//  不是这个布局，解析会报 badMagic / tooShort。
//

import Foundation

/// 单色调整（三值一组）。注意 hue 在两种上下文里含义不同：
/// - ColorBlender 里是 -100~100 的色相偏移（度）；
/// - ColorGrading 里是 0~360 的目标色相（度）。
public struct NP3ColorAdjust: Equatable {
    public var hue: Int
    public var chroma: Int
    public var brightness: Int

    public init(hue: Int, chroma: Int, brightness: Int) {
        self.hue = hue
        self.chroma = chroma
        self.brightness = brightness
    }
}

/// Color Blender：红橙黄绿青蓝紫品红 8 色 × 色相/纯度/亮度
public struct NP3ColorBlender: Equatable {
    public var red: NP3ColorAdjust
    public var orange: NP3ColorAdjust
    public var yellow: NP3ColorAdjust
    public var green: NP3ColorAdjust
    public var cyan: NP3ColorAdjust
    public var blue: NP3ColorAdjust
    public var purple: NP3ColorAdjust
    public var magenta: NP3ColorAdjust
}

/// Color Grading：高光/中间调/阴影 × 色相/纯度/亮度 + 混合/平衡
public struct NP3ColorGrading: Equatable {
    public var highlights: NP3ColorAdjust
    public var midTone: NP3ColorAdjust
    public var shadows: NP3ColorAdjust
    /// 0~100：分区过渡的平滑程度
    public var blending: Int
    /// -100~100：中间调分界点偏移
    public var balance: Int
}

/// 自定义色调曲线：257 点原始表（0~32767）+ 控制点（0~255）
public struct NP3ToneCurve: Equatable {
    public var raw: [Int]
    public var points: [NP3ToneCurvePoint]

    public struct NP3ToneCurvePoint: Equatable {
        public var x: Int
        public var y: Int
    }
}

/// 一份 Flexible Picture Control 的全部参数
public struct NP3PictureControl: Equatable {
    public var name: String
    public var comment: String?
    /// -3.0~9.0（(byte - 0x80) / 4）
    public var sharpning: Double
    /// -5.0~5.0
    public var midRangeSharpning: Double
    /// -5.0~5.0
    public var clarity: Double
    /// -100~100；有自定义色调曲线时按原库行为返回 0（曲线已包含这部分）
    public var contrast: Int
    public var highlights: Int
    public var shadows: Int
    public var whiteLevel: Int
    public var blackLevel: Int
    /// -100~100
    public var saturation: Int
    public var colorBlender: NP3ColorBlender
    public var colorGrading: NP3ColorGrading
    /// 可能不存在（Modern Chrome Std 就没有）
    public var toneCurve: NP3ToneCurve?
}

public enum NP3ParseError: Error, LocalizedError {
    case tooShort
    case badMagic
    case badCommentChunk

    public var errorDescription: String? {
        switch self {
        case .tooShort:
            return "文件太小，不像一份 .NP3 配方。"
        case .badMagic:
            return "这个文件解析不了，可能不是 Flexible 配方（.NP3），请确认文件是从尼康 Picture Control 导出的。"
        case .badCommentChunk:
            return "这个文件解析不了，备注段损坏，可能不是 Flexible 配方。"
        }
    }
}

/// .NP3 解析器：ssssota deserialize.ts 的 Swift 移植
public enum NP3Parser {
    // MARK: - 偏移（offset.ts）
    private static let offsetName = 0x18
    private static let offsetSharpening = 0x52
    private static let offsetMidRangeSharpening = 0xf2
    private static let offsetClarity = 0x5c
    private static let offsetContrast = 0x110
    private static let offsetHighlights = 0x11a
    private static let offsetShadows = 0x124
    private static let offsetWhiteLevel = 0x12e
    private static let offsetBlackLevel = 0x138
    private static let offsetSaturation = 0x142
    private static let offsetBlenderRed = 0x14c
    private static let offsetBlenderOrange = 0x14f
    private static let offsetBlenderYellow = 0x152
    private static let offsetBlenderGreen = 0x155
    private static let offsetBlenderCyan = 0x158
    private static let offsetBlenderBlue = 0x15b
    private static let offsetBlenderPurple = 0x15e
    private static let offsetBlenderMagenta = 0x161
    private static let offsetGradingHighlights = 0x170
    private static let offsetGradingMidTone = 0x174
    private static let offsetGradingShadows = 0x178
    private static let offsetGradingBlending = 0x180
    private static let offsetGradingBalance = 0x182
    private static let offsetCommentFlagA = 0x185
    private static let offsetCommentFlagB = 0x186
    private static let offsetToneCurveFlag = 0x187
    private static let offsetToneCurveRaw = 0x1cc
    private static let offsetToneCurvePoints = 0x194

    /// base.ts 里 base 数组的长度（不带色调曲线的基准体）
    private static let baseLength = 392
    /// baseWithToneCurve.length - base.length
    private static let toneCurveExtensionLength = 586
    private static let commentLengthOffset = baseLength
    private static let commentPayloadOffset = baseLength + 4
    private static let chunkTypeLength = 4
    private static let toneCurveChunkType: UInt32 = 0x02

    public static func parse(_ data: Data) throws -> NP3PictureControl {
        guard data.count >= baseLength else { throw NP3ParseError.tooShort }
        // 文件头必须是 "NCP"（原库没校验，这里多一道，防止把 JPG 之类误当配方读）
        guard data[0] == 0x4e && data[1] == 0x43 && data[2] == 0x50 else {
            throw NP3ParseError.badMagic
        }
        let bytes = [UInt8](data)
        let toneCurve = readToneCurve(bytes)
        let hasTC = toneCurve != nil

        func s8(_ offset: Int) -> Int { Int(bytes[offset]) - 0x80 }
        func s4(_ offset: Int) -> Double { (Double(bytes[offset]) - 0x80) / 4 }

        return NP3PictureControl(
            name: readName(bytes),
            comment: readComment(bytes),
            sharpning: s4(offsetSharpening),
            midRangeSharpning: s4(offsetMidRangeSharpening),
            clarity: s4(offsetClarity),
            contrast: hasTC ? 0 : s8(offsetContrast),
            highlights: hasTC ? 0 : s8(offsetHighlights),
            shadows: hasTC ? 0 : s8(offsetShadows),
            whiteLevel: hasTC ? 0 : s8(offsetWhiteLevel),
            blackLevel: hasTC ? 0 : s8(offsetBlackLevel),
            saturation: s8(offsetSaturation),
            colorBlender: NP3ColorBlender(
                red: readBlender(bytes, offsetBlenderRed),
                orange: readBlender(bytes, offsetBlenderOrange),
                yellow: readBlender(bytes, offsetBlenderYellow),
                green: readBlender(bytes, offsetBlenderGreen),
                cyan: readBlender(bytes, offsetBlenderCyan),
                blue: readBlender(bytes, offsetBlenderBlue),
                purple: readBlender(bytes, offsetBlenderPurple),
                magenta: readBlender(bytes, offsetBlenderMagenta)
            ),
            colorGrading: NP3ColorGrading(
                highlights: readGrading(bytes, offsetGradingHighlights),
                midTone: readGrading(bytes, offsetGradingMidTone),
                shadows: readGrading(bytes, offsetGradingShadows),
                blending: s8(offsetGradingBlending),
                balance: s8(offsetGradingBalance)
            ),
            toneCurve: toneCurve
        )
    }

    private static func readName(_ buf: [UInt8]) -> String {
        let slice = buf[offsetName ..< offsetName + 19]
        let bytes = slice.prefix(while: { $0 != 0 })
        return String(bytes: bytes, encoding: .ascii)
            ?? String(bytes: bytes, encoding: .utf8)
            ?? ""
    }

    private static func readBlender(_ buf: [UInt8], _ offset: Int) -> NP3ColorAdjust {
        NP3ColorAdjust(
            hue: Int(buf[offset]) - 0x80,
            chroma: Int(buf[offset + 1]) - 0x80,
            brightness: Int(buf[offset + 2]) - 0x80
        )
    }

    private static func readGrading(_ buf: [UInt8], _ offset: Int) -> NP3ColorAdjust {
        NP3ColorAdjust(
            hue: ((Int(buf[offset]) & 0x0f) << 8) + Int(buf[offset + 1]),
            chroma: Int(buf[offset + 2]) - 0x80,
            brightness: Int(buf[offset + 3]) - 0x80
        )
    }

    private static func readComment(_ buf: [UInt8]) -> String? {
        guard let chunk = readCommentChunk(buf) else { return nil }
        let payload = buf[commentPayloadOffset ..< commentPayloadOffset + chunk.payloadLength]
        guard let terminator = payload.firstIndex(of: 0) else { return nil }
        let text = payload[..<terminator]
        return String(bytes: text, encoding: .utf8)
    }

    private static func readToneCurve(_ buf: [UInt8]) -> NP3ToneCurve? {
        guard let start = toneCurveStart(buf) else { return nil }
        let delta = start - baseLength
        var raw: [Int] = []
        raw.reserveCapacity(257)
        for i in 0 ..< 257 {
            let o = offsetToneCurveRaw + delta + i * 2
            raw.append((Int(buf[o]) << 8) + Int(buf[o + 1]))
        }
        var points: [NP3ToneCurve.NP3ToneCurvePoint] = []
        let count = Int(buf[offsetToneCurvePoints + delta])
        for i in 0 ..< count {
            let o = offsetToneCurvePoints + delta + 1 + i * 2
            points.append(NP3ToneCurve.NP3ToneCurvePoint(x: Int(buf[o]), y: Int(buf[o + 1])))
        }
        return NP3ToneCurve(raw: raw, points: points)
    }

    private struct CommentChunk {
        let payloadLength: Int
        let nextChunkType: UInt32
    }

    private static func hasCommentFlag(_ buf: [UInt8]) -> Bool {
        buf[offsetCommentFlagA] == 1 && buf[offsetCommentFlagB] == 1
    }

    private static func readCommentChunk(_ buf: [UInt8]) -> CommentChunk? {
        guard hasCommentFlag(buf),
              buf.count >= commentPayloadOffset + chunkTypeLength else { return nil }
        let payloadLength = Int(readU32BE(buf, commentLengthOffset))
        guard payloadLength != 0, payloadLength % 2 == 0 else { return nil }
        let payloadEnd = commentPayloadOffset + payloadLength
        guard payloadEnd + chunkTypeLength <= buf.count else { return nil }
        let payload = buf[commentPayloadOffset ..< payloadEnd]
        guard let terminator = payload.firstIndex(of: 0),
              payload[terminator...].allSatisfy({ $0 == 0 }) else { return nil }
        return CommentChunk(
            payloadLength: payloadLength,
            nextChunkType: readU32BE(buf, payloadEnd)
        )
    }

    private static func toneCurveStart(_ buf: [UInt8]) -> Int? {
        if let chunk = readCommentChunk(buf) {
            guard chunk.nextChunkType == toneCurveChunkType else { return nil }
            let start = commentPayloadOffset + chunk.payloadLength + chunkTypeLength
            return buf.count >= start + toneCurveExtensionLength ? start : nil
        }
        guard buf.count >= baseLength + toneCurveExtensionLength else { return nil }
        return buf[offsetToneCurveFlag] == 0x02 ? baseLength : nil
    }

    private static func readU32BE(_ buf: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(buf[offset]) << 24)
            | (UInt32(buf[offset + 1]) << 16)
            | (UInt32(buf[offset + 2]) << 8)
            | UInt32(buf[offset + 3])
    }
}
