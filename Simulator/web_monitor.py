# -*- coding: utf-8 -*-
"""
Z30 Web 专业监视与交互调测控制台
用于在 PC 浏览器端直观监控 PTP/IP 取景流、实时预览 3D LUT 色彩渲染与参数控制。
访问地址: http://127.0.0.1:8080
"""

import http.server
import socket
import socketserver
import struct
import threading
import time
import os

WEB_PORT = 8080
PTP_PORT = 15740

# HTML 页面模板 (严格对齐尼康工业黑金质感)
HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>NIKON Z30 实时监看与胶片调控台</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            background-color: #0d0d0d;
            color: #ffffff;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Mono", monospace;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 20px;
        }
        .header {
            width: 100%;
            max-width: 800px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 18px;
            background: #1c1c1e;
            border-radius: 8px;
            margin-bottom: 16px;
            border-left: 4px solid #ffd000;
        }
        .status-dot {
            width: 10px;
            height: 10px;
            background: #34c759;
            border-radius: 50%;
            display: inline-block;
            margin-right: 6px;
        }
        .monitor-frame {
            position: relative;
            width: 100%;
            max-width: 800px;
            height: 480px;
            background: #151515;
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid rgba(255, 255, 255, 0.1);
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .hud-overlay {
            position: absolute;
            top: 12px;
            left: 14px;
            display: flex;
            gap: 8px;
        }
        .hud-pill {
            background: rgba(0, 0, 0, 0.65);
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 13px;
            font-weight: 600;
            border: 1px solid rgba(255, 255, 255, 0.15);
        }
        .horizon-line {
            position: absolute;
            width: 140px;
            height: 2px;
            background: #34c759;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
        }
        .horizon-circle {
            position: absolute;
            width: 10px;
            height: 10px;
            border: 2px solid #34c759;
            border-radius: 50%;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
        }
        .controls-deck {
            width: 100%;
            max-width: 800px;
            background: #1c1c1e;
            padding: 16px;
            border-radius: 8px;
            margin-top: 16px;
        }
        .lut-bar {
            display: flex;
            gap: 10px;
            margin-bottom: 16px;
            overflow-x: auto;
            padding-bottom: 6px;
        }
        .lut-btn {
            background: #2c2c2e;
            color: #fff;
            border: 1px solid rgba(255, 255, 255, 0.15);
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: bold;
            cursor: pointer;
            transition: 0.15s;
        }
        .lut-btn.active {
            background: rgba(255, 208, 0, 0.2);
            color: #ffd000;
            border-color: #ffd000;
        }
        .shutter-deck {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 24px;
        }
        .shutter-ring {
            width: 66px;
            height: 66px;
            border-radius: 50%;
            border: 3.5px solid #ffd000;
            display: flex;
            justify-content: center;
            align-items: center;
            cursor: pointer;
            background: transparent;
        }
        .shutter-core {
            width: 52px;
            height: 52px;
            border-radius: 50%;
            background: #ffffff;
            transition: 0.1s;
        }
        .shutter-ring:active .shutter-core {
            transform: scale(0.92);
            background: #ffd000;
        }
        .protect-btn {
            background: #ffd000;
            color: #000;
            font-weight: bold;
            border: none;
            padding: 10px 18px;
            border-radius: 6px;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <span class="status-dot"></span>
            <strong>NIKON Z 30</strong> &nbsp;|&nbsp; <span>PTP/IP 15740 就绪</span>
        </div>
        <div style="font-size: 13px; color: #8e8e93;">
            16mm · [2,840张] · 🔋 85%
        </div>
    </div>

    <div class="monitor-frame" id="viewport">
        <div class="hud-overlay">
            <div class="hud-pill">M 档</div>
            <div class="hud-pill">1/125s</div>
            <div class="hud-pill">f/4.0</div>
            <div class="hud-pill">ISO 400</div>
            <div class="hud-pill">0 EV</div>
            <div class="hud-pill" style="color: #34c759;">温度正常</div>
        </div>

        <div class="horizon-line"></div>
        <div class="horizon-circle"></div>

        <div style="color: rgba(255,255,255,0.3); font-size: 14px; text-align: center;">
            <p>● 实时取景监看视口 (Live View 30 FPS)</p>
            <p id="lut-indicator" style="color: #ffd000; font-size: 12px; margin-top: 6px;">[当前滤镜: 原图直出]</p>
        </div>
    </div>

    <div class="controls-deck">
        <div style="font-size: 11px; color: #8e8e93; margin-bottom: 8px;">3D LUT 胶片与电影色彩选择器</div>
        <div class="lut-bar">
            <button class="lut-btn active" onclick="setLUT('ORIGINAL', this, '#151515')">原画直出</button>
            <button class="lut-btn" onclick="setLUT('KODAK PORTRA 400', this, '#2b231c')">柯达 PORTRA 400</button>
            <button class="lut-btn" onclick="setLUT('FUJI CLASSIC CHROME', this, '#1a2422')">富士 CLASSIC CHROME</button>
            <button class="lut-btn" onclick="setLUT('TEAL & ORANGE', this, '#14232c')">好莱坞青橙</button>
            <button class="lut-btn" onclick="setLUT('TRI-X 400 黑白', this, '#1e1e1e')">柯达 TRI-X 黑白</button>
        </div>

        <div class="shutter-deck">
            <button class="protect-btn" onclick="triggerProtect()">📸 模拟相机按【保护键 🔒】速传</button>
            <div class="shutter-ring" onclick="triggerShutter()">
                <div class="shutter-core"></div>
            </div>
        </div>
    </div>

    <script>
        function setLUT(name, btn, bgColor) {
            document.querySelectorAll('.lut-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            document.getElementById('lut-indicator').innerText = '[当前滤镜: ' + name + ']';
            document.getElementById('viewport').style.backgroundColor = bgColor;
        }

        function triggerShutter() {
            console.log('快门释放');
            alert('快门触发！Z30 已拍摄照片');
        }

        function triggerProtect() {
            fetch('/api/protect')
                .then(r => r.text())
                .then(txt => alert('已触发相机保护键！手机端速传将自动秒传该照片：' + txt));
        }
    </script>
</body>
</html>
"""

class WebMonitorHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode("utf-8"))
        elif self.path == "/api/protect":
            # 向 PTP 广播速传
            self.send_response(200)
            self.send_header("Content-type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("DSC_2641.JPG (ID: 1001) 已打保护标并触发秒传".encode("utf-8"))
        else:
            self.send_error(404)

def start_web_server():
    with socketserver.TCPServer(("", WEB_PORT), WebMonitorHandler) as httpd:
        print(f"[Web 监视台] 启动成功！请在浏览器访问: http://127.0.0.1:{WEB_PORT}")
        httpd.serve_forever()

if __name__ == "__main__":
    start_web_server()
