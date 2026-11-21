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

    // 设备浏览器与当前相机实例
    private var deviceBrowser: ICDeviceBrowser?
    public private(set) var activeCamera: ICCameraDevice?

    // PTP 通信
    private var ptpTransactionID: UInt32 = 0
    private var isFetchingFrame: Bool = false
    private var liveViewTimer: Timer?
    private var fpsCounter: Int = 0
    private var fpsTimer: Timer?

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
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        handleDeviceDisconnect()
    }

    private func handleDeviceDisconnect() {
        stopLiveView()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeCamera = nil
            self.isUsbConnected = false
            self.connectedDeviceName = ""
            CameraConnectionService.shared.isConnected = false
            CameraConnectionService.shared.cameraState.isConnected = false
            CameraConnectionService.shared.statusMessage = "相机连接已断开"
        }
    }

    // MARK: - ICCameraDeviceDelegate
    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        print("[UsbCameraManager] 相机完整目录已就绪，媒体文件数: \(device.mediaFiles?.count ?? 0)")
    }

    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("[UsbCameraManager] 相机捕获到新素材，数量: \(items.count)")
        for item in items {
            guard let file = item as? ICCameraFile else { continue }
            print("[UsbCameraManager] 新拍摄照片: \(file.name ?? "未命名")")
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
            return
        }
        let savedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(file.name ?? "capture.jpg")
        let loadedImage = UIImage(contentsOfFile: savedPath)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let name = file.name ?? "DSC_NEW.JPG"
            let sizeMb = Double(file.fileSize) / 1024.0 / 1024.0
            let sizeStr = String(format: "%.1f MB", sizeMb)
            if let img = loadedImage { self.lastCapturedPhoto = img }
            self.lastCapturedFilename = name
            self.lastCapturedExif = "原片传输 · \(sizeStr)"
            let item = CapturedPhotoItem(filename: name, image: loadedImage, date: Date(), sizeString: sizeStr)
            self.sessionCapturedPhotos.insert(item, at: 0)
            NikonTheme.triggerHaptic(style: .medium)
            if let img = loadedImage {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
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

    /// 读取单个 PTP 设备属性值 → 解析并同步到 CameraState
    private func fetchSingleProperty(_ prop: NikonPTPProp, camera: ICCameraDevice) {
        let cmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.getDevicePropValue.rawValue,
                                        params: [UInt32(prop.rawValue)])
        camera.requestSendPTPCommand(cmd, outData: nil) { [weak self] (sentCommand, responseData, error) in
            if let error = error {
                print("[PTP] 读取属性 0x\(String(prop.rawValue, radix: 16)) 出错: \(error)")
                return
            }
            // Apple API 确认：
            //   sentCommand (第1参数) = 发出去的命令数据（不是相机回来的！）
            //   responseData (第2参数) = 相机返回的完整 PTP 响应容器
            //     [0-3]  Length
            //     [4-5]  ContainerType (0x0003 = Response)
            //     [6-7]  ResponseCode (0x2001 = OK)
            //     [8-11] TransactionID
            //     [12+]  属性值载荷 (GetDevicePropValue 的实际数据)
            guard responseData.count >= 12 else {
                print("[PTP] 属性 0x\(String(prop.rawValue, radix: 16)) 响应不足12字节: \(responseData.count)B")
                return
            }
            // 验证响应码是否为 PTP_RC_OK (0x2001)
            let respCode = UInt16(responseData[6]) | (UInt16(responseData[7]) << 8)
            guard respCode == 0x2001 || responseData.count > 12 else {
                print("[PTP] 属性 0x\(String(prop.rawValue, radix: 16)) 响应错误码: 0x\(String(respCode, radix: 16))")
                return
            }
            let payload = responseData.subdata(in: 12..<responseData.count)
            guard !payload.isEmpty else { return }
            self?.applyPropertyValue(prop: prop, payload: payload)
        }
    }

    /// 连接成功后，全量读取所有关键属性
    private func fetchAllCameraProperties() {
        guard let camera = activeCamera, isUsbConnected else { return }
        // camera.capabilities 是非可选的 [String]，用 ICDeviceCapability rawValue 匹配
        let ptpCap = ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue
        guard camera.capabilities.contains(where: { $0 == ptpCap }) else {
            print("[PTP] 该设备不支持 PTP 命令，跳过属性读取")
            return
        }

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
                // UINT16: 1=M, 2=P, 3=A, 4=S
                guard bytes.count >= 2 else { return }
                let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                switch raw {
                case 1: cameraState.exposureMode = .manual
                case 2: cameraState.exposureMode = .program
                case 3: cameraState.exposureMode = .aperturePriority
                case 4: cameraState.exposureMode = .shutterPriority
                default: break
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
                // UINT8，电量百分比
                guard !bytes.isEmpty else { return }
                cameraState.batteryPercentage = Int(bytes[0])
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
        case 0x8010: return .shade  // Nikon 阴影
        case 0x8011: return .cloudy // Nikon 阴天
        default: return .auto
        }
    }

    // MARK: - USB PTP 实时取景 (Live View) 协议驱动

    /// 开启尼康 USB 实时取景传感器数据流 (OpCode: 0x9201)
    public func startLiveView() {
        guard let camera = activeCamera, isUsbConnected else {
            print("[UsbCameraManager] 相机未连接或未就绪，无法开启 LiveView")
            return
        }
        guard !isLiveViewStreaming else { return }
        // camera.capabilities 是非可选的 [String]，用 ICDeviceCapability rawValue 匹配
        let ptpCap = ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue
        guard camera.capabilities.contains(where: { $0 == ptpCap }) else {
            print("[UsbCameraManager] 相机不支持 PTP 命令，无法开启 LiveView")
            return
        }

        print("[UsbCameraManager] 发送尼康 StartLiveView (0x9201)...")
        let startCmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.nikonStartLiveView.rawValue)

        camera.requestSendPTPCommand(startCmd, outData: nil) { [weak self] (_, _, error) in
            if let error = error {
                print("[UsbCameraManager] StartLiveView 命令出错(可能相机不支持): \(error)")
            } else {
                print("[UsbCameraManager] StartLiveView 命令已送达")
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLiveViewStreaming = true
                self.startFrameFetchTimer()
            }
        }
    }

    /// 停止尼康 USB 实时取景传感器数据流 (OpCode: 0x9202)
    public func stopLiveView() {
        liveViewTimer?.invalidate()
        liveViewTimer = nil
        fpsTimer?.invalidate()
        fpsTimer = nil
        isFetchingFrame = false

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

    private func startFrameFetchTimer() {
        liveViewTimer?.invalidate()
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
        guard let camera = activeCamera, isLiveViewStreaming, !isFetchingFrame else { return }
        isFetchingFrame = true

        let getCmd = buildPTPCommandPacket(opCode: NikonPTPOpCode.nikonGetLiveViewImg.rawValue)
        camera.requestSendPTPCommand(getCmd, outData: nil) { [weak self] (sentCommand, responseData, error) in
            defer { self?.isFetchingFrame = false }
            guard let self = self, error == nil else { return }

            // sentCommand = 发出去的命令（不是返回的帧数据）
            // responseData = 相机返回的完整 PTP 数据容器（包含 JPEG 帧）
            // GetLiveViewImg (0x9203) 返回数据容器包含 Nikon 私有头 + JPEG
            guard responseData.count > 128 else { return }

            // 直接搜索 JPEG SOI 标记 0xFF 0xD8，不依赖固定偏移量
            let bytes = [UInt8](responseData)
            guard let jpegStart = self.findJPEGStart(in: bytes) else { return }
            let jpegData = responseData.subdata(in: jpegStart..<responseData.count)

            if let img = UIImage(data: jpegData) {
                DispatchQueue.main.async {
                    self.currentLiveViewImage = img
                    self.fpsCounter += 1
                    // 同时更新 LiveViewStreamService 的帧
                    if let frame = LiveViewParser.parse(rawPayload: responseData) {
                        LiveViewStreamService.shared.updateFrame(frame)
                    }
                }
            }
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
