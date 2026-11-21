"""v1.0.16 回归：AF-ON 真对焦的接线检查。

AF-ON 在 v1.0.15 之前是假的：只亮 0.6 秒绿灯，不发任何命令。
v1.0.16 把它接到尼康 AfDrive 操作码上。这里验三件事（源码级接线，
真机行为须由用户在相机上验证——按 AF-ON 看画面是否真的合焦）：
1. 操作码：nikonAfDrive 必须是 0x90C1（Wireshark packet-ptpip.h：
   PTP_OC_NIKON_AfDrive = 0x90C1；0x90C0 是 Capture，不是 AF）。
2. 两条通路都有带回执的中心点对焦：Wi-Fi（PtpIpClient）与 USB
   （UsbCameraManager）都以 [5000, 5000] 发 AfDrive；USB 发之前
   先停取景帧拉取（和 setCameraProp 一样，不然命令排在 20fps 帧后面）。
3. 取景页竖屏/横屏两个 AF-ON 按钮都走 triggerAutofocus，不再是
   “亮 0.6 秒就灭”的假逻辑；失败时按钮红闪（afFailed）。
"""

import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()

def run():
    passed = failed = 0
    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name}: {detail}")

    consts = read("Z30Control/Protocol/PtpConstants.swift")
    m = re.search(r"case nikonAfDrive\s*=\s*(0x[0-9A-Fa-f]+)", consts)
    check("操作码 nikonAfDrive = 0x90C1（Wireshark 定义）",
          m and m.group(1).lower() == "0x90c1",
          f"源码里是 {m.group(1) if m else '没找到'}")

    wifi = read("Z30Control/Protocol/PtpIpClient.swift")
    check("Wi-Fi 有 driveAutofocusAtCenter",
          "func driveAutofocusAtCenter" in wifi)
    check("Wi-Fi 中心点坐标 5000, 5000",
          "driveAutofocus(x: 5000, y: 5000" in wifi)
    check("Wi-Fi 用 nikonAfDrive 发包",
          "opCode: PtpOperationCode.nikonAfDrive.rawValue" in wifi)
    check("Wi-Fi 回执按 0x2001 判成功",
          "code == PtpResponseCode.ok.rawValue" in wifi)
    check("点画面对焦复用同一条 AfDrive（setTouchFocus 委托）",
          re.search(r"func setTouchFocus.*?driveAutofocus\(x: focusX, y: focusY",
                    wifi, re.S) is not None)

    usb = read("Z30Control/Services/UsbCameraManager.swift")
    check("USB 枚举里有 afDrive = 0x90C1",
          re.search(r"case afDrive\s*=\s*0x90C1", usb) is not None)
    check("USB 有 driveAutofocusAtCenter",
          "func driveAutofocusAtCenter" in usb)
    check("USB 中心点坐标 [5000, 5000]",
          "params: [5000, 5000]" in usb)
    check("USB 发之前停取景帧拉取",
          re.search(r"func driveAutofocusAtCenter.*?pauseLiveViewFetching\(\)",
                    usb, re.S) is not None)
    check("USB 对焦被拒写诊断",
          "对焦被拒" in usb)

    view = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
    check("取景页有 triggerAutofocus",
          "func triggerAutofocus()" in view)
    check("竖屏/横屏两个 AF-ON 按钮都调 triggerAutofocus",
          view.count("triggerAutofocus()") >= 3)  # 定义 1 次 + 调用 2 次
    check("triggerAutofocus 走 USB 通路",
          "usbCamera.driveAutofocusAtCenter" in view)
    check("triggerAutofocus 走 Wi-Fi 通路",
          "client.driveAutofocusAtCenter" in view)
    check("失败红闪（afFailed）",
          "afFailed" in view and "tallyRed" in view)
    check("5 秒没回执也算失败（防绿灯一直亮）",
          re.search(r"asyncAfter\(deadline: \.now\(\) \+ 5\).*?flashAfFailed",
                    view, re.S) is not None)
    check("旧的“亮 0.6 秒就灭”假逻辑已删",
          "asyncAfter(deadline: .now() + 0.6)" not in view)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(run())
