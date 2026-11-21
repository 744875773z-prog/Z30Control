//
//  ControlDashboardView.swift
//  Z30Control
//
//  相机全参数中控仪表盘 (修复白底白字与重叠遮挡，专业高对比度暗黑影控设计)
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
    
    // 专业高对比暗黑影控调色盘
    private let pageBgColor = NikonTheme.pitchBlack
    private let cardBgColor = NikonTheme.surfaceDark
    private let borderStroke = Color.white.opacity(0.12)
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // 1. 顶部 Navigation 栏
                headerNavigationBar
                    .padding(.top, 48) // 适配灵动岛安全区
                
                // 2. 状态条 (绿点“就绪”、电量、WiFi 药丸)
                statusBannerSection
                
                // 3. 硬件身份与镜头信息卡片
                hardwareCardsSection
                
                // 4. 存储卡进度与画质格式卡片
                storageAndFormatSection
                
                // 5. 标签筛选栏 (全部 / 编辑)
                tagFilterSection
                
                // 6. 核心参数网格矩阵
                parameterGridSection
                
                // 7. 底部控制台 (内置在滚动流末端，绝不发生悬浮重叠遮挡！)
                bottomConsoleSection
                    .padding(.top, 8)
                
                Spacer(minLength: 100) // 预留底部悬浮 TabBar 空间
            }
            .padding(.horizontal, 16)
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("中控仪表盘")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            HStack(spacing: 10) {
                // 点击一键切换到实时取景监看
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    onSwitchToLiveView?()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "viewfinder")
                        Text("监看")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NikonTheme.nikonYellow)
                    .cornerRadius(14)
                }
            }
        }
    }
    
    // MARK: - 2. 状态条 (绿点“就绪”、电量、WiFi 药丸)
    private var statusBannerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(cameraState.isConnected ? NikonTheme.readyGreen : Color.orange)
                    .frame(width: 8, height: 8)
                Text(cameraState.isConnected ? "机身在线" : "未连相机")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Image(systemName: "battery.75")
                    .font(.system(size: 13))
                    .foregroundColor(NikonTheme.readyGreen)
                Text("\(cameraState.batteryPercentage)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // WiFi 状态药丸
            HStack(spacing: 4) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 10, weight: .bold))
                Text(cameraState.isConnected ? "USB-C 有线" : "待插线")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(cameraState.isConnected ? NikonTheme.readyGreen : NikonTheme.nikonYellow)
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
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16))
                        .foregroundColor(NikonTheme.nikonYellow)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cameraState.modelName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(cameraState.firmwareVersion) · \(cameraState.serialNumber)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .background(cardBgColor)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderStroke, lineWidth: 0.8))
            }
            
            // 镜头卡片
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                Text("Z 16-50mm VR")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderStroke, lineWidth: 0.8))
        }
    }
    
    // MARK: - 4. 存储与画质卡片
    private var storageAndFormatSection: some View {
        HStack(spacing: 10) {
            // 存储卡容量指示
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("SD 卡")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NikonTheme.nikonYellow)
                    Spacer()
                    Text("\(String(format: "%.0f", cameraState.cardUsedGB))/\(Int(cameraState.cardTotalGB))GB · \(cameraState.cardUsagePercent)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                ProgressView(value: cameraState.cardUsedGB, total: cameraState.cardTotalGB)
                    .tint(NikonTheme.nikonYellow)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderStroke, lineWidth: 0.8))
            
            // 图像画质与分辨率卡片
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 16))
                    .foregroundColor(NikonTheme.nikonYellow)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(cameraState.resolution)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("RAW+JPEG/HEIF")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 58)
            .background(cardBgColor)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderStroke, lineWidth: 0.8))
        }
    }
    
    // MARK: - 5. 标签筛选条
    private var tagFilterSection: some View {
        HStack(spacing: 8) {
            tagFilterButton(title: "全部参数", icon: "square.grid.2x2", tag: 0)
            tagFilterButton(title: "常用编辑", icon: "slider.horizontal.3", tag: 1)
            Spacer()
        }
        .padding(.top, 2)
    }
    
    private func tagFilterButton(title: String, icon: String, tag: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title).font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(selectedFilterTag == tag ? .black : .gray)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(selectedFilterTag == tag ? NikonTheme.nikonYellow : Color.white.opacity(0.08))
        .cornerRadius(12)
        .onTapGesture {
            NikonTheme.triggerHaptic(style: .light)
            selectedFilterTag = tag
        }
    }
    
    // MARK: - 6. 参数矩阵 (3列高对比黑金圆角卡片)
    private var parameterGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            gridCard(icon: "timer", title: "快门", value: cameraState.shutterSpeed, hasIndicator: true)
            gridCard(icon: "camera.aperture", title: "光圈", value: cameraState.aperture, hasIndicator: true)
            isoGridCard
            
            gridCard(icon: "dial.min", title: "拍摄模式", value: cameraState.exposureMode.rawValue.prefix(4).description, hasIndicator: true)
            gridCard(icon: "drop.fill", title: "白平衡", value: cameraState.whiteBalance.rawValue.components(separatedBy: " ").first ?? "自动", hasIndicator: true)
            gridCard(icon: "viewfinder", title: "测光", value: cameraState.meteringMode.rawValue, hasIndicator: false)
            
            gridCard(icon: "plusminus", title: "± EV", value: cameraState.exposureCompensation, hasIndicator: true)
            gridCard(icon: "scope", title: "对焦", value: cameraState.focusMode.rawValue, hasIndicator: true)
            gridCard(icon: "square.dashed", title: "AF 区域", value: cameraState.afAreaMode, hasIndicator: true)
            
            gridCard(icon: "circle.grid.2x2", title: "镜头", value: "16-50mm", hasIndicator: false)
            gridCard(icon: "circle.lefthalf.filled", title: "色调模式", value: "SDR", hasIndicator: true)
            pictureControlGridCard
        }
    }
    
    private func gridCard(icon: String, title: String, value: String, hasIndicator: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(10)
            
            Spacer(minLength: 0)
            
            if hasIndicator {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(NikonTheme.nikonYellow)
                    .frame(width: 3, height: 16)
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 64)
        .background(cardBgColor)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderStroke, lineWidth: 0.8))
    }
    
    private var isoGridCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text("ISO")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("A")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 14, height: 14)
                        .background(NikonTheme.nikonYellow)
                        .clipShape(Circle())
                }
                Spacer(minLength: 0)
                Text(cameraState.isoActual)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(10)
        }
        .frame(height: 64)
        .background(cardBgColor)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderStroke, lineWidth: 0.8))
    }
    
    private var pictureControlGridCard: some View {
        Button(action: {
            NikonTheme.triggerHaptic(style: .medium)
            showingPictureControlPicker = true
        }) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
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
                            .foregroundColor(NikonTheme.nikonYellow)
                    }
                    Spacer(minLength: 0)
                    Text(cameraState.pictureControl.rawValue.components(separatedBy: " ").first ?? "标准")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(10)
            }
            .frame(height: 64)
            .background(cardBgColor)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderStroke, lineWidth: 0.8))
        }
    }
    
    // MARK: - 7. 嵌入式底部控制台 (位于文档流底部，绝不悬浮重叠遮挡)
    private var bottomConsoleSection: some View {
        HStack(spacing: 20) {
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
            }) {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
            }) {
                Text("AF-ON")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(NikonTheme.nikonYellow)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.nikonYellow.opacity(0.6), lineWidth: 1.5))
            }
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
                cameraState.remainingShots = max(0, cameraState.remainingShots - 1)
            }) {
                ZStack {
                    Circle()
                        .stroke(NikonTheme.nikonYellow, lineWidth: 4)
                        .frame(width: 58, height: 58)
                        .shadow(color: NikonTheme.nikonYellow.opacity(0.5), radius: 6, x: 0, y: 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                }
            }
            
            Spacer()
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
            }) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(cardBgColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderStroke, lineWidth: 0.8))
    }
}
