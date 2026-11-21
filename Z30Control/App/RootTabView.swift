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
    @StateObject private var cameraState = CameraState()
    @State private var selectedTab: MainTabItem = .control
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            VStack(spacing: 0) {
                // MARK: - 主页面分发区 (占满上方，贴合灵动岛安全区下方，绝无冗余空白)
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
                    pureWhiteBlueTabBar(bottomInset: geometry.safeAreaInsets.bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .ignoresSafeArea(.container, edges: .bottom) // 允许底部背景直通屏幕物理底边缘
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
            
            // 垫高 iPhone 16 Pro Max 底部手势横条安全区
            Spacer().frame(height: max(bottomInset - 6, 8))
        }
        .background(Color.white)
    }
}
