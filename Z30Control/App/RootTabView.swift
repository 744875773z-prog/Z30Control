//
//  RootTabView.swift
//  Z30Control
//
//  4 大核心 Tab 导航底座 (控制 / 实时取景 / 速传 / 图库)
//  100% 完整对齐网页版 4 大 Tab 架构与纯白蓝调视觉体系
//

import SwiftUI

public enum MainTabItem: Int, CaseIterable {
    case control = 0      // 控制
    case liveView = 1     // 实时取景
    case fastTransfer = 2 // 速传
    case gallery = 3      // 图库
    
    var title: String {
        switch self {
        case .control: return "控制"
        case .liveView: return "实时取景"
        case .fastTransfer: return "速传"
        case .gallery: return "图库"
        }
    }
    
    var iconName: String {
        switch self {
        case .control: return "camera.fill"
        case .liveView: return "viewfinder"
        case .fastTransfer: return "dot.radiowaves.left.and.right"
        case .gallery: return "photo.stack.fill"
        }
    }
}

public struct RootTabView: View {
    @StateObject private var cameraState = CameraState()
    @State private var selectedTab: MainTabItem = .control // 默认进入【控制】页 (对齐网页版图 2)
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack(alignment: .bottom) {
                // MARK: - 主页面分发
                Group {
                    switch selectedTab {
                    case .control:
                        ControlDashboardView(cameraState: cameraState)
                    case .liveView:
                        LiveViewMonitorView(cameraState: cameraState)
                    case .fastTransfer:
                        FastTransferView()
                    case .gallery:
                        CameraGalleryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea() // 确保在 LaunchScreen 加持下，满幅适配 iPhone 16 Pro Max 全屏
                
                // MARK: - 底部 TabBar (横屏下自动隐藏，竖屏下纯白蓝调对齐网页版)
                if !isLandscape {
                    pureWhiteBlueTabBar
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 6))
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
    
    // MARK: - 纯白蓝调网页版 1:1 导航栏
    private var pureWhiteBlueTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTabItem.allCases, id: \.self) { tab in
                let isSelected = (selectedTab == tab)
                
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    selectedTab = tab
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: -4)
                .overlay(
                    Rectangle()
                        .fill(NikonTheme.borderDim)
                        .frame(height: 0.8),
                    alignment: .top
                )
        )
    }
}
