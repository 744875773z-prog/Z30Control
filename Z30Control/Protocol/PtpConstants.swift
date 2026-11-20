//
//  PtpConstants.swift
//  Z30Control
//
//  尼康 PTP/IP 协议常量定义与专有操作码规范
//

import Foundation

/// PTP/IP 数据包类型 (Packet Types)
public enum PtpIpPacketType: UInt32 {
    case initCommandRequest  = 1
    case initCommandAck      = 2
    case initEventRequest    = 3
    case initEventAck        = 4
    case initFail            = 5
    case cmdRequest          = 6
    case cmdResponse         = 7
    case event               = 8
    case startDataPacket     = 9
    case dataPacket          = 10
    case cancelTransaction   = 11
    case endDataPacket       = 12
    case ping                = 13
    case pong                = 14
}

/// 标准 PTP 与尼康厂商专有操作码 (Operation Codes)
public enum PtpOperationCode: UInt16 {
    // 标准 PTP 操作码
    case getDeviceInfo           = 0x1001
    case openSession             = 0x1002
    case closeSession            = 0x1003
    case getStorageIDs           = 0x1004
    case getStorageInfo          = 0x1005
    case getNumObjects           = 0x1006
    case getObjectHandles        = 0x1007
    case getObjectInfo           = 0x1008
    case getObject               = 0x1009
    case getThumb                = 0x100A
    case deleteObject            = 0x100B
    case sendObjectInfo          = 0x100C
    case sendObject              = 0x100D
    case initiateCapture         = 0x100E
    case getDevicePropDesc       = 0x1014
    case getDevicePropValue      = 0x1015
    case setDevicePropValue      = 0x1016
    case resetDevicePropValue    = 0x1017
    case terminateOpenCapture    = 0x1018
    case getPartialObject        = 0x101B
    
    // 尼康专用扩展操作码 (Nikon Vendor Extensions)
    case nikonGetEvent           = 0x90C7
    case nikonStartLiveView      = 0x9201 // 开启实时取景
    case nikonEndLiveView        = 0x9202 // 结束实时取景
    case nikonGetLiveViewImg     = 0x9203 // 获取实时取景帧
    case nikonMfDrive            = 0x9204 // 手动对焦微调驱动
    case nikonDeviceReady        = 0x90C8 // 检查相机是否就绪
    case nikonAfDrive            = 0x90C1 // 自动对焦驱动
}

/// PTP 事件代码 (Event Codes)
public enum PtpEventCode: UInt16 {
    case cancelTransaction       = 0x4001
    case objectAdded             = 0x4002 // 相机拍下新照片
    case objectRemoved           = 0x4003
    case storeAdded              = 0x4004
    case storeRemoved            = 0x4005
    case devicePropChanged       = 0x4006 // 相机参数变动
    case objectInfoChanged       = 0x4007 // 对象信息变更(如打上保护锁)
    case deviceInfoChanged       = 0x4008
    case requestObjectTransfer   = 0x4009
    case storeFull               = 0x400A
    case deviceReset             = 0x400B
    case storageInfoChanged      = 0x400C
    case captureComplete         = 0x400D
    case nikonDevicePropChanged  = 0xC101 // 尼康专有属性变动
}

/// PTP 响应代码 (Response Codes)
public enum PtpResponseCode: UInt16 {
    case ok                      = 0x2001
    case generalError            = 0x2002
    case sessionNotOpen          = 0x2003
    case invalidTransactionID    = 0x2004
    case operationNotSupported   = 0x2005
    case parameterNotSupported   = 0x2006
    case deviceBusy              = 0x2019
    case accessDenied            = 0x200F
}

/// 相机设备属性代码 (Device Property Codes - DPC)
public enum PtpDevicePropertyCode: UInt16 {
    case batteryLevel            = 0x5001 // 电池电量
    case whiteBalance            = 0x5005 // 白平衡
    case fNumber                 = 0x5007 // 光圈值 (F-Stop)
    case focalLength             = 0x5008 // 镜头焦距 (mm)
    case focusMode               = 0x500A // 对焦模式 (AF-S / AF-C / MF)
    case exposureMeteringMode    = 0x500B // 测光模式 (矩阵/中央/点测光)
    case flashMode               = 0x500C // 闪光灯
    case exposureTime            = 0x500D // 快门速度
    case exposureProgramMode     = 0x500E // 曝光模式 (P / S / A / M)
    case exposureIndex           = 0x500F // ISO 感光度
    case exposureBiasCompensation= 0x5010 // 曝光补偿 (+/- EV)
    case stillCaptureMode        = 0x5013 // 驱动模式 (单张/连拍/自拍)
    
    // 尼康专有优化校准与色彩属性
    case nikonPictureControl     = 0xD1A0 // 优化校准预设 (Standard, Neutral, Vivid 等)
    case nikonActiveDLighting    = 0xD1A1 // 动态 D-Lighting
    case nikonColorSpace         = 0xD01E // 色彩空间 (sRGB / AdobeRGB)
    case nikonRecordingState     = 0xD1B0 // 录制视频状态
    case nikonAfAreaMode         = 0xD08B // 对焦区域模式 (单点/广域等)
}
