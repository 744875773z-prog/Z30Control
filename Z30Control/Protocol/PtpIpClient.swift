//
//  PtpIpClient.swift
//  Z30Control
//
//  PTP/IP 客户端（v1.0.3 修复版）
//  本次修复：
//  1. 指令通道串行执行器：PTP 同一时间只允许一个事务在途。之前取景循环、
//     图库拉取、保护键速传可能同时发包、互相抢响应报文，导致流错乱。
//  2. 新增数据阶段（Data Phase）读取：GetLiveViewImg / GetObjectHandles /
//     GetObject 等操作的返回是 StartData + Data/EndData + CmdResponse 多包
//     序列，之前只读一个包就当成整帧，导致取景帧永远解析失败。
//  3. 新增 GetStorageIDs / GetObjectHandles / GetObjectInfo / GetObject /
//     GetThumb 真实方法（之前客户端根本没有这些方法，图库只能用假数据）。
//  4. 删除 Ping 心跳：相机回的 Pong 会混进指令通道，被当成下一条命令的
//     响应。TCP keepalive 已开启，会话由正常流量维持。
//  5. 删除连接后立即发的畸形 SetDevicePropValue(0xD1A2)：按 PTP 规范
//     SetDevicePropValue 只带 1 个参数（属性码），值要走数据阶段发送，
//     之前把值当第 2 个参数发，相机可能直接拒答。
//  6. OpenSession / StartLiveView 现在校验响应码，非 OK 不再谎报“已连接”。
//  7. SetDevicePropValue 按规范用数据阶段发送（供半按快门等调用）。
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

/// GetObjectInfo (0x1008) 解析结果
public struct PtpObjectInfo {
    public let handle: UInt32
    public let filename: String
    public let sizeBytes: UInt64
    public let formatCode: UInt16
    public let protectionStatus: UInt16
    public let captureDate: Date?
}

public final class PtpIpClient {
    
    public weak var delegate: PtpIpClientDelegate?
    
    // 网络通道与工作队列
    private var cmdConnection: NWConnection?
    private var eventConnection: NWConnection?
    private let workQueue = DispatchQueue(label: "com.z30control.ptpip.serial", qos: .userInitiated)
    
    // TCP 流式解包接收缓冲区
    private var cmdReceiveBuffer = Data()
    private var eventReceiveBuffer = Data()
    
    // 事务管理与状态机
    private var transactionId: UInt32 = 1
    private var connectionNumber: UInt32 = 0
    public private(set) var isSessionOpen = false
    public private(set) var isStreamingLiveView = false
    private var isTransactionBusy = false
    private var liveViewFailures = 0
    
    // 重连机制
    private var reconnectAttempt = 0
    // v1.0.10：握手超时用的轮次号，每次 connect() 加一，旧轮次的超时器不再生效
    private var connectionAttemptID: UInt64 = 0
    private var currentHost = "192.168.0.1"
    private var currentPort: UInt16 = 15740
    private var intentionalDisconnect = false
    
    // MARK: - 指令通道串行执行器
    // PTP 规范：同一时间只能有一个事务在途。所有经指令通道发包的操作
    // （无数据命令 / 数据接收 / 数据发送）都排队经这里执行，避免取景循环
    // 与图库拉取、速传下载互相抢响应报文。
    private struct CmdJob { let run: (@escaping () -> Void) -> Void }
    private var cmdJobQueue: [CmdJob] = []
    private var cmdJobRunning = false
    
    private func enqueueCmdJob(_ job: @escaping (@escaping () -> Void) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.cmdJobQueue.append(CmdJob(run: job))
            self.runNextCmdJob()
        }
    }
    
    private func runNextCmdJob() {
        guard !cmdJobRunning, !cmdJobQueue.isEmpty else { return }
        cmdJobRunning = true
        let job = cmdJobQueue.removeFirst()
        job.run { [weak self] in
            guard let self = self else { return }
            self.workQueue.async {
                self.cmdJobRunning = false
                self.runNextCmdJob()
            }
        }
    }
    
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
        self.intentionalDisconnect = false
        self.isTransactionBusy = false
        self.isStreamingLiveView = false
        self.liveViewFailures = 0
        self.cmdJobQueue.removeAll()
        self.cmdJobRunning = false
        self.status = .connecting
        // v1.0.10：先断掉上一轮残留的连接。相机同时只接受一个 PTP/IP 会话，
        // 连续点两次连接会留下两个半会话，相机可能直接不回握手。
        cmdConnection?.cancel()
        eventConnection?.cancel()
        cmdConnection = nil
        eventConnection = nil
        // v1.0.10：握手超时。之前这里没有任何超时：相机 TCP 端口通着
        // （局域网扫描能找到它）但不回 InitCommandAck 时，readNextCmdPacket
        // 永远等下去，界面一直显示“正在连接...”没有任何报错和重试。
        connectionAttemptID += 1
        let attemptID = connectionAttemptID

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
                break
            default:
                break
            }
        }
        cmdConnection?.start(queue: workQueue)

        // v1.0.12：握手超时分两档。TCP 不通 8 秒就报失败；TCP 通了但相机
        // 不回握手，给 30 秒——首次连接时相机要等用户在机身上按 OK 确认，
        // 不能 8 秒就判死刑。30 秒还没回才报失败，并提示走智能设备那条路。
        workQueue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self else { return }
            guard self.connectionAttemptID == attemptID else { return } // 已是新一轮连接
            switch self.status {
            case .connecting:
                self.disconnect(isIntentional: true)
                self.status = .failed("连接超时：连不上 \(host):15740。请确认手机和相机在同一 Wi-Fi，且相机 Wi-Fi 已打开。")
            case .handshaking:
                self.workQueue.asyncAfter(deadline: .now() + 22) { [weak self] in
                    guard let self = self else { return }
                    guard self.connectionAttemptID == attemptID else { return }
                    guard case .handshaking = self.status else { return }
                    self.disconnect(isIntentional: true)
                    self.status = .failed("握手超时：已连上 \(host):15740，但相机没有回 PTP/IP 握手。请确认相机在【连接到智能设备 → Wi-Fi 连接（STA 模式）】而不是【连接到电脑】，并在相机屏幕上按 OK 确认连接。")
                }
            default:
                break
            }
        }
    }
    
    // MARK: - 异常断线与自动指数退避重连
    private func handleConnectionFailure(_ reason: String) {
        guard !intentionalDisconnect else { return }
        if case .reconnecting = status { return } // 已在重连流程中，不重复触发
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
            guard self.cmdResponseCode(respPacket) == PtpResponseCode.ok.rawValue else {
                // 会话被拒（例如相机已被 SnapBridge 占用）：不要谎报已连接
                self.isSessionOpen = false
                let code = self.cmdResponseCode(respPacket) ?? 0
                self.status = .failed("会话开启被拒 (响应码 0x\(String(format: "%04X", code)))，请先退出 SnapBridge 再连")
                return
            }
            self.isSessionOpen = true
            self.status = .connected(cameraName: cameraName, connectionNumber: self.connectionNumber)
        }
    }
    
    // MARK: - 远程触控对焦 (Touch-to-Focus)
    /// 向相机下发屏幕触控对焦位置
    /// - Parameters:
    ///   - x: 归一化横坐标 (0.0 ~ 1.0)
    ///   - y: 归一化纵坐标 (0.0 ~ 1.0)
    public func setTouchFocus(x: Float, y: Float) {
        // 将归一化坐标转为尼康传感器内部对焦平面绝对坐标 (通常范围 0 ~ 10000)
        let focusX = UInt32(max(0, min(1.0, x)) * 10000)
        let focusY = UInt32(max(0, min(1.0, y)) * 10000)
        driveAutofocus(x: focusX, y: focusY, completion: nil)
    }

    // MARK: - AF-ON：自动对焦驱动（带回执）
    /// AfDrive (0x90C1，见 Wireshark packet-ptpip.h 的 PTP_OC_NIKON_AfDrive）
    /// 驱动自动对焦，参数为对焦平面坐标（0~10000）。AF-ON 对画面中心对焦：
    /// x=y=5000。回执 0x2001=OK；相机在手动对焦或未取景时可能拒答。
    // MARK: - v1.0.19：删除机内照片（DeleteObject 0x100B，图库批量删除用）
    /// 按句柄删卡里一张照片。响应 0x2001=删掉了，其他=没删成。
    /// 注意：删了就真没了，调用方（图库多选删除）必须先弹确认框。
    public func deleteObject(handle: UInt32, completion: ((Bool, UInt16?) -> Void)? = nil) {
        guard isSessionOpen else { completion?(false, nil); return }
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.deleteObject.rawValue,
            transactionId: nextTransactionId(),
            params: [handle]
        )
        sendCmdPacket(packet) { [weak self] resp in
            guard let self = self else { completion?(false, nil); return }
            let code = self.cmdResponseCode(resp)
            completion?(code == PtpResponseCode.ok.rawValue, code)
        }
    }

    public func driveAutofocus(x: UInt32, y: UInt32, completion: ((Bool, UInt16?) -> Void)? = nil) {
        guard isSessionOpen else { completion?(false, nil); return }
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.nikonAfDrive.rawValue,
            transactionId: nextTransactionId(),
            params: [x, y]
        )
        sendCmdPacket(packet) { [weak self] resp in
            guard let self = self else { completion?(false, nil); return }
            let code = self.cmdResponseCode(resp)
            completion?(code == PtpResponseCode.ok.rawValue, code)
        }
    }
    
    // MARK: - 按 PTP 规范设置设备属性（值走数据阶段发送）
    /// SetDevicePropValue (0x1016)：命令只带 1 个参数（属性码），值以
    /// StartData + EndData 数据阶段发送。之前把值当第 2 个参数发的写法
    /// 不符合规范，相机可能直接拒答。
    public func setDevicePropValue(code: UInt16, value: Data, completion: ((Bool) -> Void)? = nil) {
        guard isSessionOpen else { completion?(false); return }
        enqueueCmdJob { [weak self] done in
            guard let self = self else { done(); return }
            let transId = self.nextTransactionId()
            let packet = PtpIpPacket.makeCmdRequest(
                opCode: PtpOperationCode.setDevicePropValue.rawValue,
                transactionId: transId,
                dataPhase: 2,
                params: [UInt32(code)]
            )
            self.cmdConnection?.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self = self, error == nil else { completion?(false); done(); return }
                var start = Data()
                start.append(contentsOf: UInt32(20).littleEndianBytes)
                start.append(contentsOf: PtpIpPacketType.startDataPacket.rawValue.littleEndianBytes)
                start.append(contentsOf: transId.littleEndianBytes)
                start.append(contentsOf: UInt64(value.count).littleEndianBytes)
                var end = Data()
                end.append(contentsOf: UInt32(12 + value.count).littleEndianBytes)
                end.append(contentsOf: PtpIpPacketType.endDataPacket.rawValue.littleEndianBytes)
                end.append(contentsOf: transId.littleEndianBytes)
                end.append(value)
                self.cmdConnection?.send(content: start, completion: .contentProcessed { [weak self] e1 in
                    guard let self = self, e1 == nil else { completion?(false); done(); return }
                    self.cmdConnection?.send(content: end, completion: .contentProcessed { [weak self] e2 in
                        guard let self = self, e2 == nil else { completion?(false); done(); return }
                        self.readNextCmdPacket { resp in
                            completion?(self.cmdResponseCode(resp) == PtpResponseCode.ok.rawValue)
                            done()
                        }
                    })
                })
            })
        }
    }
    
    // MARK: - 触发物理半按快门 (测光与对焦锁)
    public func triggerHalfPress(active: Bool) {
        guard isSessionOpen else { return }
        let stateValue: UInt32 = active ? 0x0001 : 0x0000
        var value = Data()
        value.append(contentsOf: stateValue.littleEndianBytes)
        // 0xD00A 为尼康半按快门相关属性码（best-effort，未在真机上逐项验证）
        setDevicePropValue(code: 0xD00A, value: value, completion: nil)
    }
    
    // MARK: - 实时取景取流控制
    public func startLiveView() {
        guard isSessionOpen, !isStreamingLiveView else { return }
        isStreamingLiveView = true
        liveViewFailures = 0
        
        let packet = PtpIpPacket.makeCmdRequest(opCode: PtpOperationCode.nikonStartLiveView.rawValue, transactionId: nextTransactionId())
        sendCmdPacket(packet) { [weak self] resp in
            guard let self = self else { return }
            if self.cmdResponseCode(resp) != PtpResponseCode.ok.rawValue {
                // 相机拒绝进入取景（例如正在回放/录像）：停掉，避免空转刷请求
                self.isStreamingLiveView = false
                return
            }
            self.fetchNextLiveViewFrame()
        }
    }
    
    public func stopLiveView() {
        guard isStreamingLiveView else { return }
        isStreamingLiveView = false
        let packet = PtpIpPacket.makeCmdRequest(opCode: PtpOperationCode.nikonEndLiveView.rawValue, transactionId: nextTransactionId())
        sendCmdPacket(packet, completion: nil)
    }
    
    private func fetchNextLiveViewFrame() {
        guard isStreamingLiveView, !isTransactionBusy else { return }
        
        isTransactionBusy = true
        sendDataRequest(opCode: PtpOperationCode.nikonGetLiveViewImg.rawValue) { [weak self] data, code in
            guard let self = self else { return }
            self.isTransactionBusy = false
            
            if let data = data, code == PtpResponseCode.ok.rawValue,
               let frame = LiveViewParser.parse(rawPayload: data) {
                self.liveViewFailures = 0
                DispatchQueue.main.async {
                    self.delegate?.ptpClient(self, didUpdateLiveViewFrame: frame)
                }
            } else {
                self.liveViewFailures += 1
                if self.liveViewFailures >= 10 {
                    // 连续 10 帧失败：停掉取景，避免对相机狂发请求
                    self.isStreamingLiveView = false
                    return
                }
            }
            
            // 控制帧率平滑迭代 (30 FPS 周期为 33ms)
            if self.isStreamingLiveView {
                self.workQueue.asyncAfter(deadline: .now() + 0.033) {
                    self.fetchNextLiveViewFrame()
                }
            }
        }
    }
    
    // MARK: - 存储卡与文件操作（真实 PTP 操作，之前缺失）
    
    /// GetStorageIDs (0x1004)：取存储卷 ID 列表
    public func getStorageIDs(completion: @escaping ([UInt32]) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getStorageIDs.rawValue) { data, code in
            guard let data = data, code == PtpResponseCode.ok.rawValue else { completion([]); return }
            completion(Self.parseUInt32Array(data))
        }
    }
    
    /// GetObjectHandles (0x1007)：取某存储卷下的全部对象句柄
    /// - Parameters:
    ///   - storageID: 存储卷 ID，0xFFFFFFFF 表示全部存储卷
    public func getObjectHandles(storageID: UInt32 = 0xFFFFFFFF, completion: @escaping ([UInt32]) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getObjectHandles.rawValue, params: [storageID, 0, 0]) { data, code in
            guard let data = data, code == PtpResponseCode.ok.rawValue else { completion([]); return }
            completion(Self.parseUInt32Array(data))
        }
    }
    
    /// GetObjectInfo (0x1008)：取单个对象的文件名、大小、保护标记等
    public func getObjectInfo(handle: UInt32, completion: @escaping (PtpObjectInfo?) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getObjectInfo.rawValue, params: [handle]) { data, code in
            guard let data = data, code == PtpResponseCode.ok.rawValue else { completion(nil); return }
            completion(Self.parseObjectInfo(data, handle: handle))
        }
    }
    
    /// GetObject (0x1009)：下载对象原图数据
    public func getObject(handle: UInt32, completion: @escaping (Data?) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getObject.rawValue, params: [handle]) { data, code in
            completion(code == PtpResponseCode.ok.rawValue ? data : nil)
        }
    }
    
    /// GetThumb (0x100A)：下载对象缩略图（JPEG）
    public func getThumb(handle: UInt32, completion: @escaping (Data?) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getThumb.rawValue, params: [handle]) { data, code in
            completion(code == PtpResponseCode.ok.rawValue ? data : nil)
        }
    }

    // MARK: - v1.0.4：存储卡信息、电量与真实快门（Wi-Fi）

    /// 存储卷信息（与 USB 端 UsbCameraManager.parseStorageInfo 同一套数据集布局）
    public struct PtpStorageInfo {
        public let maxCapacity: UInt64
        public let freeBytes: UInt64
        public let freeImages: UInt32
    }

    /// GetStorageInfo (0x1005)：取某存储卷的容量、剩余空间与相机自带的剩余张数
    public func getStorageInfo(storageID: UInt32, completion: @escaping (PtpStorageInfo?) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getStorageInfo.rawValue, params: [storageID]) { data, code in
            guard let data = data, code == PtpResponseCode.ok.rawValue, data.count >= 26 else {
                completion(nil)
                return
            }
            var maxCap: UInt64 = 0
            var freeB: UInt64 = 0
            for i in 0..<8 {
                maxCap |= UInt64(data[6 + i]) << (8 * i)
                freeB |= UInt64(data[14 + i]) << (8 * i)
            }
            let freeImages = UInt32(data[22]) | (UInt32(data[23]) << 8) | (UInt32(data[24]) << 16) | (UInt32(data[25]) << 24)
            completion(PtpStorageInfo(maxCapacity: maxCap, freeBytes: freeB, freeImages: freeImages))
        }
    }

    /// GetDevicePropValue (0x1015)：读单个设备属性的原始值（例如电量 0x5001 为 1 字节）
    public func getDevicePropValue(code: UInt16, completion: @escaping (Data?) -> Void) {
        sendDataRequest(opCode: PtpOperationCode.getDevicePropValue.rawValue, params: [UInt32(code)]) { data, code in
            completion(code == PtpResponseCode.ok.rawValue ? data : nil)
        }
    }

    /// InitiateCapture (0x100E)：触发快门。成功只代表“已触发”，成片随后经
    /// 事件通道的 ObjectAdded (0x4002) 回来，由 MediaSyncService 接手下载。
    public func initiateCapture(completion: @escaping (Bool) -> Void) {
        guard isSessionOpen else { completion(false); return }
        // v1.0.5：存储 ID 用 0x00010001（Z30 的 SD 卡槽），0xFFFFFFFF 会被尼康报 0x2008 无效存储 ID
        let packet = PtpIpPacket.makeCmdRequest(
            opCode: PtpOperationCode.initiateCapture.rawValue,
            transactionId: nextTransactionId(),
            params: [0x00010001, 0]
        )
        sendCmdPacket(packet) { [weak self] resp in
            completion(self?.cmdResponseCode(resp) == PtpResponseCode.ok.rawValue)
        }
    }
    
    // MARK: - 数据阶段请求（收数据方向的操作共用）
    /// 发送一条“收数据”命令并完整读回数据阶段：
    /// StartDataPacket -> [DataPacket ...] -> EndDataPacket -> CmdResponse。
    /// 之前取景循环只读一个包就当成整帧，是取景黑屏的另一半原因。
    public func sendDataRequest(opCode: UInt16, params: [UInt32] = [], completion: @escaping (Data?, UInt16?) -> Void) {
        guard isSessionOpen else { completion(nil, nil); return }
        enqueueCmdJob { [weak self] done in
            guard let self = self else { done(); return }
            let packet = PtpIpPacket.makeCmdRequest(opCode: opCode, transactionId: self.nextTransactionId(), dataPhase: 3, params: params)
            self.cmdConnection?.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self = self, error == nil else { completion(nil, nil); done(); return }
                self.readDataPhase(accumulated: Data()) { data, code in
                    completion(data, code)
                    done()
                }
            })
        }
    }
    
    /// 循环读包直到 EndDataPacket，再读一条 CmdResponse 收尾
    private func readDataPhase(accumulated: Data, completion: @escaping (Data?, UInt16?) -> Void) {
        readNextCmdPacket { [weak self] packet in
            guard let self = self else { return }
            guard packet.count >= 8 else { completion(nil, nil); return }
            let pktType = packet.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            switch pktType {
            case PtpIpPacketType.startDataPacket.rawValue:
                // 20 字节头，无载荷，继续读
                self.readDataPhase(accumulated: accumulated, completion: completion)
            case PtpIpPacketType.dataPacket.rawValue:
                var next = accumulated
                if packet.count > 12 { next.append(packet.subdata(in: 12..<packet.count)) }
                self.readDataPhase(accumulated: next, completion: completion)
            case PtpIpPacketType.endDataPacket.rawValue:
                var next = accumulated
                if packet.count > 12 { next.append(packet.subdata(in: 12..<packet.count)) }
                self.readNextCmdPacket { resp in
                    completion(next, self.cmdResponseCode(resp))
                }
            case PtpIpPacketType.cmdResponse.rawValue:
                // 出错时相机直接回 CmdResponse，没有数据阶段
                completion(nil, self.cmdResponseCode(packet))
            default:
                completion(nil, nil)
            }
        }
    }
    
    // MARK: - 响应码与数据解析辅助
    
    /// CmdResponse 包（type 7）里的响应码位于第 8~9 字节
    private func cmdResponseCode(_ packet: Data) -> UInt16? {
        guard packet.count >= 10 else { return nil }
        let pktType = packet.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard pktType == PtpIpPacketType.cmdResponse.rawValue else { return nil }
        return packet.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    /// 数据阶段首 4 字节为元素个数，后跟若干 UInt32
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
    
    /// 解析 PTP ObjectInfo 数据集（标准布局 52 字节固定头 + 字符串区）。
    /// 仓库自带模拟器的 ObjectInfo 是简化版（12 字节头 + 文件名），也兼容。
    private static func parseObjectInfo(_ data: Data, handle: UInt32) -> PtpObjectInfo? {
        // 标准布局：固定头 52 字节，文件名起于偏移 52
        if data.count >= 53,
           let parsed = parseStandardObjectInfo(data, handle: handle) {
            return parsed
        }
        // 简化布局（模拟器）：StorageID(U32) + 格式(U32) + 保护(U16) + 大小(U32)
        // + 1 字节名长 + UTF-16 文件名（注意：模拟器把格式包成 4 字节，
        // 不是标准 PTP 的 2 字节，偏移量和标准布局不一样）
        if data.count >= 15 {
            let formatCode = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            let protection = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let size = data.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self) }
            if let (name, _) = readPTPString(data, offset: 14), !name.isEmpty {
                return PtpObjectInfo(handle: handle, filename: name, sizeBytes: UInt64(size),
                                     formatCode: UInt16(formatCode & 0xFFFF), protectionStatus: protection, captureDate: nil)
            }
        }
        return nil
    }
    
    private static func parseStandardObjectInfo(_ data: Data, handle: UInt32) -> PtpObjectInfo? {
        guard data.count >= 52 else { return nil }
        let formatCode = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self) }
        let protection = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self) }
        let size = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard let (filename, nextOffset) = readPTPString(data, offset: 52), !filename.isEmpty else { return nil }
        var captureDate: Date? = nil
        if let (dateString, _) = readPTPString(data, offset: nextOffset), !dateString.isEmpty {
            captureDate = parsePTPDate(dateString)
        }
        return PtpObjectInfo(handle: handle, filename: filename, sizeBytes: UInt64(size),
                             formatCode: formatCode, protectionStatus: protection, captureDate: captureDate)
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
    
    /// PTP 日期 "YYYYMMDDTHHMMSS"（可能带 ".s" 小数部分）
    private static func parsePTPDate(_ text: String) -> Date? {
        let trimmed = String(text.prefix(15))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: trimmed)
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
            if totalLength >= 4, currentBuffer.count >= Int(totalLength) {
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
            guard let self = self else { return }
            // 传输层出错或对端关闭：走重连流程，不要让等响应的调用方永远挂起
            if error != nil || chunk == nil || chunk!.isEmpty {
                if !self.intentionalDisconnect {
                    self.handleConnectionFailure(error?.localizedDescription ?? "连接中断")
                }
                return
            }
            if channel == .cmd {
                self.cmdReceiveBuffer.append(chunk!)
            } else {
                self.eventReceiveBuffer.append(chunk!)
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
    /// 无数据命令：发包后读一条 CmdResponse 响应。经串行执行器排队。
    /// 注意：即使调用方不关心响应，也必须把这条响应读掉丢弃，否则它会
    /// 留在流里，被当成下一条命令的响应。
    private func sendCmdPacket(_ packet: Data, completion: ((Data) -> Void)?) {
        enqueueCmdJob { [weak self] done in
            guard let self = self else { done(); return }
            self.cmdConnection?.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self = self, error == nil else { done(); return }
                self.readNextCmdPacket { resp in
                    completion?(resp)
                    done()
                }
            })
        }
    }
    
    private func nextTransactionId() -> UInt32 {
        transactionId += 1
        return transactionId
    }
    
    public func disconnect(isIntentional: Bool = true) {
        if isIntentional {
            intentionalDisconnect = true
        }
        isStreamingLiveView = false
        isSessionOpen = false
        cmdJobQueue.removeAll()
        cmdJobRunning = false
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
