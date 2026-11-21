//
//  RootTabView.swift
//  Z30Control
//
//  主页面 4 大核心 Tab 导航底座 (控制 / 速传 / 图库 / 设置)
//

import SwiftUI

public enum MainTabItem: Int {
    case control = 0
    case fastTransfer = 1
    case gallery = 2
    case settings = 3
}

public struct RootTabView: View {
    @StateObject private var cameraState = CameraState()
    @State private var selectedTab: MainTabItem = .control
    @State private var controlSubMode: Int = 0 // 0: 实时取景监看, 1: 硬件中控仪表盘
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 【控制】(支持取景监看与中控仪表盘模式)
            ZStack(alignment: .topTrailing) {
                if controlSubMode == 0 {
                    LiveViewMonitorView(cameraState: cameraState)
                } else {
                    ControlDashboardView(cameraState: cameraState)
                }
                
                // 右上角模式切换药丸浮标 (在“实时取景”与“参数仪表盘”之间一键切换)
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlSubMode = (controlSubMode == 0) ? 1 : 0
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: controlSubMode == 0 ? "slider.vertical.3" : "video.fill")
                        Text(controlSubMode == 0 ? "仪表盘" : "取景监看")
                    }
                    .proHUDText(size: 11, weight: .bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(NikonTheme.nikonYellow)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NikonTheme.nikonYellow.opacity(0.8), lineWidth: 1))
                }
                .padding(.top, 42)
                .padding(.trailing, 16)
            }
            .tabItem {
                Image(systemName: "camera.fill")
                Text("控制")
            }
            .tag(MainTabItem.control)
            
            // Tab 2: 【速传】(“相机标记保护键自动秒传”)
            FastTransferView()
                .tabItem {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("速传")
                }
                .tag(MainTabItem.fastTransfer)
            
            // Tab 3: 【图库】(SD 卡与本地相册下载管理)
            CameraGalleryView()
                .tabItem {
                    Image(systemName: "photo.stack.fill")
                    Text("图库")
                }
                .tag(MainTabItem.gallery)
            
            // Tab 4: 【设置】(系统偏好与相机时钟同步)
            SettingsView(cameraState: cameraState)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                }
                .tag(MainTabItem.settings)
        }
        .accentColor(NikonTheme.nikonYellow) // 选中高亮统一采用经典尼康黄！
    }
}
