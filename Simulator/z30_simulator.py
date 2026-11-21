# -*- coding: utf-8 -*-
"""
Nikon Z30 PTP/IP Virtual Camera Simulator (完整全功能工业级仿真版)
全面支持:
1. PTP/IP 双通道握手与保活 (InitCommand, InitEvent, Ping/Pong)
2. 实时取景开启、抓帧、水平仪与对焦流 (StartLiveView, GetLiveViewImg, EndLiveView)
3. 存储卡与文件系统管理 (GetStorageIDs, GetObjectHandles, GetObjectInfo, GetObject, GetThumb)
4. 相机硬件属性调控 (GetDevicePropValue, SetDevicePropValue - 光圈/快门/ISO/优化校准)
5. “相机按保护键速传”异步事件广播 (ObjectInfoChanged 0x4007)
"""

import socket
import struct
import threading
import time
import uuid

PORT = 15740
CAMERA_NAME = "NIKON Z 30"
GUID = uuid.uuid4().bytes

# PTP/IP 包类型
PKT_INIT_CMD_REQ = 1
PKT_INIT_CMD_ACK = 2
PKT_INIT_EVENT_REQ = 3
PKT_INIT_EVENT_ACK = 4
PKT_CMD_REQ = 6
PKT_CMD_RESP = 7
PKT_EVENT = 8
PKT_START_DATA = 9
PKT_DATA = 10
PKT_END_DATA = 12
PKT_PING = 13
PKT_PONG = 14

# 操作码
OP_OPEN_SESSION = 0x1002
OP_CLOSE_SESSION = 0x1003
OP_GET_STORAGE_IDS = 0x1004
OP_GET_STORAGE_INFO = 0x1005
OP_GET_OBJECT_HANDLES = 0x1007
OP_GET_OBJECT_INFO = 0x1008
OP_GET_OBJECT = 0x1009
OP_GET_THUMB = 0x100A
OP_INITIATE_CAPTURE = 0x100E
OP_GET_DEVICE_PROP_VALUE = 0x1015
OP_SET_DEVICE_PROP_VALUE = 0x1016
OP_NIKON_START_LIVEVIEW = 0x9201
OP_NIKON_END_LIVEVIEW = 0x9202
OP_NIKON_GET_LIVEVIEW_IMG = 0x9203
OP_NIKON_AF_DRIVE = 0x90C1

# 响应码
RC_OK = 0x2001
RC_GENERAL_ERROR = 0x2002

def make_test_jpeg():
    header = b'\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00'
    sof = b'\xff\xc0\x00\x0b\x08\x00\x08\x00\x08\x01\x01\x11\x00'
    sos = b'\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xbf\x00'
    footer = b'\xff\xd9'
    return header + sof + sos + footer

TEST_JPEG = make_test_jpeg()

class NikonZ30Simulator:
    def __init__(self, host="0.0.0.0", port=PORT):
        self.host = host
        self.port = port
        self.server_sock = None
        self.cmd_sock = None
        self.event_sock = None
        self.connection_number = 1001
        self.is_running = False
        self.session_open = False
        self.live_view_active = False
        
        # 相机当前硬件属性状态
        self.props = {
            0x500D: "1/125",     # 快门速度
            0x5007: 400,         # 光圈 f/4.0 (数值 * 100)
            0x500F: 400,         # ISO 感光度
            0x5010: 0,           # 曝光补偿 0 EV
            0xD1A0: "Standard"   # 优化校准 Picture Control
        }
        
        # 虚拟卡内照片数据库
        self.media_db = {
            1001: {"name": "DSC_2641.JPG", "size": len(TEST_JPEG), "protected": 1},
            1002: {"name": "DSC_2642.JPG", "size": len(TEST_JPEG), "protected": 0},
            1003: {"name": "DSC_2631.JPG", "size": len(TEST_JPEG), "protected": 0},
            1004: {"name": "DSC_2632.NEF", "size": len(TEST_JPEG) * 3, "protected": 0}
        }
        
    def start(self):
        self.is_running = True
        self.server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_sock.bind((self.host, self.port))
        self.server_sock.listen(5)
        print(f"[Z30 模拟器] 服务已启动，正在监听 {self.host}:{self.port} (TCP)")
        print(f"[Z30 模拟器] 设备名: {CAMERA_NAME}，准备就绪...")
        
        while self.is_running:
            try:
                client_sock, client_addr = self.server_sock.accept()
                threading.Thread(target=self.handle_incoming_connection, args=(client_sock, client_addr), daemon=True).start()
            except Exception as e:
                if self.is_running:
                    print(f"[Z30 模拟器] 接受连接异常: {e}")
                break

    def handle_incoming_connection(self, sock, addr):
        print(f"[Z30 模拟器] 收到来自 {addr} 的连接请求")
        while self.is_running:
            try:
                header = sock.recv(8)
                if not header or len(header) < 8:
                    break
                length, pkt_type = struct.unpack("<II", header)
                payload_len = length - 8
                payload = b""
                while len(payload) < payload_len:
                    chunk = sock.recv(payload_len - len(payload))
                    if not chunk:
                        break
                    payload += chunk
                
                # 1. 指令通道握手
                if pkt_type == PKT_INIT_CMD_REQ:
                    self.cmd_sock = sock
                    self.send_init_cmd_ack(sock)
                # 2. 事件通道握手
                elif pkt_type == PKT_INIT_EVENT_REQ:
                    self.event_sock = sock
                    self.send_init_event_ack(sock)
                # 3. 标准指令请求
                elif pkt_type == PKT_CMD_REQ:
                    self.handle_cmd_request(sock, payload)
                # 4. 心跳 Ping
                elif pkt_type == PKT_PING:
                    pong = struct.pack("<II", 8, PKT_PONG)
                    sock.sendall(pong)
            except Exception as e:
                print(f"[Z30 模拟器] 连接处理终止: {e}")
                break

    def send_init_cmd_ack(self, sock):
        name_utf16 = (CAMERA_NAME + "\x00").encode("utf-16le")
        total_len = 4 + 4 + 4 + len(GUID) + len(name_utf16) + 4
        version = 0x00010000
        packet = struct.pack("<III", total_len, PKT_INIT_CMD_ACK, self.connection_number)
        packet += GUID
        packet += name_utf16
        packet += struct.pack("<I", version)
        sock.sendall(packet)

    def send_init_event_ack(self, sock):
        packet = struct.pack("<II", 8, PKT_INIT_EVENT_ACK)
        sock.sendall(packet)

    def handle_cmd_request(self, sock, payload):
        data_phase, op_code, trans_id = struct.unpack("<IHI", payload[:10])
        params = []
        offset = 10
        while offset + 4 <= len(payload):
            params.append(struct.unpack("<I", payload[offset:offset+4])[0])
            offset += 4
            
        print(f"[Z30 模拟器] 执行 OpCode: 0x{op_code:04X}, TransID: {trans_id}, 参数: {params}")
        
        # 1. 开启会话
        if op_code == OP_OPEN_SESSION:
            self.session_open = True
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 2. 实时取景控制
        elif op_code == OP_NIKON_START_LIVEVIEW:
            self.live_view_active = True
            self.send_cmd_response(sock, RC_OK, trans_id)
        elif op_code == OP_NIKON_END_LIVEVIEW:
            self.live_view_active = False
            self.send_cmd_response(sock, RC_OK, trans_id)
        elif op_code == OP_NIKON_GET_LIVEVIEW_IMG:
            self.send_live_view_frame(sock, trans_id)
        elif op_code == OP_NIKON_AF_DRIVE:
            fx, fy = params[0] if len(params) > 0 else 5000, params[1] if len(params) > 1 else 5000
            print(f"[Z30 模拟器] 🎯 接收到触控对焦指令 (Focus Coordinates: {fx}, {fy})")
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 3. 存储卡与文件检索 (GetStorageIDs 0x1004)
        elif op_code == OP_GET_STORAGE_IDS:
            storage_ids = [0x00010001] # 模拟 SD 卡 StorageID
            payload = struct.pack("<I", len(storage_ids))
            for sid in storage_ids:
                payload += struct.pack("<I", sid)
            self.send_data_payload(sock, trans_id, payload)
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 3b. 存储卷信息 (GetStorageInfo 0x1005，v1.0.4 新增)
        elif op_code == OP_GET_STORAGE_INFO:
            def ptp_str(s):
                units = (s + "\x00").encode("utf-16le")
                return struct.pack("<B", len(s) + 1) + units
            # StorageType=0x0003(可移动), FilesystemType=0x0002(DCF),
            # AccessCapability=0x0000(读写), 64GB 卡 / 剩余 40.5GB / 可拍 2840 张
            info = struct.pack("<HHHQQI", 0x0003, 0x0002, 0x0000,
                               64_000_000_000, 40_500_000_000, 2840)
            info += ptp_str("SD") + ptp_str("Z30_SD")
            self.send_data_payload(sock, trans_id, info)
            self.send_cmd_response(sock, RC_OK, trans_id)

        # 3c. 设备属性读取 (GetDevicePropValue 0x1015，v1.0.4 新增)
        elif op_code == OP_GET_DEVICE_PROP_VALUE:
            prop = params[0] if params else 0
            values = {
                0x5001: struct.pack("<B", 78),    # 电量 78%
                0x500D: struct.pack("<I", 80),    # 快门 1/125s（80 = 0.008s × 10000）
                0x5007: struct.pack("<H", 400),   # 光圈 f/4.0
                0x500F: struct.pack("<H", 400),   # ISO 400
                0x5010: struct.pack("<h", 0),     # EV 0
            }
            self.send_data_payload(sock, trans_id, values.get(prop, b""))
            self.send_cmd_response(sock, RC_OK, trans_id)

        # 3d. 触发快门 (InitiateCapture 0x100E，v1.0.4 新增)
        elif op_code == OP_INITIATE_CAPTURE:
            new_id = max(self.media_db.keys()) + 1
            self.media_db[new_id] = {"name": "DSC_3983.JPG", "size": len(TEST_JPEG), "protected": 0}
            print(f"[Z30 模拟器] 📸 快门触发，新照片 {new_id} DSC_3983.JPG 已写入卡")
            self.send_cmd_response(sock, RC_OK, trans_id)

        # 4. 获取文件句柄列表 (GetObjectHandles 0x1007)
        elif op_code == OP_GET_OBJECT_HANDLES:
            handles = list(self.media_db.keys())
            payload = struct.pack("<I", len(handles))
            for h in handles:
                payload += struct.pack("<I", h)
            self.send_data_payload(sock, trans_id, payload)
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 5. 获取对象信息 (GetObjectInfo 0x1008)
        elif op_code == OP_GET_OBJECT_INFO:
            obj_id = params[0] if params else 1001
            info = self.media_db.get(obj_id, {"name": "DSC_TEST.JPG", "size": len(TEST_JPEG), "protected": 0})
            name_bytes = (info["name"] + "\x00").encode("utf-16le")
            
            # 模拟 PTP ObjectInfo 格式
            obj_info_data = struct.pack("<IIH", 0x00010001, 0x3801, info["protected"]) # StorageID, ObjectFormat (0x3801=JPEG), ProtectionStatus
            obj_info_data += struct.pack("<I", info["size"]) # CompressedSize
            obj_info_data += struct.pack("<B", len(info["name"])) # String len
            obj_info_data += name_bytes
            
            self.send_data_payload(sock, trans_id, obj_info_data)
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 6. 下载照片原图数据 (GetObject 0x1009)
        elif op_code == OP_GET_OBJECT or op_code == OP_GET_THUMB:
            self.send_data_payload(sock, trans_id, TEST_JPEG)
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        # 7. 设置优化校准与硬件属性 (SetDevicePropValue 0x1016)
        elif op_code == OP_SET_DEVICE_PROP_VALUE:
            prop_code = params[0] if params else 0
            print(f"[Z30 模拟器] 成功接收相机属性修改请求: 0x{prop_code:04X}")
            self.send_cmd_response(sock, RC_OK, trans_id)
            
        else:
            self.send_cmd_response(sock, RC_OK, trans_id)

    def send_live_view_frame(self, sock, trans_id):
        nikon_header = bytearray(64)
        nikon_header[20] = 0x01 # 合焦
        struct.pack_into("<h", nikon_header, 32, 5) # 水平仪角度
        frame_payload = bytes(nikon_header) + TEST_JPEG
        self.send_data_payload(sock, trans_id, frame_payload)
        self.send_cmd_response(sock, RC_OK, trans_id)

    def send_data_payload(self, sock, trans_id, payload):
        start_data = struct.pack("<IIIQ", 20, PKT_START_DATA, trans_id, len(payload))
        sock.sendall(start_data)
        end_data_hdr = struct.pack("<III", 12 + len(payload), PKT_END_DATA, trans_id)
        sock.sendall(end_data_hdr + payload)

    def send_cmd_response(self, sock, resp_code, trans_id):
        packet = struct.pack("<IIHI", 14, PKT_CMD_RESP, resp_code, trans_id)
        sock.sendall(packet)

    def trigger_camera_protect_event(self, object_id=1001):
        if self.event_sock:
            trans_id = 0
            event_code = 0x4007 # ObjectInfoChanged
            packet = struct.pack("<IIHI", 18, PKT_EVENT, event_code, trans_id)
            packet += struct.pack("<I", object_id)
            self.event_sock.sendall(packet)
            print(f"[Z30 模拟器] 📸 已模拟相机按下【保护键 🔒】事件！广播对象 ID: {object_id}")

if __name__ == "__main__":
    import sys
    sim = NikonZ30Simulator()
    t = threading.Thread(target=sim.start, daemon=True)
    t.start()
    
    if sys.stdin.isatty():
        print("\n按 Enter 模拟相机按保护键速传，按 q 退出：")
        while True:
            cmd = input()
            if cmd.strip().lower() == 'q':
                sim.is_running = False
                break
            else:
                sim.trigger_camera_protect_event(1001)
    else:
        while sim.is_running:
            time.sleep(1)
