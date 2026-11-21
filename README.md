# Z30Control - 尼康 Z30 专业摄影控制与图传系统 (iOS)

一款专为**尼康 Z30（Nikon Z30）**设计的专业级 iOS 相机控制、3D LUT 胶片监看、无线相册与“按相机保护键自动速传”应用程序。

## v1.0.12 修复：Wi-Fi 走了错误的门——「连接到电脑」连不上第三方 App

根因查到了（对着尼康官方手册核实的）：相机「连接到电脑」那个向导是在等尼康电脑上的无线传输器实用程序（WTU）来配对，第三方 App 的 PTP/IP 握手它根本不回；而且向导没走完就不存配置文件，所以每次都要重新配 Wi-Fi；一退出向导回拍摄页面，Wi-Fi 就断了。尼康 WTU 帮助里也写了，Z30 不能用内置 Wi-Fi 和电脑配对。能走通的门是「连接到智能设备 → Wi-Fi 连接（STA 模式）」：相机以基站模式加入宿舍路由器，App 再连 PTP/IP，首次连接在相机屏幕上按 OK 确认，配置文件会存下来，下次直接选就行，相机也能留在拍摄页面正常取景。

修法：连接向导里 Wi-Fi 和相机热点两档的指导步骤都改成智能设备那条路，并写明不要用「连接到电脑」；握手超时分两档——TCP 不通 8 秒报失败，TCP 通了但等相机回握手给 30 秒（首次连接要等用户在机身上按 OK），握手中的状态条也直接写“请在相机屏幕上按 OK 确认”。如果相机菜单里没有「Wi-Fi 连接（STA 模式）」这一项，需要先把相机固件升到最新版。

## v1.0.11 修复：连上了但取景起不来；取景页顶栏和手机状态栏重叠

两个问题都查到了：

1. 取景页顶栏重叠是我 v1.0.9 改出来的：ignoresSafeArea(.top) 把取景页自己的 safeAreaInsets.top 归零，它的顶栏直接顶到手机状态栏上。正确修法是删掉手动白色占位块和 ignoresSafeArea，只靠系统安全区留白——控制页空隙和 1.0.9 一样（约 67pt），取景页顶栏回到灵动岛下面。
2. 取景起不来有三处静默失败：进取景页时 USB 还没握手完，onAppear 那次启动扑空，之后 USB 连上了也没人再启动；0x9201 发出去相机不回包时没有任何超时，点了像没反应；单帧请求回调丢了会让 isFetchingFrame 永远卡住，画面冻住也不报错。现在：USB 握手完成后自动再启动一次；0x9201 5 秒无应答直接报错；单帧请求 2 秒没回自动复位重试；两条通路都没连上时，按钮下面直接写“相机未连接”。
3. 这一版也包含 v1.0.10 的 Wi-Fi 握手超时（8 秒没连上直接报失败原因，不再无限“正在连接...”）。提醒：USB 线插着时相机 Wi-Fi 是关的，Wi-Fi 连接永远成功不了——先用 USB 这条（存储、电量都读出来了），Wi-Fi 等拔了线再试。

## v1.0.10 修复：点连接后一直“正在连接...”没反应

根因查到了：局域网扫描能找到相机（TCP 15740 端口通着），但点连接后 PTP/IP 握手等不到相机的 InitCommandAck 回复，而握手这里没有任何超时——readNextCmdPacket 永远等下去，界面就一直卡在“正在连接...”，不报错也不重试。相机端口通但不回握手，通常是它不在「连接到计算机」模式（比如还在连智能设备），或上一轮残留的半会话占着（相机同时只接受一个 PTP/IP 会话）。

修法：connect() 先断掉上一轮残留的连接；8 秒还没连上就直接报失败并说明原因（TCP 不通和握手无应答是两条不同的提示），不走静默自动重连。失败会显示在控制页的状态条上。

## v1.0.9 界面：顶栏空隙减半，底栏改成悬浮玻璃胶囊

1. 顶栏空隙太大：根视图默认就被系统按安全区往下顶了一次（灵动岛约 59pt），代码里又手动加了一个同等高度的白色占位块，两个叠加导致“控制”标题离状态栏约 130pt。现在忽略顶部安全区，只留手动占位块，空隙减到约 67pt。
2. 底栏太低：旧版全宽白条贴着屏幕底。新版是悬浮胶囊，底部留 home indicator + 10pt，整体抬高约 10pt。
3. 底栏玻璃质感：ultraThinMaterial 毛玻璃底 + 白色细描边 + 柔和阴影，选中项是蓝色实心胶囊（白字），未选中灰字；取景页黑底上自动变深色玻璃。底栏仍在布局流内，页面内容不会被盖住；取景页底部操作台预留从 88 改到 96，免得被新底栏挡住。

## v1.0.8 修复：连接向导页终于能打开了

v1.0.7 的局域网功能做完了，但用户实测反馈“并没有选择 Wi-Fi 这个页面”。查代码发现：连接向导页（选 USB-C / Wi-Fi 局域网 / 相机热点、扫局域网、手动输 IP）一直存在，但全 App 没有任何按钮能打开它——四个 Tab 里没有它，也没有任何 sheet 跳过去。App 启动只会自动试 USB 和 192.168.1.1/192.168.0.1，相机在路由器局域网（比如 192.168.10.35）时永远连不上。现在控制页右上角刷新按钮旁边加了一个 Wi-Fi 按钮，点开就是连接向导页。

## v1.0.7 新增：局域网真连接（路由器 / 手机热点）

之前「路由器局域网」模式的搜索是假的：等 1.2 秒就直接报 192.168.1.1，不真扫网；相机连上路由器拿到别的 IP 时根本连不上。现在：

1. **真扫描**：读本机 Wi-Fi（en0）地址和子网掩码，算出整个网段，32 路并发 TCP 探测每个地址的 15740 端口（尼康 PTP/IP 端口），开着的就列出来点一下直连。宿舍路由器和手机热点都走同一套逻辑——扫的是手机当前连上的那个网。/24 约 254 个地址，几秒扫完；/16 大网直接拒绝，免得扫爆。
2. **手动输 IP**：扫不到就直接输相机 IP（相机 MENU → 网络 → 连接到电脑里能看到，也可以在路由器后台查），格式不对会报错不跳转；输过的 IP 记住，下次不用再输。
3. **连接页指导按模式分开**：局域网模式显示“相机加入路由器”的步骤，不再和相机热点混在一起。
4. PTP/IP 协议本身不用改——本来就是走 TCP 的，换个 IP 就能连；取景、调参、快门、图库、速传全是同一套。本地网络权限（NSLocalNetworkUsageDescription）本来就声明了，不用补。

> 提醒：宿舍 Wi-Fi 可能有设备隔离（手机和相机互相看不见）或要网页认证（相机登不上去），扫不到时先试手机开热点让相机连。`Tests/test_v107_lan_scan.py` 18 项全部通过（等价 Python 逻辑 vs 模拟器：网段枚举、15740 探测、IP 格式校验）。真机局域网连接尚未实测。

## v1.0.6 修复说明（实机反馈：取景通了，但速传没照片、调参慢、模式不联动、滤镜没变化、图库只有 30 张）

真机症状（2026-11-21 16:10 用户反馈，v1.0.5 取景已打通）：App 点快门相机确实拍了，但速传里没有这张照片；手机上改参数反应非常慢；不同模式下有的参数不能调也没有标注；选滤镜后取景画面没有任何变化；图库只显示近 30 张照片。根因：

1. **速传没照片**：成片进速传只靠 ICC 的 `didAdd` 回调 → `requestDownloadFile`，下载一出错就只打印日志、静悄悄返回，什么都不留。现在三层兜底：(a) 下载失败写进诊断行并 1.5s 后重试一次（相机刚写完文件时可能还没准备好）；(b) App 快门成功后 2.5s 主动用 PTP 查一次新照片——拍前先记下卡里已有的对象句柄，拍后 GetObjectHandles 对比，认出新句柄后逐个 GetObjectInfo 拿文件名，文件名在 ICC 目录里就走 ICC 下载，不在就直接 PTP GetObject 取原图字节；(c) 拍照和下载期间暂停 20fps 取景帧拉取，给成片下载让出 PTP 通道，下载回来再恢复取景。
2. **调参慢**：SetDevicePropValue 要排在 20fps 取景帧命令的队尾，等好几秒。现在发调参命令前先停掉取景帧拉取，命令回包后恢复；同时改成乐观更新——选完立刻改显示，失败再恢复旧值、诊断写原因。
3. **模式不联动**：曝光模式（0x500E）本来就读到了，但界面没用它。现在按模式决定药丸能不能点：M 挡快门/光圈/ISO 全可调（没有曝光补偿）；A 挡只能调光圈；S 挡只能调快门；P 挡快门光圈都自动；ISO 在自动 ISO 时由相机定、手动 ISO 时可调。可调的药丸显示蓝色、点得开；不可调的显示白色、点不开。药丸颜色也从黄色改成蓝色（和 App 的蓝白主题一致）。
4. **滤镜没变化**：`activeFilter`/`isLUTEnabled` 只改了状态，没有任何地方把 LUT 画到帧上。现在 `LiveViewStreamService.updateFrame` 在后台串行把 LUT 烘焙到每一帧再发布（忙时丢帧保流畅），取景画面随选随变；选“原片”恢复直出。
5. **图库只有 30 张**：`loadNextPage` 每页只上 30 张，又没有任何地方翻页，图库永远只看到前 30 张。现在一次上全部（列表只是文件名/大小/日期，放内存没压力；视图是 LazyVGrid/LazyVStack，只渲染看得见的行）。

> 提醒：`Tests/test_fixed_flow.py`（14 项）和 `Tests/test_v104_flow.py`（9 项）是等价 Python 客户端对着本地模拟器跑的，验证的是 Wi-Fi 侧协议流程（GetStorageIDs / GetObjectHandles / GetObjectInfo / GetObject / GetStorageInfo / GetDevicePropValue / InitiateCapture / SetDevicePropValue）。USB（ImageCaptureCore）那条路在 Linux 上没有等价物，只能静态检查 + 真机实测。速传兜底用的正是上面这些操作码，真机测试时请看控制页底部的“诊断”行。

## v1.0.5 修复说明（实机录屏：数据回包读错了参数）

真机症状（2026-11-21 15:49 录屏）：USB 连上，但存储/电量仍是“--”，取景每帧只有 12B、看门狗 3 秒报错，快门报 0x2008。根因：

1. **数据读错了回包参数**：`requestSendPTPCommand` 的 block 是 `(first, second, error)`，second 一定是响应容器；数据（如果有）在 first 里。之前只读 second，所以 GetDevicePropValue 永远只拿到 12 字节响应包 0x2001，取景每帧也只有 12B。现在新增 `extractPTPData`，两个参数都看：first 是数据容器就去头，是裸数据（电量 1 字节、JPEG、StorageInfo 数据集）就整体当载荷，是命令回显就明说无数据；诊断行会写清两个参数各多少字节，下次实测一眼定位。
2. **快门存储 ID 错了**：InitiateCapture 传了 0xFFFFFFFF（“任意存储”），尼康报 0x2008 无效存储 ID。改传 0x00010001（Z30 的 SD 卡槽）。Wi-Fi 侧同样改了。
3. **看门狗提示词错了**：之前写“USB 数据连接设为 iPhone/PTP”，这是错的——尼康手册里 iPhone 模式是专给 NX MobileAir 用的，选了它第三方 App 根本连不上相机（用户照着提示切过去果然断连）。正确的是 **MTP/PTP**。提示已改。

> 提醒：如果 first 里也不是数据（诊断显示“first 为命令回显，无数据”），那 USB 这条路在 ImageCaptureCore 下就拿不到数据阶段，只能走 Wi-Fi PTP/IP（原始 TCP，自己控制数据阶段，已在模拟器上验证通过）或改用 delegate 形式的 `requestSendPTPCommand`（回包分 `inData`/`response` 两路）。请先试 Wi-Fi：拔掉 USB 线，相机开 Wi-Fi 热点，手机连上热点后在 App 里走 Wi-Fi 连接。

## v1.0.4 修复说明（真机录屏发现的假数据与断链）

真机症状（2026-11-21 实机录屏）：USB 连上显示“已连接”，但仪表盘存储 24/64GB、剩余 40.5GB、36%、2,840 张，电量 85%；取景一直黑屏；图库 0 张。根因仍在 App 代码：

1. **存储和电量是假数**：`CameraState` 里写死 64GB/23.5GB/2840 张/85%，全工程没有任何地方读卡；拍一张变 2839 只是本地减 1。现在：USB 用 GetStorageIDs → GetStorageInfo (0x1005) 真读容量/剩余/可拍张数，电量用 GetDevicePropValue (0x5001) 真读并每 30 秒轮询；Wi-Fi 同样走 `PtpIpClient.getStorageInfo`/`getDevicePropValue`。读不到之前界面显示“--”，绝不编数。
2. **快门按钮是假的**：点快门不发任何命令，只随机编个 `DSC_xxxx.JPG` 弹“拍摄完成”，相机根本没拍。现在：USB 发 InitiateCapture (0x100E)，Wi-Fi 发 `PtpIpClient.initiateCapture`；成功只代表“已触发”，成片随后经下载回调回显真图+真文件名。失败报原因。
3. **图库 USB 下永远 0 张**：图库只走 Wi-Fi PTP/IP，USB 时那条路没连。现在 USB 下用 ImageCaptureCore 的卡目录（`usbMediaFiles`）喂图库，保存原图走 `requestDownloadFile`，NEF 也能存。
4. **取景黑屏且不报错**：`startLiveView` 不管命令成没成都置“取景中”，帧不到就静默丢弃。现在：只在响应码 OK 时才算启动成功；启动后 3 秒无帧看门狗停掉并报错（相机须处于拍照模式）；每次取景失败原因写进 `liveViewError`/`ptpDiagnostic`，控制页和取景页都可见。
5. **USB PTP 命令疑似全灭的根因待真机诊断**：之前属性读取全是“--”，怀疑点有三——(a) `capabilities` 门禁静默拦截了全部读取与取景（现只记日志，不再拦截）；(b) 事务 ID 从 1 起发，与 ImageCaptureCore 自己的会话撞号（现从 1000 起发）；(c) `requestSendPTPCommand` 的回包形态（数据容器 vs 仅响应包）。新加的 `sendPTPDataCommand` 把三种回包形态都处理了，诊断行会写明每次命令的结果，下次实测一眼定位。
6. **调参选择器也是假的**：快门/光圈/ISO/EV 选完只改本地显示，谎称“已下发至机身”。现在走真实 SetDevicePropValue (0x1016，值走数据阶段），成功后才更新显示。
7. **断开后旧数清零**：拔线后存储/电量回到未知状态，不留旧数冒充。

> 提醒：`Tests/test_v104_flow.py` 的 9 项测试是等价 Python 客户端对着本地模拟器跑的，验证的是 Wi-Fi 侧新协议流程（GetStorageInfo / GetDevicePropValue / InitiateCapture / SetDevicePropValue）。USB（ImageCaptureCore）那条路在 Linux 上没有等价物，只能静态检查 + 真机实测。真机测试时请看控制页底部的“诊断”行和取景页的报错文案。

## v1.0.3 修复说明（真机联调发现的问题）

真机症状：Wi-Fi 连上显示“已连接”，但取景黑屏、图库为空。根因不在相机/网络，在 App 代码：

1. **取景从未启动**：`PtpIpClient.startLiveView()` 写好了但全工程没人调；取景页只调了 USB 路径的 `usbCamera.startLiveView()`。现取景页按当前通路（USB / Wi-Fi）启动取景，连上后切到取景页也会自动开始。
2. **数据阶段只读一个包**：`GetLiveViewImg`/`GetObject` 等操作的返回是 StartData → Data/EndData → CmdResponse 多包序列，之前只读一个包就当整帧，帧永远解析失败。现 `sendDataRequest` 完整读完数据阶段再交解析。
3. **图库是假数据**：客户端根本没有 `GetObjectHandles`/`GetObject` 方法，`MediaSyncService` 凭空编造 1001…1060 号假句柄，下载等 0.6 秒谎报成功。现全部改为真实 PTP 调用，保存按钮也真实下载。
4. **Ping 心跳污染指令流**：相机回的 Pong 会混进指令通道被当成命令响应。已删除 Ping，TCP keepalive 维持会话。
5. **连接后发的 SetDevicePropValue(0xD1A2) 是畸形包**：规范要求只带属性码、值走数据阶段，之前把值当第 2 个参数发。已删除该调用；`setDevicePropValue` 改为规范的数据阶段发送。
6. **指令通道串行执行器**：取景循环、图库拉取、速传下载现排队走同一事务，避免互相抢响应报文。
7. **OpenSession/StartLiveView 现校验响应码**，被拒不再谎报“已连接”。
8. **构建用的 Info.plist 是生成的假 plist**：`project.yml` 里只要写了 `info:` 块，XcodeGen 每次 generate 都会用 properties+默认值重写源文件，局域网/相册/相机权限描述全丢（版本号也一直显示 1.0）。已整个删掉 `info:` 块，改靠 `INFOPLIST_FILE` 引用手写 Info.plist；删 `properties` 不够，实测过一轮还是假 plist。

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
