//
//  CameraMediaItem.swift
//  Z30Control
//
//  相机 SD 卡照片/视频文件对象与速传数据模型
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 媒体格式类型
public enum MediaFormatType: String, CaseIterable {
    case jpeg = "JPEG"
    case rawNEF = "NEF (RAW)"
    case rawPlusJpeg = "RAW+JPEG"
    case videoMOV = "MOV (Video)"
    case videoMP4 = "MP4 (Video)"
}

/// 相机存储卡内的单个媒体文件
public struct CameraMediaItem: Identifiable, Equatable {
    /// PTP 内部对象句柄 ID
    public let id: UInt32
    
    /// 文件名 (例如 "DSC_0128.JPG", "DSC_0129.NEF")
    public let filename: String
    
    /// 文件字节大小
    public let sizeBytes: UInt64
    
    /// 媒体格式
    public let format: MediaFormatType
    
    /// 拍摄生成日期
    public let captureDate: Date
    
    /// 是否已被相机标记为保护 (Protect Lock 🔒) - 核心用于“按相机保护键速传”!
    public var isProtected: Bool
    
    /// 缩略图二进制缓存
    public var thumbData: Data?
    
    /// 是否已经成功下载保存到手机相册
    public var isDownloaded: Bool
    
    /// 连拍序列张数标记 (可选)
    public var burstCount: Int?
    
    public init(
        id: UInt32,
        filename: String,
        sizeBytes: UInt64,
        format: MediaFormatType,
        captureDate: Date = Date(),
        isProtected: Bool = false,
        thumbData: Data? = nil,
        isDownloaded: Bool = false,
        burstCount: Int? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.format = format
        self.captureDate = captureDate
        self.isProtected = isProtected
        self.thumbData = thumbData
        self.isDownloaded = isDownloaded
        self.burstCount = burstCount
    }
    
    /// 友好的文件大小文本 (例如 "14.8 MB")
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }
    
    /// 格式化拍摄时间
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: captureDate)
    }
}
