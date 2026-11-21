//
//  UsbCameraManager.swift
//  Z30Control
//
//  基于 Apple 原生 ImageCaptureCore 框架的 USB 数码相机硬件级直连管理器
//  真实 PTP 协议通信 - GetDevicePropValue + 事件驱动参数同步 + Live View 帧拉取
//

import Foundation
import ImageCaptureCore
import UIKit
import Combine

// MARK: - 尼康标准 PTP 设备属性码 (ISO 15740)
private enum NikonPTPProp: UInt16 {
    case batteryLevel       = 0x5001  // UINT8: 电量百分比
    case whiteBalance       = 0x5005  // UINT16: 白平衡
    case fNumber            = 0x5007  // UINT16: 光圈 (值 / 100 = F数)
    case focusMode          = 0x500A  // UINT16: 对焦模式
    case meteringMode       = 0x500B  // UINT16: 测光模式
    case flashMode          = 0x500C  // UINT16: 闪光模式
    case exposureTime       = 0x500D  // UINT32: 快门速度 (值 / 10000 = 秒)
    case exposureProgramMode = 0x500E // UINT16: 曝光模式 (1=M,2=P,3=A,4=S)
    case exposureIndex      = 0x500F  // UINT16: ISO感光度 (0xFFFF=Auto)
    case exposureBias       = 0x5010  // INT16: 曝光补偿 (值 / 1000 = EV)
    // Nikon 厂商私有属性
    case nikonISOAuto       = 0xD054  // UINT8: Auto ISO 开关 (0=关, 1=开)
    case nikonLiveViewStatus = 0xD1A2 // UINT8: 实时取景状态
}

// MARK: - 尼康 PTP 操作码
private enum NikonPTPOpCode: UInt16 {
    case getDevicePropValue  = 0x1015 // 读取设备属性值
    case setDevicePropValue  = 0x1016 // 设置设备属性值
    case initiateCapture     = 0x100E // 触发快门拍摄
    case nikonStartLiveView  = 0x9201 // 开启实时取景
    case nikonEndLiveView    = 0x9202 // 结束实时取景
    case nikonGetLiveViewImg = 0x9203 // 拉取实时取景帧
}

// MARK: - 尼康 PTP 事件码
private enum NikonPTPEvent: UInt16 {
    case devicePropChanged  = 0x4006  // 设备属性已变化
    case objectAdded        = 0x4002  // 新照片拍摄完成
    case captureComplete    = 0x400D  // 拍摄序列完成
}

// MARK: - UsbCameraManager
public final class UsbCameraManager: NSObject, ObservableObject,
    ICDeviceBrowserDelegate, ICCameraDeviceDelegate, ICCameraDeviceDownloadDelegate {

    public static let shared = UsbCameraManager()

    // MARK: - Published 状态
    @Published public var isUsbConnected: Bool = false
    @Published public var connectedDeviceName: String = ""
    @Published public var lastCapturedPhoto: UIImage? = nil
    @Published public var lastCapturedFilename: String = ""
    @Published public var lastCapturedExif: String = ""
    @Published public var sessionCapturedPhotos: [CapturedPhotoItem] = []

    // Live View 状态
    @Published public var isLiveViewStreaming: Bool = false
    @Published public var currentLiveViewImage: UIImage? = nil
    @Published public var liveViewFPS: Int = 0
    // v1.0.4：取景失败原因（显示在取景页，不再静悄悄黑屏）
    @Published public var liveViewError: String = ""
    // v1.0.4：最近一次 PTP 命令的诊断（一行，供控制页显示，例如
    // “GetStorageInfo → 响应 0x2001，数据 38B” / “0x5001 → 只回响应包，无数据段”）
    @Published public var ptpDiagnostic: String = ""
    // v1.0.4：USB 卡内文件目录（ImageCaptureCore 完整目录，供图库页显示）
    @Published public var usbMediaFiles: [ICCameraFile] = []

    // 设备浏览器与当前相机实例
    private var deviceBrowser: ICDeviceBrowser?
    public private(set) var activeCamera: ICCameraDevice?

    // PTP 通信
    // v1.0.4：事务 ID 从 1000 起——ImageCaptureCore 自己的会话已经占用了
    // 低位 ID（OpenSession 等），从 1 起发会和框架的命令撞号，相机可能拒答。
    private var ptpTransactionID: UInt32 = 1000
    private var isFetchingFrame: Bool = false
    private var liveViewTimer: Timer?
    private var fpsCounter: Int = 0
    private var fpsTimer: Timer?
    // v1.0.4：取景看门狗（启动后 3 秒没帧就停掉并报错）；电量轮询定时器（30 秒）
    private var liveViewWatchdog: Timer?
    private var lastFrameAt: Date?
    // v1.0.11：0x9201 启动命令 5 秒无应答的超时轮次号；单帧请求开始时间
    // （ICC 回调丢了会让 isFetchingFrame 永远卡住，之后每帧都直接 return）
    private var liveViewStartToken = UUID()
    private var fetchStartedAt: Date?
    private var batteryTimer: Timer?
    private var lastFrameErrorAt: Date?
    // v1.0.4：图库“保存原图”用的下载回调（按文件名挂起）
    private var usbDownloadCompletions: [String: (Data?) -> Void] = [:]
    // v1.0.6：调参/拍照时暂停取景帧拉取，让出 PTP 通道（不结束 LiveView）
    private var frameFetchingPaused = false
    // v1.0.6：App 快门前卡里已有的对象句柄，拍后复查时用来认新照片
    private var preCaptureHandles: Set<UInt32> = []
    // v1.0.6：拍前快照是否成功读到（失败时不做复查，免得把整张卡都当成新照片）
    private var preCaptureSnapshotOK = false
    private var captureCheckWorkItem: DispatchWorkItem?
    // v1.0.6：didAdd 触发的下载（走速传），失败重试一次；按文件名记，防止重复重试
    private var didAddDownloadNames: Set<String> = []
    private var retriedDownloads: Set<String> = []

    // 属性读取队列 (避免 USB 拥塞)
    private let ptpQueue = DispatchQueue(label: "com.z30control.ptp.serial", qos: .userInitiated)
    private var isPropFetching: Bool = false

    public struct CapturedPhotoItem: Identifiable {
        public let id = UUID()
        public let filename: String
        public let image: UIImage?
        public let date: Date
        public let sizeString: String
    }

    private override init() {
        super.init()
    }

    // MARK: - 启动 USB 硬件相机设备监听
    public func startListening() {
        if deviceBrowser == nil {
            let browser = ICDeviceBrowser()
            browser.delegate = self
            self.deviceBrowser = browser
        }
        deviceBrowser?.start()
        print("[UsbCameraManager] 已启动 ImageCaptureCore USB 相机总线监听...")
    }

    public func stopListening() {
        stopLiveView()
        batteryTimer?.invalidate()
        batteryTimer = nil
        deviceBrowser?.stop()
        activeCamera?.requestCloseSession()
        activeCamera = nil
        isUsbConnected = false
        print("[UsbCameraManager] 已停止 USB 监听")
    }

    // MARK: - ICDeviceBrowserDelegate 回调
    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        print("[UsbCameraManager] 发现外接硬件设备: \(device.name ?? "未知设备")")
        guard let camera = device as? ICCameraDevice else { return }
        self.activeCamera = camera
        camera.delegate = self
        camera.requestOpenSession()
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        print("[UsbCameraManager] 外接设备已拔出: \(device.name ?? "")")
        if device == activeCamera {
            handleDeviceDisconnect()
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
        if device == activeCamera {
            DispatchQueue.main.async {
                self.connectedDeviceName = device.name ?? "尼康相机"
            }
        }
    }

    // MARK: - ICDeviceDelegate
    public func didRemove(_ device: ICDevice) {
        if device == activeCamera { handleDeviceDisconnect() }
    }

    public func deviceDidBecomeReady(_ device: ICDevice) {
        print("[UsbCameraManager] 设备基础就绪: \(device.name ?? "")")
    }

    public func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error = error {
            print("[UsbCameraManager] 打开会话失败: \(error)")
            return
        }
        guard let camera = device as? ICCameraDevice else { return }
        let devName = camera.name ?? "Nikon Z 30"
        print("[UsbCameraManager] 成功打开硬件会话: \(devName)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUsbConnected = true
            self.connectedDeviceName = devName

            CameraConnectionService.shared.isConnected = true
            CameraConnectionService.shared.isConnecting = false
            CameraConnectionService.shared.statusMessage = "已通过 USB 硬件连接: \(devName)"
            CameraConnectionService.shared.selectedModel = devName
            CameraConnectionService.shared.cameraState.isConnected = true
            CameraConnectionService.shared.cameraState.modelName = devName

            NikonTheme.triggerHaptic(style: .heavy)
        }

        // 连接成功后 0.5 秒开始全量读取相机参数
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchAllCameraProperties()
            // v1.0.4：读卡信息（容量/剩余张数）+ 启动电量轮询（30 秒一次）
            self?.refreshStorageInfo()
            self?.startBatteryPolling()
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        handleDeviceDisconnect()
    }

    private func handleDeviceDisconnect() {
        stopLiveView()
        batteryTimer?.invalidate()
        batteryTimer = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeCamera = nil
            self.isUsbConnected = false
            self.connectedDeviceName = ""
            self.usbMediaFiles = []
            CameraConnectionService.shared.isConnected = false
            CameraConnectionService.shared.cameraState.isConnected = false
            CameraConnectionService.shared.statusMessage = "相机连接已断开"
            // 断开后读到的数全部作废，回到未知状态（v1.0.4，不留旧数冒充）
            CameraConnectionService.shared.cameraState.resetToDefaults()
        }
    }

    // MARK: - ICCameraDeviceDelegate
    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        let files = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        print("[UsbCameraManager] 相机完整目录已就绪，媒体文件数: \(files.count)")
        DispatchQueue.main.async { [weak self] in
            // v1.0.4：USB 卡内目录喂给图库（之前图库只走 Wi-Fi，USB 下永远 0 张）
            self?.usbMediaFiles = files.sorted(by: { ($0.name ?? "") > ($1.name ?? "") })
            // v1.0.14：目录到了才重建图库列表——之前只改了 usbMediaFiles，
            // 图库的 mediaItems 没人重建，用户在图库页看到的永远是打开时那份
            // （常常是空的），目录晚到了也不会自己出现。
            MediaSyncService.shared.refreshFromUSB()
        }
    }

    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("[UsbCameraManager] 相机捕获到新素材，数量: \(items.count)")
        // v1.0.4：新拍的照片也进 USB 目录，图库不用等下次刷新
        let newFiles = items.compactMap { $0 as? ICCameraFile }
        if !newFiles.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var all = self.usbMediaFiles
                for f in newFiles where !all.contains(where: { $0.name == f.name }) {
                    all.insert(f, at: 0)
                }
                self.usbMediaFiles = all
                // v1.0.14：新照片进了目录，图库列表也要跟着重建，否则图库页
                // 还是旧的那份，看不到刚拍的。
                MediaSyncService.shared.refreshFromUSB()
            }
        }
        for item in items {
            guard let file = item as? ICCameraFile else { continue }
            print("[UsbCameraManager] 新拍摄照片: \(file.name ?? "未命名")")
            // v1.0.6：记下这是 didAdd 触发的下载，失败时才走速传重试（图库保存的下载不重试进速传）
            if let name = file.name { didAddDownloadNames.insert(name) }
            let downloadOptions: [ICDownloadOption: Any] = [:]
            camera.requestDownloadFile(
                file,
                options: downloadOptions,
                downloadDelegate: self,
                didDownloadSelector: #selector(didDownloadPhoto(_:error:options:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
                              for item: ICCameraItem, error: (any Error)?) {
        if let cgImg = thumbnail {
            let uiImg = UIImage(cgImage: cgImg)
            DispatchQueue.main.async { [weak self] in
                self?.lastCapturedPhoto = uiImg
                self?.lastCapturedFilename = item.name ?? "NEW_PHOTO.JPG"
            }
        }
    }

    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
                              for item: ICCameraItem, error: (any Error)?) {}

    /// ⭐ 核心：接收相机硬件推送的 PTP 事件，事件驱动参数同步
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        parsePTPEvent(eventData: eventData, camera: camera)
    }

    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    // MARK: - 下载完成 Selector 回调
    @objc private func didDownloadPhoto(_ file: ICCameraFile, error: Error?,
                                         options: [String: Any],
                                         contextInfo: UnsafeMutableRawPointer?) {
        if let error = error {
            print("[UsbCameraManager] 照片下载出错: \(error)")
            // v1.0.4：图库“保存原图”等着的下载也要给个失败答复，别让它一直转
            if let name = file.name, let cb = usbDownloadCompletions.removeValue(forKey: name) {
                cb(nil)
            }
            // v1.0.6：下载失败以前只打印日志，速传里什么都没有，用户不知道卡在哪。
            // 现在写进诊断，并对 didAdd 触发的下载 1.5s 后重试一次（相机刚写完文件时可能还没准备好）。
            if let name = file.name {
                if didAddDownloadNames.contains(name), !retriedDownloads.contains(name) {
                    retriedDownloads.insert(name)
                    didAddDownloadNames.remove(name)
                    setDiagnostic("速传下载失败：\(error.localizedDescription)，1.5s 后重试")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        // v1.0.14：ICC 重试也可能失败（目录里根本没这张），
                        // 那就走 PTP 直接按文件名在卡里找，找到就下原图。
                        self?.downloadUSBFile(named: name) { [weak self] data in
                            if data == nil { self?.rescanCardForNewPhotos() }
                        }
                    }
                } else {
                    didAddDownloadNames.remove(name)
                    setDiagnostic("速传下载失败：\(error.localizedDescription)")
                }
            }
            return
        }
        let savedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(file.name ?? "capture.jpg")
        let loadedImage = UIImage(contentsOfFile: savedPath)
        // v1.0.4：图库保存原图要的是文件数据（NEF 不能转 UIImage，得走原数据）
        let fileData = try? Data(contentsOf: URL(fileURLWithPath: savedPath))
        if let name = file.name, let cb = usbDownloadCompletions.removeValue(forKey: name) {
            cb(fileData)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let name = file.name ?? "DSC_NEW.JPG"
            didAddDownloadNames.remove(name)
            // v1.0.6：成片进速传的逻辑抽成 addCapturedPhoto，PTP 兜底下载也走同一条路
            self.addCapturedPhoto(image: loadedImage, filename: name, sizeBytes: Int(file.fileSize))
            // v1.0.6：拍完下载回来，恢复取景帧拉取（capturePhoto 里暂停过）
            self.resumeLiveViewFetching()
        }
    }

    // MARK: - v1.0.4：图库“保存原图”（USB）
    /// 按文件名从卡里下载原文件，回调给原数据（NEF 也能走这条路）。
    public func downloadUSBFile(named filename: String, completion: @escaping (Data?) -> Void) {
        guard let camera = activeCamera, isUsbConnected else { completion(nil); return }
        guard let file = usbMediaFiles.first(where: { $0.name == filename }) else { completion(nil); return }
        usbDownloadCompletions[filename] = completion
        camera.requestDownloadFile(
            file,
            options: [:],
            downloadDelegate: self,
            didDownloadSelector: #selector(didDownloadPhoto(_:error:options:contextInfo:)),
            contextInfo: nil
        )
    }

    // MARK: - v1.0.6：速传兜底（App 快门拍完，成片必须进速传）

    /// 把一张真实成片放进速传列表（didAdd 下载和 PTP 兜底下载共用）。
    /// 拍完一张，卡的剩余张数变了，顺手重新读一次存储信息。
    private func addCapturedPhoto(image: UIImage?, filename: String, sizeBytes: Int) {
        let sizeStr = String(format: "%.1f MB", Double(sizeBytes) / 1024.0 / 1024.0)
        if let img = image { lastCapturedPhoto = img }
        lastCapturedFilename = filename
        lastCapturedExif = "原片传输 · \(sizeStr)"
        let item = CapturedPhotoItem(filename: filename, image: image, date: Date(), sizeString: sizeStr)
        sessionCapturedPhotos.insert(item, at: 0)
        NikonTheme.triggerHaptic(style: .medium)
        if let img = image {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        }
        refreshStorageInfo()
    }

    /// 直接问相机要全部对象句柄（GetStorageIDs → GetObjectHandles），不经过 ICC 目录。
    /// ICC 的 didAdd 回调没来时，靠这条路认出新拍的照片。
    /// nil = 读存储失败（没法复查）；[] = 读成功但卡是空的。
    private func fetchAllObjectHandles(completion: @escaping ([UInt32]?) -> Void) {
        sendPTPDataCommand(opCode: 0x1004) { [weak self] payload, _, _ in
            guard let payload = payload else { completion(nil); return }
            let ids = Self.parseUInt32Array(payload)
            guard let storage = ids.first else { completion(nil); return }
            self?.sendPTPDataCommand(opCode: 0x1007, params: [storage, 0, 0]) { payload2, _, _ in
                guard let payload2 = payload2 else { completion(nil); return }
                completion(Self.parseUInt32Array(payload2))
            }
        }
    }

    /// 从 ObjectInfo 数据集里只取文件名（标准布局文件名在偏移 52，模拟器简化布局在 14）
    private static func parseObjectInfoFilename(_ data: Data) -> String? {
        if data.count >= 53, let (name, _) = readPTPString(data, offset: 52), !name.isEmpty { return name }
        if data.count >= 15, let (name, _) = readPTPString(data, offset: 14), !name.isEmpty { return name }
        return nil
    }

    /// PTP 字符串：首字节为 UTF-16 码元个数（含结尾空字符），后跟对应码元
    private static func readPTPString(_ data: Data, offset: Int) -> (String, Int)? {
        guard offset < data.count else { return nil }
        let charCount = Int(data[offset])
        guard charCount > 0 else { return ("", offset + 1) }
        let byteCount = charCount * 2
        guard offset + 1 + byteCount <= data.count else { return nil }
        let stringData = data.subdata(in: (offset + 1)..<(offset + 1 + byteCount))
        guard var text = String(data: stringData, encoding: .utf16LittleEndian) else { return nil }
        text = text.trimmingCharacters(in: .controlCharacters)
        return (text, offset + 1 + byteCount)
    }

    /// App 快门成功后查两次新照片（2.5s 和 6s）。v1.0.14：之前只查一次，
    /// 相机写卡慢一点（NEF、大卡、连拍后）就查不到，速传永远空着。
    private func scheduleCaptureCheck() {
        captureCheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkForNewCapture(attempt: 1) }
        captureCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func checkForNewCapture(attempt: Int = 1) {
        guard isUsbConnected else {
            DispatchQueue.main.async { [weak self] in self?.resumeLiveViewFetching() }
            return
        }
        // 拍前快照没读到就别复查了，只靠 didAdd，免得把整张卡都当成新照片
        guard preCaptureSnapshotOK else {
            print("[UsbCameraManager] 拍后复查跳过：拍前快照未读到")
            setDiagnostic("拍后复查跳过：拍前卡快照没读到，只靠相机推送")
            DispatchQueue.main.async { [weak self] in self?.resumeLiveViewFetching() }
            return
        }
        fetchAllObjectHandles { [weak self] handles in
            guard let self = self else { return }
            guard let handles = handles else {
                print("[UsbCameraManager] 拍后复查：读句柄失败，只靠 didAdd")
                self.setDiagnostic("拍后复查：读卡句柄失败，只靠相机推送")
                DispatchQueue.main.async { self.resumeLiveViewFetching() }
                return
            }
            let newHandles = handles.filter { !self.preCaptureHandles.contains($0) }
            guard !newHandles.isEmpty else {
                print("[UsbCameraManager] 拍后复查：卡里没有新对象（didAdd 已处理或相机未写入）")
                if attempt == 1 {
                    // 第一次没查到不等于没有——相机可能还没写完卡，3.5s 后再查一次
                    self.setDiagnostic("拍后复查：2.5s 未见新照片，6s 后再查一次")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                        self?.checkForNewCapture(attempt: 2)
                    }
                } else {
                    self.setDiagnostic("拍后复查：卡里没有新对象（didAdd 已处理或相机未写入）")
                    DispatchQueue.main.async { self.resumeLiveViewFetching() }
                }
                return
            }
            print("[UsbCameraManager] 拍后复查：发现 \(newHandles.count) 个新对象句柄")
            // 逐个查文件名（串行，防 DeviceBusy）
            self.fetchNewCapturedFiles(handles: newHandles, index: 0) {
                DispatchQueue.main.async { self.resumeLiveViewFetching() }
            }
        }
    }

    private func fetchNewCapturedFiles(handles: [UInt32], index: Int, done: @escaping () -> Void) {
        guard index < handles.count else { done(); return }
        let handle = handles[index]
        sendPTPDataCommand(opCode: 0x1008, params: [handle]) { [weak self] payload, code, _ in
            guard let self = self else { done(); return }
            if let payload = payload, let filename = Self.parseObjectInfoFilename(payload), !filename.isEmpty {
                if !self.sessionCapturedPhotos.contains(where: { $0.filename == filename }) {
                    if self.usbMediaFiles.contains(where: { $0.name == filename }) {
                        self.downloadUSBFile(named: filename) { _ in }
                    } else {
                        self.downloadRawObject(handle: handle, filename: filename)
                    }
                }
            } else {
                print("[UsbCameraManager] 新对象 0x\(String(handle, radix: 16)) 读不到文件名（响应 \(code.map { String(format: "0x%04X", $0) } ?? "无")）")
            }
            self.fetchNewCapturedFiles(handles: handles, index: index + 1, done: done)
        }
    }

    /// ICC 目录里没有的新照片，直接 PTP GetObject 取原图字节
    private func downloadRawObject(handle: UInt32, filename: String) {
        downloadRawObjectData(handle: handle, filename: filename) { [weak self] payload in
            guard let self = self, let payload = payload, !payload.isEmpty else { return }
            let img = UIImage(data: payload)
            DispatchQueue.main.async {
                self.addCapturedPhoto(image: img, filename: filename, sizeBytes: payload.count)
            }
        }
    }

    /// v1.0.14：对外暴露的 PTP 原图下载（图库“保存原图”兜底用）。
    /// ICC 目录里找不到文件时，图库不再直接报失败，改走这条路按句柄取原图。
    public func downloadRawObjectData(handle: UInt32, filename: String, completion: @escaping (Data?) -> Void) {
        sendPTPDataCommand(opCode: 0x1009, params: [handle]) { [weak self] payload, _, diag in
            guard let self = self else { completion(nil); return }
            guard let payload = payload, !payload.isEmpty else {
                self.setDiagnostic("速传取原图失败：\(diag)")
                completion(nil)
                return
            }
            completion(payload)
        }
    }

    /// v1.0.14：手动重新扫描——速传页的“重新扫描卡内照片”按钮和
    /// didAdd 下载失败的兜底都走这里。不依赖拍前快照：直接问卡里最新
    /// 的 5 个对象，文件名还没进速传的就下载（机身快门拍的也一样能捡回来）。
    public func rescanCardForNewPhotos() {
        guard isUsbConnected else { return }
        setDiagnostic("正在重新扫描卡内照片…")
        fetchAllObjectHandles { [weak self] handles in
            guard let self = self, let handles = handles, !handles.isEmpty else {
                self?.setDiagnostic("重新扫描：读卡句柄失败")
                return
            }
            // 句柄按拍摄顺序递增，最大的 5 个就是最新的 5 张
            let newest = Array(handles.sorted(by: >).prefix(5))
            self.fetchNewCapturedFiles(handles: newest, index: 0) {
                DispatchQueue.main.async {
                    self.setDiagnostic("重新扫描完成：本次速传共 \(self.sessionCapturedPhotos.count) 张")
                }
            }
        }
    }

    /// v1.0.14：图库兜底——ICC 目录迟迟不到时，直接用 PTP 列卡里的文件。
    /// 返回最新在前的（句柄、文件名、字节数），最多取 300 个（串行查
    /// GetObjectInfo，整卡几千张全查太慢；ICC 目录到了走正常路，不受此限）。
    public func fetchCardItemsViaPTP(completion: @escaping ([(handle: UInt32, filename: String, sizeBytes: UInt64)]) -> Void) {
        fetchAllObjectHandles { [weak self] handles in
            guard let self = self, let handles = handles else { completion([]); return }
            let newest = Array(handles.sorted(by: >).prefix(300))
            self.fetchCardInfoSequentially(handles: newest, index: 0, accumulated: [], done: completion)
        }
    }

    private func fetchCardInfoSequentially(handles: [UInt32], index: Int, accumulated: [(handle: UInt32, filename: String, sizeBytes: UInt64)], done: @escaping ([(handle: UInt32, filename: String, sizeBytes: UInt64)]) -> Void) {
        guard index < handles.count else { done(accumulated); return }
        let handle = handles[index]
        sendPTPDataCommand(opCode: 0x1008, params: [handle]) { [weak self] payload, _, _ in
            guard let self = self else { done(accumulated); return }
            var next = accumulated
            if let payload = payload, let filename = Self.parseObjectInfoFilename(payload), !filename.isEmpty {
                // 标准 ObjectInfo：大小 U32 在偏移 10（模拟器简化布局也是 10）
                var size: UInt64 = 0
                if payload.count >= 14 {
                    size = UInt64(UInt32(payload[10]) | (UInt32(payload[11]) << 8) | (UInt32(payload[12]) << 16) | (UInt32(payload[13]) << 24))
                }
                next.append((handle: handle, filename: filename, sizeBytes: size))
            }
            self.fetchCardInfoSequentially(handles: handles, index: index + 1, accumulated: next, done: done)
        }
    }

    // MARK: - ⭐ 真实 PTP 属性读取核心引擎

    /// 构建标准 USB PTP 命令数据容器 (Little-Endian，符合 ISO 15740 规范)
    private func buildPTPCommandPacket(opCode: UInt16, params: [UInt32] = []) -> Data {
        ptpTransactionID &+= 1
        var packet = Data()
        // Length (4B) = 12字节头 + 每个参数4字节
        var length = UInt32(12 + params.count * 4).littleEndian
        packet.append(Data(bytes: &length, count: 4))
        // Container Type (2B): 0x0001 = Command Block
        var type: UInt16 = 0x0001
        packet.append(Data(bytes: &type, count: 2))
        // Operation Code (2B)
        var code = opCode.littleEndian
        packet.append(Data(bytes: &code, count: 2))
        // Transaction ID (4B)
        var txID = ptpTransactionID.littleEndian
        packet.append(Data(bytes: &txID, count: 4))
        // Parameters
        for var p in params {
            var pLE = p.littleEndian
            packet.append(Data(bytes: &pLE, count: 4))
        }
        return packet
    }

    /// v1.0.5：从 requestSendPTPCommand 的两个回包参数里找数据。
    /// 实测（2026-11-21 录屏）证明：只读第二个参数永远只能拿到 12 字节响应包，
    /// 数据不在那。苹果这个接口的 block 是 (first, second, error)，second 一定是
    /// 响应容器；first 可能是数据——带 12 字节头的数据容器，也可能是裸数据；
    /// 也可能是原样回显的命令包。三种都处理，绝不再把数据扔掉。
    /// 返回：数据载荷（无则 nil）、响应码、给诊断行看的一句话。
    private static func extractPTPData(first: Data, second: Data) -> (payload: Data?, responseCode: UInt16?, note: String) {
        // 1) second 是响应容器 → 取响应码（两个参数里响应一定在这）
        var code: UInt16? = nil
        if second.count >= 8 {
            let t = UInt16(second[4]) | (UInt16(second[5]) << 8)
            if t == 0x0003 { code = UInt16(second[6]) | (UInt16(second[7]) << 8) }
        }
        // 2) second 本身是数据容器 → 之前就有的路（以防万一）
        if second.count >= 12 {
            let t = UInt16(second[4]) | (UInt16(second[5]) << 8)
            if t == 0x0002 {
                let dataLen = Int(UInt32(second[0]) | (UInt32(second[1]) << 8) | (UInt32(second[2]) << 16) | (UInt32(second[3]) << 24))
                let end = min(dataLen, second.count)
                if end > 12 { return (second.subdata(in: 12..<end), code, "数据在 second（容器）") }
            }
        }
        // 3) first 是数据容器（12 字节头 + 载荷）
        if first.count >= 12 {
            let len = Int(UInt32(first[0]) | (UInt32(first[1]) << 8) | (UInt32(first[2]) << 16) | (UInt32(first[3]) << 24))
            let t = UInt16(first[4]) | (UInt16(first[5]) << 8)
            if len == first.count && t == 0x0002 {
                return (first.subdata(in: 12..<first.count), code, "数据在 first（容器）")
            }
            if len == first.count && t == 0x0001 {
                return (nil, code, "first 为命令回显，无数据")
            }
            if len == first.count && t == 0x0003 {
                return (nil, code, "first 也是响应包，无数据")
            }
            // first 不是完整容器 → 当裸数据（电量 1 字节、JPEG、StorageInfo 数据集都长这样）
            return (first, code, "数据在 first（裸数据）")
        }
        if first.count > 0 {
            return (first, code, "数据在 first（裸数据）")
        }
        return (nil, code, "两参均无数据")
    }

    /// v1.0.4：统一的 USB PTP 数据读取入口。之前每个地方各自猜响应格式，
    /// 读不到就静悄悄返回，取景和参数全灭也不吭声。现在把三种可能都处理了，
    /// 并把结果写进 ptpDiagnostic（控制页可见），下次实测一眼就知道卡在哪一步：
    /// - 数据容器 (type 0x0002)：载荷在 12 字节头后面（GetDevicePropValue、GetStorageInfo 都是这种）
    /// - 响应容器 (type 0x0003)：只有 12 字节响应码，没有数据段——说明这条路拿不到数据
    /// - 数据容器后跟响应包：顺手把响应码也读出来
    /// v1.0.5：实测证明数据根本不在第二个参数里（GetDevicePropValue 只回 12 字节
    /// 响应包 0x2001，取景每帧也只有 12B）。改走 extractPTPData，两个参数都看。
    private func sendPTPDataCommand(opCode: UInt16, params: [UInt32] = [], completion: @escaping (Data?, UInt16?, String) -> Void) {
        guard let camera = activeCamera, isUsbConnected else {
            completion(nil, nil, "未连接相机")
            return
        }
        let label = String(format: "0x%04X", opCode)
        let cmd = buildPTPCommandPacket(opCode: opCode, params: params)
        camera.requestSendPTPCommand(cmd, outData: nil) { (first, second, error) in
            if let error = error {
                completion(nil, nil, "\(label) 出错：\(error.localizedDescription)")
                return
            }
            let (payload, code, note) = Self.extractPTPData(first: first, second: second)
            let diag = "\(label) → \(note)（first \(first.count)B / second \(second.count)B）" + (code.map { String(format: "，响应 0x%04X", $0) } ?? "")
            completion(payload, code, diag)
        }
    }

    private func setDiagnostic(_ text: String) {
        print("[PTP] \(text)")
        DispatchQueue.main.async { [weak self] in self?.ptpDiagnostic = text }
    }

    /// 读取单个 PTP 设备属性值 → 解析并同步到 CameraState
    private func fetchSingleProperty(_ prop: NikonPTPProp, camera: ICCameraDevice) {
        sendPTPDataCommand(opCode: NikonPTPOpCode.getDevicePropValue.rawValue,
                           params: [UInt32(prop.rawValue)]) { [weak self] payload, code, diag in
            self?.setDiagnostic(diag)
            guard let payload = payload, !payload.isEmpty else {
                print("[PTP] 属性 0x\(String(prop.rawValue, radix: 16)) 未读到数据：\(diag)")
                return
            }
            if let code = code, code != 0x2001 {
                print("[PTP] 属性 0x\(String(prop.rawValue, radix: 16)) 响应码 0x\(String(code, radix: 16))")
                return
            }
            self?.applyPropertyValue(prop: prop, payload: payload)
        }
    }

    /// 连接成功后，全量读取所有关键属性
    private func fetchAllCameraProperties() {
        guard let camera = activeCamera, isUsbConnected else { return }
        // v1.0.4：之前这里拿 capabilities 做门禁，门禁不过就静默跳过全部读取，
        // 取景和参数全灭也不吭声。现在只记日志，照样发命令，用响应码说话。
        print("[PTP] 相机 capabilities: \(camera.capabilities)")

        let propsToFetch: [NikonPTPProp] = [
            .exposureTime, .fNumber, .exposureIndex,
            .exposureProgramMode, .exposureBias,
            .whiteBalance, .meteringMode, .batteryLevel,
            .focusMode, .nikonISOAuto
        ]

        // 顺序读取，每次间隔 100ms，防止 USB 管道拥塞
        for (i, prop) in propsToFetch.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { [weak self] in
                guard let self = self, let cam = self.activeCamera else { return }
                self.fetchSingleProperty(prop, camera: cam)
            }
        }
    }

    // MARK: - v1.0.4：存储卡真实读取（GetStorageIDs → GetStorageInfo）

    private struct StorageInfo {
        let maxCapacity: UInt64
        let freeBytes: UInt64
        let freeImages: UInt32
    }

    /// StorageInfo 数据集：StorageType(2) FilesystemType(2) AccessCapability(2)
    /// MaxCapacity(8) FreeSpaceInBytes(8) FreeSpaceInImages(4) …
    private static func parseStorageInfo(_ data: Data) -> StorageInfo? {
        guard data.count >= 26 else { return nil }
        let u32 = { (o: Int) in UInt32(data[o]) | (UInt32(data[o + 1]) << 8) | (UInt32(data[o + 2]) << 16) | (UInt32(data[o + 3]) << 24) }
        var maxCap: UInt64 = 0
        var freeB: UInt64 = 0
        for i in 0..<8 {
            maxCap |= UInt64(data[6 + i]) << (8 * i)
            freeB |= UInt64(data[14 + i]) << (8 * i)
        }
        return StorageInfo(maxCapacity: maxCap, freeBytes: freeB, freeImages: u32(22))
    }

    private static func parseUInt32Array(_ data: Data) -> [UInt32] {
        guard data.count >= 4 else { return [] }
        let count = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [UInt32] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            result.append(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) })
            offset += 4
        }
        return result
    }

    /// 读卡：容量、剩余空间、相机自带的剩余张数，写进 CameraState（替代写死的假数）
    public func refreshStorageInfo() {
        guard isUsbConnected else { return }
        sendPTPDataCommand(opCode: 0x1004) { [weak self] payload, _, diag in
            self?.setDiagnostic(diag)
            guard let payload = payload else { return }
            let ids = Self.parseUInt32Array(payload)
            guard let first = ids.first else { return }
            self?.sendPTPDataCommand(opCode: 0x1005, params: [first]) { [weak self] infoPayload, _, diag2 in
                self?.setDiagnostic(diag2)
                guard let infoPayload = infoPayload,
                      let info = Self.parseStorageInfo(infoPayload) else { return }
                let state = CameraConnectionService.shared.cameraState
                DispatchQueue.main.async {
                    state.cardTotalGB = Double(info.maxCapacity) / 1_000_000_000
                    state.cardUsedGB = Double(info.maxCapacity - info.freeBytes) / 1_000_000_000
                    // 相机自带的剩余张数；0xFFFFFFFF 表示未知时按 25MB/张估算
                    state.remainingShots = info.freeImages == 0xFFFFFFFF
                        ? Int(info.freeBytes / 25_000_000)
                        : Int(info.freeImages)
                    state.storageKnown = true
                    print("[PTP] 存储卡：总量 \(String(format: "%.1f", state.cardTotalGB))GB，剩余 \(String(format: "%.1f", Double(info.freeBytes) / 1_000_000_000))GB，可拍 \(state.remainingShots) 张")
                }
            }
        }
    }

    // MARK: - v1.0.4：电量轮询（30 秒读一次，之前只在连接时读一次）

    private func startBatteryPolling() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, self.isUsbConnected, let cam = self.activeCamera else { return }
            self.fetchSingleProperty(.batteryLevel, camera: cam)
        }
    }

    public func refreshBatteryLevel() {
        guard isUsbConnected, let cam = activeCamera else { return }
        fetchSingleProperty(.batteryLevel, camera: cam)
    }

    /// 解析 PTP 数据容器载荷并更新 CameraState
    private func applyPropertyValue(prop: NikonPTPProp, payload: Data) {
        let cameraState = CameraConnectionService.shared.cameraState
        let bytes = [UInt8](payload)
        guard !bytes.isEmpty else { return }

        DispatchQueue.main.async {
            switch prop {
            case .exposureTime:
                // UINT32 Little-Endian，值 / 10000 = 秒数
                guard bytes.count >= 4 else { return }
                let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
                cameraState.shutterSpeed = Self.decodeShutterSpeed(raw)
                print("[PTP] 快门速度: \(cameraState.shutterSpeed) (原始=\(raw))")

            case .fNumber:
                // UINT16 Little-Endian，值 / 100 = F数
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                let fVal = Double(raw) / 100.0
                cameraState.aperture = "f/\(fVal.clean)"
                print("[PTP] 光圈: \(cameraState.aperture) (原始=\(raw))")

            case .exposureIndex:
                // UINT16，0xFFFF = Auto ISO
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                if raw == 0xFFFF {
                    cameraState.isAutoISO = true
                    cameraState.isoActual = "AUTO"
                } else {
                    cameraState.isoBase = "\(raw)"
                    cameraState.isoActual = "\(raw)"
                }
                print("[PTP] ISO: \(cameraState.isoActual) (原始=\(raw))")

            case .exposureProgramMode:
                // UINT16：标准值 1=M、2=P、3=A、4=S；尼康厂商值 0x8010 起排
                // 推断为 AUTO/U1/U2/U3（真机验证中，未识别的值进 .unknown，
                // 原始值写进诊断行，方便对表修正）。
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                cameraState.exposureModeRaw = raw
                switch raw {
                case 1: cameraState.exposureMode = .manual
                case 2: cameraState.exposureMode = .program
                case 3: cameraState.exposureMode = .aperturePriority
                case 4: cameraState.exposureMode = .shutterPriority
                case 0x8010: cameraState.exposureMode = .auto
                case 0x8011: cameraState.exposureMode = .user1
                case 0x8012: cameraState.exposureMode = .user2
                case 0x8013: cameraState.exposureMode = .user3
                default:
                    cameraState.exposureMode = .unknown
                    self?.setDiagnostic(String(format: "曝光模式未识别：原始值 0x%04X，请把这个值发给开发者对表", raw))
                }
                print("[PTP] 曝光模式: \(cameraState.exposureMode.rawValue) (原始=\(raw))")

            case .exposureBias:
                // INT16，值 / 1000 = EV 补偿
                guard bytes.count >= 2 else { return }
                let raw = Int16(bitPattern: UInt16(bytes[0]) | (UInt16(bytes[1]) << 8))
                let ev = Double(raw) / 1000.0
                if ev == 0 {
                    cameraState.exposureCompensation = "0 EV"
                } else {
                    cameraState.exposureCompensation = String(format: "%+.1f EV", ev)
                }
                print("[PTP] 曝光补偿: \(cameraState.exposureCompensation) (原始=\(raw))")

            case .whiteBalance:
                // UINT16，值映射到白平衡枚举
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                cameraState.whiteBalance = Self.decodeWhiteBalance(raw)
                print("[PTP] 白平衡: \(cameraState.whiteBalance.rawValue) (原始=\(raw))")

            case .meteringMode:
                // UINT16: 1=矩阵, 2=中央重点, 3=点测光
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                switch raw {
                case 1: cameraState.meteringMode = .matrix
                case 2: cameraState.meteringMode = .centerWeighted
                case 3: cameraState.meteringMode = .spot
                case 4: cameraState.meteringMode = .spot
                default: break
                }
                print("[PTP] 测光: \(cameraState.meteringMode.rawValue) (原始=\(raw))")

            case .batteryLevel:
                // UINT8，电量百分比；读到一次才算“已知”，之前默认 85% 是假数
                guard !bytes.isEmpty else { return }
                cameraState.batteryPercentage = Int(bytes[0])
                cameraState.batteryKnown = true
                print("[PTP] 电量: \(bytes[0])%")

            case .focusMode:
                // UINT16: 1=MF, 2=AF-S, 3=AF-C
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                switch raw {
                case 1: cameraState.focusMode = .manual
                case 2: cameraState.focusMode = .afSingle
                case 3: cameraState.focusMode = .afContinuous
                default: break
                }

            case .nikonISOAuto:
                // UINT8: 0=关, 1=开
                guard !bytes.isEmpty else { return }
                cameraState.isAutoISO = bytes[0] == 1
                if cameraState.isAutoISO && !cameraState.isoActual.hasPrefix("AUTO") {
                    cameraState.isoActual = "AUTO"
                }

            case .nikonLiveViewStatus:
                break

            default:
                break
            }
        }
    }

    /// 解析 PTP 事件包，仅对变化的属性执行一次精准读取
    private func parsePTPEvent(eventData: Data, camera: ICCameraDevice) {
        guard eventData.count >= 10 else { return }
        let bytes = [UInt8](eventData)
        // PTP 事件容器结构 (Little-Endian):
        //   [0-3]  Length (4B)
        //   [4-5]  ContainerType (2B): 0x0004 = Event
        //   [6-7]  EventCode (2B)
        //   [8-11] TransactionID (4B)
        //   [12-15] Parameter1 (4B, 变化的属性码)
        let eventCode = UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)
        print("[PTP Event] 收到事件: 0x\(String(eventCode, radix: 16))")

        switch eventCode {
        case NikonPTPEvent.devicePropChanged.rawValue:
            // Parameter1 = 变化的属性码（32位，取低16位即属性码）
            guard bytes.count >= 16 else { return }
            let propCode = UInt16(bytes[12]) | (UInt16(bytes[13]) << 8)
            print("[PTP Event] 属性已变化: 0x\(String(propCode, radix: 16))")
            if let prop = NikonPTPProp(rawValue: propCode) {
                // 只读取那一个变化的属性，不轮询
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.fetchSingleProperty(prop, camera: camera)
                }
            }

        case NikonPTPEvent.objectAdded.rawValue:
            // 新照片被加入，ICCameraDeviceDelegate.didAdd 会处理下载
            print("[PTP Event] 新照片拍摄事件，等待 didAdd 回调")

        case NikonPTPEvent.captureComplete.rawValue:
            print("[PTP Event] 拍摄序列完成")

        default:
            break
        }
    }

    // MARK: - 快门速度解码 (PTP ExposureTime UINT32 -> 显示字符串)
    private static func decodeShutterSpeed(_ raw: UInt32) -> String {
        if raw == 0 { return "BULB" }
        if raw == 0xFFFFFFFF { return "BULB" }

        let seconds = Double(raw) / 10000.0

        // 大于等于 1 秒
        if seconds >= 1.0 {
            if seconds == Double(Int(seconds)) {
                return "\(Int(seconds))s"
            } else {
                return String(format: "%.1fs", seconds)
            }
        }

        // 小于 1 秒，显示 1/N 格式
        let denom = Int(10000.0 / Double(raw) + 0.5)
        return "1/\(denom)"
    }

    // MARK: - 白平衡解码
    private static func decodeWhiteBalance(_ raw: UInt16) -> WhiteBalanceMode {
        switch raw {
        case 2: return .auto
        case 4: return .daylight
        case 5: return .fluorescent
        case 6: return .incandescent
        // v1.0.14 更正：之前 0x8010/0x8011 写反了。开源项目 ptp_misc.cpp
        // 的尼康表证实：0x8010=Cloudy（阴天）、0x8011=Shade（阴影）。
        case 0x8010: return .cloudy
        case 0x8011: return .shade
        case 0x8012: return .customKelvin // Nikon 色温
        default: return .auto
        }
    }

    // MARK: - USB PTP 实时取景 (Live View) 协议驱动

    /// 开启尼康 USB 实时取景传感器数据流 (OpCode: 0x9201)
    /// v1.0.4：之前不管命令成没成，回包一到就把 isLiveViewStreaming 置 true，
    /// 然后帧一直不到也不报错，界面就永远是黑底占位图。现在：
    /// 1) 只在响应码为 OK 时才算启动成功，否则把原因写进 liveViewError；
    /// 2) 启动后 3 秒没收到帧，看门狗停掉并报错（相机须处于拍照模式，
    ///    回放/菜单状态下取景起不来）。
    public func startLiveView() {
        guard let camera = activeCamera, isUsbConnected else {
            DispatchQueue.main.async { [weak self] in
                self?.liveViewError = "相机未连接，无法开启取景"
            }
            print("[UsbCameraManager] 相机未连接或未就绪，无法开启 LiveView")
            return
        }
        guard !isLiveViewStreaming else { return }
        DispatchQueue.main.async { [weak self] in self?.liveViewError = "" }

        // v1.0.11：0x9201 发出去后如果相机根本不回包，requestSendPTPCommand
        // 的回调永远不触发，之前就静悄悄卡住，按钮点了像没反应。5 秒没应答
        // 直接报错，让用户看到原因。
        let token = UUID()
        liveViewStartToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            guard self.liveViewStartToken == token, !self.isLiveViewStreaming else { return }
            self.liveViewError = "取景启动无应答：相机 5 秒没回 0x9201，请确认相机在拍照模式（不在回放/菜单），或重连/重启相机"
        }

        print("[UsbCameraManager] 发送尼康 StartLiveView (0x9201)...")
        let startCmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.nikonStartLiveView.rawValue)

        camera.requestSendPTPCommand(startCmd, outData: nil) { [weak self] (_, responseData, error) in
            guard let self = self else { return }
            self.liveViewStartToken = UUID() // 回包了，上面那个 5 秒超时作废
            if let error = error {
                print("[UsbCameraManager] StartLiveView 命令出错: \(error)")
                DispatchQueue.main.async {
                    self.liveViewError = "取景启动失败：\(error.localizedDescription)"
                }
                return
            }
            // 响应包 [6-7] 为响应码，0x2001=OK；只回响应包、无数据段也算正常
            //（StartLiveView 本来就不带数据）
            var respCode: UInt16? = nil
            if responseData.count >= 8 {
                let t = UInt16(responseData[4]) | (UInt16(responseData[5]) << 8)
                if t == 0x0003, responseData.count >= 8 {
                    respCode = UInt16(responseData[6]) | (UInt16(responseData[7]) << 8)
                }
            }
            if let code = respCode, code != 0x2001 {
                print("[UsbCameraManager] StartLiveView 被拒，响应码 0x\(String(code, radix: 16))")
                DispatchQueue.main.async {
                    self.liveViewError = String(format: "取景启动被拒（0x%04X）：请确认相机处于拍照模式，不在回放/菜单", code)
                }
                return
            }
            print("[UsbCameraManager] StartLiveView 命令已送达，响应码 \(respCode.map { String(format: "0x%04X", $0) } ?? "未知")")
            DispatchQueue.main.async {
                self.isLiveViewStreaming = true
                self.lastFrameAt = nil
                self.startFrameFetchTimer()
                self.startLiveViewWatchdog()
            }
        }
    }

    /// 取景看门狗：启动后 3 秒仍无帧，停掉并给出原因
    private func startLiveViewWatchdog() {
        liveViewWatchdog?.invalidate()
        liveViewWatchdog = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isLiveViewStreaming, self.lastFrameAt == nil {
                print("[UsbCameraManager] 取景看门狗：3 秒内未收到帧")
                self.stopLiveView()
                DispatchQueue.main.async {
                    self.liveViewError = "已启动但 3 秒内未收到取景帧：请确认相机处于拍照模式（非回放/菜单），USB 设为 MTP/PTP 后重连"
                }
            }
        }
    }

    /// 停止尼康 USB 实时取景传感器数据流 (OpCode: 0x9202)
    public func stopLiveView() {
        liveViewTimer?.invalidate()
        liveViewTimer = nil
        fpsTimer?.invalidate()
        fpsTimer = nil
        liveViewWatchdog?.invalidate()
        liveViewWatchdog = nil
        isFetchingFrame = false
        // v1.0.6：停取景时清掉暂停标志，免得下次开取景还以为被暂停着
        frameFetchingPaused = false

        DispatchQueue.main.async { [weak self] in
            self?.isLiveViewStreaming = false
            self?.liveViewFPS = 0
        }

        guard let camera = activeCamera, isUsbConnected else { return }
        let endCmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.nikonEndLiveView.rawValue)
        camera.requestSendPTPCommand(endCmd, outData: nil) { _, _, _ in
            print("[UsbCameraManager] EndLiveView 已完成")
        }
    }

    /// v1.0.6：暂停取景帧拉取（调参/拍照时让出 PTP 通道），不结束 LiveView。
    /// 只在主线程调用（调用方都是界面操作）。
    public func pauseLiveViewFetching() {
        guard isLiveViewStreaming else { return }
        frameFetchingPaused = true
        liveViewTimer?.invalidate()
        liveViewTimer = nil
    }

    /// 恢复取景帧拉取（仅当仍在取景且之前被暂停过）
    public func resumeLiveViewFetching() {
        guard frameFetchingPaused else { return }
        frameFetchingPaused = false
        guard isLiveViewStreaming else { return }
        startFrameFetchTimer()
    }

    private func startFrameFetchTimer() {
        liveViewTimer?.invalidate()
        fpsTimer?.invalidate()
        // 以约 20 FPS 拉取帧，给 PTP 总线留出属性读取的带宽
        liveViewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.fetchLiveViewFrame()
        }
        // FPS 计数器
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.liveViewFPS = self.fpsCounter
                self.fpsCounter = 0
            }
        }
    }

    private func fetchLiveViewFrame() {
        // v1.0.11：上一帧请求如果 2 秒没回（ICC 回调丢了），isFetchingFrame
        // 会永远卡住，之后每次都直接 return，画面冻住也不报错。在这里复位，
        // 让下一拍重试，并写一行诊断。
        if isFetchingFrame, let started = fetchStartedAt, Date().timeIntervalSince(started) > 2 {
            isFetchingFrame = false
            fetchStartedAt = nil
            noteFrameError("取景帧请求超时未回，已重试")
        }
        guard let camera = activeCamera, isLiveViewStreaming, !isFetchingFrame else { return }
        isFetchingFrame = true
        fetchStartedAt = Date()

        let getCmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.nikonGetLiveViewImg.rawValue)
        camera.requestSendPTPCommand(getCmd, outData: nil) { [weak self] (first, second, error) in
            defer {
                self?.isFetchingFrame = false
                self?.fetchStartedAt = nil
            }
            guard let self = self else { return }
            if let error = error {
                self.noteFrameError("取景帧出错：\(error.localizedDescription)")
                return
            }

            // v1.0.5：数据可能在 first 里（数据容器或裸 JPEG），也可能在 second 里。
            // 之前只看 second，second 永远是 12 字节响应包，所以每帧都报“仅 12B，无图像数据”。
            let (payload, _, note) = Self.extractPTPData(first: first, second: second)
            guard let payload = payload, payload.count > 64 else {
                self.noteFrameError("取景帧无图像数据（\(note)，first \(first.count)B / second \(second.count)B）")
                return
            }

            // 直接搜索 JPEG SOI 标记 0xFF 0xD8，不依赖固定偏移量
            let bytes = [UInt8](payload)
            guard let jpegStart = self.findJPEGStart(in: bytes) else {
                self.noteFrameError("取景帧 \(payload.count)B，无 JPEG 标记（\(note)）")
                return
            }
            let jpegData = payload.subdata(in: jpegStart..<payload.count)

            if let img = UIImage(data: jpegData) {
                self.lastFrameAt = Date()
                DispatchQueue.main.async {
                    self.currentLiveViewImage = img
                    self.fpsCounter += 1
                    // 同时更新 LiveViewStreamService 的帧
                    if let frame = LiveViewParser.parse(rawPayload: payload) {
                        LiveViewStreamService.shared.updateFrame(frame)
                    }
                }
            } else {
                self.noteFrameError("取景帧 JPEG 解码失败（\(jpegData.count)B）")
            }
        }
    }

    /// 取景帧失败记录（节流：1 秒最多记一次，避免刷爆诊断栏）
    private func noteFrameError(_ text: String) {
        let now = Date()
        if let last = lastFrameErrorAt, now.timeIntervalSince(last) < 1.0 { return }
        lastFrameErrorAt = now
        print("[UsbCameraManager] \(text)")
        DispatchQueue.main.async { [weak self] in self?.ptpDiagnostic = text }
    }

    // MARK: - v1.0.4：真实快门（InitiateCapture 0x100E）

    /// 向相机发拍摄命令。成功只代表“快门已触发”，成片随后经 didAdd 回调
    /// 自动下载（见 cameraDevice(_:didAdd:)），再由界面回显真图。
    /// 之前快门按钮是假的：不发任何命令，只随机编个 DSC_xxxx.JPG 弹“拍摄完成”。
    public func capturePhoto(completion: @escaping (Bool, String?) -> Void) {
        guard let camera = activeCamera, isUsbConnected else {
            completion(false, "相机未连接")
            return
        }
        // v1.0.6：拍照时先停掉 20fps 取景帧拉取，给快门和成片下载让出 PTP 通道；
        // 下载回来（didDownloadPhoto）或拍后复查（checkForNewCapture）时会恢复取景。
        pauseLiveViewFetching()
        // v1.0.6：先记下卡里已有的对象句柄，再发快门——拍完复查时靠这个认新照片。
        // 快照是异步的，等它回来再发快门，免得新照片混进快照里认不出来。
        fetchAllObjectHandles { [weak self] handles in
            guard let self = self else { completion(false, "相机断开"); return }
            if let handles = handles {
                self.preCaptureHandles = Set(handles)
                self.preCaptureSnapshotOK = true
            } else {
                // 拍前快照没读到，复查时不认新照片（只靠 didAdd），免得把整张卡都当成新拍的
                self.preCaptureSnapshotOK = false
            }
            // v1.0.5：存储 ID 不能用 0xFFFFFFFF（“任意存储”），尼康会报 0x2008 无效存储 ID。
            // Z30 只有一个 SD 卡槽，存储 ID 是 0x00010001。
            let cmd = self.buildPTPCommandPacket(opCode: NikonPTPOpCode.initiateCapture.rawValue, params: [0x00010001, 0])
            camera.requestSendPTPCommand(cmd, outData: nil) { [weak self] (_, responseData, error) in
                if let error = error {
                    DispatchQueue.main.async { [weak self] in self?.resumeLiveViewFetching() }
                    completion(false, error.localizedDescription)
                    return
                }
                var code: UInt16? = nil
                if responseData.count >= 8 {
                    let t = UInt16(responseData[4]) | (UInt16(responseData[5]) << 8)
                    if t == 0x0003 {
                        code = UInt16(responseData[6]) | (UInt16(responseData[7]) << 8)
                    }
                }
                if let code = code, code != 0x2001 {
                    self?.setDiagnostic(String(format: "快门被拒 0x%04X", code))
                    DispatchQueue.main.async { [weak self] in self?.resumeLiveViewFetching() }
                    completion(false, String(format: "相机返回 0x%04X", code))
                    return
                }
                print("[UsbCameraManager] 快门已触发，等待相机回传成片")
                completion(true, nil)
                // v1.0.6：2.5s 后主动查一次新照片（didAdd 没来也兜底）；查完恢复取景
                self?.scheduleCaptureCheck()
            }
        }
    }

    // MARK: - v1.0.4：真实调参（SetDevicePropValue 0x1016，值走数据阶段）

    /// 设置单个设备属性。USB 上 outData 就是数据阶段的值。
    /// v1.0.6：调用方先改显示再发命令（乐观更新），失败再恢复旧值；
    /// 发命令前先停掉 20fps 取景帧拉取，不然 Set 命令要排在成堆帧命令后面等好几秒。
    public func setCameraProp(code: UInt16, value: Data, completion: @escaping (Bool) -> Void) {
        guard let camera = activeCamera, isUsbConnected else { completion(false); return }
        pauseLiveViewFetching()
        let cmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.setDevicePropValue.rawValue,
                                        params: [UInt32(code)])
        camera.requestSendPTPCommand(cmd, outData: value) { [weak self] (_, responseData, error) in
            // 恢复取景（在主线程，因为要重建 Timer）
            DispatchQueue.main.async { [weak self] in self?.resumeLiveViewFetching() }
            guard error == nil else {
                self?.setDiagnostic("设置属性 0x\(String(code, radix: 16)) 出错：\(error!.localizedDescription)")
                completion(false)
                return
            }
            var respCode: UInt16? = nil
            if responseData.count >= 8 {
                let t = UInt16(responseData[4]) | (UInt16(responseData[5]) << 8)
                if t == 0x0003 {
                    respCode = UInt16(responseData[6]) | (UInt16(responseData[7]) << 8)
                }
            }
            let ok = respCode == nil || respCode == 0x2001
            if !ok {
                self?.setDiagnostic(String(format: "设置属性被拒 0x%04X", respCode!))
            }
            completion(ok)
        }
    }

    private func findJPEGStart(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 2 else { return nil }
        for i in 0..<(bytes.count - 1) {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 {
                return i
            }
        }
        return nil
    }
}

// MARK: - Double 格式化辅助
private extension Double {
    var clean: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
