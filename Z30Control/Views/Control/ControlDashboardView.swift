//
//  ControlDashboardView.swift
//  Z30Control
//
//  相机全参数中控仪表盘 (九宫格硬件调控、机身状态、优化校准与 AF-ON)
//

import SwiftUI

public struct ControlDashboardView: View {
    @ObservedObject var cameraState: CameraState
    @State private var showingPictureControlPicker = false
    @State private var showingConnectionWizard = false
    
    public init(cameraState: CameraState) {
        self.cameraState = cameraState
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 1. 顶部硬件身份卡片 (机身、固件、卡容量)
                hardwareInfoSection
                
                // 2. 核心参数九宫格矩阵 (对齐截图排版)
                parameterGridSection
                
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            dashboardBottomBar
        }
        .sheet(isPresented: $showingConnectionWizard) {
            ConnectionWizardView()
        }
        .actionSheet(isPresented: $showingPictureControlPicker) {
            ActionSheet(
                title: Text("切换相机机内【优化校准】(Picture Control)"),
                message: Text("通过 PTP 协议直接下发给 Z30 机身硬件"),
                buttons: PictureControlMode.allCases.map { mode in
                    .default(Text(mode.rawValue)) {
                        NikonTheme.triggerHaptic(style: .selection)
                        cameraState.pictureControl = mode
                    }
                } + [.cancel(Text("取消"))]
            )
        }
    }
    
    // MARK: - 硬件身份与存储卡卡片
    private var hardwareInfoSection: some View {
        VStack(spacing: 8) {
            // 机身与镜头行
            HStack(spacing: 8) {
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    showingConnectionWizard = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundColor(NikonTheme.nikonYellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cameraState.modelName)
                                .proHUDText(size: 13, weight: .bold)
                                .foregroundColor(Color.primary)
                            Text("\(cameraState.firmwareVersion) · \(cameraState.serialNumber)")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                
                HStack {
                    Image(systemName: "camera.aperture")
                        .foregroundColor(.gray)
                    Text("16-50mm VR")
                        .proHUDText(size: 12, weight: .semibold)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }
            
            // SD 卡容量指示条与格式
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SD")
                            .proHUDText(size: 10, weight: .bold)
                            .foregroundColor(NikonTheme.nikonYellow)
                        Spacer()
                        Text("\(String(format: "%.1f", cameraState.cardUsedGB))/\(Int(cameraState.cardTotalGB))GB · \(cameraState.cardUsagePercent)%")
                            .proHUDText(size: 10)
                            .foregroundColor(.gray)
                    }
                    ProgressView(value: cameraState.cardUsedGB, total: cameraState.cardTotalGB)
                        .tint(NikonTheme.nikonYellow)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(cameraState.resolution)
                        .proHUDText(size: 11, weight: .bold)
                    Text(cameraState.imageQuality)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - 参数九宫格矩阵
    private var parameterGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            dashboardCard(title: "快门", value: cameraState.shutterSpeed, icon: "timer")
            dashboardCard(title: "光圈", value: cameraState.aperture, icon: "camera.aperture")
            dashboardCard(title: "ISO", value: cameraState.isoActual, subtitle: "基础 \(cameraState.isoBase)", icon: "sun.max")
            
            dashboardCard(title: "拍摄模式", value: cameraState.exposureMode.rawValue.prefix(1).description, icon: "dial.min")
            dashboardCard(title: "白平衡", value: cameraState.whiteBalance.rawValue, icon: "drop.fill")
            dashboardCard(title: "测光", value: cameraState.meteringMode.rawValue, icon: "viewfinder")
            
            dashboardCard(title: "± EV", value: cameraState.exposureCompensation, icon: "plusminus")
            dashboardCard(title: "对焦", value: cameraState.focusMode.rawValue, icon: "scope")
            dashboardCard(title: "AF 区域", value: cameraState.afAreaMode, icon: "square.dashed")
            
            dashboardCard(title: "色调模式", value: "SDR", icon: "circle.lefthalf.filled")
            
            // 优化校准卡片 (点击切换)
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
                showingPictureControlPicker = true
            }) {
                dashboardCard(title: "优化校准", value: cameraState.pictureControl.rawValue.components(separatedBy: " ").first ?? "标准", icon: "paintpalette.fill", isActionable: true)
            }
            
            dashboardCard(title: "防抖减震", value: "开 (Normal)", icon: "hand.raised.fill")
        }
    }
    
    // MARK: - 单个指标卡片 (左侧带尼康黄标条)
    private func dashboardCard(title: String, value: String, subtitle: String? = nil, icon: String, isActionable: Bool = false) -> some View {
        HStack(spacing: 0) {
            // 尼康黄垂直状态标
            Rectangle()
                .fill(NikonTheme.nikonYellow)
                .frame(width: 3.5)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                    if isActionable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(NikonTheme.nikonYellow)
                    }
                }
                
                Text(value)
                    .proHUDText(size: 13, weight: .bold)
                    .foregroundColor(Color.primary)
                    .lineLimit(1)
                
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .frame(height: 64)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    // MARK: - 底部控制底座 (含独立 AF-ON 键)
    private var dashboardBottomBar: some View {
        HStack(spacing: 24) {
            Button(action: {}) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primary)
            }
            
            // 独立 AF-ON 对焦按钮 (长按/轻点)
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
            }) {
                Text("AF-ON")
                    .proHUDText(size: 12, weight: .bold)
                    .frame(width: 64, height: 34)
                    .background(Color(UIColor.tertiarySystemFill))
                    .foregroundColor(Color.primary)
                    .cornerRadius(17)
            }
            
            // 黄色快门环
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
            }) {
                ZStack {
                    Circle()
                        .stroke(NikonTheme.nikonYellow, lineWidth: 3.5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 42, height: 42)
                }
            }
            
            // 拍照/录像切换
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
            }) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(.ultraThinMaterial)
    }
}
