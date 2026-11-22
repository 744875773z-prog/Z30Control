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

    // v1.0.17：图库缩略图与下载兜底用的文件名→PTP 句柄映射表。
    // ICC 目录列出来的项目没有句柄，靠这张表把文件名翻译成句柄，
    // 再用 PTP GetThumb 取缩略图、GetObject 取原图。
    private var filenameHandleMap: [String: UInt32] = [:]
    private var handleMapLoading = false

    // 缩略图缓存（按项目 id，存 JPEG 数据）+ 在途去重 + 等映射表的挂起请求。
    // PTP 同一时间只允许一个事务在途，并发取图会让相机回 DeviceBusy，
    // 所以取图走串行队列，一次只取一张。
    private var thumbCache: [UInt32: Data] = [:]
    private var thumbInFlight: Set<UInt32> = []
    private var thumbWaiters: [UInt32: [(Data?) -> Void]] = [:]
    private var thumbPending: [(item: CameraMediaItem, completion: (Data?) -> Void)] = []
    private let thumbQueue = DispatchQueue(label: "com.z30control.thumbs.serial", qos: .utility)

    // v1.0.19：钉住刚拍的照片——拍后复查插进来的项目，在下一次目录刷新
    // （ICC 目录投递慢、新文件还没进目录）时会被整表替换冲掉，图库里
    // 就看不到刚拍的照片。钉住的项目在刷新后重新合并到列表最前面，
    // 直到它出现在目录里为止（最多钉 50 张）。
    private var pinnedCapturedItems: [CameraMediaItem] = []

    // v1.0.19：等句柄映射表建好的回调（批量删除要用映射表翻译句柄）。
    private var handleMapWaiters: [() -> Void] = []
    
    private var ptpClient: PtpIpClient { CameraConnectionService.shared.client }
    
    public init() {
        // 初始真实空状态，等待连接相机真实介质
        self.mediaItems = []
        self.stats = FastTransferStats()
    }
    
    // v1.0.39：新照片出现时的轻量观察者（拍后滤镜版保存用）。
    // Wi-Fi 的 ObjectAdded 事件、USB 拍后复查插进图库的新对象都走这里；
    // 只通知句柄，不下载、不改列表。观察者自己负责线程切换。
    private var objectAddedObservers: [UUID: (UInt32) -> Void] = [:]
    private let objectAddedObserversLock = NSLock()

    public func addObjectAddedObserver(_ observer: @escaping (UInt32) -> Void) -> UUID {
        objectAddedObserversLock.lock()
        defer { objectAddedObserversLock.unlock() }
        let id = UUID()
        objectAddedObservers[id] = observer
        return id
    }

    public func removeObjectAddedObserver(_ id: UUID) {
        objectAddedObserversLock.lock()
        defer { objectAddedObserversLock.unlock() }
        objectAddedObservers.removeValue(forKey: id)
    }

    private func notifyObjectAdded(_ handle: UInt32) {
        objectAddedObserversLock.lock()
        let observers = Array(objectAddedObservers.values)
        objectAddedObserversLock.unlock()
        for o in observers { o(handle) }
    }

    // MARK: - 捕获相机保护事件
    public func handlePtpEvent(eventCode: UInt16, objectId: UInt32) {
        // v1.0.39：先通知观察者（拍后滤镜版保存），不管自动速传开没开。
        if eventCode == PtpEventCode.objectAdded.rawValue {
            notifyObjectAdded(objectId)
        }
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
    /// v1.0.17：取一张图库项目的原图数据（JPEG/NEF/视频都原样返回）。
    /// USB：先走 ICC 下载；ICC 下不来（-9934）就按句柄走 PTP GetObject
    /// （句柄优先用项目自带的，没有就查文件名→句柄映射表）。
    /// Wi-Fi：直接 PTP GetObject。任何路都保证调一次 completion。
    public func downloadOriginalData(item: CameraMediaItem, completion: @escaping (Data?) -> Void) {
        if let usbName = item.usbFilename {
            UsbCameraManager.shared.downloadUSBFile(named: usbName) { [weak self] data in
                guard let self = self else { completion(nil); return }
                if let data = data { completion(data); return }
                let handle = item.ptpHandle ?? self.filenameHandleMap[item.filename]
                guard let handle = handle else { completion(nil); return }
                UsbCameraManager.shared.downloadRawObjectData(handle: handle, filename: item.filename) { raw in
                    completion(raw)
                }
            }
            return
        }
        ptpClient.getObject(handle: item.id) { data in
            completion(data)
        }
    }

    public func downloadAndSaveToPhotos(item: CameraMediaItem, completion: @escaping (Bool) -> Void) {
        // v1.0.17：下载收敛到 downloadOriginalData。之前这里 ICC 失败且
        // 项目没句柄时直接没了下文，completion 永远不调，详情页按钮
        // “正在从相机下载…”转到天荒地老。现在任何结果都有答复。
        downloadOriginalData(item: item) { [weak self] data in
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

    /// v1.0.18：拍完照直接进图库——速传删了，成片不再先下载再进速传，
    /// 而是查到新文件就直接插进图库列表最前面（文件名去重，重复的不插）。
    /// 插进来的项目和 ICC 目录列出来的一样用文件名哈希做 id，目录刷新
    /// 后两者是同一张，不会重复；缩略图靠句柄（有就直接取，没句柄就等映射表）。
    public func insertCapturedItem(filename: String, sizeBytes: UInt64, ptpHandle: UInt32? = nil, usbFilename: String? = nil) {
        let ext = (filename as NSString).pathExtension.lowercased()
        let item = CameraMediaItem(
            id: UInt32(truncatingIfNeeded: filename.hashValue),
            filename: filename,
            sizeBytes: sizeBytes,
            format: Self.format(for: ext),
            captureDate: Date(),
            usbFilename: usbFilename ?? filename,
            ptpHandle: ptpHandle
        )
        DispatchQueue.main.async {
            guard !self.fetchedItems.contains(where: { $0.filename == filename }) else { return }
            self.fetchedItems.insert(item, at: 0)
            self.mediaItems.insert(item, at: 0)
            self.stats.indexedTotalFiles = self.fetchedItems.count
            // v1.0.39：USB 拍后复查插进来的新对象也通知观察者（拍后滤镜版保存认新照片用）。
            if let handle = ptpHandle { self.notifyObjectAdded(handle) }
            // v1.0.19：钉住刚拍的照片，防下一次目录刷新把它冲掉。
            if !self.pinnedCapturedItems.contains(where: { $0.filename == filename }) {
                self.pinnedCapturedItems.insert(item, at: 0)
                if self.pinnedCapturedItems.count > 50 { self.pinnedCapturedItems.removeLast() }
            }
        }
    }

    /// v1.0.19：目录刷新时把钉住的刚拍照片合并回列表最前面（目录里还没
    /// 有它才补）；已经进目录的就不再钉住。调用方都在主线程。
    private func mergePinned(into ordered: [CameraMediaItem]) -> [CameraMediaItem] {
        let missing = pinnedCapturedItems.filter { p in
            !ordered.contains(where: { $0.filename == p.filename })
        }
        pinnedCapturedItems.removeAll { p in
            ordered.contains(where: { $0.filename == p.filename })
        }
        return missing + ordered
    }

    /// v1.0.18：批量保存（图库多选）。一张一张串行下，防 PTP 拥塞；
    /// 每下一张调一次 progress（已下张数/总数），最后调 completion（成功张数/总数）。
    public func saveItems(_ items: [CameraMediaItem], progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Int) -> Void) {
        var succeeded = 0
        func next(_ index: Int) {
            guard index < items.count else { completion(succeeded, items.count); return }
            progress(index + 1, items.count)
            downloadAndSaveToPhotos(item: items[index]) { ok in
                if ok { succeeded += 1 }
                next(index + 1)
            }
        }
        next(0)
    }

    /// v1.0.18：批量取原图数据（图库多选分享）。串行下，下不到的跳过，
    /// 最后一起调 completion。
    public func downloadItemsData(_ items: [CameraMediaItem], completion: @escaping ([(filename: String, data: Data)]) -> Void) {
        var results: [(filename: String, data: Data)] = []
        func next(_ index: Int) {
            guard index < items.count else { completion(results); return }
            downloadOriginalData(item: items[index]) { data in
                if let data = data { results.append((filename: items[index].filename, data: data)) }
                next(index + 1)
            }
        }
        next(0)
    }

    /// v1.0.19：批量删除机内照片（图库多选）。一张一张串行删，防 PTP 拥塞；
    /// 每删一张调一次 progress（已删张数/总数），最后调 completion（成功张数/总数）。
    /// 删掉的立刻从列表、缩略图缓存和已拍钉住列表里去掉。句柄优先用项目
    /// 自带的，没有就查文件名→句柄映射表；映射表还没建好就等它建好再删
    /// （建表只跑一次，不会每张都等）。
    public func deleteItems(_ items: [CameraMediaItem], progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Int) -> Void) {
        let needsMap = items.contains { $0.ptpHandle == nil && filenameHandleMap[$0.filename] == nil }
        if needsMap && UsbCameraManager.shared.isUsbConnected {
            handleMapWaiters.append { [weak self] in
                guard let self = self else { return }
                self.deleteItemsResolved(items, progress: progress, completion: completion)
            }
            ensureFilenameHandleMap()
            return
        }
        deleteItemsResolved(items, progress: progress, completion: completion)
    }

    private func deleteItemsResolved(_ items: [CameraMediaItem], progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Int) -> Void) {
        var succeeded = 0
        func next(_ index: Int) {
            guard index < items.count else { completion(succeeded, items.count); return }
            progress(index + 1, items.count)
            let item = items[index]
            deleteOne(item) { ok in
                if ok {
                    succeeded += 1
                    DispatchQueue.main.async {
                        self.mediaItems.removeAll { $0.filename == item.filename }
                        self.fetchedItems.removeAll { $0.filename == item.filename }
                        self.thumbCache.removeValue(forKey: item.id)
                        self.pinnedCapturedItems.removeAll { $0.filename == item.filename }
                        self.stats.indexedTotalFiles = self.fetchedItems.count
                    }
                }
                next(index + 1)
            }
        }
        next(0)
    }

    private func deleteOne(_ item: CameraMediaItem, completion: @escaping (Bool) -> Void) {
        if UsbCameraManager.shared.isUsbConnected {
            guard let handle = item.ptpHandle ?? filenameHandleMap[item.filename] else {
                completion(false)
                return
            }
            UsbCameraManager.shared.deleteObject(handle: handle, completion: completion)
            return
        }
        // Wi-Fi：句柄就是 PTP 列卡时的 id（映射表兜底）
        let handle = item.ptpHandle ?? filenameHandleMap[item.filename] ?? item.id
        ptpClient.deleteObject(handle: handle) { ok, _ in completion(ok) }
    }
    
    /// v1.0.39：拍后滤镜版保存用——把已渲染好的图片数据存进系统相册，
    /// 复用图库批量保存同一条存相册通道（PHPhotoLibrary）。
    public func saveImageDataToPhotos(_ data: Data, filename: String, completion: @escaping (Bool) -> Void) {
        saveDataToPhotosOrFiles(data, filename: filename, completion: completion)
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
        // v1.0.17：ICC 列出来的项目没有 PTP 句柄，缩略图和下载兜底都得靠
        // 文件名→句柄映射表。后台建表，不堵列表显示。
        ensureFilenameHandleMap()
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
            // v1.0.19：钉住的刚拍照片合并回来（目录投递慢时它还没进目录）。
            let merged = self.mergePinned(into: ordered)
            self.fetchedItems = merged
            self.isSyncingIndex = false
            self.stats.indexedTotalFiles = merged.count
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
                // v1.0.19：钉住的刚拍照片合并回来（PTP 列卡还没看到它时）。
                let merged = self.mergePinned(into: items)
                self.fetchedItems = merged
                self.isSyncingIndex = false
                self.stats.indexedTotalFiles = merged.count
                self.currentPage = 0
                self.hasMorePages = true
                self.mediaItems.removeAll()
                self.loadNextPage()
            }
        }
    }

    /// v1.0.17：后台建文件名→句柄映射表（卡里最新 1000 个对象）。
    /// 一次建表，多处用：缩略图、图库下载兜底。建表时不堵界面；
    /// 建好后把等映射表的缩略图请求一起放掉。
    public func ensureFilenameHandleMap() {
        guard UsbCameraManager.shared.isUsbConnected else { return }
        guard !handleMapLoading else { return }
        handleMapLoading = true
        UsbCameraManager.shared.fetchCardItemsViaPTP(limit: 1000) { [weak self] entries in
            guard let self = self else { return }
            var map: [String: UInt32] = [:]
            for e in entries { map[e.filename] = e.handle }
            DispatchQueue.main.async {
                self.filenameHandleMap = map
                self.handleMapLoading = false
                // v1.0.19：等映射表的批量删除一起放掉。
                let waiters = self.handleMapWaiters
                self.handleMapWaiters = []
                for w in waiters { w() }
                let pending = self.thumbPending
                self.thumbPending = []
                for p in pending { self.thumbnail(for: p.item, completion: p.completion) }
            }
        }
    }

    /// v1.0.17：取一张图库项目的缩略图数据（懒加载，格子露出来时才取）。
    /// 有句柄的直接取；ICC 项目没句柄就等映射表建好再按文件名翻译；
    /// 映射表还在建就先挂起，建好后统一放掉。结果走缓存，同一张不重复取。
    /// v1.0.19：修了两个让格子永久占位图的 bug——(1) 挂起的请求在映射表
    /// 建好后重跑时被 thumbInFlight 挡住（挂起前没摘掉），completion 永远
    /// 不调，上面几行就一直是占位图，下面滚动后才出现的格子反而能显示；
    /// (2) 同一张图第二个来取的直接被丢掉，现在排队等第一个的结果。
    public func thumbnail(for item: CameraMediaItem, completion: @escaping (Data?) -> Void) {
        if let cached = thumbCache[item.id] { completion(cached); return }
        if thumbInFlight.contains(item.id) {
            thumbWaiters[item.id, default: []].append(completion)
            return
        }
        thumbInFlight.insert(item.id)
        let finish: (Data?) -> Void = { [weak self] data in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.thumbInFlight.remove(item.id)
                if let data = data { self.thumbCache[item.id] = data }
                completion(data)
                let waiters = self.thumbWaiters.removeValue(forKey: item.id) ?? []
                for w in waiters { w(data) }
            }
        }
        let fetch: (UInt32) -> Void = { [weak self] handle in
            guard let self = self else { return }
            self.thumbQueue.async {
                UsbCameraManager.shared.fetchThumbnailData(handle: handle) { data in
                    finish(data)
                }
            }
        }
        if let handle = item.ptpHandle { fetch(handle); return }
        if let handle = filenameHandleMap[item.filename] { fetch(handle); return }
        guard UsbCameraManager.shared.isUsbConnected else {
            finish(nil)
            return
        }
        // 挂起前先把 inFlight 摘掉，不然映射表建好后重跑会被挡住。
        thumbInFlight.remove(item.id)
        thumbPending.append((item: item, completion: completion))
        ensureFilenameHandleMap()
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
                        // v1.0.19：钉住的刚拍照片合并回来。
                        let merged = self.mergePinned(into: items)
                        self.fetchedItems = merged
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
