//
//  LUTFilter.swift
//  Z30Control
//
//  3D LUT 胶片滤镜与色彩预设模型
//

import Foundation

/// 滤镜分类
public enum LUTCategory: String, CaseIterable {
    case film = "复古胶片"
    case cinema = "电影色调"
    case monochrome = "经典黑白"
    case clean = "人像清透"
    case custom = "用户导入"
}

/// 3D LUT 滤镜实体
public struct LUTFilter: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let category: LUTCategory
    public let subtitle: String
    public var intensity: Float // 浓度 0.0 ~ 1.0 (默认 1.0)
    public let cubeFileName: String? // 本地资源文件名或用户导入路径
    public var isBuiltIn: Bool
    
    public init(
        id: String,
        name: String,
        category: LUTCategory,
        subtitle: String,
        intensity: Float = 1.0,
        cubeFileName: String? = nil,
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.subtitle = subtitle
        self.intensity = intensity
        self.cubeFileName = cubeFileName
        self.isBuiltIn = isBuiltIn
    }
    
    /// 内置的专业经典滤镜库 (开箱即用)
    public static let builtinPresets: [LUTFilter] = [
        LUTFilter(id: "kodak_portra_400", name: "PORTRA 400", category: .film, subtitle: "经典暖调胶片/通透肤色", intensity: 1.0),
        LUTFilter(id: "fuji_classic_chrome", name: "CLASSIC CHROME", category: .film, subtitle: "富士经典正片/低饱和高反差", intensity: 1.0),
        LUTFilter(id: "cinematic_teal_orange", name: "TEAL & ORANGE", category: .cinema, subtitle: "好莱坞青橙电影感", intensity: 0.85),
        LUTFilter(id: "tri_x_400", name: "TRI-X 400 B&W", category: .monochrome, subtitle: "柯达经典高反差黑白", intensity: 1.0),
        LUTFilter(id: "tokyo_clean", name: "TOKYO DAY", category: .clean, subtitle: "日系高光清新蓝调", intensity: 0.8),
        LUTFilter(id: "nordic_mood", name: "NORDIC MOOD", category: .cinema, subtitle: "北欧冷冽氛围暗调", intensity: 0.9)
    ]
}
