# -*- coding: utf-8 -*-
"""
v1.0.3 修复流程验证（Python 等价客户端）

目的：这份测试用与修复后 Swift 代码完全相同的逻辑（长度前缀拆包、
串行事务、StartData -> Data/EndData -> CmdResponse 数据阶段读取、
响应码校验）对着仓库自带模拟器跑一遍，验证修复后的协议流程能通。
它不执行 Swift 代码——iOS App 仍需在真机上实测。

跑法：python Tests/test_fixed_flow.py
"""

import socket
import struct
import sys
import os
import threading
import time

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Simulator")))
from z30_simulator import NikonZ30Simulator

PORT = 15740
RC_OK = 0x2001

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


class PacketReader:
    """等价于 Swift readPacket：按 4 字节 Length 拆包，缓冲 + 小块 recv。"""

    def __init__(self, sock):
        self.sock = sock
        self.buf = b""

    def read_packet(self):
        while True:
            if len(self.buf) >= 4:
                total = struct.unpack("<I", self.buf[:4])[0]
                assert 4 <= total <= 64 * 1024 * 1024, f"非法包长 {total}"
                if len(self.buf) >= total:
                    pkt, self.buf = self.buf[:total], self.buf[total:]
                    return pkt
            # 故意小块读，强制 TCP 分片/粘包（模拟真实网络）
            chunk = self.sock.recv(32)
            assert chunk, "连接被对端关闭"
            self.buf += chunk


class FixedClient:
    """等价于修复后的 PtpIpClient（串行事务 + 数据阶段读取）。"""

    def __init__(self, host="127.0.0.1", port=PORT):
        self.trans_id = 1
        self.cmd = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.cmd.connect((host, port))
        self.cmd_reader = PacketReader(self.cmd)
        self.evt = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.evt.connect((host, port))
        self.evt_reader = PacketReader(self.evt)

    def _next_trans(self):
        self.trans_id += 1
        return self.trans_id

    def _cmd_request(self, op, params=(), data_phase=1):
        trans = self._next_trans()
        pkt = struct.pack("<IIIHI", 4 + 4 + 4 + 2 + 4 + 4 * len(params),
                          PKT_CMD_REQ, data_phase, op, trans)
        for p in params:
            pkt += struct.pack("<I", p)
        self.cmd.sendall(pkt)
        return trans

    def cmd_no_data(self, op, params=()):
        """无数据命令：发包后读一条 CmdResponse，校验响应码。"""
        self._cmd_request(op, params, data_phase=1)
        resp = self.cmd_reader.read_packet()
        ptype, code = struct.unpack("<IH", resp[4:10])
        assert ptype == PKT_CMD_RESP, f"期望 CmdResponse，得到 type={ptype}"
        return code

    def data_request(self, op, params=()):
        """收数据命令：StartData -> Data/EndData -> CmdResponse。"""
        self._cmd_request(op, params, data_phase=3)
        payload = b""
        while True:
            pkt = self.cmd_reader.read_packet()
            ptype = struct.unpack("<I", pkt[4:8])[0]
            if ptype == PKT_START_DATA:
                continue
            if ptype == PKT_DATA:
                payload += pkt[12:]
                continue
            if ptype == PKT_END_DATA:
                payload += pkt[12:]
                break
            if ptype == PKT_CMD_RESP:
                code = struct.unpack("<H", pkt[8:10])[0]
                return None, code
            raise AssertionError(f"数据阶段出现未知包类型 {ptype}")
        resp = self.cmd_reader.read_packet()
        ptype, code = struct.unpack("<IH", resp[4:10])
        assert ptype == PKT_CMD_RESP, f"期望 CmdResponse，得到 type={ptype}"
        return payload, code


def parse_ptp_string(data, offset):
    """等价于 Swift readPTPString。"""
    count = data[offset]
    if count == 0:
        return "", offset + 1
    raw = data[offset + 1: offset + 1 + count * 2]
    text = raw.decode("utf-16le").rstrip("\x00")
    return text, offset + 1 + count * 2


def parse_standard_object_info(data):
    """等价于 Swift parseStandardObjectInfo（标准 52 字节头）。"""
    assert len(data) >= 52
    fmt = struct.unpack("<H", data[4:6])[0]
    prot = struct.unpack("<H", data[6:8])[0]
    size = struct.unpack("<I", data[8:12])[0]
    name, off = parse_ptp_string(data, 52)
    assert name, "标准 ObjectInfo 文件名解析失败"
    date_str, _ = parse_ptp_string(data, off)
    return {"filename": name, "size": size, "format": fmt,
            "protected": prot, "capture_date": date_str}


def parse_sim_object_info(data):
    """等价于 Swift parseObjectInfo 的模拟器简化布局分支。"""
    assert len(data) >= 15
    fmt = struct.unpack("<I", data[4:8])[0]
    prot = struct.unpack("<H", data[8:10])[0]
    size = struct.unpack("<I", data[10:14])[0]
    name, _ = parse_ptp_string(data, 14)
    assert name, "模拟器 ObjectInfo 文件名解析失败"
    return {"filename": name, "size": size, "format": fmt & 0xFFFF,
            "protected": prot, "capture_date": None}


def make_standard_object_info():
    """构造一条标准 PTP ObjectInfo，供解析器自测。"""
    def ptp_str(s):
        units = (s + "\x00").encode("utf-16le")
        return struct.pack("<B", len(s) + 1) + units
    fixed = struct.pack("<IHHIHIIIIIIIHII",
                        0x00010001, 0x3801, 1, 5432100,
                        0x3801, 1234, 160, 120, 5568, 3712, 24, 0, 0, 0, 0)
    assert len(fixed) == 52, len(fixed)
    return fixed + ptp_str("DSC_0001.JPG") + ptp_str("20261121T143000") \
        + ptp_str("20261121T143000") + ptp_str("")


def extract_jpeg(payload):
    """等价于 Swift LiveViewParser：取首个 FF D8 到 FF D9。"""
    assert len(payload) > 64, f"帧过小: {len(payload)}"
    start = payload.find(b"\xff\xd8")
    end = payload.find(b"\xff\xd9", start + 2)
    assert start >= 0 and end > start, "帧里找不到完整 JPEG"
    return payload[start:end + 2]


def run_test():
    sim = NikonZ30Simulator(host="127.0.0.1", port=PORT)
    threading.Thread(target=sim.start, daemon=True).start()
    time.sleep(0.5)

    c = FixedClient()

    # 1. InitCommandRequest -> InitCommandAck
    import uuid
    guid = uuid.uuid4().bytes
    name = ("Z30 Pro Controller\x00").encode("utf-16le")
    pkt = struct.pack("<II", 4 + 4 + 16 + len(name) + 4, PKT_INIT_CMD_REQ) \
        + guid + name + struct.pack("<I", 0x00010000)
    c.cmd.sendall(pkt)
    ack = c.cmd_reader.read_packet()
    assert struct.unpack("<I", ack[4:8])[0] == PKT_INIT_CMD_ACK
    conn_num = struct.unpack("<I", ack[8:12])[0]
    cam_name = ack[28:-4].decode("utf-16le").rstrip("\x00")
    print(f"✅ 握手成功：{cam_name}，连接号 {conn_num}")

    # 2. InitEventRequest -> InitEventAck
    c.evt.sendall(struct.pack("<III", 12, PKT_INIT_EVENT_REQ, conn_num))
    ev_ack = c.evt_reader.read_packet()
    assert struct.unpack("<I", ev_ack[4:8])[0] == PKT_INIT_EVENT_ACK
    print("✅ 事件通道握手成功")

    # 3. OpenSession（校验响应码，之前不校验）
    assert c.cmd_no_data(0x1002, [1]) == RC_OK
    print("✅ OpenSession 0x1002 -> OK")

    # 4. StartLiveView（校验响应码）
    assert c.cmd_no_data(0x9201) == RC_OK
    print("✅ StartLiveView 0x9201 -> OK")

    # 5. GetLiveViewImg x3（数据阶段完整读取 + JPEG 解析）
    for i in range(3):
        payload, code = c.data_request(0x9203)
        assert code == RC_OK, f"GetLiveViewImg 响应码 0x{code:04X}"
        jpeg = extract_jpeg(payload)
        print(f"✅ 取景帧 {i + 1}：载荷 {len(payload)} 字节，JPEG {len(jpeg)} 字节")
    # 6. EndLiveView
    assert c.cmd_no_data(0x9202) == RC_OK
    print("✅ EndLiveView 0x9202 -> OK")

    # 7. GetStorageIDs
    payload, code = c.data_request(0x1004)
    assert code == RC_OK
    count = struct.unpack("<I", payload[:4])[0]
    storages = [struct.unpack("<I", payload[4 + 4 * i:8 + 4 * i])[0] for i in range(count)]
    print(f"✅ GetStorageIDs：{['0x%08X' % s for s in storages]}")

    # 8. GetObjectHandles
    payload, code = c.data_request(0x1007, [storages[0], 0, 0])
    assert code == RC_OK
    count = struct.unpack("<I", payload[:4])[0]
    handles = [struct.unpack("<I", payload[4 + 4 * i:8 + 4 * i])[0] for i in range(count)]
    print(f"✅ GetObjectHandles：{count} 个对象 {handles}")
    assert handles == [1001, 1002, 1003, 1004]

    # 9. GetObjectInfo（模拟器简化布局解析）
    for h in handles:
        payload, code = c.data_request(0x1008, [h])
        assert code == RC_OK
        info = parse_sim_object_info(payload)
        print(f"✅ GetObjectInfo {h}：{info['filename']}，{info['size']} 字节，保护={info['protected']}")
    assert parse_sim_object_info(
        c.data_request(0x1008, [1001])[0])["protected"] == 1, "保护标记应为 1"

    # 10. 标准布局 ObjectInfo 解析自测（真机用的布局）
    std_info = parse_standard_object_info(make_standard_object_info())
    assert std_info["filename"] == "DSC_0001.JPG", std_info
    assert std_info["size"] == 5432100 and std_info["protected"] == 1
    assert std_info["capture_date"] == "20261121T143000", std_info
    print(f"✅ 标准 ObjectInfo 解析：{std_info}")

    # 11. GetObject 下载原图
    payload, code = c.data_request(0x1009, [handles[0]])
    assert code == RC_OK and payload.startswith(b"\xff\xd8") and payload.rstrip(b"") .endswith(b"\xff\xd9")
    print(f"✅ GetObject：下载 {len(payload)} 字节 JPEG")

    # 12. GetThumb
    payload, code = c.data_request(0x100A, [handles[0]])
    assert code == RC_OK and b"\xff\xd8" in payload
    print(f"✅ GetThumb：{len(payload)} 字节")

    # 13. CloseSession
    assert c.cmd_no_data(0x1003) == RC_OK
    print("✅ CloseSession 0x1003 -> OK")

    # 14. 保护键事件（事件通道）
    sim.trigger_camera_protect_event(object_id=1001)
    ev = c.evt_reader.read_packet()
    ev_code = struct.unpack("<H", ev[8:10])[0]
    ev_obj = struct.unpack("<I", ev[14:18])[0]
    assert ev_code == 0x4007 and ev_obj == 1001
    print("✅ 事件通道收到保护键事件 0x4007，对象 1001")

    c.cmd.close()
    c.evt.close()
    sim.is_running = False
    print("\n🏆 修复流程 14 项全部通过（等价 Python 客户端 vs 模拟器）")
    return True


if __name__ == "__main__":
    run_test()
