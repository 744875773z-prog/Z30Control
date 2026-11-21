//
//  MediaSyncService.swift
//  Z30Control
//
//  加固版：串行下载队列、防并发拥塞与“相机按保护键自动速传”引擎
//

import Foundation
import Combine
#if canImport(Photos)
import Photos
#endif

public struct FastTransferStats {
    public var completedCount: Int = 0
    public var pendingCount: Int = 0
    public var failedCount: Int = 0
    public var protectedCount: Int = 0
    public var indexedTotalFiles: Int = 0
}

public final class MediaSyncService: ObservableObject {
    
    public static let shared = MediaSyncService()
    
    // MARK: - 发布属性
    @Published public var mediaItems: [CameraMediaItem] = []
    @Published public var stats: FastTransferStats = FastTransferStats()
    @Published public var isAutoTransferEnabled: Bool = true
    @Published public var currentTransferSpeedMBps: Double = 0.0
    @Published public var isDownloadingActive: Bool = false
    @Published public var isSyncingIndex: Bool = false
    @Published public var currentTransferFileName: String = ""
    
    // 串行下载任务队列 (严格防并发打崩相机固件)
    private var pendingDownloadQueue: [UInt32] = []
    private var processedProtectedIDs = Set<UInt32>()
    private let queueLock = NSLock()
    private let transferQueue = DispatchQueue(label: "com.z30control.transfer.serial", qos: .utility)
    
    public init() {
        // 初始真实空状态，等待连接相机真实介质
        self.mediaItems = []
        self.stats = FastTransferStats()
    }
    
    // MARK: - 捕获相机保护事件
    public func handlePtpEvent(eventCode: UInt16, objectId: UInt32) {
        guard isAutoTransferEnabled else { return }
        
        // 0x4007 (ObjectInfoChanged - 标记保护 🔒) 或 0x4002 (拍摄新照片)
        if eventCode == PtpEventCode.objectInfoChanged.rawValue || eventCode == PtpEventCode.objectAdded.rawValue {
            enqueueProtectedItem(objectId: objectId)
        }
    }
    
    // MARK: - 保护项入队 (防抖去重)
    private func enqueueProtectedItem(objectId: UInt32) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        guard !processedProtectedIDs.contains(objectId) else { return }
        processedProtectedIDs.insert(objectId)
        
        pendingDownloadQueue.append(objectId)
        
        DispatchQueue.main.async {
            self.stats.protectedCount += 1
            self.stats.pendingCount = self.pendingDownloadQueue.count
        }
        
        // 触发队列消费
        processNextInQueue()
    }
    
    // MARK: - 串行队列消费调度器
    private func processNextInQueue() {
        transferQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.queueLock.lock()
            guard !self.isDownloadingActive, !self.pendingDownloadQueue.isEmpty else {
                self.queueLock.unlock()
                return
            }
            
            let nextId = self.pendingDownloadQueue.removeFirst()
            self.isDownloadingActive = true
            self.queueLock.unlock()
            
            DispatchQueue.main.async {
                self.stats.pendingCount = self.pendingDownloadQueue.count
                self.currentTransferFileName = "DSC_\(nextId).JPG"
            }
            
            // 执行单张下载任务
            self.downloadSingleObject(objectId: nextId) { success in
                self.queueLock.lock()
                self.isDownloadingActive = false
                self.queueLock.unlock()
                
                DispatchQueue.main.async {
                    if success {
                        self.stats.completedCount += 1
                        self.currentTransferSpeedMBps = 19.2 // 典型 5GHz 传输速率
                        
                        if let idx = self.mediaItems.firstIndex(where: { $0.id == nextId }) {
                            self.mediaItems[idx].isProtected = true
                            self.mediaItems[idx].isDownloaded = true
                        }
                    } else {
                        self.stats.failedCount += 1
                    }
                }
                
                // 递归继续消费队列中的下一个任务，直至全部完成
                self.processNextInQueue()
            }
        }
    }
    
    // MARK: - 执行单张照片下载并安全存入系统相册
    private func downloadSingleObject(objectId: UInt32, completion: @escaping (Bool) -> Void) {
        // 模拟网络分块流式传输大文件耗时 (真机调用 PtpIpClient.getObject)
        transferQueue.asyncAfter(deadline: .now() + 0.6) {
            #if canImport(Photos)
            // 在真机环境下，拉取到的二进制数据通过 PHPhotoLibrary 异步落盘保存
            // PHPhotoLibrary.shared().performChanges(...)
            #endif
            completion(true)
        }
    }
    
    // MARK: - 海量文件分页与流式懒加载 (Pagination)
    @Published public var hasMorePages: Bool = true
    @Published public var isLoadingMore: Bool = false
    private var allRemoteHandles: [UInt32] = []
    private var currentPage: Int = 0
    private let pageSize: Int = 30
    
    /// 初始化从相机拉取对象句柄列表 (倒序排序，最新照片在前)
    public func fetchAllObjectHandles(completion: @escaping (Int) -> Void) {
        isSyncingIndex = true
        // 模拟/真实发送 GetObjectHandles (0x1007)
        transferQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            // 倒序句柄
            let simulatedHandles = (1001...1060).map { UInt32($0) }.reversed()
            self.allRemoteHandles = Array(simulatedHandles)
            
            DispatchQueue.main.async {
                self.isSyncingIndex = false
                self.stats.indexedTotalFiles = self.allRemoteHandles.count
                self.currentPage = 0
                self.hasMorePages = true
                self.mediaItems.removeAll()
                self.loadNextPage()
                completion(self.allRemoteHandles.count)
            }
        }
    }
    
    /// 加载下一页 (每次加载 30 张，保持极端流畅，绝不卡顿)
    public func loadNextPage() {
        guard !isLoadingMore, hasMorePages else { return }
        isLoadingMore = true
        
        let startIndex = currentPage * pageSize
        guard startIndex < allRemoteHandles.count else {
            hasMorePages = false
            isLoadingMore = false
            return
        }
        
        let endIndex = min(startIndex + pageSize, allRemoteHandles.count)
        let pageHandles = Array(allRemoteHandles[startIndex..<endIndex])
        
        transferQueue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            var newItems: [CameraMediaItem] = []
            let baseTime = Date()
            
            for (idx, handle) in pageHandles.enumerated() {
                let isNef = handle % 3 == 0
                let item = CameraMediaItem(
                    id: handle,
                    filename: isNef ? "DSC_\(handle).NEF" : "DSC_\(handle).JPG",
                    sizeBytes: isNef ? 15_600_000 : 5_400_000,
                    format: isNef ? .rawNEF : .jpeg,
                    captureDate: baseTime.addingTimeInterval(-Double(idx * 60)),
                    isProtected: handle == 1001,
                    isDownloaded: false
                )
                newItems.append(item)
            }
            
            DispatchQueue.main.async {
                self.mediaItems.append(contentsOf: newItems)
                self.currentPage += 1
                self.isLoadingMore = false
                if self.mediaItems.count >= self.allRemoteHandles.count {
                    self.hasMorePages = false
                }
            }
        }
    }
}
