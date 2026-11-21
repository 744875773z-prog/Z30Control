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
                    
                    // 4. 局域网发现与手动 IP（仅路由器局域网模式）
                    if connectionService.transportMode == .wifiLocal {
                        lanDiscoverySection
                    }
                    
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
                } else if connectionService.transportMode == .wifiLocal {
                    guideStepRow(step: "2", text: "相机 MENU ➔【网络】➔【连接到智能设备】➔【Wi-Fi 连接（STA 模式）】➔ 创建配置文件，搜宿舍路由器连上（和手机同一个 Wi-Fi）。注意：不要用【连接到电脑】，那是传图给尼康电脑软件用的，第三方 App 连不上。")
                    guideStepRow(step: "3", text: "首次连接时相机屏幕会问是否允许，在相机上按 OK；然后点下方“重新扫描”找相机，扫不到就手动输 IP。")
                } else {
                    guideStepRow(step: "2", text: "相机 MENU ➔【网络】➔【连接到智能设备】➔【Wi-Fi 连接（AP 模式）】➔【建立 Wi-Fi 连接】，记下相机显示的 SSID 和密码。")
                    guideStepRow(step: "3", text: "手机 Wi-Fi 加入那个以 Z_30_ 开头的热点；首次连接时在相机上按 OK 确认。")
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
    
    // MARK: - 局域网发现与手动 IP（仅路由器局域网模式）
    private var lanDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("局域网相机")
                .proHUDText(size: 13, weight: .bold)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 10) {
                if connectionService.isSearchingLAN {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在扫描局域网…")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                } else if connectionService.discoveredCameras.isEmpty {
                    Text("还没找到相机。确认相机已连上同一 Wi-Fi 后点“重新扫描”，或直接手动输入 IP。")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                } else {
                    ForEach(connectionService.discoveredCameras, id: \.self) { ip in
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .heavy)
                            connectionService.targetIP = ip
                            connectionService.startConnecting()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(NikonTheme.nikonYellow)
                                Text(ip)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primary)
                                Spacer()
                                Text("连接")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(NikonTheme.nikonYellow)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Divider()

                // 手动输入 IP
                HStack(spacing: 8) {
                    TextField("相机 IP，例如 192.168.1.100", text: $connectionService.manualIP)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.systemGroupedBackground))
                        .cornerRadius(8)
                    Button("连接") {
                        NikonTheme.triggerHaptic(style: .heavy)
                        if connectionService.connectToManualIP(connectionService.manualIP) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NikonTheme.nikonYellow)
                    .cornerRadius(8)
                }

                Text(connectionService.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
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
