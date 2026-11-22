//
//  PictCtrlPayload.swift
//  Z30Control
//
//  v1.0.28：机身优化校准 614 字节载荷的构建与解析。
//  移植自 haotiandi1011-lgtm/1dlut-z30-filters（MIT）的 z30fit/payload.py，
//  布局照抄 z-cloud-ai 的 PcPayload614.fallbackTemplate（真机 0x90CC 读回
//  Fuji Provia / Astia 逐字节比对出来的骨架）。
//
//  布局：
//    +0x000   2   版本 02 00
//    +0x002  20   ASCII 名称（NUL 补齐，中文进载荷会变 ?，UI 上拦住）
//    +0x016   2   保留
//    +0x018   7   参数区：快速锐化（1/级）、锐化/中等锐化/清晰度/饱和度（0.25/级，int8），
//                 对比度/亮度在有自定义曲线时被机身禁用，恒 0
//    +0x01F   4   保留 0
//    +0x023   1   0x01 标志位
//    +0x024   2   "I0" 机型/系列标记
//    +0x026   1   0
//    +0x027   1   0xFF
//    +0x028   1   0
//    +0x029   1   0xFF
//    +0x02A   1   0x01
//    +0x02B   1   0x0F
//    +0x02C   1   族标记（0x05 可用）
//    +0x02D   2   保留
//    +0x02F   8   4 组 (x, y) 控制点，仅用于机身 LCD 画曲线，不影响成像
//    +0x037  47   保留 0
//    +0x066 512   256 × u16 大端 LUT，值域 0..32767 ← 成像真值
//    ----------  0x66 + 512 = 0x266 = 614
//

import Foundation

/// 机身 C 槽：C1–C9 对应槽位号 0x00C9–0x00D1（1dlut 项目实测，不是传闻的 0x00CB–0x00D3）
public enum PictCtrlSlot: Int, CaseIterable, Identifiable {
    case c1 = 1, c2, c3, c4, c5, c6, c7, c8, c9

    public var id: Int { rawValue }
    /// PTP 槽位号
    public var code: UInt32 { UInt32(0x00C8 + rawValue) }
    public var label: String { "C\(rawValue)" }
}

public enum PictCtrlPayload {
    public static let size = 614
    public static let lutOffset = 0x066
    public static let lutBytes = 512
    public static let lutMax = 32767
    public static let nameOffset = 0x002
    public static let nameLength = 20
    public static let controlPointsOffset = 0x02F

    /// 参数区偏移（1dlut 真机回读验证：顺序与机身菜单一致）
    public enum Param: UInt8 {
        case quickSharp = 0x18  // 快速锐化，1/级
        case sharp = 0x19       // 锐化，0.25/级
        case midSharp = 0x1A    // 中等锐化，0.25/级
        case clarity = 0x1B     // 清晰度，0.25/级
        case contrast = 0x1C    // 对比度，有曲线时被机身禁用，恒 0
        case brightness = 0x1D  // 亮度，有曲线时被机身禁用，恒 0
        case saturation = 0x1E  // 饱和度，0.25/级

        var step: Double {
            self == .quickSharp ? 1.0 : 0.25
        }
    }

    /// 参数值 → 字节（有符号补码）：round(value / step) & 0xFF。
    /// 例：sharp 9.0 → 0x24，clarity −5.0 → 0xEC，saturation 3.0 → 0x0C。
    public static func encodeParam(_ value: Double, param: Param) -> UInt8 {
        UInt8(Int(round(value / param.step)) & 0xFF)
    }

    /// 参数字节 → 值。
    public static func decodeParam(_ raw: UInt8, param: Param) -> Double {
        let v = raw < 128 ? Int(raw) : Int(raw) - 256
        return (Double(v) * param.step * 100).rounded() / 100
    }

    /// fallback 模板：614 字节骨架（其余字节全 0）。
    /// 注意模板自带锐化 +2（0x019=0x08）、中等锐化 +1（0x01A=0x04）的默认值，
    /// 调用方用 setParams 覆盖参数区时会被改掉。
    public static func fallbackTemplate(family: UInt8 = 0x05) -> Data {
        var p = Data(count: size)
        p[0x000] = 0x02
        p[0x001] = 0x00
        p[0x019] = 0x08
        p[0x01A] = 0x04
        p[0x023] = 0x01
        p[0x024] = 0x49 // "I"
        p[0x025] = 0x30 // "0"
        p[0x027] = 0xFF
        p[0x029] = 0xFF
        p[0x02A] = 0x01
        p[0x02B] = 0x0F
        p[0x02C] = family
        return p
    }

    /// 曲线 → 614 字节载荷。curve 为 256 点，0..1 或 0..32767 均可。
    /// name 必须是 ASCII（超长截断到 20 字节，NUL 补齐）；中文请在 UI 层拦住。
    public static func buildPayload(curve: [Double], name: String, family: UInt8 = 0x05,
                                    params: [Param: Double]? = nil) -> Data? {
        guard curve.count == 256 else { return nil }
        let table: [Int] = curve.map { v in
            let scaled = v <= 1.0 + 1e-9 ? v * Double(lutMax) : v
            return max(0, min(lutMax, Int(scaled.rounded())))
        }
        var out = fallbackTemplate(family: family)
        // 名称：ASCII，截断到 20 字节，NUL 补齐
        let ascii = name.unicodeScalars.filter { $0.value < 128 }.map { UInt8($0.value) }
        let nameBytes = Array(ascii.prefix(nameLength))
        for i in 0..<nameLength {
            out[nameOffset + i] = i < nameBytes.count ? nameBytes[i] : 0
        }
        // 控制点：x 在 0.2/0.4/0.6/0.8 处插值，8 位量化（只影响 LCD 曲线图）
        let cps = controlPoints(table: table)
        for i in 0..<4 {
            out[controlPointsOffset + i * 2] = cps[i].0
            out[controlPointsOffset + i * 2 + 1] = cps[i].1
        }
        // LUT：256 × u16 大端
        for i in 0..<256 {
            let v = UInt16(table[i])
            out[lutOffset + i * 2] = UInt8(v >> 8)
            out[lutOffset + i * 2 + 1] = UInt8(v & 0xFF)
        }
        // 参数区（有则覆盖模板默认值）
        if let params = params {
            for (key, value) in params {
                out[Int(key.rawValue)] = encodeParam(value, param: key)
            }
        }
        return out
    }

    /// LCD 画图用的 4 组 (x, y)，8 位量化。只影响屏幕显示，不影响成像。
    public static func controlPoints(table: [Int]) -> [(UInt8, UInt8)] {
        let xs: [Double] = [0.2, 0.4, 0.6, 0.8]
        return xs.map { x in
            let pos = x * Double(table.count - 1)
            let lo = Int(pos)
            let hi = min(lo + 1, table.count - 1)
            let frac = pos - Double(lo)
            let y = Double(table[lo]) * (1 - frac) + Double(table[hi]) * frac
            return (UInt8((x * 255).rounded()), UInt8(((y / Double(lutMax)) * 255).rounded()))
        }
    }

    // MARK: - 解析 / 槽位分类

    /// 读回的槽内容分类（1dlut 项目的三分法）
    public enum SlotContent: Equatable {
        case empty          // 全零 = 空槽
        case paramsOnly     // 36 字节 = 只有参数（相机菜单里手动建的），无曲线
        case full(name: String) // 614 字节 = 完整配方
        case unknown(bytes: Int) // 其他长度：不敢碰
    }

    public static func classify(_ data: Data?) -> SlotContent? {
        guard let data = data else { return nil }
        if data.count == 0 { return .empty }
        if data.allSatisfy({ $0 == 0 }) { return .empty }
        if data.count == 36 { return .paramsOnly }
        if data.count == size { return .full(name: parseName(data) ?? "") }
        return .unknown(bytes: data.count)
    }

    /// 载荷里的配方名（ASCII，NUL 截断）
    public static func parseName(_ data: Data) -> String? {
        guard data.count >= nameOffset + nameLength else { return nil }
        let raw = data.subdata(in: nameOffset..<(nameOffset + nameLength))
        let trimmed = raw.prefix(while: { $0 != 0 })
        return String(bytes: trimmed, encoding: .ascii)
    }

    /// LUT 段读成 256 点（u16 大端）
    public static func parseLUT(_ data: Data) -> [Int]? {
        guard data.count >= lutOffset + lutBytes else { return nil }
        var out: [Int] = []
        out.reserveCapacity(256)
        for i in 0..<256 {
            let hi = Int(data[lutOffset + i * 2])
            let lo = Int(data[lutOffset + i * 2 + 1])
            out.append((hi << 8) | lo)
        }
        return out
    }
}
