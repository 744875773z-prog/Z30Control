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
    @State private var isAfOnActive = false
    @State private var instantPreviewName: String? = nil
    @State private var showingWiredHelp = false
    
    // 参数选择 Sheet
    @State private var activeParamPicker: String? = nil
    
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
        .actionSheet(item: Binding<ActionSheetItem?>(
            get: { activeParamPicker.map { ActionSheetItem(id: $0) } },
            set: { activeParamPicker = $0?.id }
        )) { item in
            makeParamActionSheet(for: item.id)
        }
        .onAppear {
            if usbCamera.isUsbConnected {
                usbCamera.startLiveView()
            }
        }
        .onDisappear {
            usbCamera.stopLiveView()
        }
    }
    
    // MARK: - 监看核心视口 (支持实时图像渲染、触控对焦、参考线与即时回放)
    private func cameraViewport(isLandscape: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                // 1. 核心画面渲染层 (优先渲染真实视频流 / 最新快门成片 / 光学景深取景底图)
                Group {
                    if let frameImg = streamService.currentFrame?.image {
                        Image(uiImage: frameImg)
                            .resizable()
                            .scaledToFit()
                    } else if let usbLiveImg = usbCamera.currentLiveViewImage {
                        Image(uiImage: usbLiveImg)
                            .resizable()
                            .scaledToFit()
                    } else if let lastPhoto = usbCamera.lastCapturedPhoto {
                        Image(uiImage: lastPhoto)
                            .resizable()
                            .scaledToFit()
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Text("📷 最新联机拍摄成片")
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.65))
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                        Spacer()
                                    }
                                    .padding(12)
                                }
                            )
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
                
                // 电子水平仪
                if !isCleanScreen {
                    horizonLevelIndicator
                }
                
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
                
                let normX = Float(location.x / geo.size.width)
                let normY = Float(location.y / geo.size.height)
                CameraConnectionService.shared.client.setTouchFocus(x: normX, y: normY)
                
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
            
            // 居中核心交互状态卡片 (消除死黑)
            VStack(spacing: 14) {
                if isDeviceConnected {
                    if usbCamera.isLiveViewStreaming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("正在拉取 Z 30 实时镜头画面...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .medium)
                            usbCamera.startLiveView()
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
                    
                    Text("💡 联机模式：按相机机身快门拍摄，成片将立即全屏回显并存入手机")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("未检测到相机信号")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("请使用 USB-C 数据线将 iPhone 直连尼康 Z 30")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.black.opacity(0.4))
            .cornerRadius(16)
            
            // 监视器实时状态徽标
            VStack(spacing: 8) {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(isDeviceConnected ? NikonTheme.readyGreen : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(isDeviceConnected ? "USB 联机待命中 · Z 30 硬件就绪" : "未检测到取景信号 · 请连接相机")
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
    
    // MARK: - 竖屏专业监视器布局 (对齐网页版，可调三要素在上，不可调在下可折叠)
    private var portraitProHUD: some View {
        VStack(spacing: 0) {
            if !isCleanScreen {
                // 顶部状态条与线连指引入口
                topConnectionBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
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
            
            if !isCleanScreen {
                // 底部 3D LUT 胶片模拟滤镜条
                lutFilterSelectorStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                
                // 底部综合操作台 (清屏 DISP、AF-ON、大快门环、展开参数)
                portraitBottomControlDeck
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88) // 预留底部 TabBar
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
                            
                            Text("[\(cameraState.remainingShots)]")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)
                        }
                        
                        // 曝光参数垂直卡片 (点击调参)
                        VStack(spacing: 6) {
                            hudParamPill(title: "快门", value: cameraState.shutterSpeed, isActionable: true) {
                                activeParamPicker = "shutter"
                            }
                            hudParamPill(title: "光圈", value: cameraState.aperture, isActionable: true) {
                                activeParamPicker = "aperture"
                            }
                            hudParamPill(title: "ISO", value: cameraState.isoActual, isActionable: true) {
                                activeParamPicker = "iso"
                            }
                            hudParamPill(title: "EV", value: cameraState.exposureCompensation, isActionable: true) {
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
                            
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                streamService.toggleLUT()
                            }) {
                                Image(systemName: "square.3.layers.3d.down.right.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(streamService.isLUTEnabled ? NikonTheme.nikonYellow : .gray)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                    .frame(width: 120)
                    
                    Spacer()
                    
                    // 右翼：DISP、滤镜滑条、AF-ON、大快门环
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
                        
                        // AF-ON 椭圆对焦胶囊按钮
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .heavy)
                            isAfOnActive = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                isAfOnActive = false
                            }
                        }) {
                            Text("AF-ON")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(isAfOnActive ? .black : NikonTheme.nikonYellow)
                                .frame(width: 76, height: 38)
                                .background(isAfOnActive ? NikonTheme.readyGreen : Color.black.opacity(0.5))
                                .cornerRadius(19)
                                .overlay(RoundedRectangle(cornerRadius: 19).stroke(isAfOnActive ? NikonTheme.readyGreen : NikonTheme.nikonYellow, lineWidth: 2))
                        }
                        
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
                    if usbCamera.isLiveViewStreaming {
                        usbCamera.stopLiveView()
                    } else {
                        usbCamera.startLiveView()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: usbCamera.isLiveViewStreaming ? "video.fill" : "video.slash")
                            .font(.system(size: 10, weight: .bold))
                        Text(usbCamera.isLiveViewStreaming ? "取景中" : "启动取景")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(usbCamera.isLiveViewStreaming ? .black : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(usbCamera.isLiveViewStreaming ? NikonTheme.readyGreen : NikonTheme.accentBlue)
                    .cornerRadius(12)
                }
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
            hudParamPill(title: "快门", value: cameraState.shutterSpeed, isActionable: true) {
                activeParamPicker = "shutter"
            }
            hudParamPill(title: "光圈", value: cameraState.aperture, isActionable: true) {
                activeParamPicker = "aperture"
            }
            hudParamPill(title: "ISO", value: cameraState.isoActual, isActionable: true) {
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
            hudParamPill(title: "模式", value: cameraState.exposureMode.rawValue.prefix(1).description, isActionable: true) {
                activeParamPicker = "mode"
            }
            hudParamPill(title: "白平衡", value: cameraState.whiteBalance.rawValue.components(separatedBy: " ").first ?? "自动", isActionable: true) {
                activeParamPicker = "wb"
            }
            hudParamPill(title: "测光", value: cameraState.meteringMode.rawValue.prefix(2).description, isActionable: false)
            hudParamPill(title: "± EV", value: cameraState.exposureCompensation, isActionable: true) {
                activeParamPicker = "ev"
            }
        }
    }
    
    // MARK: - 3D LUT 胶片模拟滤镜水平滚轴
    private var allDisplayFilters: [LUTFilter] {
        return LUTFilter.builtinPresets + LUTStorageManager.shared.customFilters
    }
    
    private var lutFilterSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 原画 (无 LUT)
                lutPill(name: "原片 (Off)", isSelected: !streamService.isLUTEnabled) {
                    streamService.isLUTEnabled = false
                    streamService.setFilter(nil)
                }
                
                // 各款胶片滤镜
                ForEach(allDisplayFilters) { (filter: LUTFilter) in
                    let selected = streamService.isLUTEnabled && streamService.activeFilter?.id == filter.id
                    lutPill(name: filter.name, isSelected: selected) {
                        streamService.isLUTEnabled = true
                        streamService.setFilter(filter)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
    }
    
    private func lutPill(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            NikonTheme.triggerHaptic(style: .light)
            action()
        }) {
            Text(name)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? NikonTheme.nikonYellow : Color.white.opacity(0.1))
                .cornerRadius(10)
        }
    }
    
    // MARK: - 底部操作行 (清屏 DISP + AF-ON + 全屏大快门)
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
            
            // AF-ON 按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
                isAfOnActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isAfOnActive = false
                }
            }) {
                Text("AF-ON")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(isAfOnActive ? .black : NikonTheme.nikonYellow)
                    .frame(width: 78, height: 42)
                    .background(isAfOnActive ? NikonTheme.readyGreen : Color.black.opacity(0.6))
                    .cornerRadius(21)
                    .overlay(RoundedRectangle(cornerRadius: 21).stroke(isAfOnActive ? NikonTheme.readyGreen : NikonTheme.nikonYellow, lineWidth: 2))
            }
            
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
                    .foregroundColor(isActionable ? NikonTheme.nikonYellow : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActionable ? NikonTheme.nikonYellow.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 0.8)
            )
        }
        .disabled(!isActionable)
    }
    
    // MARK: - 触发快门拍摄
    private func triggerShutterCapture() {
        NikonTheme.triggerHaptic(style: .heavy)
        
        cameraState.remainingShots = max(0, cameraState.remainingShots - 1)
        let name = "DSC_\(Int.random(in: 3000...3999)).JPG"
        withAnimation(.easeInOut(duration: 0.15)) {
            self.instantPreviewName = name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                if self.instantPreviewName == name {
                    self.instantPreviewName = nil
                }
            }
        }
    }
    
    // MARK: - 拍摄后即时大图回放浮层
    private func instantPreviewOverlay(filename: String) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 12) {
                HStack {
                    Text("拍摄完成 · 即时预览 (2s)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NikonTheme.nikonYellow)
                        .cornerRadius(4)
                    Spacer()
                    Text(filename)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(NikonTheme.readyGreen)
                
                Text("成片已安全落盘 · RAW+JPEG 原片同步")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - 水平仪与辅助线
    private var horizonLevelIndicator: some View {
        HStack(spacing: 8) {
            Rectangle().fill(NikonTheme.readyGreen).frame(width: 40, height: 1.5)
            Circle().stroke(NikonTheme.readyGreen, lineWidth: 1.5).frame(width: 6, height: 6)
            Rectangle().fill(NikonTheme.readyGreen).frame(width: 40, height: 1.5)
        }
    }
    
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
                            Text("• 【USB-C 有线模式】（当前）：像素蛋糕同款底层，用于高保真联机拍摄与拍立得速传。使用机身快门拍摄，照片瞬间秒传至手机并存入相册。")
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
    
    // MARK: - 参数选择器 ActionSheet 映射
    private func makeParamActionSheet(for param: String) -> ActionSheet {
        switch param {
        case "shutter":
            let speeds = ["1/8000", "1/4000", "1/2000", "1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/4", "1s", "2s"]
            return ActionSheet(
                title: Text("调节快门速度 (Shutter Speed)"),
                message: Text("通过 PTP 实时下发至机身硬件"),
                buttons: speeds.map { s in
                    .default(Text(s)) {
                        cameraState.shutterSpeed = s
                    }
                } + [.cancel(Text("取消"))]
            )
        case "aperture":
            let aps = ["f/1.8", "f/2.8", "f/3.5", "f/4.0", "f/5.6", "f/8.0", "f/11", "f/16"]
            return ActionSheet(
                title: Text("调节镜头光圈 (Aperture)"),
                buttons: aps.map { a in
                    .default(Text(a)) {
                        cameraState.aperture = a
                    }
                } + [.cancel(Text("取消"))]
            )
        case "iso":
            let isos = ["100", "200", "400", "800", "1600", "3200", "6400", "12800", "自动 (Auto)"]
            return ActionSheet(
                title: Text("调节感光度 (ISO)"),
                buttons: isos.map { iso in
                    .default(Text(iso)) {
                        if iso.contains("自动") {
                            cameraState.isAutoISO = true
                            cameraState.isoActual = "自动"
                        } else {
                            cameraState.isAutoISO = false
                            cameraState.isoBase = iso
                            cameraState.isoActual = iso
                        }
                    }
                } + [.cancel(Text("取消"))]
            )
        case "ev":
            let evs = ["+2.0 EV", "+1.0 EV", "+0.7 EV", "+0.3 EV", "0 EV", "-0.3 EV", "-0.7 EV", "-1.0 EV", "-2.0 EV"]
            return ActionSheet(
                title: Text("曝光补偿 (± EV)"),
                buttons: evs.map { ev in
                    .default(Text(ev)) {
                        cameraState.exposureCompensation = ev
                    }
                } + [.cancel(Text("取消"))]
            )
        default:
            return ActionSheet(title: Text("设置"), buttons: [.cancel(Text("关闭"))])
        }
    }
}

private struct ActionSheetItem: Identifiable {
    let id: String
}
