//
//  MediaSyncService.swift
//  Z30Control
//
//  串行下载队列、防并发拥塞与“相机按保护键自动速传”引擎（v1.0.3 修复版）
//  本次修复：
//  1. fetchAllObjectHandles 改为真实调用：GetStorageIDs -> GetObjectHandles
//     -> 逐个 GetObjectInfo，之前是凭空编造 1001...1060 号假句柄和假文件名。
//  2. downloadSingleObject 改为真实调用 GetObject 下载原图并存入相册，
//     之前是等 0.6 秒就谎报成功，什么都没下载。
//  3. loadNextPage 改为从真实拉取的列表分页，之前按假句柄编造文件名和大小。
//  4. 新增 downloadAndSaveToPhotos：供图库详情页“保存原图”按钮真实下载。
//  5. 传输速度按真实字节数/耗时计算，之前是写死的 19.2 MB/s。
//  注意：GetObjectInfo 逐个串行拉取是刻意的——PTP 同一时间只允许一个
//  事务在途，并发拉取会让相机回 DeviceBusy (0x2019)。
//

import Foundation
import Combine
import ImageCaptureCore
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
    
    // 真实从相机拉取的完整列表（最新在前），分页从这里取
    private var fetchedItems: [CameraMediaItem] = []
    
    private var ptpClient: PtpIpClient { CameraConnectionService.shared.client }
    
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
                self.currentTransferFileName = self.fetchedItems.first(where: { $0.id == nextId })?.filename ?? "DSC_\(nextId).JPG"
            }
            
            // 执行单张下载任务
            self.downloadSingleObject(objectId: nextId) { success in
                self.queueLock.lock()
                self.isDownloadingActive = false
                self.queueLock.unlock()
                
                DispatchQueue.main.async {
                    if success {
                        self.stats.completedCount += 1
                        
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
        let started = Date()
        ptpClient.getObject(handle: objectId) { [weak self] data in
            guard let self = self, let data = data else { completion(false); return }
            let filename = self.fetchedItems.first(where: { $0.id == objectId })?.filename ?? "DSC_\(objectId).JPG"
            self.saveDataToPhotosOrFiles(data, filename: filename) { ok in
                if ok {
                    let elapsed = Date().timeIntervalSince(started)
                    if elapsed > 0 {
                        let mbps = Double(data.count) / elapsed / 1_000_000
                        DispatchQueue.main.async { self.currentTransferSpeedMBps = mbps }
                    }
                }
                completion(ok)
            }
        }
    }
    
    /// 图库详情页“保存原图”调用：真实从相机下载并存入相册/文稿
    public func downloadAndSaveToPhotos(item: CameraMediaItem, completion: @escaping (Bool) -> Void) {
        // v1.0.4：USB 来源走 ImageCaptureCore 下载（之前只认 PTP 句柄，USB 的 item 根本下不下来）
        if let usbName = item.usbFilename {
            UsbCameraManager.shared.downloadUSBFile(named: usbName) { [weak self] data in
                guard let self = self else { completion(false); return }
                // v1.0.14：ICC 目录里没有这张（PTP 兜底列出来的），改按句柄走 PTP 取原图
                if let data = data {
                    self.saveDataToPhotosOrFiles(data, filename: item.filename) { ok in
                        if ok {
                            DispatchQueue.main.async {
                                if let idx = self.mediaItems.firstIndex(where: { $0.id == item.id }) {
                                    self.mediaItems[idx].isDownloaded = true
                                }
                                self.stats.completedCount += 1
                            }
                        }
                        completion(ok)
                    }
                } else if let handle = item.ptpHandle {
                    // 只有 PTP 兜底列出来的项目才有真句柄，拿它取原图；
                    // ICC 目录的项目没有句柄，ICC 下不来就真的下不来。
                    UsbCameraManager.shared.downloadRawObjectData(handle: handle, filename: item.filename) { [weak self] rawData in
                        guard let self = self, let rawData = rawData else { completion(false); return }
                        self.saveDataToPhotosOrFiles(rawData, filename: item.filename) { ok in
                            if ok {
                                DispatchQueue.main.async {
                                    if let idx = self.mediaItems.firstIndex(where: { $0.id == item.id }) {
                                        self.mediaItems[idx].isDownloaded = true
                                    }
                                    self.stats.completedCount += 1
                                }
                            }
                            completion(ok)
                        }
                    }
                }
            }
            return
        }
        ptpClient.getObject(handle: item.id) { [weak self] data in
            guard let self = self, let data = data else { completion(false); return }
            self.saveDataToPhotosOrFiles(data, filename: item.filename) { ok in
                if ok {
                    DispatchQueue.main.async {
                        if let idx = self.mediaItems.firstIndex(where: { $0.id == item.id }) {
                            self.mediaItems[idx].isDownloaded = true
                        }
                        self.stats.completedCount += 1
                    }
                }
                completion(ok)
            }
        }
    }
    
    /// JPEG/视频存入系统相册；NEF 无法直接写入相册，存到 App 文稿目录
    private func saveDataToPhotosOrFiles(_ data: Data, filename: String, completion: @escaping (Bool) -> Void) {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "nef" {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                completion(true)
            } catch {
                completion(false)
            }
            return
        }
        let isVideo = (ext == "mov" || ext == "mp4")
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: isVideo ? .video : .photo, data: data, options: nil)
        }) { success, _ in
            completion(success)
        }
    }
    
    // MARK: - 从相机拉取文件索引（真实 PTP 调用）
    
    /// 供连接成功后与图库页主动调用：刷新相机卡内文件列表
    public func refreshIndexFromCamera() {
        // v1.0.4：USB 下图库之前永远 0 张——它只走 Wi-Fi PTP/IP。
        // USB 时直接用 ImageCaptureCore 的卡目录。
        if UsbCameraManager.shared.isUsbConnected {
            refreshFromUSB()
            return
        }
        fetchAllObjectHandles()
    }

    /// USB：把 ImageCaptureCore 的卡目录映射成图库列表
    public func refreshFromUSB() {
        let files = UsbCameraManager.shared.usbMediaFiles
        // v1.0.14：ICC 目录还没到（刚连上、目录投递慢）时，图库之前直接显示
        // 0 张。目录为空就改走 PTP 直接列卡，不用等目录。
        guard !files.isEmpty else {
            refreshFromUSBViaPTP()
            return
        }
        let items: [CameraMediaItem] = files.map { file in
            let name = file.name ?? "DSC_NEW.JPG"
            let ext = (name as NSString).pathExtension.lowercased()
            return CameraMediaItem(
                id: UInt32(truncatingIfNeeded: name.hashValue),
                filename: name,
                sizeBytes: UInt64(file.fileSize),
                format: Self.format(for: ext),
                captureDate: file.creationDate ?? Date(),
                isProtected: false,
                usbFilename: name
            )
        }
        // 文件名 DSC_xxxx 递增即拍摄顺序，倒序后最新在前
        let ordered = items.sorted(by: { $0.filename > $1.filename })
        DispatchQueue.main.async {
            self.fetchedItems = ordered
            self.isSyncingIndex = false
            self.stats.indexedTotalFiles = ordered.count
            self.currentPage = 0
            self.hasMorePages = true
            self.mediaItems.removeAll()
            self.loadNextPage()
        }
    }

    /// USB 图库兜底：ICC 目录为空时，用 PTP 直接列卡里的文件。
    /// 这里的 item.id 就是 PTP 对象句柄，下载时 ICC 找不到就走 PTP 取原图。
    private func refreshFromUSBViaPTP() {
        guard !isSyncingIndex else { return }
        isSyncingIndex = true
        UsbCameraManager.shared.fetchCardItemsViaPTP { [weak self] entries in
            guard let self = self else { return }
            let items: [CameraMediaItem] = entries.map { e in
                let ext = (e.filename as NSString).pathExtension.lowercased()
                return CameraMediaItem(
                    id: e.handle,
                    filename: e.filename,
                    sizeBytes: e.sizeBytes,
                    format: Self.format(for: ext),
                    captureDate: Date(),
                    isProtected: false,
                    usbFilename: e.filename,
                    ptpHandle: e.handle
                )
            }
            DispatchQueue.main.async {
                self.fetchedItems = items
                self.isSyncingIndex = false
                self.stats.indexedTotalFiles = items.count
                self.currentPage = 0
                self.hasMorePages = true
                self.mediaItems.removeAll()
                self.loadNextPage()
            }
        }
    }

    private static func format(for ext: String) -> MediaFormatType {
        switch ext {
        case "nef": return .rawNEF
        case "mov": return .videoMOV
        case "mp4": return .videoMP4
        default: return .jpeg
        }
    }

    /// 读存储卡容量与电量（USB 与 Wi-Fi 各走各的真读，读不到就保持未知、不编数）
    public func refreshStorageFromCamera() {
        if UsbCameraManager.shared.isUsbConnected {
            UsbCameraManager.shared.refreshStorageInfo()
            UsbCameraManager.shared.refreshBatteryLevel()
            return
        }
        guard ptpClient.isSessionOpen else { return }
        ptpClient.getStorageIDs { [weak self] ids in
            guard let self = self, let first = ids.first else { return }
            self.ptpClient.getStorageInfo(storageID: first) { info in
                guard let info = info else { return }
                let state = CameraConnectionService.shared.cameraState
                DispatchQueue.main.async {
                    state.cardTotalGB = Double(info.maxCapacity) / 1_000_000_000
                    state.cardUsedGB = Double(info.maxCapacity - info.freeBytes) / 1_000_000_000
                    state.remainingShots = info.freeImages == 0xFFFFFFFF
                        ? Int(info.freeBytes / 25_000_000)
                        : Int(info.freeImages)
                    state.storageKnown = true
                }
            }
        }
        ptpClient.getDevicePropValue(code: 0x5001) { data in
            guard let data = data, let first = data.first else { return }
            let state = CameraConnectionService.shared.cameraState
            DispatchQueue.main.async {
                state.batteryPercentage = Int(first)
                state.batteryKnown = true
            }
        }
    }
    
    /// 初始化从相机拉取对象句柄列表 (倒序排序，最新照片在前)
    public func fetchAllObjectHandles(completion: @escaping (Int) -> Void = { _ in }) {
        guard !isSyncingIndex else { return }
        guard ptpClient.isSessionOpen else { completion(0); return }
        isSyncingIndex = true
        ptpClient.getStorageIDs { [weak self] storageIDs in
            guard let self = self else { return }
            let storageID = storageIDs.first ?? 0xFFFFFFFF
            self.ptpClient.getObjectHandles(storageID: storageID) { handles in
                // PTP 句柄按拍摄顺序递增，倒序后最新照片在前
                let ordered = handles.sorted(by: >)
                self.allRemoteHandles = ordered
                self.fetchInfoSequentially(handles: ordered, index: 0, accumulated: []) { items in
                    DispatchQueue.main.async {
                        self.fetchedItems = items
                        self.isSyncingIndex = false
                        self.stats.indexedTotalFiles = ordered.count
                        self.currentPage = 0
                        self.hasMorePages = true
                        self.mediaItems.removeAll()
                        self.loadNextPage()
                        completion(ordered.count)
                    }
                }
            }
        }
    }
    
    /// 逐个串行拉取 GetObjectInfo（刻意串行，避免 DeviceBusy）
    private func fetchInfoSequentially(handles: [UInt32], index: Int, accumulated: [CameraMediaItem], done: @escaping ([CameraMediaItem]) -> Void) {
        guard index < handles.count else { done(accumulated); return }
        ptpClient.getObjectInfo(handle: handles[index]) { [weak self] info in
            guard let self = self else { return }
            var next = accumulated
            if let info = info { next.append(Self.makeItem(from: info)) }
            self.fetchInfoSequentially(handles: handles, index: index + 1, accumulated: next, done: done)
        }
    }
    
    private static func makeItem(from info: PtpObjectInfo) -> CameraMediaItem {
        let ext = (info.filename as NSString).pathExtension.lowercased()
        return CameraMediaItem(
            id: info.handle,
            filename: info.filename,
            sizeBytes: info.sizeBytes,
            format: Self.format(for: ext),
            captureDate: info.captureDate ?? Date(),
            isProtected: info.protectionStatus != 0,
            thumbData: nil,
            isDownloaded: false
        )
    }
    
    // MARK: - v1.0.6：图库一次上全部（之前每页只上 30 张，又没有任何地方翻页，
    // 图库永远只看到前 30 张。列表本身只是文件名/大小/日期，全部放内存没压力；
    // 视图是 LazyVGrid/LazyVStack，只渲染看得见的行，不会卡）
    @Published public var hasMorePages: Bool = true
    @Published public var isLoadingMore: Bool = false
    private var allRemoteHandles: [UInt32] = []
    private var currentPage: Int = 0

    /// 上全部剩余项（不再按 30 张分页）
    public func loadNextPage() {
        guard !isLoadingMore, hasMorePages else { return }
        isLoadingMore = true

        let remaining = Array(fetchedItems.dropFirst(mediaItems.count))
        guard !remaining.isEmpty else {
            hasMorePages = false
            isLoadingMore = false
            return
        }

        DispatchQueue.main.async {
            self.mediaItems.append(contentsOf: remaining)
            self.currentPage += 1
            self.isLoadingMore = false
            self.hasMorePages = false
        }
    }
}
