//
//  ConnectionWizardView.swift
//  Z30Control
//
//  连接新相机可视化引导向导 (对齐截图 2 工业级设计)
//

import SwiftUI

public struct ConnectionWizardView: View {
    @ObservedObject var connectionService = CameraConnectionService.shared
    @Environment(\.presentationMode) var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. 相机机型选择板块
                    cameraModelSection
                    
                    // 2. 连接通道单选板块 (USB-C / Wi-Fi / 相机热点)
                    transportModeSection
                    
                    // 3. 步骤连接指导卡片
                    connectionGuideSection
                    
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("连接新相机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color.primary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomConnectBar
            }
        }
    }
    
    // MARK: - 相机机型板块
    private var cameraModelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("相机")
                .proHUDText(size: 13, weight: .bold)
                .foregroundColor(.gray)
            
            HStack {
                Text("Z 机型")
                    .proHUDText(size: 14, weight: .semibold)
                Spacer()
                Menu {
                    Button("Z 30 (当前设备)") { connectionService.selectedModel = "Z 30" }
                    Button("Z 50 II") { connectionService.selectedModel = "Z 50 II" }
                    Button("Z fc") { connectionService.selectedModel = "Z fc" }
                    Button("Z 8") { connectionService.selectedModel = "Z 8" }
                } label: {
                    HStack(spacing: 4) {
                        Text(connectionService.selectedModel)
                            .proHUDText(size: 14, weight: .bold)
                            .foregroundColor(NikonTheme.nikonYellow)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11))
                            .foregroundColor(NikonTheme.nikonYellow)
                    }
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
            
            Text("连接选项将根据所选相机机型自动调整。")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - 连接模式单选
    private var transportModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连接通道")
                .proHUDText(size: 13, weight: .bold)
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                modeOptionRow(
                    mode: .usbC,
                    title: "USB-C",
                    icon: "cable.connector",
                    isSelected: connectionService.transportMode == .usbC
                )
                
                modeOptionRow(
                    mode: .wifiLocal,
                    title: "Wi-Fi 或手机热点",
                    icon: "wifi",
                    isSelected: connectionService.transportMode == .wifiLocal
                )
                
                modeOptionRow(
                    mode: .cameraAP,
                    title: "相机热点 (推荐模式)",
                    icon: "antenna.radiowaves.left.and.right",
                    isSelected: connectionService.transportMode == .cameraAP
                )
            }
        }
    }
    
    private func modeOptionRow(mode: ConnectionTransportMode, title: String, icon: String, isSelected: Bool) -> some View {
        Button(action: {
            NikonTheme.triggerHaptic(style: .light)
            connectionService.setTransportMode(mode)
        }) {
            HStack(spacing: 12) {
                // 左侧尼康黄竖标条 (对齐截图 2)
                if isSelected {
                    Rectangle()
                        .fill(NikonTheme.nikonYellow)
                        .frame(width: 3.5, height: 20)
                        .cornerRadius(1.75)
                }
                
                Image(systemName: icon)
                    .foregroundColor(isSelected ? NikonTheme.nikonYellow : .gray)
                    .frame(width: 24)
                
                Text(title)
                    .proHUDText(size: 13, weight: isSelected ? .bold : .medium)
                    .foregroundColor(Color.primary)
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? NikonTheme.nikonYellow : Color.gray.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(NikonTheme.nikonYellow)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 步骤连接指导卡片 (对齐截图 2 序号标)
    private var connectionGuideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连接指导")
                .proHUDText(size: 13, weight: .bold)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 12) {
                guideStepRow(step: "1", text: "开启 Z30 相机电源。")
                
                if connectionService.transportMode == .usbC {
                    guideStepRow(step: "2", text: "使用 USB-C 数据线将 iPhone 与相机直接连接。")
                    guideStepRow(step: "3", text: "确认相机中的【USB 数据连接】设为“MTP/PTP”。")
                } else {
                    guideStepRow(step: "2", text: "按相机 MENU 键 ➔【连接至智能设备】➔ 开启【Wi-Fi 连接】。")
                    guideStepRow(step: "3", text: "在手机 Wi-Fi 列表中加入以“Z30_”开头的热点网络。")
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
    
    private func guideStepRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.gray.opacity(0.6))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - 底部操作栏 (对齐截图 2 大黄色胶囊按钮)
    private var bottomConnectBar: some View {
        VStack(spacing: 8) {
            // 设备就绪提示
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(NikonTheme.readyGreen)
                        .frame(width: 6, height: 6)
                    Text("\(connectionService.selectedModel) (\(connectionService.targetIP):15740)")
                        .proHUDText(size: 11, weight: .bold)
                }
                Spacer()
                Button("重新扫描") {
                    NikonTheme.triggerHaptic(style: .light)
                    connectionService.discoverCamerasInLAN()
                }
                .font(.system(size: 11))
                .foregroundColor(NikonTheme.nikonYellow)
            }
            .padding(.horizontal, 16)
            
            // 主连接按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
                connectionService.startConnecting()
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("开始连接")
                        .proHUDText(size: 15, weight: .bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(NikonTheme.nikonYellow)
                .foregroundColor(.black)
                .cornerRadius(25)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
