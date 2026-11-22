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
    // v1.0.25：网格 8 选 1（无网格 + 7 种），选择存在 UserDefaults。
    @State private var gridStyle: GridStyle = GridStyle.load()
    @State private var showingGridPicker = false
    @State private var isCleanScreen = false // DISP 清屏按键
    @State private var isFullScreen = false  // 全屏展开监看
    @State private var touchFocusPosition: CGPoint? = nil
    @State private var isFocusPulsing = false
    @State private var instantPreviewName: String? = nil
    // v1.0.4：回显浮层的标题/副标题（之前写死“拍摄完成/已安全落盘”，快门本身是假的）
    @State private var previewTitle = "拍摄完成 · 即时预览 (2s)"
    @State private var previewSubtitle = "成片已回传至手机"
    @State private var isCapturing = false
    // v1.0.32：取景页左侧竖向滤镜条选中的预设（nil = 原图，默认）。
    // v1.0.31 是顶部横条，用户 2026-11-22 19:14 截图反馈：横着拍时顶条
    // 挡画面，挪到最左边竖着放，11 组照旧，中文横着写，白芯片、不要黑底条。
    @State private var selectedPreviewPresetID: String? = nil
    // v1.0.34：竖条组内联展开当前展开的组（nil = 全部收起）。
    // 用户 2026-11-22 19:40 纠正：不要两级钻取，点组直接在该组上方
    // 展开组内选项选；芯片背景改磨砂玻璃质感，不用纯白。
    // v1.0.37：展开方式改成横向——组内预设不再插进同一列，改成竖条右侧
    // 紧贴着的第二列；该状态仍是“当前展开哪个组”，一次只展开一组。
    // v1.0.38：第二列改成网格（previewExpandedGrid），一次全显、不滚动；
    // 该状态仍是“当前展开哪个组”，一次只展开一组。v1.0.37 的对齐机
    // 制（RailGroupTopKey + railGroupTops）随第二列一起删了——网格顶
    // 对齐，不用跟被点分组的可见位置对齐。
    @State private var railExpandedGroupTitle: String? = nil
    
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
                }

                // 3b. v1.0.14：参数选择面板（页内底部面板，不走系统 ActionSheet，
                // 永远浮在底栏上面，不会被挡住）。点遮罩或 × 关闭，可连续点多个值。
                if let picker = activeParamPicker, !isCleanScreen {
                    paramPickerPanel(for: picker)
                }

                // v1.0.26：取景网格选择面板——和参数面板同一个做法（页内底部
                // 面板），不走系统 confirmationDialog，那是 iOS 15 才有的，
                // mini 5 的 14.2 用不了。
                if showingGridPicker && !isCleanScreen {
                    gridPickerPanel()
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
            // v1.0.31：离开取景页就清掉预览选择，别让滤镜状态漏到别处。
            streamService.previewPreset = nil
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
                if gridStyle != .none && !isCleanScreen {
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
            // v1.0.26：带位置的 onTapGesture 是 iOS 17 才有的；14 上用
            // 零距离拖拽手势拿点按位置，效果一样（手指抬起时触发）。
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let location = value.location
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
            )
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
            // v1.0.34 整个删了（用户 2026-11-22 19:40 黄圈），连接入口只留在
            // 「控制」页；未连接时取景页就是空画面 + 竖条 + 底栏。
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
            VStack(spacing: 0) {
                // v1.0.34：滤镜竖条贴左边缘、顶到最上方（不要 topSafeInset
                // 的留白），从屏幕顶一直到底栏上面。
                // v1.0.38：展开方式改成网格——点组后组内预设出现在竖条右侧
                // 紧贴着的网格（previewExpandedGrid），一列放不下就多列，
                // 一次全显、不滚动（v1.0.37 的单列 12 个放不下，轻胶片被
                // 截在底栏处还滑不到底）。字顺时针转 90°（跟框一个方向），
                // 横握手机时才横着读；芯片磨砂玻璃质感、容器全透明、不要黑底条。
                // 清屏时竖条和展开网格一起藏起来。未连接的空状态整块删了
                // （同日黄圈），连接入口只留在「控制」页。
                // 底栏挪出 HStack、单独放最下面一行占满宽，快门还在屏幕正中央。
                HStack(alignment: .top, spacing: 0) {
                    if !isCleanScreen {
                        previewFilterRail
                        // 网格可用区：竖条占 42pt，左右各留一点边；高上底栏
                        // 约 90pt，再留 110pt 余量——网格内容一定比这矮（见
                        // previewGridLayout 的验算），不会顶到底栏。
                        previewExpandedGrid(
                            availWidth: geo.size.width - 42 - 16,
                            availHeight: geo.size.height - 200
                        )
                    }
                    // v1.0.36：竖条被 VStack 默认居中顶到了屏幕正中间（v1.0.34
                    // 删空状态时把 HStack 里撑宽的内容一起删了，只剩 42pt 宽的竖条）。
                    // 加 Spacer 把 HStack 撑满宽，竖条贴到最左边缘；顶到最上方不变。
                    Spacer()
                }

                if !isCleanScreen {
                    // v1.0.19：本次拍摄条、滤镜条都不要了。底栏直接贴在 TabBar
                    // 上面一点（之前 96pt 空一大截，快门键离底栏太远）。
                    portraitBottomControlDeck
                        .padding(.horizontal, 16)
                        // 底栏在 VStack 流里，取景页框底就是 TabBar 顶边，
                        // 只留 12pt 间隙，快门键就贴在底栏上方。
                        .padding(.bottom, 12 + max(bottomSafeInset(geo) - 20, 0))
                }
            }
        }
    }
    
    // v1.0.26：iOS 14 没有 GeometryProxy.safeAreaInsets（iOS 15 才有）。
    // 14 上从当前窗口拿；mini 5 有 Home 键，本来就是 0。
    private func bottomSafeInset(_ geo: GeometryProxy) -> CGFloat {
        if #available(iOS 15, *) {
            return geo.safeAreaInsets.bottom
        } else {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            return windowScene?.windows.first?.safeAreaInsets.bottom ?? 0
        }
    }

    // MARK: - v1.0.34：取景页左侧竖向滤镜预览条（组内联展开）
    /// 全部 121 套预设，按机身滤镜 tab 的 11 组顺序排（组顺序不变），
    /// 点芯片时按 id 反查预设用；竖条里显示时按组分（见 previewFilterRail）。
    private var allPreviewPresets: [PictCtrlPreset] {
        PictCtrlPresets.groups.flatMap { $0.presets }
    }

    /// 当前选中的预设所属的组（没选或选了原图时为 nil）；第一级用它标组。
    private var selectedPresetGroupTitle: String? {
        guard let pid = selectedPreviewPresetID else { return nil }
        return PictCtrlPresets.groups.first(where: { group in
            group.presets.contains(where: { $0.id == pid })
        })?.title
    }

    /// v1.0.38：网格展开——竖条本身只显示「原图」+ 11 个组名，点组不再
    /// 往同一列里插预设（v1.0.34–36 的内联展开：插进去的预设把分组顶走，
    /// 位置老不对），也不再是竖条右侧的单列（v1.0.37：单列 12 个放不下，
    /// 通用影调的轻胶片被截在底栏处、滑不到底——列太长超出可视区，滚动
    /// 也够不到底）。组内预设改成竖条右侧紧贴着的网格，一列放不下就
    /// 自动多列（见 previewGridLayout），全部一次全显、没有 ScrollView、
    /// 不用滚；分组列表本身不动、不位移；点一个组就换一个网格，一次只
    /// 展开一组，再点收起。选中态两处都有标记（选中的预设芯片变蓝，它
    /// 所在的组名也变蓝）。容器全透明、没有黑底条；点中哪个，取景画面
    /// 实时套上该滤镜的样子；点「原图」恢复原样。只改手机屏幕显示，
    /// 不写相机、不动原图。
    private var previewFilterRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                previewChip(id: nil, title: "原图")
                ForEach(PictCtrlPresets.groups) { group in
                    railChip(title: group.title, selected: selectedPresetGroupTitle == group.title) {
                        NikonTheme.triggerHaptic(style: .light)
                        let expanding = railExpandedGroupTitle != group.title
                        withAnimation {
                            railExpandedGroupTitle = expanding ? group.title : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 42)
    }

    /// v1.0.38：网格排版（纯函数，好验算）——输入组内预设个数、组内最长
    /// 名字字数、可用宽/高（竖屏坐标），输出列数、芯片统一高、列距、字号。
    /// 芯片统一高：组内最长名 ×（字号 + 1）+ 16 上下留白（12pt 字时就是
    /// 老公式 字数 × 13 + 16；同组芯片等高，网格才齐）。
    /// 算法：字号从 12 往下试（12 → 8）、列距从 42 往下收（42 → 30）——
    /// 先按可用高算一列最多放几行（行高 = 芯片高 + 6 间距），再算需要几列；
    /// 列数 × 列距塞得进可用宽就定下来。最先试到的就是最大字号、最宽列距。
    /// 验算（Tests/test_v138_grid_expand.py）：胶片组 24 个、13 字名在
    /// iPhone 16 Pro Max（440×956，可用 382×673）是 8 列 × 3 行、12pt 字、
    /// 列距 42；390 宽 iPhone 是 8 列 × 3 行、11pt 字、列距 36；mini 5
    /// （768×1024）是 6 列 × 4 行、12pt 字、列距 42——三台机子都不滚动。
    /// 只有 375 宽以下的旧小屏才会一路收到 8pt 字——Yuan 的两台机子走不到那步。
    private struct PreviewGridLayout {
        let columns: Int
        let chipHeight: CGFloat
        let colPitch: CGFloat
        let fontSize: CGFloat
    }

    private func previewGridLayout(
        presetCount: Int, maxNameLength: Int, availWidth: CGFloat, availHeight: CGFloat
    ) -> PreviewGridLayout {
        let spacing: CGFloat = 6
        for fontSize in [12, 11, 10, 9, 8] as [CGFloat] {
            let chipHeight = CGFloat(maxNameLength) * (fontSize + 1) + 16
            let rows = max(1, Int((availHeight + spacing) / (chipHeight + spacing)))
            let columns = (presetCount + rows - 1) / rows
            for colPitch in [42, 36, 34, 30] as [CGFloat] {
                if CGFloat(columns) * colPitch <= availWidth {
                    return PreviewGridLayout(
                        columns: columns, chipHeight: chipHeight,
                        colPitch: colPitch, fontSize: fontSize
                    )
                }
            }
        }
        // 兜底（理论上到不了：上面 8pt 字 + 30 列距已是最小）：按最小规格排，
        // 至少保证不崩；超小屏上网格可能顶出可视区，但不会闪退。
        let chipHeight = CGFloat(maxNameLength) * 9 + 16
        let rows = max(1, Int((availHeight + spacing) / (chipHeight + spacing)))
        return PreviewGridLayout(
            columns: (presetCount + rows - 1) / rows,
            chipHeight: chipHeight, colPitch: 30, fontSize: 8
        )
    }

    /// v1.0.38：横向展开的网格——紧贴在竖条右侧（同一 HStack 里，
    /// alignment .top、spacing 0），只放当前展开那组的预设；按列填
    /// （先填满第一列、再填第二列，跟原来单列从上往下的阅读顺序一致），
    /// 列数、芯片高、列距、字号全由 previewGridLayout 按可用区算出来，
    /// 保证一次全显。没有 ScrollView，换组时 id 变了整个网格重建。
    /// 点预设就应用预览；点预设的芯片样式跟竖条同款（磨砂玻璃、白字）。
    private func previewExpandedGrid(availWidth: CGFloat, availHeight: CGFloat) -> some View {
        Group {
            if let title = railExpandedGroupTitle,
               let group = PictCtrlPresets.groups.first(where: { $0.title == title }) {
                let maxLen = group.presets.map { $0.displayName.count }.max() ?? 1
                let layout = previewGridLayout(
                    presetCount: group.presets.count, maxNameLength: maxLen,
                    availWidth: availWidth, availHeight: availHeight
                )
                let rows = (group.presets.count + layout.columns - 1) / layout.columns
                HStack(alignment: .top, spacing: layout.colPitch - 30) {
                    ForEach(0..<layout.columns, id: \.self) { col in
                        let start = col * rows
                        let end = min(start + rows, group.presets.count)
                        if start < end {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.presets[start..<end]) { preset in
                                    previewChip(
                                        id: preset.id, title: preset.displayName,
                                        height: layout.chipHeight, fontSize: layout.fontSize
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 4)
                .id("preview-grid-\(title)")
            }
        }
    }

    /// 磨砂玻璃背景（UIVisualEffectView 的 SwiftUI 包装，iOS 14 可用；
    /// SwiftUI 的 Material 是 iOS 15 才有的，mini 5 的 14.2 用不了）。
    /// v1.0.34：滤镜芯片的白底改成磨砂玻璃质感。
    private struct FrostedGlassView: UIViewRepresentable {
        var style: UIBlurEffect.Style

        func makeUIView(context: Context) -> UIVisualEffectView {
            UIVisualEffectView(effect: UIBlurEffect(style: style))
        }

        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
            uiView.effect = UIBlurEffect(style: style)
        }
    }

    /// 竖条芯片：磨砂玻璃质感底、白字，选中蓝底白字。字顺时针转 90°（跟取景框
    /// 同一个方向），横握手机时横着读。芯片窄而高：宽 30pt，高随字数走。
    /// v1.0.36：v1.0.34 用的 systemMaterialLight 太不透，看着像纯白底（用户
    /// 2026-11-22 20:04 截图纠正）；改成最透的 systemUltraThinMaterialDark，
    /// 深色取景画面透得出来才是真玻璃；未选中字改白字，不然看不清；再加一圈
    /// 细白描边定住玻璃边缘。选中态在磨砂底上再盖一层半透明蓝，仍是蓝底白字。
    /// v1.0.38：竖条和展开网格共用这一个芯片做法——竖条按名字算高（railChip），
    /// 网格按组内最长名统一高、字号可能收小（previewChip 传 height/fontSize）。
    private func railChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        filterChipButton(
            title: title, height: railChipHeight(for: title), fontSize: 12,
            selected: selected, action: action
        )
    }

    private func filterChipButton(
        title: String, height: CGFloat, fontSize: CGFloat,
        selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .rotationEffect(.degrees(90))
                .foregroundColor(.white)
                .frame(width: 30, height: height)
                .background(
                    ZStack {
                        FrostedGlassView(style: .systemUltraThinMaterialDark)
                        if selected {
                            NikonTheme.accentBlue.opacity(0.8)
                        }
                    }
                )
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        // v1.0.36：点按区域明确成整个芯片矩形（转 90° 的字别把热区带偏）。
        .contentShape(Rectangle())
    }

    /// 芯片高 = 字数 × 13pt + 16pt 上下留白（12pt 字，汉字宽 12pt，留点余量）。
    /// 转 90° 后字的横向长度变成芯片的高度，估小了字会顶出框。
    private func railChipHeight(for title: String) -> CGFloat {
        CGFloat(title.count) * 13 + 16
    }

    /// 点预设芯片应用预览。默认按名字算高、12pt 字（竖条里用）；展开网格
    /// 里用统一高 + 可能收小的字号（previewGridLayout 算出来，见调用处）。
    private func previewChip(
        id: String?, title: String, height: CGFloat? = nil, fontSize: CGFloat = 12
    ) -> some View {
        let selected = selectedPreviewPresetID == id
        return filterChipButton(
            title: title, height: height ?? railChipHeight(for: title),
            fontSize: fontSize, selected: selected
        ) {
            NikonTheme.triggerHaptic(style: .light)
            selectedPreviewPresetID = id
            // id 为 nil（原图）时 flatMap 得到 nil，预览清除。
            streamService.previewPreset = id.flatMap { pid in
                allPreviewPresets.first(where: { $0.id == pid })
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
                                showingGridPicker = true
                            }) {
                                Image(systemName: gridStyle == .none ? "grid.circle" : "grid")
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
    
    // MARK: - 底部操作行 (清屏 DISP + 全屏大快门，v1.0.19：AF-ON 不要了)
    private var portraitBottomControlDeck: some View {
        // v1.0.24：快门严格居中——三组等宽（左 DISP+满屏 / 中快门 / 右网格+增强），
        // 快门落在屏幕正中央。之前是 Spacer 两边夹，快门被右边两个键顶偏。
        // 满屏/完整切换从顶部挪到这里，功能没删。
        HStack(spacing: 0) {
            // 左组：DISP 清屏 + 满屏/完整切换（靠左）
            HStack(spacing: 12) {
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

                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    withAnimation(.easeInOut(duration: 0.2)) { isFillScreen.toggle() }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: isFillScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 16))
                        Text(isFillScreen ? "满屏" : "完整")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中：主快门按钮（严格居中）
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
            .frame(maxWidth: .infinity, alignment: .center)

            // 右组：网格、增强（靠右）
            HStack(spacing: 12) {
                // 辅助网格切换
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    showingGridPicker = true
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: gridStyle == .none ? "grid.circle" : "grid")
                            .font(.system(size: 16))
                        Text(gridStyle == .none ? "关" : "网格")
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
            .frame(maxWidth: .infinity, alignment: .trailing)
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
            // v1.0.25：按所选样式画线
            GridStyle.path(for: gridStyle, in: geo.size)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
        }
    }
    
    // MARK: - USB-C 有线连接排查指引弹窗 (极度关键：帮助用户解决无法线连相机的困惑)
    
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

    // MARK: - 取景网格选择面板（v1.0.26：页内底部面板，iOS 14 也能用）
    private func gridPickerPanel() -> some View {
        VStack(spacing: 0) {
            // 遮罩：点空白处关闭
            Color.black.opacity(0.35)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { showingGridPicker = false }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("取景网格")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) { showingGridPicker = false }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                // 8 个选项：无网格 + 7 种网格，点一个立即生效并关闭
                ForEach(GridStyle.allCases, id: \.self) { style in
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        gridStyle = style
                        style.save()
                        withAnimation(.easeInOut(duration: 0.15)) { showingGridPicker = false }
                    }) {
                        HStack {
                            Text(style.displayName)
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            if style == gridStyle {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundColor(style == gridStyle ? .black : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(style == gridStyle ? NikonTheme.accentBlue : Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
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

