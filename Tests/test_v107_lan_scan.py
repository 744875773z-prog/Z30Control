"""v1.0.7 回归：局域网真扫描（取代之前等 1.2 秒就报 192.168.1.1 的假搜索）。

做法：读本机 Wi-Fi（en0）地址和子网掩码，算出整个网段，并行 TCP
探测每个地址的 15740 端口（尼康 PTP/IP 端口）。开着这个端口的，
基本就是相机。宿舍路由器、手机热点都走同一套逻辑——扫的是手机
当前连上的那个网。手动 IP 直连带格式校验，记到 UserDefaults。

这里验源码接线 + 纯逻辑镜像（网段算主机、IPv4 校验）+ 对模拟器的
真实 TCP 探测（15740 通、没开的端口不通）。
"""

import os, sys, threading, socket

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))
sys.path.insert(0, os.path.join(ROOT, "Simulator"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# --- 网段算主机镜像（hosts(inSubnet:netmask:)）---
def hosts_in_subnet(ip, netmask):
    def octets(s):
        parts = s.split(".")
        if len(parts) != 4:
            return None
        try:
            nums = [int(p) for p in parts]
        except ValueError:
            return None
        if any(n < 0 or n > 255 for n in nums):
            return None
        return nums

    ip_o = octets(ip)
    mask_o = octets(netmask)
    if ip_o is None or mask_o is None:
        return []
    ip32 = 0
    mask32 = 0
    for b in ip_o:
        ip32 = (ip32 << 8) | b
    for b in mask_o:
        mask32 = (mask32 << 8) | b
    network = ip32 & mask32
    broadcast = network | (~mask32 & 0xFFFFFFFF)
    if broadcast <= network + 1:
        return []
    host_count = broadcast - network - 1
    if host_count > 512:
        return []
    out = []
    for h in range(1, host_count + 1):
        a = network + h
        out.append("%d.%d.%d.%d" % ((a >> 24) & 0xFF, (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF))
    return out


# --- IPv4 校验镜像（isValidIPv4）---
def is_valid_ipv4(s):
    parts = s.split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p or not p.isdigit():
            return False
        if not 0 <= int(p) <= 255:
            return False
    return True


# --- 单个 TCP 探测镜像（probeHost）---
def probe_host(ip, port, timeout=0.6):
    try:
        s = socket.create_connection((ip, port), timeout=timeout)
        s.close()
        return True
    except OSError:
        return False


def run():
    passed = failed = 0

    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name} {detail}")

    svc = read("Z30Control/Services/CameraConnectionService.swift")

    print("== 局域网扫描接线 ==")
    check("discoverCamerasInLAN 存在", "func discoverCamerasInLAN()" in svc)
    check("按 IP + 掩码算网段主机", "func hosts(inSubnet ip: String, netmask: String)" in svc)
    check("扫 15740 端口（尼康 PTP/IP）", "port: 15740" in svc)
    check("32 路并发探测", "maxConcurrentOperationCount = 32" in svc)
    check("单点超时 0.6 秒", "timeout: 0.6" in svc)
    check("手动 IP 校验 + 记到 UserDefaults",
          "isValidIPv4" in svc and "z30.lastCameraIP" in svc)
    check("主机数超 512 不扫（免得扫爆）", "hostCount <= 512" in svc)

    print("== 纯逻辑：网段算主机 ==")
    h24 = hosts_in_subnet("192.168.1.5", "255.255.255.0")
    check("/24 网段 254 个主机", len(h24) == 254, f"got={len(h24)}")
    check("首尾是 .1 和 .254", h24[0] == "192.168.1.1" and h24[-1] == "192.168.1.254")
    check("去掉网络地址和广播地址", "192.168.1.0" not in h24 and "192.168.1.255" not in h24)
    check("本机地址也在扫描列表里", "192.168.1.5" in h24)
    h25 = hosts_in_subnet("192.168.1.130", "255.255.255.128")
    check("/25 网段 126 个主机", len(h25) == 126, f"got={len(h25)}")
    check("/16 大网返回空", hosts_in_subnet("10.0.0.5", "255.255.0.0") == [])
    check("IP/掩码格式不对返回空",
          hosts_in_subnet("192.168.1", "255.255.255.0") == []
          and hosts_in_subnet("192.168.1.5", "xxx") == [])

    print("== 纯逻辑：IPv4 校验 ==")
    check("192.168.1.100 合法", is_valid_ipv4("192.168.1.100"))
    check("256 越界不合法", not is_valid_ipv4("192.168.1.256"))
    check("三段不合法", not is_valid_ipv4("192.168.1"))

    print("== 模拟器：真实 TCP 探测 ==")
    from z30_simulator import NikonZ30Simulator
    import time as _time
    sim = NikonZ30Simulator(host="127.0.0.1", port=15740)
    t = threading.Thread(target=sim.start, daemon=True)
    t.start()
    _time.sleep(0.5)
    check("模拟器 15740 探得通", probe_host("127.0.0.1", 15740))
    check("扫没开的端口找不到", not probe_host("127.0.0.1", 15741))

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
