# -*- coding: utf-8 -*-
"""
v1.0.4 修复流程验证（Python 等价客户端）

验证 v1.0.4 新增的三条真读链路（与 Swift 代码相同的协议逻辑）：
1. 存储卡：GetStorageIDs -> GetStorageInfo，容量/剩余/可拍张数全部来自相机
   （之前是写死的 64GB / 23.5GB / 2840 张）。
2. 电量与曝光参数：GetDevicePropValue (0x5001 电量 / 0x500D 快门等)。
3. 真快门：InitiateCapture (0x100E)，拍完卡里多一张，图库句柄数 +1
   （之前快门按钮是假的：随机编个 DSC_xxxx.JPG 弹“拍摄完成”）。
4. 真调参：SetDevicePropValue (0x1016，值走数据阶段)，如快门 1/250。
5. StorageInfo 数据集纯解析自测（128GB 卡，独立于模拟器）。

它不执行 Swift 代码——iOS App 仍需在真机上实测。
USB（ImageCaptureCore）那条路在 Linux 上没有等价物，只能静态检查 + 真机测。

跑法：python Tests/test_v104_flow.py
"""

import socket
import struct
import sys
import os
import threading
import time
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Simulator")))
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
from z30_simulator import NikonZ30Simulator
from test_fixed_flow import FixedClient, PKT_CMD_REQ, PKT_CMD_RESP, PKT_START_DATA, PKT_DATA, PKT_END_DATA

PORT = 15740
RC_OK = 0x2001


def parse_storage_info(data):
    """等价于 Swift UsbCameraManager.parseStorageInfo / PtpIpClient.getStorageInfo。

    StorageInfo 数据集：StorageType(2) FilesystemType(2) AccessCapability(2)
    MaxCapacity(8) FreeSpaceInBytes(8) FreeSpaceInImages(4) …
    """
    assert len(data) >= 26, f"StorageInfo 数据集过短: {len(data)}"
    max_cap = struct.unpack("<Q", data[6:14])[0]
    free_bytes = struct.unpack("<Q", data[14:22])[0]
    free_images = struct.unpack("<I", data[22:26])[0]
    return {"max_capacity": max_cap, "free_bytes": free_bytes, "free_images": free_images}


def decode_shutter_speed(raw):
    """等价于 Swift UsbCameraManager.decodeShutterSpeed。"""
    if raw == 0 or raw == 0xFFFFFFFF:
        return "BULB"
    seconds = raw / 10000.0
    if seconds >= 1.0:
        return f"{int(seconds)}s" if seconds == int(seconds) else f"{seconds:.1f}s"
    return f"1/{int(10000.0 / raw + 0.5)}"


def set_device_prop_value(client, code, value_bytes):
    """等价于 Swift PtpIpClient.setDevicePropValue（值走数据阶段）。"""
    trans = client._next_trans()
    pkt = struct.pack("<IIIHI", 4 + 4 + 4 + 2 + 4 + 4, PKT_CMD_REQ, 2, 0x1016, trans)
    pkt += struct.pack("<I", code)
    client.cmd.sendall(pkt)
    start = struct.pack("<IIIQ", 20, PKT_START_DATA, trans, len(value_bytes))
    client.cmd.sendall(start)
    end = struct.pack("<III", 12 + len(value_bytes), PKT_END_DATA, trans) + value_bytes
    client.cmd.sendall(end)
    resp = client.cmd_reader.read_packet()
    ptype, resp_code = struct.unpack("<IH", resp[4:10])
    assert ptype == PKT_CMD_RESP, f"期望 CmdResponse，得到 type={ptype}"
    return resp_code


def run_test():
    sim = NikonZ30Simulator(host="127.0.0.1", port=PORT)
    threading.Thread(target=sim.start, daemon=True).start()
    time.sleep(0.5)

    c = FixedClient()

    # 1. 握手 + OpenSession
    guid = uuid.uuid4().bytes
    name = ("Z30 Pro Controller\x00").encode("utf-16le")
    pkt = struct.pack("<II", 4 + 4 + 16 + len(name) + 4, 1) + guid + name + struct.pack("<I", 0x00010000)
    c.cmd.sendall(pkt)
    ack = c.cmd_reader.read_packet()
    conn_num = struct.unpack("<I", ack[8:12])[0]
    c.evt.sendall(struct.pack("<III", 12, 3, conn_num))
    c.evt_reader.read_packet()
    assert c.cmd_no_data(0x1002, [1]) == RC_OK
    print("✅ 握手 + OpenSession")

    # 2. GetStorageIDs
    payload, code = c.data_request(0x1004)
    assert code == RC_OK
    storages = [struct.unpack("<I", payload[4 + 4 * i:8 + 4 * i])[0]
                for i in range(struct.unpack("<I", payload[:4])[0])]
    assert storages == [0x00010001], storages
    print(f"✅ GetStorageIDs：{['0x%08X' % s for s in storages]}")

    # 3. GetStorageInfo：容量/剩余/可拍张数全部来自相机回包
    payload, code = c.data_request(0x1005, [storages[0]])
    assert code == RC_OK
    info = parse_storage_info(payload)
    assert info["max_capacity"] == 64_000_000_000, info
    assert info["free_bytes"] == 40_500_000_000, info
    assert info["free_images"] == 2840, info
    total_gb = info["max_capacity"] / 1_000_000_000
    used_gb = (info["max_capacity"] - info["free_bytes"]) / 1_000_000_000
    assert total_gb == 64.0 and used_gb == 23.5
    print(f"✅ GetStorageInfo：总量 {total_gb}GB，已用 {used_gb}GB，"
          f"剩余 {info['free_bytes'] / 1e9}GB，可拍 {info['free_images']} 张（全部来自相机）")

    # 4. GetDevicePropValue 电量 0x5001：读到 78，不是写死的 85
    payload, code = c.data_request(0x1015, [0x5001])
    assert code == RC_OK and len(payload) == 1
    battery = payload[0]
    assert battery == 78, f"电量应为 78，得到 {battery}"
    print(f"✅ GetDevicePropValue 0x5001：电量 {battery}%（真读，非默认值）")

    # 5. GetDevicePropValue 快门 0x500D：80 -> 1/125
    payload, code = c.data_request(0x1015, [0x500D])
    assert code == RC_OK
    raw = struct.unpack("<I", payload[:4])[0]
    shutter = decode_shutter_speed(raw)
    assert shutter == "1/125", f"快门解码应为 1/125，得到 {shutter}（原始={raw}）"
    print(f"✅ GetDevicePropValue 0x500D：快门原始值 {raw} -> {shutter}")

    # 6. 真快门 InitiateCapture：响应 OK，卡里多一张 DSC_3983.JPG
    assert c.cmd_no_data(0x100E, [0xFFFFFFFF, 0]) == RC_OK
    payload, code = c.data_request(0x1007, [storages[0], 0, 0])
    assert code == RC_OK
    handles = [struct.unpack("<I", payload[4 + 4 * i:8 + 4 * i])[0]
               for i in range(struct.unpack("<I", payload[:4])[0])]
    assert len(handles) == 5 and 1005 in handles, handles
    payload, code = c.data_request(0x1008, [1005])
    from test_fixed_flow import parse_sim_object_info
    assert code == RC_OK
    assert parse_sim_object_info(payload)["filename"] == "DSC_3983.JPG", payload
    print(f"✅ InitiateCapture 0x100E -> OK，卡内对象 {len(handles)} 个，新增 DSC_3983.JPG")

    # 7. 真调参 SetDevicePropValue：快门改 1/250（原始值 40，值走数据阶段）
    assert set_device_prop_value(c, 0x500D, struct.pack("<I", 40)) == RC_OK
    print("✅ SetDevicePropValue 0x500D：快门 1/250（值走数据阶段，响应 OK）")

    # 8. StorageInfo 纯解析自测：128GB 卡 / 剩余 90GB / 可拍 5120 张
    blob = struct.pack("<HHHQQI", 0x0003, 0x0002, 0x0000,
                       128_000_000_000, 90_000_000_000, 5120)
    info2 = parse_storage_info(blob)
    assert info2 == {"max_capacity": 128_000_000_000,
                     "free_bytes": 90_000_000_000, "free_images": 5120}, info2
    print("✅ StorageInfo 纯解析：128GB 卡 -> 总量 128.0GB，剩余 90.0GB，可拍 5120 张")

    # 9. CloseSession
    assert c.cmd_no_data(0x1003) == RC_OK
    print("✅ CloseSession 0x1003 -> OK")

    c.cmd.close()
    c.evt.close()
    sim.is_running = False
    print("\n🏆 v1.0.4 修复流程 9 项全部通过（等价 Python 客户端 vs 模拟器）")
    return True


if __name__ == "__main__":
    run_test()
