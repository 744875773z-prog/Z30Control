//
//  PtpIpPacket.swift
//  Z30Control
//
//  PTP/IP 数据报文封包与二进制解包实现 (ISO 15740 小端序)
//

import Foundation

/// PTP/IP 报文解析与封装协议
public struct PtpIpPacket {
    
    // MARK: - 构建指令通道握手包 (InitCommandRequest)
    /// 手机向相机发送初始建立指令通道请求
    /// - Parameters:
    ///   - guid: 客户端唯一 16 字节 GUID
    ///   - friendlyName: 客户端设备名 (如 "iPhone Z30 Controller")
    public static func makeInitCommandRequest(guid: UUID = UUID(), friendlyName: String = "iPhone Controller") -> Data {
        var data = Data()
        var guidBytes = guid.uuid
        let guidData = withUnsafeBytes(of: &guidBytes) { Data($0) }
        
        let nameData = friendlyName.data(using: .utf16LittleEndian) ?? Data()
        let nullTerminator = Data([0x00, 0x00]) // UTF-16LE 终止符
        let version: UInt32 = 0x00010000 // PTP/IP 协议版本 1.0
        
        // 计算总包长度: 4 (Length) + 4 (Type) + 16 (GUID) + Name length + 2 (Null) + 4 (Version)
        let totalLength = UInt32(4 + 4 + 16 + nameData.count + 2 + 4)
        
        data.append(contentsOf: totalLength.littleEndianBytes)
        data.append(contentsOf: PtpIpPacketType.initCommandRequest.rawValue.littleEndianBytes)
        data.append(guidData)
        data.append(nameData)
        data.append(nullTerminator)
        data.append(contentsOf: version.littleEndianBytes)
        
        return data
    }
    
    // MARK: - 构建事件通道握手包 (InitEventRequest)
    /// 手机向相机发送事件通道建立请求 (携带指令通道返回的 ConnectionNumber)
    public static func makeInitEventRequest(connectionNumber: UInt32) -> Data {
        var data = Data()
        let totalLength: UInt32 = 4 + 4 + 4
        
        data.append(contentsOf: totalLength.littleEndianBytes)
        data.append(contentsOf: PtpIpPacketType.initEventRequest.rawValue.littleEndianBytes)
        data.append(contentsOf: connectionNumber.littleEndianBytes)
        
        return data
    }
    
    // MARK: - 构建标准 PTP 命令请求包 (CmdRequest)
    /// 发送 PTP 指令请求
    /// - Parameters:
    ///   - opCode: 操作码 (例如 StartLiveView, GetObjectHandles)
    ///   - transactionId: 事务自增 ID
    ///   - dataPhase: 数据阶段 (1=无数据流, 2=发数据, 3=收数据)
    ///   - params: 参数列表 (0~5个 UInt32)
    public static func makeCmdRequest(
        opCode: UInt16,
        transactionId: UInt32,
        dataPhase: UInt32 = 1,
        params: [UInt32] = []
    ) -> Data {
        var data = Data()
        let paramCount = params.count
        let totalLength = UInt32(4 + 4 + 4 + 2 + 4 + (paramCount * 4))
        
        data.append(contentsOf: totalLength.littleEndianBytes)
        data.append(contentsOf: PtpIpPacketType.cmdRequest.rawValue.littleEndianBytes)
        data.append(contentsOf: dataPhase.littleEndianBytes)
        data.append(contentsOf: opCode.littleEndianBytes)
        data.append(contentsOf: transactionId.littleEndianBytes)
        
        for param in params {
            data.append(contentsOf: param.littleEndianBytes)
        }
        
        return data
    }
    
    // MARK: - 构建心跳包 (Ping)
    public static func makePing() -> Data {
        var data = Data()
        let totalLength: UInt32 = 8
        data.append(contentsOf: totalLength.littleEndianBytes)
        data.append(contentsOf: PtpIpPacketType.ping.rawValue.littleEndianBytes)
        return data
    }
}

// MARK: - 辅助拓展：数值小端序字节转换
extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
