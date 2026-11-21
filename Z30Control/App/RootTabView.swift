//
//  RootTabView.swift
//  Z30Control
//
//  4 大核心 Tab 导航底座 (控制 / 实时取景 / 速传 / 图库)
//  完美贴底无悬空、状态栏/灵动岛避让无重叠、纯白蓝调对齐网页版
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
    @ObservedObject private var connectionService = CameraConnectionService.shared
    private var cameraState: CameraState { connectionService.cameraState }
    @State private var selectedTab: MainTabItem = .control
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let topSafeArea = geometry.safeAreaInsets.top
            let bottomSafeArea = geometry.safeAreaInsets.bottom
            
            VStack(spacing: 0) {
                // MARK: - 顶部安全区占位 (灵动岛/刘海/状态栏，避免内容与系统状态栏重叠)
                // 仅对非全屏黑背景的页面（控制页/速传/图库）显示，实时取景页自行处理
                if selectedTab != .liveView {
                    Color.white
                        .frame(height: topSafeArea)
                        .frame(maxWidth: .infinity)
                }
                
                // MARK: - 主页面分发区
                Group {
                    switch selectedTab {
                    case .control:
                        ControlDashboardView(cameraState: cameraState)
                    case .liveView:
                        LiveViewMonitorView(cameraState: cameraState, onExitToControl: {
                            selectedTab = .control
                        })
                    case .fastTransfer:
                        FastTransferView()
                    case .gallery:
                        CameraGalleryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // MARK: - 底部 TabBar (绝对贴底，绝不悬空，横屏下自动隐藏)
                if !isLandscape {
                    pureWhiteBlueTabBar(bottomInset: bottomSafeArea)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (selectedTab == .liveView ? Color.black : Color.white)
                    .ignoresSafeArea()
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .ignoresSafeArea(.container, edges: .bottom) // 底部直通物理边缘
    }
    
    // MARK: - 纯白蓝调网页版 1:1 导航栏 (贴底无白块断层)
    private func pureWhiteBlueTabBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 顶部分隔线
            Rectangle()
                .fill(NikonTheme.borderDim)
                .frame(height: 0.8)
            
            // 4 个 Tab 按钮行
            HStack(spacing: 0) {
                ForEach(MainTabItem.allCases, id: \.self) { tab in
                    let isSelected = (selectedTab == tab)
                    
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        selectedTab = tab
                    }) {
                        VStack(spacing: 3) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 21, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                            
                            Text(tab.title)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            
            // 底部手势横条安全区 (贴底，不留多余空白)
            Color.white
                .frame(height: bottomInset)
        }
        .background(Color.white)
    }
}
