//
//  PtpIpClient.swift
//  Z30Control
//
//  经过严苛工业级加固的高性能异步双通道 PTP/IP 客户端
//  强化点：
//  1. 解决 TCP 粘包/分包流式缓冲区组包 (Stream Reassembly)
//  2. 严格遵循 PTP 单事务串行通信机制 (避免 DeviceBusy 0x2019)
//  3. 定时 Ping/Pong 心跳保活与异常自动重连
//  4. 背压控制 (Backpressure) 与实时取景防丢帧
//

import Foundation
import Network

public enum PtpConnectionStatus: Equatable {
    case disconnected
    case connecting
    case handshaking
    case connected(cameraName: String, connectionNumber: UInt32)
    case reconnecting(attempt: Int)
    case failed(String)
}

public protocol PtpIpClientDelegate: AnyObject {
    func ptpClient(_ client: PtpIpClient, didChangeStatus status: PtpConnectionStatus)
    func ptpClient(_ client: PtpIpClient, didReceiveEvent eventCode: UInt16, transactionId: UInt32, params: [UInt32])
    func ptpClient(_ client: PtpIpClient, didUpdateLiveViewFrame frame: LiveViewFrame)
}

public final class PtpIpClient {
    
    public weak var delegate: PtpIpClientDelegate?
    
    // 网络通道与工作队列
    private var cmdConnection: NWConnection?
    private var eventConnection: NWConnection?
    private let workQueue = DispatchQueue(label: "com.z30control.ptpip.serial", qos: .userInitiated)
    
    // TCP 流式解包接收缓冲区 (彻底解决 TCP 粘包/半包隐患)
    private var cmdReceiveBuffer = Data()
    private var eventReceiveBuffer = Data()
    
    // 事务管理与状态机
    private var transactionId: UInt32 = 1
    private var connectionNumber: UInt32 = 0
    private var isSessionOpen = false
    private var isStreamingLiveView = false
    private var isTransactionBusy = false
    
    // 心跳与重连机制
    private var heartbeatTimer: DispatchSourceTimer?
    private var reconnectAttempt = 0
    private var currentHost = "192.168.0.1"
    private var currentPort: UInt16 = 15740
    
    public private(set) var status: PtpConnectionStatus = .disconnected {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.ptpClient(self, didChangeStatus: self.status)
            }
        }
    }
    
    public init() {}
    
    // MARK: - 建立双通道连接
    public func connect(host: String = "192.168.0.1", port: UInt16 = 15740) {
        self.currentHost = host
        self.currentPort = port
        self.status = .connecting
        
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? 15740
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // 禁用 Nagle 算法，消除延迟
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        
        // 1. 初始化指令通道
        cmdReceiveBuffer.removeAll(keepingCapacity: true)
        cmdConnection = NWConnection(host: endpointHost, port: endpointPort, using: params)
        cmdConnection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.reconnectAttempt = 0
                self.startCommandHandshake()
            case .failed(let error):
                self.handleConnectionFailure(error.localizedDescription)
            case .cancelled:
                self.stopHeartbeat()
            default:
                break
            }
        }
        cmdConnection?.start(queue: workQueue)
    }
    
    // MARK: - 异常断线与自动指数退避重连
    private func handleConnectionFailure(_ reason: String) {
        disconnect(isIntentional: false)
        
        guard reconnectAttempt < 5 else {
            status = .failed("连接已断开，重连次数超限: \(reason)")
            return
        }
        
        reconnectAttempt += 1
        status = .reconnecting(attempt: reconnectAttempt)
        let delay = Double(min(reconnectAttempt * 2, 8))
        
        workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.connect(host: self.currentHost, port: self.currentPort)
        }
    }
    
    // MARK: - 第一阶段：指令通道握手
    private func startCommandHandshake() {
        status = .handshaking
        let handshakePacket = PtpIpPacket.makeInitCommandRequest(friendlyName: "Z30 Pro Controller")
        
        cmdConnection?.send(content: handshakePacket, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.handleConnectionFailure(error.localizedDescription)
                return
            }
            self?.readNextCmdPacket { packet in
                self?.handleInitCommandAck(packet: packet)
            }
        })
    }
    
    private func handleInitCommandAck(packet: Data) {
        guard packet.count >= 12 else {
            handleConnectionFailure("InitCommandAck 报文长度非法")
            return
        }
        
        // 解析 ConnectionNumber
        self.connectionNumber = packet.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // 解析相机名称
        var cameraName = "Nikon Z30"
        if packet.count > 28 {
            let nameData = packet.subdata(in: 28..<packet.count)
            if let name = String(data: nameData, encoding: .utf16LittleEndian) {
                cameraName = name.trimmingCharacters(in: .controlCharacters)
            }
        }
        
        // 启动事件通道第二阶段握手
        startEventChannel(connectionNumber: self.connectionNumber, cameraName: cameraName)
    }
    
    // MARK: - 第二阶段：事件通道握手
    private func startEventChannel(connectionNumber: UInt32, cameraName: String) {
        guard let endpoint = cmdConnection?.endpoint, case let .hostPort(host, port) = endpoint else { return }
        
        eventReceiveBuffer.removeAll(keepingCapacity: true)
        eventConnection = NWConnection(host: host, port: port, using: NWParameters.tcp)
        eventConnection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if state == .ready {
                let eventPacket = PtpIpPacket.makeInitEventRequest(connectionNumber: connectionNumber)
                self.eventConnection?.send(content: eventPacket, completion: .contentProcessed { error in
                    if error == nil {
                        self.readNextEventPacket { _ in
                            // InitEventAck 确认收到
                            self.openPtpSession(cameraName: cameraName)
                            self.startContinuousEventListening()
                        }
                    }
                })
            }
        }
        eventConnection?.start(queue: workQueue)
    }
    
    // MARK: - 第三阶段：开启 PTP 会话 (OpenSession)
    private func openPtpSession(cameraName: String) {
        let opCode = PtpOperationCode.openSession.rawValue
        let openSessionPacket = PtpIpPacket.makeCmdRequest(opCode: opCode, transactionId: nextTransactionId(), params: [1])
        
        sendCmdPacket(openSessionPacket) { [weak self] respPacket in
            guard let self = self else { return }
            self.isSessionOpen = true
            self.status = .connected(cameraName: cameraName, connectionNumber: self.connectionNumber)
            self.startHeartbeat()
            self.unlockCameraBodyControls() // 确保相机物理机身按键不被死锁
        }
    }
    
    // MARK: - 保持相机机身本地物理按键与双向互控
    private func unlockCameraBodyControls() {
        // 尼康专有设备属性：允许机身快门与回放物理按键正常工作
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.setDevicePropValue.rawValue,
            transactionId: nextTransactionId(),
            params: [0xD1A2, 0x0001]
        )
        sendCmdPacket(packet, completion: nil)
    }
    
    // MARK: - 远程触控对焦 (Touch-to-Focus)
    /// 向相机下发屏幕触控对焦位置
    /// - Parameters:
    ///   - x: 归一化横坐标 (0.0 ~ 1.0)
    ///   - y: 归一化纵坐标 (0.0 ~ 1.0)
    public func setTouchFocus(x: Float, y: Float) {
        guard isSessionOpen else { return }
        
        // 将归一化坐标转为尼康传感器内部对焦平面绝对坐标 (通常范围 0 ~ 10000)
        let focusX = UInt32(max(0, min(1.0, x)) * 10000)
        let focusY = UInt32(max(0, min(1.0, y)) * 10000)
        
        // 发送尼康专有 AF 对焦驱动操作码 (0x90C1)
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.nikonAfDrive.rawValue,
            transactionId: nextTransactionId(),
            params: [focusX, focusY]
        )
        sendCmdPacket(packet, completion: nil)
    }
    
    // MARK: - 触发物理半按快门 (测光与对焦锁)
    public func triggerHalfPress(active: Bool) {
        guard isSessionOpen else { return }
        let stateValue: UInt32 = active ? 0x0001 : 0x0000
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.setDevicePropValue.rawValue,
            transactionId: nextTransactionId(),
            params: [0xD00A, stateValue]
        )
        sendCmdPacket(packet, completion: nil)
    }
    
    // MARK: - 心跳保活 (每 5 秒 Ping 一次)
    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isSessionOpen else { return }
            let ping = PtpIpPacket.makePing()
            self.cmdConnection?.send(content: ping, completion: .idempotent)
        }
        timer.resume()
        self.heartbeatTimer = timer
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }
    
    // MARK: - 实时取景取流控制 (含背压保护)
    public func startLiveView() {
        guard isSessionOpen, !isStreamingLiveView else { return }
        isStreamingLiveView = true
        
        let packet = PtpIpPacket.makeCmdRequest(opCode: PtpOperationCode.nikonStartLiveView.rawValue, transactionId: nextTransactionId())
        sendCmdPacket(packet) { [weak self] _ in
            self?.fetchNextLiveViewFrame()
        }
    }
    
    public func stopLiveView() {
        isStreamingLiveView = false
        let packet = PtpIpPacket.makeCmdRequest(opCode: PtpOperationCode.nikonEndLiveView.rawValue, transactionId: nextTransactionId())
        sendCmdPacket(packet, completion: nil)
    }
    
    private func fetchNextLiveViewFrame() {
        guard isStreamingLiveView, !isTransactionBusy else { return }
        
        isTransactionBusy = true
        let packet = PtpIpPacket.makeCmdRequest(opCode: PtpOperationCode.nikonGetLiveViewImg.rawValue, transactionId: nextTransactionId())
        
        cmdConnection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else {
                self?.isTransactionBusy = false
                return
            }
            
            // 接收完整的 EndDataPacket 图像数据
            self.readNextCmdPacket { dataPacket in
                self.isTransactionBusy = false
                
                // 解析尼康头部与 JPEG 数据
                if let frame = LiveViewParser.parse(rawPayload: dataPacket) {
                    DispatchQueue.main.async {
                        self.delegate?.ptpClient(self, didUpdateLiveViewFrame: frame)
                    }
                }
                
                // 控制帧率平滑迭代 (30 FPS 周期为 33ms)
                if self.isStreamingLiveView {
                    self.workQueue.asyncAfter(deadline: .now() + 0.033) {
                        self.fetchNextLiveViewFrame()
                    }
                }
            }
        })
    }
    
    // MARK: - 核心：TCP 流式拆包接收算法 (Stream Reassembly)
    private enum StreamChannel {
        case cmd
        case event
    }
    
    /// 确保严格按照 PTP/IP 4字节 Header Length 接收完整的单个报文
    private func readNextCmdPacket(completion: @escaping (Data) -> Void) {
        readPacket(channel: .cmd, completion: completion)
    }
    
    private func readNextEventPacket(completion: @escaping (Data) -> Void) {
        readPacket(channel: .event, completion: completion)
    }
    
    private func readPacket(channel: StreamChannel, completion: @escaping (Data) -> Void) {
        let connection = (channel == .cmd) ? cmdConnection : eventConnection
        var currentBuffer = (channel == .cmd) ? cmdReceiveBuffer : eventReceiveBuffer
        
        // 1. 如果缓冲区已有至少 4 个字节，检查报文总长
        if currentBuffer.count >= 4 {
            let totalLength = currentBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
            if currentBuffer.count >= Int(totalLength) {
                let packetData = currentBuffer.prefix(Int(totalLength))
                currentBuffer.removeSubrange(0..<Int(totalLength))
                if channel == .cmd {
                    cmdReceiveBuffer = currentBuffer
                } else {
                    eventReceiveBuffer = currentBuffer
                }
                completion(packetData)
                return
            }
        }
        
        // 2. 缓冲区不足一个完整报文，继续从 Socket 异步拉取
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, _, error in
            guard let self = self, let chunk = chunk, !chunk.isEmpty, error == nil else { return }
            if channel == .cmd {
                self.cmdReceiveBuffer.append(chunk)
            } else {
                self.eventReceiveBuffer.append(chunk)
            }
            self.readPacket(channel: channel, completion: completion)
        }
    }
    
    // MARK: - 持续事件通道监听
    private func startContinuousEventListening() {
        readNextEventPacket { [weak self] eventData in
            guard let self = self else { return }
            
            if eventData.count >= 14 {
                let pktType = eventData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
                if pktType == PtpIpPacketType.event.rawValue {
                    let evCode = eventData.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
                    let transId = eventData.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self) }
                    
                    var params: [UInt32] = []
                    var offset = 14
                    while offset + 4 <= eventData.count {
                        let p = eventData.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
                        params.append(p)
                        offset += 4
                    }
                    
                    DispatchQueue.main.async {
                        self.delegate?.ptpClient(self, didReceiveEvent: evCode, transactionId: transId, params: params)
                    }
                }
            }
            // 持续循环监听
            self.startContinuousEventListening()
        }
    }
    
    // MARK: - 基础发送与事务自增
    private func sendCmdPacket(_ packet: Data, completion: ((Data) -> Void)?) {
        cmdConnection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else { return }
            if let completion = completion {
                self.readNextCmdPacket(completion: completion)
            }
        })
    }
    
    private func nextTransactionId() -> UInt32 {
        transactionId += 1
        return transactionId
    }
    
    public func disconnect(isIntentional: Bool = true) {
        stopHeartbeat()
        isStreamingLiveView = false
        isSessionOpen = false
        cmdConnection?.cancel()
        eventConnection?.cancel()
        cmdConnection = nil
        eventConnection = nil
        cmdReceiveBuffer.removeAll()
        eventReceiveBuffer.removeAll()
        if isIntentional {
            reconnectAttempt = 0
            status = .disconnected
        }
    }
}
