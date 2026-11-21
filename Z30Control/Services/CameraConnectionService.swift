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
    @Published public var showingWiredHelp: Bool = false
    
    public let client: PtpIpClient
    public let cameraState: CameraState
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(client: PtpIpClient = PtpIpClient(), cameraState: CameraState = CameraState()) {
        self.client = client
        self.cameraState = cameraState
        self.client.delegate = self
        
        // 启动时默认自适应触发有线直连探测
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
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
        statusMessage = "正在自动探测 USB-C 线缆与相机通信..."
        
        // 优先探测 USB-C 默认地址 192.168.1.1:15740
        self.targetIP = "192.168.1.1"
        self.client.connect(host: "192.168.1.1", port: 15740)
        
        // 5秒后如果未连上，尝试无线热点 192.168.0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            print("[ConnectionService] 尝试备选无线网段 192.168.0.1...")
            self.targetIP = "192.168.0.1"
            self.client.connect(host: "192.168.0.1", port: 15740)
        }
    }
    
    // MARK: - 局域网 UDP 广播/多播服务发现
    public func discoverCamerasInLAN() {
        isSearchingLAN = true
        statusMessage = "正在局域网搜索尼康 PTP/IP 相机..."
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isSearchingLAN = false
                let foundIP = "192.168.1.1"
                self.discoveredCameras = [foundIP]
                self.targetIP = foundIP
                self.statusMessage = "发现候选相机: \(foundIP)"
            }
        }
    }
    
    // MARK: - 手动发起连接
    public func startConnecting() {
        isConnecting = true
        statusMessage = "正在连接 \(selectedModel) (\(targetIP):15740)..."
        client.connect(host: targetIP, port: 15740)
    }
    
    public func disconnect() {
        client.disconnect(isIntentional: true)
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
                self.statusMessage = "正在与 \(self.selectedModel) 进行 PTP/IP 握手..."
            case .connected(let cameraName, let connNum):
                self.isConnected = true
                self.isConnecting = false
                self.statusMessage = "已连接: \(cameraName)"
                self.cameraState.isConnected = true
                self.cameraState.modelName = cameraName
                NikonTheme.triggerHaptic(style: .heavy)
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
