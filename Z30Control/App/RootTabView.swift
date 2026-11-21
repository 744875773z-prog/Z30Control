//
//  RootTabView.swift
//  Z30Control
//
//  主页面 4 大核心 Tab 导航底座 (监看 / 仪表盘 / 速传 / 图库)
//  默认启动进入专业实时取景电影监看台，完美适配 iPhone 16 Pro Max 全屏与横竖屏旋转
//

import SwiftUI

public enum MainTabItem: Int, CaseIterable {
    case liveView = 0   // 实时取景监看 (对齐网页版默认首页)
    case dashboard = 1  // 机身中控仪表盘
    case fastTransfer = 2 // 相机保护键秒级速传
    case gallery = 3    // 图库与 SD 卡素材管理
    
    var title: String {
        switch self {
        case .liveView: return "监看"
        case .dashboard: return "中控"
        case .fastTransfer: return "速传"
        case .gallery: return "图库"
        }
    }
    
    var iconName: String {
        switch self {
        case .liveView: return "video.fill"
        case .dashboard: return "slider.horizontal.3"
        case .fastTransfer: return "dot.radiowaves.left.and.right"
        case .gallery: return "photo.stack.fill"
        }
    }
}

public struct RootTabView: View {
    @StateObject private var cameraState = CameraState()
    @State private var selectedTab: MainTabItem = .liveView // 默认直接进入实时取景监看！
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack(alignment: .bottom) {
                // MARK: - 主页面内容分发 (沉浸式全屏)
                Group {
                    switch selectedTab {
                    case .liveView:
                        LiveViewMonitorView(cameraState: cameraState)
                    case .dashboard:
                        ControlDashboardView(cameraState: cameraState, onSwitchToLiveView: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedTab = .liveView
                            }
                        })
                    case .fastTransfer:
                        FastTransferView()
                    case .gallery:
                        CameraGalleryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea() // 彻底消除 Letterbox 黑边，铺满 iPhone 16 Pro Max
                
                // MARK: - 底部悬浮高亮胶囊 TabBar
                // 横屏下自动隐藏底部 TabBar，将整块屏幕完整让给监视器画面！竖屏下保留
                if !isLandscape {
                    customFloatingTabBar
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12))
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
    
    // MARK: - 自定义高对比悬浮胶囊 TabBar
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
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: isSelected ? 15 : 14, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .black : Color.white.opacity(0.7))
                        
                        if isSelected {
                            Text(tab.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(NikonTheme.nikonYellow) // 醒目高对比的经典尼康亮黄！
                                    .shadow(color: NikonTheme.nikonYellow.opacity(0.4), radius: 6, x: 0, y: 1)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.92)) // 深色毛玻璃高对比底座
                .shadow(color: Color.black.opacity(0.5), radius: 14, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
}
