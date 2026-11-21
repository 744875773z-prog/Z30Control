//
//  RootTabView.swift
//  Z30Control
//
//  3 大核心 Tab 导航底座 (控制 / 实时取景 / 图库)
//  v1.0.18：速传页签删了——拍完照直接进图库，在图库里选图保存/分享。
//  完美贴底无悬空、状态栏/灵动岛避让无重叠、纯白蓝调对齐网页版
//

import SwiftUI

public enum MainTabItem: Int, CaseIterable {
    case control = 0      // 控制
    case liveView = 1     // 实时取景
    case gallery = 2      // 图库
    
    var title: String {
        switch self {
        case .control: return "控制"
        case .liveView: return "实时取景"
        case .gallery: return "图库"
        }
    }
    
    var iconName: String {
        switch self {
        case .control: return "camera.fill"
        case .liveView: return "viewfinder"
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
            let bottomSafeArea = geometry.safeAreaInsets.bottom

            VStack(spacing: 0) {
                // v1.0.11：顶部留白只靠系统安全区，不再手动加占位块。
                // 教训：根视图默认就被系统按安全区往下顶一次（灵动岛约 59pt），
                // 之前又手动加了一个同等高度的白色占位块，两个叠加导致空隙约 130pt。
                // v1.0.9 用 ignoresSafeArea(.top) 修了控制页，却把取景页自己的
                // safeAreaInsets.top 归零，取景页顶栏直接顶到手机状态栏上重叠。
                // 正确修法：删掉手动占位块和 ignoresSafeArea，只留系统安全区。
                // MARK: - 主页面分发区
                Group {
                    switch selectedTab {
                    case .control:
                        ControlDashboardView(cameraState: cameraState)
                    case .liveView:
                        LiveViewMonitorView(cameraState: cameraState, onExitToControl: {
                            selectedTab = .control
                        })
                    case .gallery:
                        CameraGalleryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // MARK: - 底部 TabBar (绝对贴底，绝不悬空)
                // v1.0.21：横屏也不隐藏了。之前横屏自动隐藏，进取景页强制横屏
                // 后底栏直接没了，只能点返回回控制页；用户要的是“底栏依旧存在，
                // 只有画面横过来”。底栏仍在 VStack 流内，页面内容不会被盖住。
                pureWhiteBlueTabBar(bottomInset: bottomSafeArea)
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
    
    // MARK: - 悬浮玻璃底栏（v1.0.9：贴底白条 → 苹果风毛玻璃胶囊，往上抬一点）
    // 旧版是全宽白条 + 底部 34pt 白块贴着屏幕底，看着笨重；新版是悬浮胶囊：
    // ultraThinMaterial 毛玻璃底 + 白色细描边 + 柔和阴影，选中项是蓝色实心胶囊
    // （白字），未选中灰字；底部留 bottomInset + 10pt，整体比原来抬高约 10pt。
    // 注意：底栏仍在 VStack 流内（不是 overlay），页面内容不会被盖住。
    private func pureWhiteBlueTabBar(bottomInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(MainTabItem.allCases, id: \.self) { tab in
                let isSelected = (selectedTab == tab)

                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    selectedTab = tab
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: isSelected ? .bold : .medium))

                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundColor(isSelected ? .white : NikonTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ? NikonTheme.accentBlue : Color.clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, bottomInset + 10)
        // v1.0.21：横屏时底栏收窄居中（宽屏上三个键拉满屏看着太散）。
        // 竖屏可用宽 358pt < 420，不受影响；横屏 844pt 时封顶 420pt。
        .frame(maxWidth: 420)
    }
}
