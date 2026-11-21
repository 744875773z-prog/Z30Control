//
//  CameraState.swift
//  Z30Control
//
//  尼康 Z30 硬件状态、曝光参数与仪表盘数据模型
//

import Foundation
import Combine

/// 曝光模式
/// v1.0.14：补上 AUTO 和 U1/U2/U3。0x500E 的标准值是 1=M、2=P、3=A、4=S；
/// AUTO/U1/U2/U3 是尼康厂商值，按尼康厂商区 0x8010 起排推断为
/// 0x8010=AUTO、0x8011=U1、0x8012=U2、0x8013=U3（白平衡的厂商值
/// 0x8010/0x8011 已在开源项目里证实是这个区段）。真机拨盘验证中：
/// 若某档显示成原始值（如 0x8014），把控制页诊断行的原始值发回来再改。
public enum ExposureMode: String, CaseIterable {
    case manual = "M 手动"
    case aperturePriority = "A 光圈优先"
    case shutterPriority = "S 快门优先"
    case program = "P 自动"
    case auto = "AUTO 自动"
    case user1 = "U1"
    case user2 = "U2"
    case user3 = "U3"
    case unknown = "未知"

    /// 模式药丸上显示的短标签（AUTO/U1/U2/U3 不能只取首字母，会和 A 档撞）
    public var shortLabel: String {
        switch self {
        case .manual: return "M"
        case .aperturePriority: return "A"
        case .shutterPriority: return "S"
        case .program: return "P"
        case .auto: return "AUTO"
        case .user1: return "U1"
        case .user2: return "U2"
        case .user3: return "U3"
        case .unknown: return "?"
        }
    }
}

/// 对焦模式
public enum FocusMode: String, CaseIterable {
    case afSingle = "AF-S"
    case afContinuous = "AF-C"
    case afAuto = "AF-A"
    case manual = "MF 手动"
}

/// 测光模式
public enum MeteringMode: String, CaseIterable {
    case matrix = "矩阵测光"
    case centerWeighted = "中央重点"
    case spot = "点测光"
    case highlightWeighted = "亮部重点"
}

/// 白平衡预设
public enum WhiteBalanceMode: String, CaseIterable {
    case auto = "自动"
    case daylight = "晴天 (5200K)"
    case cloudy = "阴天 (6000K)"
    case shade = "阴影 (7000K)"
    case incandescent = "白炽灯 (3000K)"
    case fluorescent = "荧光灯"
    case customKelvin = "色温 K"
}

/// 尼康优化校准预设 (Picture Control)
public enum PictureControlMode: String, CaseIterable {
    case auto = "自动 (Auto)"
    case standard = "标准 (Standard)"
    case neutral = "自然 (Neutral)"
    case vivid = "鲜明 (Vivid)"
    case monochrome = "单色 (Monochrome)"
    case portrait = "人像 (Portrait)"
    case landscape = "风景 (Landscape)"
    case flat = "平面 (Flat)"
    case creativeFilm = "创意胶片配方"
}

/// 核心相机状态监控与中控台数据源 (ObservableObject)
public final class CameraState: ObservableObject {
    
    // MARK: - 基础硬件信息（v1.0.4：默认值全部改为“未知”，绝不编数）
    @Published public var modelName: String = "NIKON Z30"
    @Published public var firmwareVersion: String = "FW V1.11"
    @Published public var serialNumber: String = "SN 7029182"
    @Published public var lensName: String = "NIKKOR Z DX 16-50mm f/3.5-6.3 VR"
    // 电量：nil = 还没从相机读到。之前默认 85% 是假数，读失败也一直显示 85%。
    @Published public var batteryPercentage: Int = 0
    @Published public var batteryKnown: Bool = false
    @Published public var isCharging: Bool = false
    @Published public var temperatureStatus: String = "温度正常"
    
    // MARK: - 连接状态
    @Published public var isConnected: Bool = false
    @Published public var connectionType: String = "Wi-Fi 5GHz"
    @Published public var ipAddress: String = "192.168.0.1"
    
    // MARK: - 存储卡状态 (Z30 为单 SD 卡槽)
    // v1.0.4：之前默认 64GB/23.5GB/2840 张是写死的假数，全工程没任何地方读卡。
    // 现在默认 0 + storageKnown=false，未读到之前界面显示“--”，绝不编数。
    @Published public var cardTotalGB: Double = 0
    @Published public var cardUsedGB: Double = 0
    @Published public var remainingShots: Int = 0
    @Published public var storageKnown: Bool = false
    public var cardUsagePercent: Int {
        guard cardTotalGB > 0 else { return 0 }
        return Int((cardUsedGB / cardTotalGB) * 100)
    }
    
    // MARK: - 曝光参数仪表盘 (连接前显示 --，连接后由 PTP 真实赋值)
    @Published public var shutterSpeed: String = "--"
    @Published public var aperture: String = "--"
    @Published public var isoBase: String = "--"
    @Published public var isoActual: String = "--"
    @Published public var isAutoISO: Bool = false
    
    @Published public var exposureMode: ExposureMode = .manual
    /// 最近一次从相机读到的 0x500E 原始值（模式识别不出来时，界面显示这个值，方便对表）
    @Published public var exposureModeRaw: UInt16 = 0
    @Published public var whiteBalance: WhiteBalanceMode = .auto
    @Published public var meteringMode: MeteringMode = .matrix
    @Published public var exposureCompensation: String = "--"
    @Published public var focusMode: FocusMode = .afContinuous
    @Published public var afAreaMode: String = "单点 AF"
    
    // MARK: - 色彩与滤镜模式
    @Published public var pictureControl: PictureControlMode = .standard
    @Published public var colorSpace: String = "sRGB"
    @Published public var imageQuality: String = "RAW + JPEG (Fine)"
    @Published public var resolution: String = "5568x3712"
    
    // MARK: - 实时拍摄状态
    @Published public var isRecordingVideo: Bool = false
    @Published public var recordingSeconds: Int = 0
    @Published public var isLiveViewActive: Bool = false
    
    public init() {}
    
    /// 断开连接时清空读到的状态（v1.0.4：之前这里会填 1/125、f/4.0、400 等假参数，
    /// 且没有任何地方调用；改成清零+未知，避免以后有人误用假数）
    public func resetToDefaults() {
        shutterSpeed = "--"
        aperture = "--"
        isoActual = "--"
        exposureCompensation = "--"
        batteryPercentage = 0
        batteryKnown = false
        cardTotalGB = 0
        cardUsedGB = 0
        remainingShots = 0
        storageKnown = false
        isLiveViewActive = false
    }
}
