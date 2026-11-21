"""v1.0.14 回归：档位识别、白平衡编解码、拍后复查重试。
（v1.0.18：手动重扫 rescanCardForNewPhotos 已删——速传没了，重扫没了
入口；那三项镜像检查一并删掉。）

镜像 Swift 端的纯逻辑（UsbCameraManager 0x500E 解析、decodeWhiteBalance、
checkForNewCapture 两次复查），跑在仓库自带的模拟器协议层之外，
只验逻辑表本身。
v1.0.17 更正：U1/U2/U3 不是 0x8011~0x8013——真机实测（Yuan 2026-11-21
拨动拨盘报回的原始值）是 0x8050=U1、0x8051=U2、0x8052=U3。
AUTO=0x8010 仍是推断，未实测；认不出的值走 .unknown 并显示原始值，
测试里也覆盖这一条。
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# --- 0x500E 曝光模式映射（镜像 UsbCameraManager parsePTPEvent）---
def decode_exposure_mode(raw):
    table = {
        1: "M", 2: "P", 3: "A", 4: "S",
        0x8010: "AUTO", 0x8050: "U1", 0x8051: "U2", 0x8052: "U3",
    }
    return table.get(raw, "UNKNOWN:0x%04X" % raw)

# --- 0x5005 白平衡解码（镜像 decodeWhiteBalance；v1.0.14 已更正阴天/阴影）---
def decode_white_balance(raw):
    table = {2: "auto", 4: "daylight", 5: "fluorescent", 6: "incandescent",
             0x8010: "cloudy", 0x8011: "shade", 0x8012: "customKelvin"}
    return table.get(raw, "auto")

# --- 白平衡下发编码（镜像 encodeWhiteBalance）---
def encode_white_balance(name):
    table = {"自动": 2, "晴天": 4, "荧光灯": 5, "白炽灯": 6, "阴天": 0x8010, "阴影": 0x8011}
    return table.get(name)

# --- 拍后复查：两次机会（镜像 scheduleCaptureCheck + checkForNewCapture）---
def capture_check_attempts(new_handles_sequence):
    """new_handles_sequence: 每次复查发现的新句柄数。返回 (第几次查到, 查到的数)。"""
    for attempt, count in enumerate(new_handles_sequence, start=1):
        if count > 0:
            return attempt, count
        if attempt == 2:
            return None, 0
    return None, 0

def run():
    passed = failed = 0
    def check(name, got, want):
        nonlocal passed, failed
        if got == want:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name}: 得到 {got!r}，期望 {want!r}")

    print("== 档位识别 0x500E ==")
    check("M=1", decode_exposure_mode(1), "M")
    check("P=2", decode_exposure_mode(2), "P")
    check("A=3", decode_exposure_mode(3), "A")
    check("S=4", decode_exposure_mode(4), "S")
    check("AUTO=0x8010", decode_exposure_mode(0x8010), "AUTO")
    check("U1=0x8050", decode_exposure_mode(0x8050), "U1")
    check("U2=0x8051", decode_exposure_mode(0x8051), "U2")
    check("U3=0x8052", decode_exposure_mode(0x8052), "U3")
    check("未知值显示原始值", decode_exposure_mode(0x8014), "UNKNOWN:0x8014")

    print("== 白平衡 0x5005（阴天/阴影不再写反）==")
    check("0x8010=阴天", decode_white_balance(0x8010), "cloudy")
    check("0x8011=阴影", decode_white_balance(0x8011), "shade")
    check("0x8012=色温", decode_white_balance(0x8012), "customKelvin")
    check("2=自动", decode_white_balance(2), "auto")
    check("下发阴天=0x8010", encode_white_balance("阴天"), 0x8010)
    check("下发阴影=0x8011", encode_white_balance("阴影"), 0x8011)

    print("== 拍后复查两次机会 ==")
    check("2.5s 查到", capture_check_attempts([1]), (1, 1))
    check("2.5s 没查到、6s 查到", capture_check_attempts([0, 2]), (2, 2))
    check("两次都没查到", capture_check_attempts([0, 0]), (None, 0))

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(run())
