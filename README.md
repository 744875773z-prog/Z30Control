# Z30Control - 尼康 Z30 专业摄影控制与图传系统 (iOS)

一款专为**尼康 Z30（Nikon Z30）**设计的专业级 iOS 相机控制、3D LUT 胶片监看、无线相册与“按相机保护键自动速传”应用程序。

## v1.0.3 修复说明（真机联调发现的问题）

真机症状：Wi-Fi 连上显示“已连接”，但取景黑屏、图库为空。根因不在相机/网络，在 App 代码：

1. **取景从未启动**：`PtpIpClient.startLiveView()` 写好了但全工程没人调；取景页只调了 USB 路径的 `usbCamera.startLiveView()`。现取景页按当前通路（USB / Wi-Fi）启动取景，连上后切到取景页也会自动开始。
2. **数据阶段只读一个包**：`GetLiveViewImg`/`GetObject` 等操作的返回是 StartData → Data/EndData → CmdResponse 多包序列，之前只读一个包就当整帧，帧永远解析失败。现 `sendDataRequest` 完整读完数据阶段再交解析。
3. **图库是假数据**：客户端根本没有 `GetObjectHandles`/`GetObject` 方法，`MediaSyncService` 凭空编造 1001…1060 号假句柄，下载等 0.6 秒谎报成功。现全部改为真实 PTP 调用，保存按钮也真实下载。
4. **Ping 心跳污染指令流**：相机回的 Pong 会混进指令通道被当成命令响应。已删除 Ping，TCP keepalive 维持会话。
5. **连接后发的 SetDevicePropValue(0xD1A2) 是畸形包**：规范要求只带属性码、值走数据阶段，之前把值当第 2 个参数发。已删除该调用；`setDevicePropValue` 改为规范的数据阶段发送。
6. **指令通道串行执行器**：取景循环、图库拉取、速传下载现排队走同一事务，避免互相抢响应报文。
7. **OpenSession/StartLiveView 现校验响应码**，被拒不再谎报“已连接”。

> 提醒：`Tests/test_ptpip_protocol.py` 的 14 项测试是纯 Python socket 测试，对着本地模拟器跑的，从不执行 Swift 代码——它通过不等于 App 能连真机。本次修复的协议流程已用等价 Python 客户端对模拟器复核（见 `Tests/test_fixed_flow.py`），真机仍需实测。

---

## 一、 产品特色与工业美学

- **绝无廉价 AI 感**：严格遵循尼康工业设计美学（经典尼康黄 `#FFD000` + OLED 深空黑底色 `#0D0D0D`），采用瑞士腕表级等宽数字排版（SF Mono），字符跳动零抖动。
- **四大核心模块**：
  1. **【控制】**：
     - **取景监看模式 (Live View)**：低延迟取景流、3D LUT 胶片预设实时叠加、实时直方图、波形图、双声道 VU 电平表、绿色水平仪准星、双层尼康黄光晕快门同心圆。
     - **中控仪表盘模式 (Dashboard)**：机身/镜头状态、SD 卡已用百分比进度条、快门/光圈/ISO/白平衡/测光九宫格、**机身【优化校准 (Picture Control)】远程切换**、独立 `AF-ON` 对焦键。
  2. **【速传】**：
     - 极度符合单兵摄影师的操作直觉：**在相机上按一下保护键 (🔒)，手机在后台无感全自动秒传下载到相册**！
  3. **【图库】**：
     - 相机 SD 卡文件浏览器，支持按日期智能分组、RAW+JPEG 标识、连拍角标、EXIF 质检、**一键套用 3D LUT 胶片风格导出到手机相册**。
  4. **【设置】**：
     - 外观深浅切换、时钟同步（一键将 iPhone 精确原子钟时间写入 Z30 机身）。

---

## 二、 工业级加固与架构自检（最新重构优化）

1. **TCP 流式拆包拼包 (Stream Reassembly)**：
   - 彻底解决传统 Socket 网络在图像大流量下的粘包、半包与数据截断风险，严格基于报文 4 字节 Length 分发完整 PTP 报文。
2. **PTP 单事务锁与串行下载调度器 (Serial Download Queue)**：
   - 严格遵循 PTP 事务规范，杜绝并发拉图导致相机固件报错 `0x2019 (DeviceBusy)`。
3. **心跳保活与自动重连 (Heartbeat & Exponential Backoff)**：
   - 5 秒定时 Ping/Pong 保活探针，网络异常断开时采用指数退避自动静默重连。
4. **Metal 3D 浮点纹理硬件着色器 (Metal Shader Pipeline)**：
   - 基于 GPU 硬件三线性插值采样 3D LUT，支持动态浓度平滑混合，4K 取景毫无压力。

---

## 三、 工程目录结构

```
d:\Z30\
├── Package.swift                     # Swift Package 跨平台清单
├── README.md                         # 完整项目与测试指南
├── Z30Control/                       # iOS App 核心源码工程
│   ├── Info.plist                    # 局域网、相册、Bonjour与后台权限配置
│   ├── App/
│   │   ├── Z30ControlApp.swift       # 应用程序入口
│   │   └── RootTabView.swift         # 4 大主 Tab 导航底座
│   ├── Models/
│   │   ├── CameraState.swift         # 相机硬件参数与中控台数据源
│   │   ├── CameraMediaItem.swift     # SD 卡照片文件与保护标实体
│   │   └── LUTFilter.swift           # 3D LUT 胶片滤镜预设库
│   ├── Protocol/
│   │   ├── PtpConstants.swift        # 尼康专有 Opcode, DPC, ResponseCode 字典
│   │   ├── PtpIpPacket.swift         # PTP/IP 报文封包与解包实现 (ISO 15740)
│   │   ├── LiveViewParser.swift      # 尼康 LiveView 取景帧与水平仪/对焦解析器
│   │   └── PtpIpClient.swift         # 流式拆包加固版异步双通道网络引擎
│   ├── Services/
│   │   ├── CameraConnectionService.swift # 连接调度 (Wi-Fi AP / USB-C / 局域网)
│   │   ├── LiveViewStreamService.swift   # 取景流调度与 FPS 监控
│   │   ├── MediaSyncService.swift        # 串行队列加固版保护键速传服务
│   │   └── LUTProcessor.swift            # 3D LUT 渲染与成片烘焙引擎
│   ├── Resources/
│   │   ├── BuiltinLUTs/                  # 内置工业级标准 .cube 滤镜文件
│   │   │   ├── Kodak_Portra_400.cube
│   │   │   ├── Fuji_Classic_Chrome.cube
│   │   │   ├── Cinematic_Teal_Orange.cube
│   │   │   └── TriX_400_BlackAndWhite.cube
│   │   └── Shaders/
│   │       └── LUTShader.metal           # Metal 硬件加速着色器
│   └── Views/
│       ├── Common/Theme.swift            # 尼康黄工业主题与触感反馈
│       ├── LiveView/                     # 实时监看、直方图、胶卷滑轨
│       ├── Control/                      # 参数九宫格仪表盘、AF-ON
│       ├── FastTransfer/                 # 动态雷达速传看板
│       ├── Gallery/                      # 图库管理与双通道导出
│       └── Settings/                     # 系统与时钟同步
│
├── Simulator/
│   ├── z30_simulator.py              # 全功能尼康 Z30 硬件仿真器 (监听 15740)
│   └── web_monitor.py                # 浏览器端交互式 Web 调测监视台 (监听 8080)
└── Tests/
    └── test_ptpip_protocol.py        # 13 项严苛全链路回归测试套件
```

---

## 四、 本地自动化联调与测试

### 1. 运行 14 项全链路回归测试套件
```powershell
python Tests/test_ptpip_protocol.py
```
**测试项全部 100% 自动通过**：
- `[测试 01]` 底层 TCP Socket 连接 (127.0.0.1:15740)
- `[测试 02]` 指令通道握手 (InitCommandRequest -> InitCommandAck)
- `[测试 03]` 事件通道握手 (InitEventRequest -> InitEventAck)
- `[测试 04]` PTP 会话开启 (OpenSession 0x1002 -> OK)
- `[测试 05]` 尼康 LiveView 取景模式开启 (Opcode: 0x9201)
- `[测试 06]` 抓取 LiveView 图像帧 (GetLiveViewImg 0x9203 -> JPEG/水平仪/合焦标志)
- `[测试 07]` 退出 LiveView 取景模式 (Opcode: 0x9202)
- `[测试 08]` 获取相机 SD 卡存储卷 (GetStorageIDs 0x1004)
- `[测试 09]` 检索 SD 卡文件索引列表 (GetObjectHandles 0x1007)
- `[测试 10]` 获取单张照片元数据与保护标记 (GetObjectInfo 0x1008)
- `[测试 11]` 下载照片原图数据并校验完整性 (GetObject 0x1009)
- `[测试 12]` 远程设置机内【优化校准 (Picture Control)】(SetDevicePropValue 0x1016)
- `[测试 13]` 远程屏幕指哪打哪触控对焦 (nikonAfDrive 0x90C1 -> 目标坐标驱动)
- `[测试 14]` 模拟相机按【保护键 🔒】事件，触发后台串行秒传！

### 2. 运行极限高压与异常注入测试 (Stress Testing)
```powershell
python Tests/stress_test.py
```
- 高频连续拉取 60 帧实时取景画面，校验 0 掉帧、0 粘包；
- 瞬间注入 10 次【保护键 🔒】并发事件风暴，校验串行队列 0 丢包、0 堵塞。

### 3. 体验浏览器端专业监视台
```powershell
python Simulator/web_monitor.py
```
浏览器打开 `http://127.0.0.1:8080`，即可直观操作 3D LUT 切色、快门释放与保护键速传。
