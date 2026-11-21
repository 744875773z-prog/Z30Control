//
//  LiveViewMonitorView.swift
//  Z30Control
//
//  支持横竖屏自适应、全屏清屏 (DISP)、两翼透明 HUD 的专业实时电影监看台
//  100% 完整对齐网页版交互与实机视觉体验
//

import SwiftUI

public struct LiveViewMonitorView: View {
    @ObservedObject var cameraState: CameraState
    @ObservedObject var streamService = LiveViewStreamService.shared
    @ObservedObject var connectionService = CameraConnectionService.shared
    @ObservedObject var usbCamera = UsbCameraManager.shared
    
    private var isDeviceConnected: Bool {
        connectionService.isConnected || cameraState.isConnected || usbCamera.isUsbConnected
    }
    
    // 控制状态
    @State private var isShowingGrid = true
    @State private var isCleanScreen = false // DISP 清屏按键
    @State private var isFullScreen = false  // 全屏展开监看
    @State private var isShowingExpandedParams = false // 展开其余次要参数
    @State private var touchFocusPosition: CGPoint? = nil
    @State private var isFocusPulsing = false
    @State private var instantPreviewName: String? = nil
    // v1.0.4：回显浮层的标题/副标题（之前写死“拍摄完成/已安全落盘”，快门本身是假的）
    @State private var previewTitle = "拍摄完成 · 即时预览 (2s)"
    @State private var previewSubtitle = "成片已回传至手机"
    @State private var isCapturing = false
    @State private var showingWiredHelp = false
    // v1.0.15：未连接空状态里的“连接 Wi-Fi 热点”入口，直接在本页弹出连接向导。
    @State private var showingConnectionWizard = false
    
    // 参数选择面板（v1.0.14：之前是系统 ActionSheet，iOS 27 上弹出后被底栏
    // 挡住大半、点不到值。现在改成页内自己的底部面板，永远在底栏上面。）
    @State private var activeParamPicker: String? = nil
    // v1.0.14：取景画面铺满方式。默认满屏（画面铺满整个视口，两边裁一点），
    // 留白问题就是这么来的——之前是完整画面，3:2 的帧在竖屏手机上天然
    // 上下各留一条黑边。想看完整画面点右上角切回“完整”。
    @State private var isFillScreen = true
    
    var onExitToControl: (() -> Void)? = nil
    
    public init(cameraState: CameraState, onExitToControl: (() -> Void)? = nil) {
        self.cameraState = cameraState
        self.onExitToControl = onExitToControl
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // 1. OLED 纯黑底色，完全消除反光并铺满全屏
                NikonTheme.pitchBlack.ignoresSafeArea()
                
                // 2. 核心画面渲染视口 (中央自适应满幅监看视口)
                cameraViewport(isLandscape: isLandscape)
                
                // 3. 横屏两翼透明 HUD 监看台 或 竖屏专业监看台
                if isLandscape {
                    landscapeTwoWingHUD(size: geometry.size)
                } else {
                    portraitProHUD
                        .sheet(isPresented: $showingConnectionWizard) {
                            ConnectionWizardView()
                        }
                }

                // 3b. v1.0.14：参数选择面板（页内底部面板，不走系统 ActionSheet，
                // 永远浮在底栏上面，不会被挡住）。点遮罩或 × 关闭，可连续点多个值。
                if let picker = activeParamPicker, !isCleanScreen {
                    paramPickerPanel(for: picker)
                }

                // 4. 清屏状态下轻巧的恢复浮标 (严格对齐用户要求：位于右上角)
                if isCleanScreen {
                    cleanScreenWakeButton
                }
                
                // 5. 横屏状态下左上角常驻返回按钮 (解决横屏无法返回上个页面问题)
                if isLandscape {
                    VStack {
                        HStack {
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                onExitToControl?()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("返回")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                            }
                            .padding(.leading, 24)
                            .padding(.top, 24)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showingWiredHelp) {
            wiredConnectionGuidanceSheet
        }
        .onAppear {
            // v1.0.22：整页锁定竖屏，底栏在原来位置不动，只有中间取景画面
            // 在页内转 90°（见 liveViewImage）。手机横过来拿，画面正过来铺满；
            // 系统方向锁定也不用开了，App 自己锁竖屏。
            OrientationLock.lockPortrait()
            // v1.0.3：之前这里只启动 USB 取景，Wi-Fi（PTP/IP）连上后从不发
            // StartLiveView，所以画面永远是黑的。现在按当前通路启动。
            startLiveViewForActiveTransport()
        }
        .onDisappear {
            OrientationLock.unlockToPortrait()
            stopLiveViewForActiveTransport()
        }
        .onChange(of: connectionService.isConnected) { connected in
            // 已在取景页时才连上相机（例如从连接页切回来）：立即开始取景
            if connected && !usbCamera.isUsbConnected {
                connectionService.client.startLiveView()
            }
        }
        .onChange(of: usbCamera.isUsbConnected) { connected in
            // v1.0.11：进取景页时 USB 还没握手完，onAppear 那次启动会扑空
            // （当时两条通路都没连上），之后 USB 连上了也没人再启动。
            // USB 握手完成后自动再启动一次，不用用户再点按钮。
            if connected && !isAnyLiveViewStreaming {
                startLiveViewForActiveTransport()
            }
        }
    }
    
    // MARK: - v1.0.3：按当前通路启停取景（USB-C / Wi-Fi PTP/IP）
    private var isAnyLiveViewStreaming: Bool {
        usbCamera.isLiveViewStreaming || connectionService.client.isStreamingLiveView
    }
    
    private func startLiveViewForActiveTransport() {
        if usbCamera.isUsbConnected {
            usbCamera.startLiveView()
        } else if connectionService.isConnected {
            connectionService.client.startLiveView()
        }
    }
    
    private func stopLiveViewForActiveTransport() {
        usbCamera.stopLiveView()
        connectionService.client.stopLiveView()
    }
    
    private func toggleLiveViewForActiveTransport() {
        if isAnyLiveViewStreaming {
            stopLiveViewForActiveTransport()
        } else {
            startLiveViewForActiveTransport()
        }
    }
    
    // MARK: - 监看核心视口 (支持实时图像渲染、触控对焦、参考线与即时回放)
    private func cameraViewport(isLandscape: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                // 1. 核心画面渲染层 (优先渲染真实视频流 / 最新快门成片 / 光学景深取景底图)
                Group {
                    if let frameImg = streamService.currentFrame?.image {
                        liveViewImage(frameImg, size: geo.size)
                    } else if let usbLiveImg = usbCamera.currentLiveViewImage {
                        liveViewImage(usbLiveImg, size: geo.size)
                    } else {
                        // 具有电影景深感与动态光斑的高拟真光学实景监看底图 (绝非死黑图标)
                        photographicLiveViewBackground(size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                
                // 构图三等分线
                if isShowingGrid && !isCleanScreen {
                    compositionGridOverlay
                }
                
                // v1.0.23：电子水平仪不要了——绿色横线+圆圈会压在“未检测到
                // 相机信号”文字上。中间这个位置留空，以后放分类滤镜。
                
                // 触控对焦点与绿框
                if let pos = touchFocusPosition {
                    Rectangle()
                        .stroke(isFocusPulsing ? NikonTheme.nikonYellow : NikonTheme.readyGreen, lineWidth: 2)
                        .frame(width: isFocusPulsing ? 56 : 46, height: isFocusPulsing ? 56 : 46)
                        .position(pos)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocusPulsing)
                }
                
                // 录像红框 Tally
                if cameraState.isRecordingVideo {
                    Rectangle()
                        .stroke(NikonTheme.tallyRed, lineWidth: 4)
                        .ignoresSafeArea()
                }
                
                // 拍照后即时大图全屏回放浮层
                if let previewName = instantPreviewName {
                    instantPreviewOverlay(filename: previewName)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard !isCleanScreen else {
                    withAnimation { isCleanScreen = false }
                    return
                }
                NikonTheme.triggerHaptic(style: .light)
                self.touchFocusPosition = location
                self.isFocusPulsing = true
                
                // v1.0.22：画面顺时针转了 90°，点按坐标也要跟着转：
                // 屏上点 (nx, ny) 对应帧上 (ny, 1-nx)——帧左上角转到了屏右上角。
                let normX = Float(location.x / geo.size.width)
                let normY = Float(location.y / geo.size.height)
                CameraConnectionService.shared.client.setTouchFocus(x: normY, y: 1 - normX)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isFocusPulsing = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.touchFocusPosition == location {
                        withAnimation { self.touchFocusPosition = nil }
                    }
                }
            }
        }
    }
    
    // MARK: - v1.0.14：取景画面铺满方式
    /// 满屏：画面铺满整个视口（两边裁一点），上下不再留黑边——默认就是这个，
    /// 之前完整画面时 3:2 的帧在竖屏手机上天然上下各留一条大黑边。
    /// 完整：整帧都看得见，画面顶到 HUD 下面（不再垂直居中留两条黑边）。
    // MARK: - v1.0.22：只有中间取景画面是横的
    /// 整页锁定竖屏（见 onAppear 的 lockPortrait），取景帧在画面内顺时针
    /// 转 90°：帧先按（高×宽）铺满/完整，再转 90°，外框裁回竖屏尺寸。
    /// 手机横过来拿（顶朝左），画面正过来铺满；底栏、参数条、快门键都
    /// 在竖屏原位置，不动也不消失。完整模式不再顶 110pt 留白，画面居中。
    private func liveViewImage(_ img: UIImage, size: CGSize) -> some View {
        Group {
            if isFillScreen {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
            } else {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // v1.0.20：取景按钮带上帧分辨率（相机实际发来的那帧多大）。
    private var liveViewStreamLabel: String {
        let size = streamService.currentFrameSize
        if size != .zero {
            return "取景中 \(Int(size.width))×\(Int(size.height))"
        }
        return "取景中"
    }

    // MARK: - 真实拟真光学取景底图 (消除死黑画面)
    private func photographicLiveViewBackground(size: CGSize) -> some View {
        ZStack {
            // 真实电影级渐变景深与虚化光斑
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.16, green: 0.18, blue: 0.22),
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.08, green: 0.09, blue: 0.11)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 虚化光斑光圈模拟 (焦外散景 Bokeh)
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: size.width * 0.7, height: size.width * 0.7)
                .blur(radius: 50)
                .offset(x: -size.width * 0.2, y: -size.height * 0.15)
            
            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: size.width * 0.5, height: size.width * 0.5)
                .blur(radius: 40)
                .offset(x: size.width * 0.25, y: size.height * 0.2)
            
            // 光学暗角 (Vignette)
            RadialGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.45)]),
                center: .center,
                startRadius: size.width * 0.35,
                endRadius: size.width * 0.8
            )
            
            // v1.0.15：这里只放“已连接但还没出画面”的启动卡片。未连接的空状态
            // 不再放这里——之前它居中在整块底图上，只有一张小卡片，上下各空
            // 一大条黑边；现在挪到 portraitProHUD 中部，带两个连接入口。
            if isDeviceConnected {
                VStack(spacing: 14) {
                    if isAnyLiveViewStreaming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("正在拉取 Z 30 实时镜头画面...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .medium)
                            startLiveViewForActiveTransport()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 15))
                                Text("开启相机实时取景")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(NikonTheme.accentBlue)
                            .foregroundColor(.white)
                            .cornerRadius(24)
                            .shadow(color: NikonTheme.accentBlue.opacity(0.4), radius: 10, y: 4)
                        }
                    }
                    
                    Text("💡 联机模式：按相机机身快门拍摄，成片直接进图库，在图库里选图保存")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    // v1.0.4：取景失败原因直接显示，不再静悄悄黑屏
                    if !usbCamera.liveViewError.isEmpty {
                        Text(usbCamera.liveViewError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    // v1.0.17：同控制页，诊断行只在真报错时显示。
                    if usbCamera.ptpDiagnosticIsError {
                        Text(usbCamera.ptpDiagnostic)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Color.black.opacity(0.4))
                .cornerRadius(16)
            }
            
            // 监视器实时状态徽标（v1.0.15：只在已连接时显示。未连接时它写的是
            // “未检测到取景信号”，和中部空状态重复，还会压到快门按钮上。）
            if isDeviceConnected {
                VStack(spacing: 8) {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(NikonTheme.readyGreen)
                            .frame(width: 7, height: 7)
                        Text("USB 联机待命中 · Z 30 硬件就绪")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(12)
                    .padding(.bottom, 90)
                }
            }
        }
    }
    
    // MARK: - 竖屏专业监视器布局 (对齐网页版，可调三要素在上，不可调在下可折叠)
    private var portraitProHUD: some View {
        GeometryReader { geo in
            // v1.0.15：这里不要再加 safeAreaInsets.top——根视图已经被系统按安全区
            // 往下顶了一次（灵动岛约 59pt），而这里的 geo.safeAreaInsets.top 还是 59，
            // 再加就是双份：实测顶栏被顶到 120pt 才出现，上面空一大条黑边（用户
            // 2026-11-21 18:03 截图）。只留 8pt 固定间距就够了。
            let topPad: CGFloat = 8
            VStack(spacing: 0) {
                if !isCleanScreen {
                    // 顶部状态条与线连指引入口 (顶部 padding 自动适配灵动岛高度)
                    topConnectionBanner
                        .padding(.horizontal, 14)
                        .padding(.top, topPad + 4)
                        .padding(.bottom, 6)
                    
                    // 核心曝光三要素调控条 (快门、光圈、ISO)
                    coreThreeParamsHUD
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    
                    // 次级不可调节/状态参数折叠区
                    if isShowingExpandedParams {
                        expandedSpecsStrip
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                Spacer()

                // v1.0.15：未连接时的空状态放在这里（参数条和底栏之间），上下两个
                // Spacer 把剩余空间均分。之前它在底图中央只是一张小卡片，上下
                // 各空一大条黑边；现在是标题 + 两个连接入口，点 USB 进线连指引，
                // 点 Wi-Fi 直接弹出连接向导。
                if !isCleanScreen && !isDeviceConnected {
                    disconnectedEmptyState
                        .padding(.horizontal, 20)
                }

                Spacer()

                if !isCleanScreen {
                    // v1.0.19：本次拍摄条、滤镜条都不要了。底栏直接贴在 TabBar
                    // 上面一点（之前 96pt 空一大截，快门键离底栏太远）。
                    portraitBottomControlDeck
                        .padding(.horizontal, 16)
                        // 底栏在 VStack 流里，取景页框底就是 TabBar 顶边，
                        // 只留 12pt 间隙，快门键就贴在底栏上方。
                        .padding(.bottom, 12 + max(geo.safeAreaInsets.bottom - 20, 0))
                }
            }
        }
    }
    
    // MARK: - 横屏专业相机两翼透明 OSD 布局 (对齐网页版，画面零遮挡)
    private func landscapeTwoWingHUD(size: CGSize) -> some View {
        ZStack {
            if !isCleanScreen {
                HStack(spacing: 0) {
                    // 左翼：机身信息与参数垂直列 (全透明背景，只有细微投影，画面穿透直达)
                    VStack(alignment: .leading, spacing: 8) {
                        // 顶部模式标牌
                        HStack(spacing: 6) {
                            Text(cameraState.exposureMode.rawValue.prefix(1).description)
                                .font(.system(size: 12, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NikonTheme.nikonYellow)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                            
                            Text(cameraState.storageKnown ? "[\(cameraState.remainingShots)]" : "[--]")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)

                            // v1.0.20：取景帧实际分辨率（相机发来的那帧多大）。
                            // 满屏放大几倍看必然糊，先让这个数字看得见。
                            if streamService.currentFrameSize != .zero {
                                Text("\(Int(streamService.currentFrameSize.width))×\(Int(streamService.currentFrameSize.height))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .shadow(color: .black, radius: 2)
                            }
                        }
                        
                        // 曝光参数垂直卡片 (点击调参)
                        VStack(spacing: 6) {
                            hudParamPill(title: "快门", value: cameraState.shutterSpeed, isActionable: isParamEditable("shutter")) {
                                activeParamPicker = "shutter"
                            }
                            hudParamPill(title: "光圈", value: cameraState.aperture, isActionable: isParamEditable("aperture")) {
                                activeParamPicker = "aperture"
                            }
                            hudParamPill(title: "ISO", value: cameraState.isoActual, isActionable: isParamEditable("iso")) {
                                activeParamPicker = "iso"
                            }
                            hudParamPill(title: "EV", value: cameraState.exposureCompensation, isActionable: isParamEditable("ev")) {
                                activeParamPicker = "ev"
                            }
                        }
                        
                        Spacer()
                        
                        // 辅助工具切换
                        HStack(spacing: 8) {
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                isShowingGrid.toggle()
                            }) {
                                Image(systemName: isShowingGrid ? "grid" : "grid.circle")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }

                            // v1.0.20：取景增强开关（降噪+锐化，默认开）。
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                streamService.isEnhanceEnabled.toggle()
                            }) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(streamService.isEnhanceEnabled ? NikonTheme.nikonYellow : .white.opacity(0.5))
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(streamService.isEnhanceEnabled ? 0.4 : 0.2))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                    .frame(width: 120)
                    
                    Spacer()
                    
                    // 右翼：DISP、大快门环（v1.0.19：AF-ON 不要了）
                    VStack(alignment: .trailing, spacing: 14) {
                        // 顶部 DISP 清屏按键
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .medium)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCleanScreen = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.slash.fill")
                                Text("DISP 清屏")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                        }
                        
                        Spacer()
                        
                        // 大拇指主快门环 (半透明设计，零遮挡)
                        Button(action: {
                            triggerShutterCapture()
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(NikonTheme.nikonYellow, lineWidth: 4)
                                    .frame(width: 66, height: 66)
                                    .shadow(color: NikonTheme.nikonYellow.opacity(0.5), radius: 8, x: 0, y: 0)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 50, height: 50)
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
                    .frame(width: 110)
                }
            }
        }
    }
    
    // MARK: - 顶部状态条与线连指引入口
    private var topConnectionBanner: some View {
        HStack(spacing: 8) {
            // 连接状态标
            HStack(spacing: 5) {
                Circle()
                    .fill(isDeviceConnected ? NikonTheme.readyGreen : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isDeviceConnected ? "已在线: \(usbCamera.connectedDeviceName.isEmpty ? cameraState.modelName : usbCamera.connectedDeviceName)" : "未连相机")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            
            Spacer()
            
            if isDeviceConnected {
                Button(action: {
                    NikonTheme.triggerHaptic(style: .medium)
                    toggleLiveViewForActiveTransport()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isAnyLiveViewStreaming ? "video.fill" : "video.slash")
                            .font(.system(size: 10, weight: .bold))
                        Text(isAnyLiveViewStreaming ? liveViewStreamLabel : "启动取景")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(isAnyLiveViewStreaming ? .black : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isAnyLiveViewStreaming ? NikonTheme.readyGreen : NikonTheme.accentBlue)
                    .cornerRadius(12)
                }
            }
            
            // v1.0.14：满屏 / 完整 切换。满屏铺满视口（两边裁一点），
            // 完整显示整帧（上下会有黑边）。默认满屏。
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                withAnimation(.easeInOut(duration: 0.2)) { isFillScreen.toggle() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isFillScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .bold))
                    Text(isFillScreen ? "满屏" : "完整")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
            }

            // USB-C 有线直连指引药丸按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                showingWiredHelp = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 10, weight: .bold))
                    Text(isDeviceConnected ? "USB-C 有线" : "线连指引 (必看)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isDeviceConnected ? Color.white : NikonTheme.nikonYellow)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - 核心可调三要素 (快门、光圈、ISO) 药丸列
    private var coreThreeParamsHUD: some View {
        HStack(spacing: 8) {
            hudParamPill(title: "快门", value: cameraState.shutterSpeed, isActionable: isParamEditable("shutter")) {
                activeParamPicker = "shutter"
            }
            hudParamPill(title: "光圈", value: cameraState.aperture, isActionable: isParamEditable("aperture")) {
                activeParamPicker = "aperture"
            }
            hudParamPill(title: "ISO", value: cameraState.isoActual, isActionable: isParamEditable("iso")) {
                activeParamPicker = "iso"
            }
            
            // 展开其余参数的小按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isShowingExpandedParams.toggle()
                }
            }) {
                VStack(spacing: 2) {
                    Image(systemName: isShowingExpandedParams ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(isShowingExpandedParams ? "收起" : "更多")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.55))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
            }
        }
    }
    
    // MARK: - 次级参数展开抽屉 (白平衡、测光、EV、格式等)
    private var expandedSpecsStrip: some View {
        HStack(spacing: 6) {
            // v1.0.14：模式只显示不点——0x500E 在尼康上是只读的（gphoto2
            // 写它会被相机拒绝），模式只能转机身拨盘。AUTO/U1/U2/U3 现在
            // 都能认出来了（短标签，不会和 A 档撞）；认不出来的显示原始值。
            hudParamPill(title: "模式", value: modeDisplayText, isActionable: false)
            hudParamPill(title: "白平衡", value: cameraState.whiteBalance.rawValue.components(separatedBy: " ").first ?? "自动", isActionable: true) {
                activeParamPicker = "wb"
            }
            hudParamPill(title: "测光", value: cameraState.meteringMode.rawValue.prefix(2).description, isActionable: false)
            hudParamPill(title: "± EV", value: cameraState.exposureCompensation, isActionable: isParamEditable("ev")) {
                activeParamPicker = "ev"
            }
        }
    }

    /// 模式药丸显示：认得出的显示短标签（AUTO/U1/U2/U3），
    /// 认不出的显示原始值（如 0x8014），方便对表修正。
    private var modeDisplayText: String {
        if cameraState.exposureMode == .unknown {
            return String(format: "0x%04X", cameraState.exposureModeRaw)
        }
        return cameraState.exposureMode.shortLabel
    }
    
    // MARK: - v1.0.15：未连接时的空状态（标题 + 两个连接入口）
    private var disconnectedEmptyState: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "cable.connector.slash")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.4))
                Text("未检测到相机信号")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Text("请使用 USB-C 数据线直连，或在「连接」页连入相机 Wi-Fi 热点")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                connectOptionRow(icon: "cable.connector", title: "USB-C 直连", subtitle: "插线即连，最稳") {
                    NikonTheme.triggerHaptic(style: .medium)
                    showingWiredHelp = true
                }
                connectOptionRow(icon: "wifi", title: "连接相机 Wi-Fi 热点", subtitle: "相机开热点，手机加入后连接") {
                    NikonTheme.triggerHaptic(style: .medium)
                    showingConnectionWizard = true
                }
            }
        }
    }

    private func connectOptionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(NikonTheme.accentBlue)
                    .frame(width: 36, height: 36)
                    .background(NikonTheme.accentBlue.opacity(0.15))
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.45))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 底部操作行 (清屏 DISP + 全屏大快门，v1.0.19：AF-ON 不要了)
    private var portraitBottomControlDeck: some View {
        HStack(spacing: 20) {
            // DISP 清屏按键
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCleanScreen = true
                }
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 16))
                    Text("DISP")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.6))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            }
            
            Spacer()
            
            // 主快门按钮
            Button(action: {
                triggerShutterCapture()
            }) {
                ZStack {
                    Circle()
                        .stroke(NikonTheme.nikonYellow, lineWidth: 4)
                        .frame(width: 66, height: 66)
                        .shadow(color: NikonTheme.nikonYellow.opacity(0.5), radius: 8, x: 0, y: 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 50, height: 50)
                }
            }
            
            Spacer()
            
            // 辅助网格切换
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                isShowingGrid.toggle()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: isShowingGrid ? "grid" : "grid.circle")
                        .font(.system(size: 16))
                    Text(isShowingGrid ? "网格" : "关")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.6))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            }

            // v1.0.20：取景增强开关（降噪+锐化，默认开）。
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                streamService.isEnhanceEnabled.toggle()
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16))
                    Text(streamService.isEnhanceEnabled ? "增强" : "关")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(streamService.isEnhanceEnabled ? NikonTheme.nikonYellow : .white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.6))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            }
        }
    }
    
    // MARK: - 清屏状态下屏幕角落淡雅唤醒浮标 (严格对齐用户要求：位于右上角)
    private var cleanScreenWakeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCleanScreen = false
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.fill")
                        Text("恢复显示")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.accentBlue, lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.4), radius: 6)
                }
                .padding(.trailing, 24)
                .padding(.top, 24)
            }
            Spacer()
        }
    }
    
    // MARK: - 通用 HUD 胶囊卡片
    // MARK: - v1.0.6：按当前曝光模式决定参数能不能调
    // M 挡快门/光圈/ISO 全可调（没有曝光补偿）；A 挡只能调光圈；S 挡只能调快门；
    // P 挡快门光圈都由相机自动；ISO 在自动 ISO 时由相机定，手动 ISO 时可调。
    // 可调的药丸显示蓝色、点得开；不可调的显示白色、点不开。
    // v1.0.14：AUTO 档相机全锁，四个参数都不能调；U1/U2/U3 槽里存的是哪档
    // （P/S/A/M）读不出来，先都放开让点，相机不接受的设置会失败回滚。
    private func isParamEditable(_ param: String) -> Bool {
        switch cameraState.exposureMode {
        case .auto:
            return false
        case .manual:
            if param == "ev" { return false }
            if param == "iso" { return !cameraState.isAutoISO }
            return true
        case .aperturePriority:
            if param == "aperture" || param == "ev" { return true }
            if param == "iso" { return !cameraState.isAutoISO }
            return false
        case .shutterPriority:
            if param == "shutter" || param == "ev" { return true }
            if param == "iso" { return !cameraState.isAutoISO }
            return false
        case .program:
            if param == "ev" { return true }
            if param == "iso" { return !cameraState.isAutoISO }
            return false
        case .user1, .user2, .user3, .unknown:
            return true
        }
    }

    private func hudParamPill(title: String, value: String, isActionable: Bool, action: (() -> Void)? = nil) -> some View {
        Button(action: {
            if isActionable {
                NikonTheme.triggerHaptic(style: .light)
                action?()
            }
        }) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.gray)
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(isActionable ? NikonTheme.accentBlue : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActionable ? NikonTheme.accentBlue.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 0.8)
            )
        }
        .disabled(!isActionable)
    }
    
    // MARK: - 触发快门拍摄（v1.0.4：真的发 InitiateCapture）
    // 之前是假的：不发任何命令，只随机编个 DSC_xxxx.JPG 弹“拍摄完成”，
    // 还顺手把剩余张数减 1。相机根本没拍。
    // 现在：发拍摄命令；成功只代表“已触发”，成片随后进图库（didAdd 或
    // 2.5s/6s 拍后复查）。失败则报原因。
    // v1.0.19：AF-ON 不要了（triggerAutofocus / driveAutofocusAtCenter
    // 都删了；点画面对焦还留着，走 Wi-Fi 的 driveAutofocus）。

    private func triggerShutterCapture() {
        guard !isCapturing else { return }
        NikonTheme.triggerHaptic(style: .heavy)
        isCapturing = true
        if usbCamera.isUsbConnected {
            usbCamera.capturePhoto { ok, err in
                DispatchQueue.main.async {
                    self.isCapturing = false
                    if ok {
                        // v1.0.18：速传删了，不再等下载回显。触发成功就提示一声，
                        // 成片 2.5s/6s 后进图库。
                        self.showPreview(
                            filename: nil,
                            title: "快门已触发",
                            subtitle: "已触发，成片见图库"
                        )
                    } else {
                        self.showPreview(
                            filename: nil,
                            title: "快门触发失败",
                            subtitle: err ?? "相机无响应"
                        )
                    }
                }
            }
        } else if connectionService.isConnected {
            connectionService.client.initiateCapture { ok in
                DispatchQueue.main.async {
                    self.isCapturing = false
                    if ok {
                        self.showPreview(
                            filename: nil,
                            title: "快门已触发",
                            subtitle: "已触发，成片见图库"
                        )
                    } else {
                        self.showPreview(
                            filename: nil,
                            title: "快门触发失败",
                            subtitle: "Wi-Fi 未响应，请重试"
                        )
                    }
                }
            }
        } else {
            isCapturing = false
            showPreview(filename: nil, title: "未连接相机", subtitle: "请先连上相机再拍摄")
        }
    }

    /// 显示回显浮层（2 秒后自动消失）；filename 为 nil 时不显示文件名行
    private func showPreview(filename: String?, title: String, subtitle: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.previewTitle = title
            self.previewSubtitle = subtitle
            self.instantPreviewName = filename ?? " "
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                if self.previewTitle == title {
                    self.instantPreviewName = nil
                }
            }
        }
    }
    
    // MARK: - 拍摄后即时大图回放浮层（只显示真实回传的照片）
    private func instantPreviewOverlay(filename: String) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 12) {
                HStack {
                    Text(previewTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NikonTheme.nikonYellow)
                        .cornerRadius(4)
                    Spacer()
                    if filename != " " {
                        Text(filename)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                // v1.0.18：速传删了，不再回显真图——只显示状态图标（成功打勾/失败打叉）。
                Image(systemName: previewTitle.contains("失败") || previewTitle.contains("未连接") ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(previewTitle.contains("失败") || previewTitle.contains("未连接") ? Color(red: 1.0, green: 0.45, blue: 0.35) : NikonTheme.readyGreen)
                
                Text(previewSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - 辅助线
    private var compositionGridOverlay: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: w * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: h * 2 / 3))
                path.addLine(to: CGPoint(x: w, y: h * 2 / 3))
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
        }
    }
    
    // MARK: - USB-C 有线连接排查指引弹窗 (极度关键：帮助用户解决无法线连相机的困惑)
    private var wiredConnectionGuidanceSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("为什么插上线无法识别相机？")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Text("尼康相机直连 iPhone 需要在机身菜单做一次模式切换，否则 iOS 系统会将其当做普通的只读电脑配件。")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 10)
                    
                    Divider()
                    
                    // 步骤 1: 相机菜单设置
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(NikonTheme.nikonYellow).frame(width: 22, height: 22)
                                .overlay(Text("1").font(.system(size: 12, weight: .bold)).foregroundColor(.black))
                            Text("关键步骤：相机机身菜单设置")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text("打开 Z 30 相机电源 -> 按 MENU 键 -> 进入【设置菜单】(扳手图标) 或【网络菜单】-> 找到【USB 数据连接】(USB Data Connection) -> 将其从默认的【MTP/PTP】更改为【iPhone】！")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(10)
                    }
                    
                    // 步骤 2: 线缆确认
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(NikonTheme.nikonYellow).frame(width: 22, height: 22)
                                .overlay(Text("2").font(.system(size: 12, weight: .bold)).foregroundColor(.black))
                            Text("线缆要求：双头 Type-C 数据线")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text("请务必使用支持数据传输的 USB-C to USB-C 线（如尼康原装 UC-E25 或手机原配快充数据线），切勿使用仅具备充电功能的地摊纯电线。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    // 模式说明: USB 联机 vs Wi-Fi 取景
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(NikonTheme.nikonYellow).frame(width: 22, height: 22)
                                .overlay(Text("3").font(.system(size: 12, weight: .bold)).foregroundColor(.black))
                            Text("两种取景与传输工作流说明")
                                .font(.system(size: 15, weight: .bold))
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 【USB-C 有线模式】（当前）：高保真联机拍摄。使用机身快门或 App 快门拍摄，成片直接进图库，在图库里选图保存到手机。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("• 【Wi-Fi 模式】：若需要无线 60 帧实时镜头画面预览与远程调参，在相机上按 MENU ➔ 连接至智能设备 ➔ 开启 Wi-Fi，手机连入相机热点即可。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(10)
                    }
                    
                    // 步骤 4: 立即重新探测
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .medium)
                        showingWiredHelp = false
                        connectionService.autoDetectAndConnect()
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("我已设置好，立即重新探测连接")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(NikonTheme.nikonYellow)
                        .cornerRadius(14)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationTitle("USB-C 线连设置指引")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showingWiredHelp = false
                    }
                }
            }
        }
    }
    
    // MARK: - v1.0.6：曝光参数真实下发 + 乐观更新
    // v1.0.4 是等相机回包才改显示，但取景帧抢通道，回包要等好几秒，看着像“反应非常慢”。
    // 现在先改显示再发命令，失败就恢复旧值，原因写进 PTP 诊断。
    private func setExposureProp(code: UInt16, value: Data, apply: @escaping () -> Void, revert: @escaping () -> Void) {
        apply()
        if usbCamera.isUsbConnected {
            usbCamera.setCameraProp(code: code, value: value) { ok in
                DispatchQueue.main.async { if !ok { revert() } }
            }
        } else if connectionService.isConnected {
            connectionService.client.setDevicePropValue(code: code, value: value) { ok in
                DispatchQueue.main.async { if !ok { revert() } }
            }
        } else {
            // 未连接：没下发就别假装改了，恢复旧值
            revert()
        }
    }

    /// “1/125”→80、“1s”→10000（ExposureTime 单位：秒×10000）
    private func encodeShutter(_ s: String) -> UInt32? {
        guard s.hasSuffix("s") else { return nil }
        let core = String(s.dropLast())
        if core.hasPrefix("1/"), let d = Double(core.dropFirst(2)), d > 0 {
            return UInt32(10000.0 / d)
        }
        if let sec = Double(core) {
            return UInt32(sec * 10000)
        }
        return nil
    }

    /// “f/4.0”→400（FNumber 单位：F值×100）
    private func encodeAperture(_ s: String) -> UInt16? {
        guard s.hasPrefix("f/"), let v = Double(s.dropFirst(2)) else { return nil }
        return UInt16(v * 100)
    }

    /// “+1.0 EV”→1000、“-0.3 EV”→-300（ExposureBias 单位：EV×1000）
    private func encodeEV(_ s: String) -> Int16? {
        let core = s.replacingOccurrences(of: " EV", with: "")
        guard let v = Double(core) else { return nil }
        return Int16(v * 1000)
    }

    // MARK: - 参数选择器 ActionSheet 映射
    // MARK: - v1.0.14：参数选择面板（页内底部面板，替代系统 ActionSheet）
    /// 之前是系统 ActionSheet，iOS 27 上弹出后只露一条边在底栏上面、
    /// 点不到值。现在是页内自己的面板：底部留出玻璃底栏的高度，永远
    /// 在底栏上面；点一个值就下发一个，不关闭，方便连续试；点遮罩或 × 关闭。
    private func paramPickerPanel(for param: String) -> some View {
        VStack(spacing: 0) {
            // 遮罩：点空白处关闭
            Color.black.opacity(0.35)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { activeParamPicker = nil }
                }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(paramPickerTitle(for: param))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) { activeParamPicker = nil }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(paramOptions(for: param), id: \.self) { value in
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                applyParamValue(param: param, value: value)
                            }) {
                                Text(value)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(isCurrentParamValue(param: param, value: value) ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isCurrentParamValue(param: param, value: value) ? NikonTheme.accentBlue : Color.white.opacity(0.12))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
            .padding(.horizontal, 12)
            // 底栏上面留出玻璃底栏的高度，别被挡住
            .padding(.bottom, 110)
        }
        .ignoresSafeArea()
    }

    private func paramPickerTitle(for param: String) -> String {
        switch param {
        case "shutter": return "快门速度"
        case "aperture": return "光圈"
        case "iso": return "感光度 ISO"
        case "ev": return "曝光补偿 (± EV)"
        case "wb": return "白平衡"
        default: return "设置"
        }
    }

    private func paramOptions(for param: String) -> [String] {
        switch param {
        case "shutter":
            return ["1/8000", "1/4000", "1/2000", "1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/4", "1s", "2s"]
        case "aperture":
            return ["f/1.8", "f/2.8", "f/3.5", "f/4.0", "f/5.6", "f/8.0", "f/11", "f/16"]
        case "iso":
            return ["100", "200", "400", "800", "1600", "3200", "6400", "12800", "自动"]
        case "ev":
            return ["+2.0 EV", "+1.0 EV", "+0.7 EV", "+0.3 EV", "0 EV", "-0.3 EV", "-0.7 EV", "-1.0 EV", "-2.0 EV"]
        case "wb":
            return ["自动", "晴天", "阴天", "阴影", "白炽灯", "荧光灯"]
        default:
            return []
        }
    }

    private func isCurrentParamValue(param: String, value: String) -> Bool {
        switch param {
        case "shutter": return cameraState.shutterSpeed == value
        case "aperture": return cameraState.aperture == value
        case "iso":
            if value == "自动" { return cameraState.isAutoISO }
            return !cameraState.isAutoISO && cameraState.isoActual == value
        case "ev": return cameraState.exposureCompensation == value
        case "wb": return cameraState.whiteBalance.rawValue.components(separatedBy: " ").first == value
        default: return false
        }
    }

    /// 点一个值就下发一个（乐观更新，相机拒绝则恢复旧值，和之前一样）。
    private func applyParamValue(param: String, value: String) {
        switch param {
        case "shutter":
            guard let raw = encodeShutter(value) else { return }
            let old = cameraState.shutterSpeed
            setExposureProp(code: 0x500D, value: Data(raw.littleEndianBytes), apply: {
                cameraState.shutterSpeed = value
            }, revert: {
                cameraState.shutterSpeed = old
            })
        case "aperture":
            guard let raw = encodeAperture(value) else { return }
            let old = cameraState.aperture
            setExposureProp(code: 0x5007, value: Data(raw.littleEndianBytes), apply: {
                cameraState.aperture = value
            }, revert: {
                cameraState.aperture = old
            })
        case "iso":
            let oldAuto = cameraState.isAutoISO
            let oldBase = cameraState.isoBase
            let oldActual = cameraState.isoActual
            let revertISO = {
                cameraState.isAutoISO = oldAuto
                cameraState.isoBase = oldBase
                cameraState.isoActual = oldActual
            }
            if value == "自动" {
                // 0xFFFF = Auto ISO
                setExposureProp(code: 0x500F, value: Data(UInt16(0xFFFF).littleEndianBytes), apply: {
                    cameraState.isAutoISO = true
                    cameraState.isoActual = "自动"
                }, revert: revertISO)
            } else if let v = UInt16(value) {
                setExposureProp(code: 0x500F, value: Data(v.littleEndianBytes), apply: {
                    cameraState.isAutoISO = false
                    cameraState.isoBase = value
                    cameraState.isoActual = value
                }, revert: revertISO)
            }
        case "ev":
            guard let raw = encodeEV(value) else { return }
            let old = cameraState.exposureCompensation
            setExposureProp(code: 0x5010, value: Data(raw.littleEndianBytes), apply: {
                cameraState.exposureCompensation = value
            }, revert: {
                cameraState.exposureCompensation = old
            })
        case "wb":
            // 白平衡 0x5005：标准值 自动=2、晴天=4、荧光灯=5、白炽灯=6；
            // 尼康厂商值 阴天=0x8010、阴影=0x8011（开源项目 ptp_misc.cpp 的尼康表证实）。
            guard let raw = encodeWhiteBalance(value) else { return }
            let old = cameraState.whiteBalance
            let newMode: WhiteBalanceMode
            switch value {
            case "晴天": newMode = .daylight
            case "阴天": newMode = .cloudy
            case "阴影": newMode = .shade
            case "白炽灯": newMode = .incandescent
            case "荧光灯": newMode = .fluorescent
            default: newMode = .auto
            }
            setExposureProp(code: 0x5005, value: Data(raw.littleEndianBytes), apply: {
                cameraState.whiteBalance = newMode
            }, revert: {
                cameraState.whiteBalance = old
            })
        default:
            break
        }
    }

    /// “晴天”→4、“阴天”→0x8010、“阴影”→0x8011（见 applyParamValue 里的注释）
    private func encodeWhiteBalance(_ s: String) -> UInt16? {
        switch s {
        case "自动": return 2
        case "晴天": return 4
        case "荧光灯": return 5
        case "白炽灯": return 6
        case "阴天": return 0x8010
        case "阴影": return 0x8011
        default: return nil
        }
    }
}

