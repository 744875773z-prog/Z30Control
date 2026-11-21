//
//  CameraConnectionService.swift
//  Z30Control
//
//  连接生命周期与多模式 (USB-C 有线直连 / 相机热点 / 局域网广播) 强化调度服务
//

import Foundation
import Combine
import Network

public enum ConnectionTransportMode: String, CaseIterable, Identifiable {
    case usbC = "USB-C 有线直连 (推荐)"
    case cameraAP = "相机 Wi-Fi 热点"
    case wifiLocal = "路由器局域网"
    
    public var id: String { rawValue }
}

public final class CameraConnectionService: ObservableObject, PtpIpClientDelegate {
    
    public static let shared = CameraConnectionService()
    
    // MARK: - 发布属性
    @Published public var selectedModel: String = "Z 30"
    @Published public var transportMode: ConnectionTransportMode = .usbC
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var statusMessage: String = "就绪 - 等待连接相机"
    @Published public var targetIP: String = "192.168.1.1" // USB-C 有线默认网段
    @Published public var isSearchingLAN: Bool = false
    @Published public var discoveredCameras: [String] = []
    // v1.0.7：手动输入的相机 IP（记住上次的，下次不用再输）
    @Published public var manualIP: String = ""
    @Published public var showingWiredHelp: Bool = false
    
    public let client: PtpIpClient
    public let cameraState: CameraState
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(client: PtpIpClient = PtpIpClient(), cameraState: CameraState = CameraState()) {
        self.client = client
        self.cameraState = cameraState
        self.client.delegate = self
        // v1.0.7：记住上次手动输过的相机 IP
        self.manualIP = UserDefaults.standard.string(forKey: "z30.lastCameraIP") ?? ""
        
        // 1. 立即启动像素蛋糕同款 ImageCaptureCore 原生 USB 硬件总线监听
        UsbCameraManager.shared.startListening()
        
        // 2. 启动时自动触发自适应连接检测
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.autoDetectAndConnect()
        }
    }
    
    // MARK: - 模式切换自适应目标 IP
    public func setTransportMode(_ mode: ConnectionTransportMode) {
        self.transportMode = mode
        switch mode {
        case .usbC:
            // USB-C 直连线缆模式 (尼康设置菜单 -> USB 数据连接 -> [iPhone] 时，通常为 192.168.1.1)
            self.targetIP = "192.168.1.1"
            self.statusMessage = "已设为【USB-C 有线】模式 (192.168.1.1)"
        case .cameraAP:
            // 相机作为独立 Wi-Fi 热点时，尼康默认网关 IP 永远是 192.168.0.1
            self.targetIP = "192.168.0.1"
            self.statusMessage = "已设为【相机热点】模式 (192.168.0.1)"
        case .wifiLocal:
            self.statusMessage = "正在检索局域网相机..."
            discoverCamerasInLAN()
        }
    }
    
    // MARK: - 自动并发双网段探测直连
    public func autoDetectAndConnect() {
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
        statusMessage = "正在探测 USB 硬件总线与相机..."
        
        // 1. 优先激活像素蛋糕同款 ImageCaptureCore 原生硬件总线扫描
        UsbCameraManager.shared.startListening()
        if let cam = UsbCameraManager.shared.activeCamera {
            cam.requestOpenSession()
            return
        }
        
        // 2. 同时探测网络信道 (默认地址 192.168.1.1:15740 与 192.168.0.1:15740)
        self.targetIP = "192.168.1.1"
        self.client.connect(host: "192.168.1.1", port: 15740)
        
        // 3秒后如果未连上，尝试无线热点 192.168.0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            print("[ConnectionService] 尝试备选无线网段 192.168.0.1...")
            self.targetIP = "192.168.0.1"
            self.client.connect(host: "192.168.0.1", port: 15740)
        }
    }
    
    // MARK: - v1.0.7：局域网真扫描（取代之前等 1.2 秒就报 192.168.1.1 的假搜索）
    // 做法：读本机 Wi-Fi（en0）地址和子网掩码，算出整个网段，并行 TCP 探测每个地址
    // 的 15740 端口（尼康 PTP/IP 端口）。开着这个端口的，基本就是相机。
    // 宿舍路由器、手机热点都走同一套逻辑——扫的是手机当前连上的那个网。
    public func discoverCamerasInLAN() {
        guard !isSearchingLAN else { return }
        isSearchingLAN = true
        discoveredCameras = []
        statusMessage = "正在局域网搜索尼康 PTP/IP 相机..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let (localIP, netmask) = Self.wifiInterfaceAddress() else {
                DispatchQueue.main.async {
                    self.isSearchingLAN = false
                    self.statusMessage = "未连 Wi-Fi：请先让手机连上与相机相同的网络（宿舍路由器或手机热点）"
                }
                return
            }
            let hosts = Self.hosts(inSubnet: localIP, netmask: netmask)
            guard !hosts.isEmpty else {
                DispatchQueue.main.async {
                    self.isSearchingLAN = false
                    self.statusMessage = "本机地址 \(localIP) 算不出网段，请手动输入相机 IP"
                }
                return
            }
            print("[ConnectionService] 本机 \(localIP)，扫描 \(hosts.count) 个地址的 15740 端口")
            self.probeHosts(hosts, port: 15740, timeout: 0.6) { found in
                DispatchQueue.main.async {
                    self.isSearchingLAN = false
                    self.discoveredCameras = found
                    if let first = found.first {
                        self.targetIP = first
                        self.statusMessage = "发现 \(found.count) 台相机：\(found.joined(separator: "、"))"
                    } else {
                        self.statusMessage = "局域网里没找到相机：确认相机已连上同一网络（MENU → 网络 → 连接到电脑），或手动输入相机 IP"
                    }
                }
            }
        }
    }

    /// 手动输入相机 IP 直连（相机 MENU → 网络 → 连接到电脑里能看到 IP，也可以在路由器后台查）。
    /// 格式不对返回 false，界面不跳转，让用户看到报错再改。
    @discardableResult
    public func connectToManualIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidIPv4(trimmed) else {
            statusMessage = "IP 格式不对，例如 192.168.1.100"
            return false
        }
        manualIP = trimmed
        targetIP = trimmed
        UserDefaults.standard.set(trimmed, forKey: "z30.lastCameraIP")
        startConnecting()
        return true
    }

    private static func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard let n = Int(p), (0...255).contains(n) else { return false }
            return !p.isEmpty && p.allSatisfy { $0.isNumber }
        }
    }

    /// 读本机 Wi-Fi 网卡（en0）的 IPv4 地址和子网掩码。没连 Wi-Fi 时返回 nil。
    private static func wifiInterfaceAddress() -> (ip: String, netmask: String)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & Int32(IFF_UP)) != 0
            let isRunning = (flags & Int32(IFF_RUNNING)) != 0
            let name = String(cString: current.pointee.ifa_name)
            if isUp && isRunning && name == "en0",
               let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               let mask = current.pointee.ifa_netmask {
                var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST)
                getnameinfo(mask, socklen_t(mask.pointee.sa_len), &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST)
                return (String(cString: ipBuf), String(cString: maskBuf))
            }
            cursor = current.pointee.ifa_next
        }
        return nil
    }

    /// 按 IP + 子网掩码算出网段内全部主机地址（去掉网络地址和广播地址）。
    /// 主机数超过 512（比如 /16 大网）直接返回空，免得扫爆。
    static func hosts(inSubnet ip: String, netmask: String) -> [String] {
        func octets(_ s: String) -> [UInt8]? {
            let parts = s.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4 else { return nil }
            return parts
        }
        guard let ipO = octets(ip), let maskO = octets(netmask) else { return [] }
        let ip32 = ipO.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let mask32 = maskO.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let network = ip32 & mask32
        let broadcast = network | ~mask32
        guard broadcast > network + 1 else { return [] }
        let hostCount = broadcast - network - 1
        guard hostCount <= 512 else { return [] }
        return (1...hostCount).map { h in
            let a = network + h
            return "\((a >> 24) & 0xFF).\((a >> 16) & 0xFF).\((a >> 8) & 0xFF).\(a & 0xFF)"
        }
    }

    /// 并行探测一批主机的 TCP 端口（32 路并发，单点超时 0.6s），返回能连通的地址。
    private func probeHosts(_ hosts: [String], port: UInt16, timeout: TimeInterval, completion: @escaping ([String]) -> Void) {
        var found: [String] = []
        let lock = NSLock()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 32
        queue.qualityOfService = .userInitiated
        for host in hosts {
            queue.addOperation {
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                self.probeHost(host, port: port, timeout: timeout) { result in
                    ok = result
                    sem.signal()
                }
                sem.wait()
                if ok {
                    lock.lock()
                    found.append(host)
                    lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        completion(found.sorted(by: { $0.compare($1, options: .numeric) == .orderedAscending }))
    }

    /// 单个 TCP 探测：连上 15740 即算找到（这个端口基本只有尼康 PTP/IP 在用；
    /// 真是不是相机，点连接时的 PTP/IP 握手会再校验一次，失败会正常报错）。
    private func probeHost(_ ip: String, port: UInt16, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { completion(false); return }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        let lock = NSLock()
        var finished = false
        let finish: (Bool) -> Void = { ok in
            lock.lock()
            let first = !finished
            finished = true
            lock.unlock()
            guard first else { return }
            conn.cancel()
            completion(ok)
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled: finish(false)
            default: break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
    
    // MARK: - 手动发起连接
    public func startConnecting() {
        isConnecting = true
        statusMessage = "正在连接 \(selectedModel) (\(targetIP):15740)..."
        client.connect(host: targetIP, port: 15740)
    }
    
    public func disconnect() {
        client.disconnect(isIntentional: true)
        UsbCameraManager.shared.stopListening()
        isConnected = false
        isConnecting = false
        statusMessage = "已断开连接"
        cameraState.isConnected = false
    }
    
    // MARK: - PtpIpClientDelegate 回调
    public func ptpClient(_ client: PtpIpClient, didChangeStatus status: PtpConnectionStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch status {
            case .disconnected:
                self.isConnected = false
                self.isConnecting = false
                self.statusMessage = "未连接 (请检查线缆或相机设置)"
                self.cameraState.isConnected = false
            case .connecting:
                self.isConnecting = true
                self.statusMessage = "正在连接 \(self.targetIP)..."
            case .handshaking:
                self.statusMessage = "正在握手…首次连接请在相机屏幕上按 OK 确认"
            case .connected(let cameraName, let connNum):
                self.isConnected = true
                self.isConnecting = false
                self.statusMessage = "已连接: \(cameraName)"
                self.cameraState.isConnected = true
                self.cameraState.modelName = cameraName
                NikonTheme.triggerHaptic(style: .heavy)
                // v1.0.3：连上后立即拉取卡内文件索引，供图库页显示。
                // 取景流不在这里启动——由取景页出现时启动（见 LiveViewMonitorView），
                // 避免用户停在控制页时相机一直出取景流。
                MediaSyncService.shared.refreshIndexFromCamera()
                // v1.0.4：同时读一次存储卡容量与电量（之前仪表盘一直是假数）
                MediaSyncService.shared.refreshStorageFromCamera()
            case .reconnecting(let attempt):
                self.isConnecting = true
                self.statusMessage = "正在尝试重连 (\(attempt))..."
            case .failed(let errorMsg):
                self.isConnected = false
                self.isConnecting = false
                self.statusMessage = "连接未就绪: \(errorMsg)"
                self.cameraState.isConnected = false
            }
        }
    }
    
    public func ptpClient(_ client: PtpIpClient, didReceiveEvent eventCode: UInt16, transactionId: UInt32, params: [UInt32]) {
        if let objectId = params.first {
            MediaSyncService.shared.handlePtpEvent(eventCode: eventCode, objectId: objectId)
        }
    }
    
    public func ptpClient(_ client: PtpIpClient, didUpdateLiveViewFrame frame: LiveViewFrame) {
        LiveViewStreamService.shared.updateFrame(frame)
    }
}
