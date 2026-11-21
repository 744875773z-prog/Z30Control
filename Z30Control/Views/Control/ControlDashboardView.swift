//
//  ControlDashboardView.swift
//  Z30Control
//
//  相机全参数中控仪表盘 (像素级对齐专业控制台参考图)
//

import SwiftUI

public struct ControlDashboardView: View {
    @ObservedObject var cameraState: CameraState
    var onSwitchToLiveView: (() -> Void)? = nil
    
    @State private var showingPictureControlPicker = false
    @State private var showingConnectionWizard = false
    @State private var selectedFilterTag = 0 // 0: 全部, 1: 编辑
    
    public init(cameraState: CameraState, onSwitchToLiveView: (() -> Void)? = nil) {
        self.cameraState = cameraState
        self.onSwitchToLiveView = onSwitchToLiveView
    }
    
    // 柔和优雅的米白/淡暖灰背景 (对齐原图 #F7F6F2)
    private let pageBgColor = Color(red: 0.965, green: 0.957, blue: 0.945)
    private let cardBgColor = Color.white
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部 Header 栏 (汉堡菜单、标题、对焦框取景切换、更多)
            headerNavigationBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            
            // 2. 状态条 (绿点“就绪”、电量、WiFi 折叠药丸)
            statusBannerSection
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            // 3. 可滚动内容区域
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // 硬件身份与镜头信息卡片
                    hardwareCardsSection
                    
                    // 存储卡进度与画质格式卡片
                    storageAndFormatSection
                    
                    // 标签筛选栏 (全部 / 编辑)
                    tagFilterSection
                    
                    // 核心参数多宫格网格矩阵
                    parameterGridSection
                    
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 14)
            }
            
            // 4. 底部悬浮控制台 (照片回放、AF-ON、金色快门环、连拍模式)
            floatingBottomConsole
                .padding(.horizontal, 16)
                .padding(.bottom, 78) // 预留悬浮 TabBar 空间
        }
        .background(pageBgColor.ignoresSafeArea())
        .sheet(isPresented: $showingConnectionWizard) {
            ConnectionWizardView()
        }
        .actionSheet(isPresented: $showingPictureControlPicker) {
            ActionSheet(
                title: Text("切换相机机内【优化校准】(Picture Control)"),
                message: Text("通过 PTP/IP 协议实时下发给 Z30 机身硬件"),
                buttons: PictureControlMode.allCases.map { mode in
                    .default(Text(mode.rawValue)) {
                        NikonTheme.triggerHaptic(style: .light)
                        cameraState.pictureControl = mode
                    }
                } + [.cancel(Text("取消"))]
            )
        }
    }
    
    // MARK: - 1. 顶部 Navigation 栏
    private var headerNavigationBar: some View {
        HStack {
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                showingConnectionWizard = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("控制")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.primary)
            
            Spacer()
            
            HStack(spacing: 12) {
                // 点击一键切换到“取景监看”模式
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    onSwitchToLiveView?()
                }) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Circle())
                }
                
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // MARK: - 2. 状态条 (绿点“就绪”、电量、WiFi 药丸)
    private var statusBannerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(NikonTheme.readyGreen)
                    .frame(width: 7, height: 7)
                Text(cameraState.isConnected ? "就绪" : "待连接")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.primary)
                Image(systemName: "battery.75")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // WiFi 状态药丸
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 10, weight: .bold))
                Text("Wi-Fi --")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(Color(red: 0.88, green: 0.58, blue: 0.2))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 1.0, green: 0.94, blue: 0.88))
            .cornerRadius(12)
        }
    }
    
    // MARK: - 3. 硬件与镜头卡片
    private var hardwareCardsSection: some View {
        HStack(spacing: 10) {
            // 机身卡片
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                showingConnectionWizard = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Text(cameraState.modelName.replacingOccurrences(of: "NIKON ", with: ""))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(cameraState.firmwareVersion)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                        Text(cameraState.serialNumber)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .background(cardBgColor)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
            }
            
            // 镜头卡片
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text("Z 16-50mm f/3.5-6.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
        }
    }
    
    // MARK: - 4. 存储与画质卡片
    private var storageAndFormatSection: some View {
        HStack(spacing: 10) {
            // 存储卡容量指示 (双插槽或单插槽)
            VStack(alignment: .leading, spacing: 6) {
                // CFe 模拟槽或 SD 槽
                VStack(spacing: 3) {
                    HStack {
                        Text("CFe")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.3))
                            .cornerRadius(3)
                            .foregroundColor(.orange)
                        
                        Spacer()
                        Text("748/1024GB · 73%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    ProgressView(value: 748, total: 1024)
                        .tint(Color(red: 0.95, green: 0.75, blue: 0.1))
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
                
                // SD 槽
                VStack(spacing: 3) {
                    HStack {
                        Text("SD")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.3))
                            .cornerRadius(3)
                            .foregroundColor(.orange)
                        
                        Spacer()
                        Text("\(String(format: "%.0f", cameraState.cardUsedGB))/\(Int(cameraState.cardTotalGB))GB · \(cameraState.cardUsagePercent)%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    ProgressView(value: cameraState.cardUsedGB, total: cameraState.cardTotalGB)
                        .tint(Color(red: 0.95, green: 0.75, blue: 0.1))
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
            
            // 图像画质与分辨率卡片
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(Color.orange.opacity(0.8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("5568x3712")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.primary)
                    Text("RAW+JPEG/HEIF (基本)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 64)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
        }
    }
    
    // MARK: - 5. 标签筛选条 (全部 / 编辑)
    private var tagFilterSection: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                Text("全部")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(selectedFilterTag == 0 ? Color.primary : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(selectedFilterTag == 0 ? Color.black.opacity(0.08) : Color.clear)
            .cornerRadius(14)
            .onTapGesture {
                NikonTheme.triggerHaptic(style: .light)
                selectedFilterTag = 0
            }
            
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                Text("编辑")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(selectedFilterTag == 1 ? Color.primary : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(selectedFilterTag == 1 ? Color.black.opacity(0.08) : Color.clear)
            .cornerRadius(14)
            .onTapGesture {
                NikonTheme.triggerHaptic(style: .light)
                selectedFilterTag = 1
            }
            
            Spacer()
        }
        .padding(.top, 4)
    }
    
    // MARK: - 6. 参数矩阵 (3列圆角卡片)
    private var parameterGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // 第 1 行：核心三要素
            standardGridCard(icon: "timer", title: "快门", value: cameraState.shutterSpeed, hasIndicator: true)
            standardGridCard(icon: "camera.aperture", title: "光圈", value: cameraState.aperture, hasIndicator: true)
            isoGridCard
            
            // 第 2 行：拍摄、白平衡、测光
            standardGridCard(icon: "dial.min", title: "拍摄模式", value: cameraState.exposureMode.rawValue.prefix(4).description, hasIndicator: true)
            standardGridCard(icon: "drop.fill", title: "白平衡", value: cameraState.whiteBalance.rawValue.components(separatedBy: " ").first ?? "自动", hasIndicator: true)
            standardGridCard(icon: "viewfinder", title: "测光", value: cameraState.meteringMode.rawValue, hasIndicator: false)
            
            // 第 3 行：曝光补偿、对焦、区域
            standardGridCard(icon: "plusminus", title: "± EV", value: cameraState.exposureCompensation, hasIndicator: true)
            standardGridCard(icon: "scope", title: "对焦", value: cameraState.focusMode.rawValue, hasIndicator: true)
            standardGridCard(icon: "square.dashed", title: "AF 区域", value: cameraState.afAreaMode, hasIndicator: true)
            
            // 第 4 行：镜头、色调模式、优化校准
            standardGridCard(icon: "circle.grid.2x2", title: "镜头 ID", value: "Z 16-50mm\nf/3.5-6.3", hasIndicator: false)
            standardGridCard(icon: "circle.lefthalf.filled", title: "色调模式", value: "SDR", hasIndicator: true)
            pictureControlGridCard
            
            // 第 5 行：减震
            standardGridCard(icon: "waveform.path", title: "减震", value: "开 (Normal)", hasIndicator: false)
        }
    }
    
    // MARK: - 通用多宫格卡片 (右边缘黄色指示条)
    private func standardGridCard(icon: String, title: String, value: String, hasIndicator: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // 顶部小图标与名称
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer(minLength: 0)
                
                // 大字主数值
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            
            Spacer(minLength: 0)
            
            // 右边缘黄色可调微指示条
            if hasIndicator {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(red: 0.95, green: 0.75, blue: 0.15))
                    .frame(width: 3, height: 16)
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 72)
        .background(cardBgColor)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
    }
    
    // ISO 专属卡片 (带自动 A 标与双层数值)
    private var isoGridCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text("ISO")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                    // 黄色圆圈 A 标记
                    Text("A")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 14, height: 14)
                        .background(Color(red: 0.95, green: 0.75, blue: 0.15))
                        .clipShape(Circle())
                }
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("基础 \(cameraState.isoBase)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                    Text("实际 \(cameraState.isoActual)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.primary)
                }
            }
            .padding(10)
        }
        .frame(height: 72)
        .background(cardBgColor)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
    }
    
    // 优化校准专属卡片 (点击调出选择器，带 i 图标)
    private var pictureControlGridCard: some View {
        Button(action: {
            NikonTheme.triggerHaptic(style: .medium)
            showingPictureControlPicker = true
        }) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text("优化校准")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))
                    }
                    
                    Spacer(minLength: 0)
                    
                    Text(cameraState.pictureControl.rawValue.components(separatedBy: " ").first ?? "标准")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.primary)
                }
                .padding(10)
            }
            .frame(height: 72)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.04), lineWidth: 0.5))
        }
    }
    
    // MARK: - 7. 悬浮底座 (回放、AF-ON、金色光环快门、连拍模式)
    private var floatingBottomConsole: some View {
        HStack(spacing: 20) {
            // 照片回放
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
            }) {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
            
            // AF-ON 胶囊对焦按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
            }) {
                Text("AF-ON")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.07))
                    .cornerRadius(16)
            }
            
            // 金色光环大快门按键
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
            }) {
                ZStack {
                    // 外层金色光环
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.88, blue: 0.2),
                                    Color(red: 0.95, green: 0.72, blue: 0.1),
                                    Color(red: 1.0, green: 0.9, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.yellow.opacity(0.3), radius: 6, x: 0, y: 0)
                    
                    // 内层白色按键
                    Circle()
                        .fill(Color.white)
                        .frame(width: 46, height: 46)
                        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                }
            }
            
            Spacer()
            
            // 拍摄 / 连拍切换
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
            }) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 10)
    }
}
