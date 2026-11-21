//
//  ControlDashboardView.swift
//  Z30Control
//
//  控制主页面 (1:1 像素级完整对齐网页版 Clean Blue-White Studio Edition)
//

import SwiftUI

public struct ControlDashboardView: View {
    @ObservedObject var cameraState: CameraState
    @ObservedObject var connectionService = CameraConnectionService.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    
    @State private var isPulsing = false
    @State private var showingModelMenu = false
    @State private var showingWiredHelp = false
    
    public init(cameraState: CameraState, onSwitchToLiveView: (() -> Void)? = nil) {
        self.cameraState = cameraState
    }
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. 顶部 Navigation 栏 (对齐网页版 .nav-bar)
                navBarSection
                    .padding(.top, 8)
                
                // 2. 提示信息横条 (对齐网页版 .search-info-strip)
                searchInfoStripSection
                
                // 3. 相机设备卡片 (对齐网页版 .camera-card)
                cameraDeviceCardSection
                
                // 4. 核心蓝色检测大按钮 (对齐网页版 科技蔚蓝按钮)
                startDetectButtonSection
                
                // 5. 连接成功后：展示用户要求的机身内存与电量卡片
                if cameraState.isConnected {
                    hardwareStorageAndBatteryCards
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer(minLength: 110) // 预留底部导航栏
            }
            .padding(.horizontal, 18)
        }
        .background(NikonTheme.bgPure.ignoresSafeArea())
        .onAppear {
            permissionManager.requestAllRequiredPermissions()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .sheet(isPresented: $showingWiredHelp) {
            wiredGuideSheet
        }
    }
    
    // MARK: - 1. 顶部标题栏 (.nav-bar)
    private var navBarSection: some View {
        HStack(alignment: .center) {
            Text("控制")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(NikonTheme.textPrimary)
            
            Spacer()
            
            // 机型选择下拉胶囊 (.nav-model-pill)
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                showingModelMenu = true
            }) {
                HStack(spacing: 4) {
                    Text(connectionService.selectedModel)
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(NikonTheme.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(NikonTheme.accentBlueLight)
                .cornerRadius(14)
            }
            .actionSheet(isPresented: $showingModelMenu) {
                ActionSheet(
                    title: Text("选择相机型号"),
                    buttons: ["Nikon Z 30", "Nikon Z 50", "Nikon Z fc", "Nikon Z 5", "Nikon Z 6 / Z 7", "Nikon Z 8 / Z 9"].map { model in
                        .default(Text(model)) {
                            connectionService.selectedModel = model
                            cameraState.modelName = model
                        }
                    } + [.cancel(Text("取消"))]
                )
            }
            
            // 右侧刷新小方块按钮
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                connectionService.autoDetectAndConnect()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(NikonTheme.accentBlue)
                    .cornerRadius(8)
                    .shadow(color: NikonTheme.accentBlue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - 2. 提示信息横条 (.search-info-strip)
    private var searchInfoStripSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraState.isConnected ? NikonTheme.readyGreen : NikonTheme.accentBlue)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.25 : 0.85)
                .shadow(color: (cameraState.isConnected ? NikonTheme.readyGreen : NikonTheme.accentBlue).opacity(0.6), radius: 4)
            
            Text(connectionService.statusMessage.isEmpty ? "正在通过 USB 与无线通道就绪..." : connectionService.statusMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(NikonTheme.textSecondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(NikonTheme.bgSubtle)
        .cornerRadius(8)
        .overlay(
            Rectangle()
                .fill(cameraState.isConnected ? NikonTheme.readyGreen : NikonTheme.accentBlue)
                .frame(width: 3.5),
            alignment: .leading
        )
    }
    
    // MARK: - 3. 相机设备卡片 (.camera-card)
    private var cameraDeviceCardSection: some View {
        Button(action: {
            NikonTheme.triggerHaptic(style: .light)
            if !cameraState.isConnected {
                connectionService.autoDetectAndConnect()
            }
        }) {
            HStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 26))
                    .foregroundColor(cameraState.isConnected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(cameraState.isConnected ? "\(connectionService.selectedModel) (物理在线就绪)" : "\(connectionService.selectedModel) (待连接)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                    
                    Text(cameraState.isConnected ? "USB-C · 物理连接握手成功" : "USB-C · 等待物理连接握手")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(NikonTheme.textSecondary)
                }
                
                Spacer()
                
                // 右侧圆圈徽标 (.cam-check-badge)
                ZStack {
                    Circle()
                        .stroke(cameraState.isConnected ? NikonTheme.accentBlue : NikonTheme.borderDim, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if cameraState.isConnected {
                        Circle()
                            .fill(NikonTheme.accentBlue)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(cameraState.isConnected ? Color(red: 0.97, green: 0.985, blue: 1.0) : NikonTheme.surfaceCard)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(cameraState.isConnected ? NikonTheme.accentBlue : NikonTheme.borderDim, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
        }
    }
    
    // MARK: - 4. 科技蔚蓝核心检测大按钮
    private var startDetectButtonSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
                connectionService.autoDetectAndConnect()
            }) {
                HStack(spacing: 8) {
                    if connectionService.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(cameraState.isConnected ? "重新检测相机" : "开始检测连接")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(NikonTheme.accentBlue)
                .cornerRadius(26)
                .shadow(color: NikonTheme.accentBlue.opacity(0.35), radius: 12, x: 0, y: 5)
            }
            
            // 插线排查与权限提示
            HStack(spacing: 12) {
                Button(action: {
                    showingWiredHelp = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("插线检测不到相机？机身设置")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NikonTheme.accentBlue)
                }
                
                Text("·")
                    .foregroundColor(NikonTheme.textTertiary)
                
                Button(action: {
                    PermissionManager.openSystemSettings()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("检查 iOS 权限")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NikonTheme.textSecondary)
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 5. 已连接机身核心硬件状态卡片 (只显示用户要求的内存与电量)
    private var hardwareStorageAndBatteryCards: some View {
        VStack(spacing: 12) {
            // 存储卡卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sdcard.fill")
                            .foregroundColor(NikonTheme.accentBlue)
                        Text("存储空间 (SD 卡)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                    }
                    Spacer()
                    Text("剩余 \(String(format: "%.1f", cameraState.cardTotalGB - cameraState.cardUsedGB)) GB")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NikonTheme.accentBlueLight)
                        .foregroundColor(NikonTheme.accentBlue)
                        .cornerRadius(6)
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text("\(String(format: "%.0f", cameraState.cardUsedGB)) / \(Int(cameraState.cardTotalGB)) GB")
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(NikonTheme.textPrimary)
                    Spacer()
                    Text("\(cameraState.cardUsagePercent)%")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(NikonTheme.textSecondary)
                }
                
                ProgressView(value: cameraState.cardUsedGB, total: cameraState.cardTotalGB)
                    .tint(NikonTheme.accentBlue)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
                
                Text("约可拍摄 \(cameraState.remainingShots) 张 RAW+JPG 高清照片")
                    .font(.system(size: 12))
                    .foregroundColor(NikonTheme.textTertiary)
            }
            .padding(18)
            .background(NikonTheme.surfaceCard)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
            
            // 电池电量卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "battery.100.bolt")
                            .foregroundColor(NikonTheme.readyGreen)
                        Text("机身供电")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                    }
                    Spacer()
                    Text("状态良好")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.92, green: 0.99, blue: 0.95))
                        .foregroundColor(NikonTheme.readyGreen)
                        .cornerRadius(6)
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text("\(cameraState.batteryPercentage)%")
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(NikonTheme.textPrimary)
                    Spacer()
                    Text("USB-C 持续供电")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(NikonTheme.textSecondary)
                }
                
                ProgressView(value: Double(cameraState.batteryPercentage), total: 100.0)
                    .tint(NikonTheme.readyGreen)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
            }
            .padding(18)
            .background(NikonTheme.surfaceCard)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
        }
    }
    
    // MARK: - USB-C 线连与权限指引弹窗
    private var wiredGuideSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("尼康相机有线连接与权限排查")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                    
                    Text("iPhone 15/16 Pro 系列通过 Type-C 直连相机，受到 iOS 18 安全与相机底层协议双重控制，请依序检查以下 4 点：")
                        .font(.system(size: 13))
                        .foregroundColor(NikonTheme.textSecondary)
                    
                    // 1. 核心权限
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("1. iOS 系统权限 (必须开启)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(NikonTheme.accentBlue)
                            Spacer()
                            Button("前往设置") {
                                PermissionManager.openSystemSettings()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(NikonTheme.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(NikonTheme.accentBlueLight)
                            .cornerRadius(8)
                        }
                        
                        Text("进入 iPhone【设置】➔ 找到【Z30 影控】，确保【本地网络】与【无线数据 (无线局域网与蜂窝数据)】处于开启状态。若本地网络被关闭，iOS 会静默拦截相机通信。")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.textSecondary)
                            .padding(10)
                            .background(NikonTheme.bgSubtle)
                            .cornerRadius(8)
                    }
                    
                    // 2. USB 供电关闭 (致命关键)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("2. 相机关闭【USB 供电】(关键防断连)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                        
                        Text("按机身 MENU 键 ➔【设置菜单】(扳手图标) ➔ 找到【USB 供电】➔ 务必设为【关 (OFF)】！\n※ 若开启供电，相机将向手机索取高功率充电，触发 iPhone 16 过流保护而切断通信。")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.textSecondary)
                            .padding(10)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(8)
                    }
                    
                    // 3. USB 模式设为 MTP/PTP 或 iPhone
                    VStack(alignment: .leading, spacing: 6) {
                        Text("3. 相机【USB 数据连接】模式")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                        
                        Text("按机身 MENU 键 ➔【设置菜单】或【网络菜单】➔ 找到【USB 数据连接】➔ 切换为【MTP/PTP】或【iPhone】。连通后相机屏幕上方会显示 [-PC-] 联机标识。")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.textSecondary)
                            .padding(10)
                            .background(NikonTheme.bgSubtle)
                            .cornerRadius(8)
                    }
                    
                    // 4. 数据线与配件允许
                    VStack(alignment: .leading, spacing: 6) {
                        Text("4. 双头 Type-C 数据线与允许配件")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                        
                        Text("① 插入线缆时若 iPhone 提示【要允许此配件连接吗？】，必须点击【允许】；\n② 务必使用支持数据传输的 USB-C 线（避免使用仅支持充电的快充线）。")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.textSecondary)
                            .padding(10)
                            .background(NikonTheme.bgSubtle)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        showingWiredHelp = false
                        connectionService.autoDetectAndConnect()
                    }) {
                        Text("我已设置完毕，立即开始检测")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(NikonTheme.accentBlue)
                            .cornerRadius(14)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingWiredHelp = false }
                }
            }
        }
    }
}
