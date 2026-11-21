//
//  RootTabView.swift
//  Z30Control
//
//  主页面 4 大核心 Tab 导航底座 (控制 / 速传 / 图库 / 设置)
//  支持对齐专业控制台参考图的沉浸式悬浮胶囊导航栏与高亮选中背景
//

import SwiftUI

public enum MainTabItem: Int, CaseIterable {
    case control = 0
    case fastTransfer = 1
    case gallery = 2
    case settings = 3
    
    var title: String {
        switch self {
        case .control: return "控制"
        case .fastTransfer: return "速传"
        case .gallery: return "图库"
        case .settings: return "设置"
        }
    }
    
    var iconName: String {
        switch self {
        case .control: return "camera.fill"
        case .fastTransfer: return "dot.radiowaves.left.and.right"
        case .gallery: return "photo.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct RootTabView: View {
    @StateObject private var cameraState = CameraState()
    @State private var selectedTab: MainTabItem = .control
    @State private var controlSubMode: Int = 1 // 默认进入控制仪表盘模式 (0: 实时取景监看, 1: 硬件中控仪表盘)
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - 主页面内容分发
            Group {
                switch selectedTab {
                case .control:
                    if controlSubMode == 0 {
                        ZStack(alignment: .topTrailing) {
                            LiveViewMonitorView(cameraState: cameraState)
                            
                            // 右上角浮动返回仪表盘按钮
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    controlSubMode = 1
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.vertical.3")
                                    Text("仪表盘")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.75))
                                .foregroundColor(NikonTheme.nikonYellow)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(NikonTheme.nikonYellow.opacity(0.8), lineWidth: 1))
                            }
                            .padding(.top, 44)
                            .padding(.trailing, 16)
                        }
                    } else {
                        ControlDashboardView(cameraState: cameraState, onSwitchToLiveView: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                controlSubMode = 0
                            }
                        })
                    }
                    
                case .fastTransfer:
                    FastTransferView()
                    
                case .gallery:
                    CameraGalleryView()
                    
                case .settings:
                    SettingsView(cameraState: cameraState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // MARK: - 底部悬浮高亮胶囊 TabBar (对齐参考图样式)
            if !(selectedTab == .control && controlSubMode == 0) {
                customFloatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    // MARK: - 自定义悬浮胶囊 TabBar
    private var customFloatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTabItem.allCases, id: \.self) { tab in
                let isSelected = (selectedTab == tab)
                
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: isSelected ? 16 : 16, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? Color(red: 0.9, green: 0.68, blue: 0.0) : Color.gray.opacity(0.8))
                        
                        if isSelected {
                            Text(tab.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.9, green: 0.68, blue: 0.0))
                        }
                    }
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 19)
                                    .fill(Color(red: 1.0, green: 0.94, blue: 0.76)) // 柔和温润的浅黄高亮药丸底
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.white.opacity(0.96))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
