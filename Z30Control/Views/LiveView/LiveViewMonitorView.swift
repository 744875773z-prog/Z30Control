//
//  LiveViewMonitorView.swift
//  Z30Control
//
//  支持横竖屏自适应的专业电影级监视器主视图 (Portrait & Landscape Cinema Mode)
//

import SwiftUI

public struct LiveViewMonitorView: View {
    @ObservedObject var cameraState: CameraState
    @ObservedObject var streamService = LiveViewStreamService.shared
    
    @State private var isShowingGrid = true
    @State private var isLocked = false
    @State private var touchFocusPosition: CGPoint? = nil
    @State private var isFocusPulsing = false
    @State private var instantPreviewName: String? = nil
    
    public init(cameraState: CameraState) {
        self.cameraState = cameraState
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // 背景底色：OLED 纯黑
                NikonTheme.pitchBlack.ignoresSafeArea()
                
                if isLandscape {
                    // 横屏电影监看模式 (Cinema Field Monitor Layout)
                    landscapeCinemaLayout(size: geometry.size)
                } else {
                    // 竖屏常规手持模式 (Portrait Layout)
                    portraitHandheldLayout
                }
            }
        }
    }
    
    // MARK: - 竖屏手持布局 (对齐原设计)
    private var portraitHandheldLayout: some View {
        VStack(spacing: 0) {
            topStatusBar
                .padding(.horizontal, 14)
                .padding(.top, 6)
            
            ZStack {
                cameraViewportBackground
                
                if isShowingGrid { compositionGridOverlay }
                horizonLevelIndicator
                focusTargetBox
                
                if cameraState.isRecordingVideo {
                    Rectangle().stroke(NikonTheme.tallyRed, lineWidth: 3.5).ignoresSafeArea(edges: .horizontal)
                }
                
                // 拍摄后即时大图全屏回放浮层 (Instant Quick Preview)
                if let previewName = instantPreviewName {
                    instantPreviewOverlay(filename: previewName)
                }
                
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        if streamService.isHistogramVisible {
                            HistogramOverlayView(points: streamService.histogramPoints)
                                .padding(.leading, 12)
                        }
                        Spacer()
                        if cameraState.isRecordingVideo {
                            AudioVUMeterView().padding(.trailing, 12)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            viewportBottomSpecBar
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            
            FilmstripSelectorView(streamService: streamService)
                .padding(.vertical, 4)
            
            shutterDeckBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
    
    // MARK: - 横屏专业电影机布局 (Cinema Monitor Layout)
    private func landscapeCinemaLayout(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // 左侧参数仪表浮层栏 (Left Pro Sidebar)
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    Text(cameraState.exposureMode.rawValue.prefix(1))
                    Text(cameraState.shutterSpeed)
                    Text(cameraState.aperture)
                    Text("ISO \(cameraState.isoActual)")
                    Text(cameraState.exposureCompensation)
                }
                .proHUDText(size: 11, weight: .bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                
                Spacer()
                
                if streamService.isHistogramVisible {
                    HistogramOverlayView(points: streamService.histogramPoints)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 10)
            .frame(width: 96)
            
            // 中央满幅监看视口 (Center Max Viewport)
            ZStack {
                cameraViewportBackground
                if isShowingGrid { compositionGridOverlay }
                horizonLevelIndicator
                focusTargetBox
                
                if cameraState.isRecordingVideo {
                    Rectangle().stroke(NikonTheme.tallyRed, lineWidth: 3.5)
                }
                
                // 顶部悬浮 OSD
                VStack {
                    topStatusBar.padding(.horizontal, 12).padding(.top, 6)
                    Spacer()
                    // 底部胶卷滑轨
                    FilmstripSelectorView(streamService: streamService)
                        .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 右侧拇指操作底座 (Right Shutter Deck)
            VStack(spacing: 16) {
                Button(action: {
                    NikonTheme.triggerHaptic(style: .medium)
                    streamService.toggleLUT()
                }) {
                    Image(systemName: "square.3.layers.3d.down.right.fill")
                        .font(.system(size: 18))
                        .foregroundColor(streamService.isLUTEnabled ? NikonTheme.nikonYellow : .gray)
                }
                
                Spacer()
                
                // 大拇指主快门按钮
                Button(action: {
                    NikonTheme.triggerHaptic(style: .heavy)
                    if cameraState.isRecordingVideo {
                        cameraState.isRecordingVideo = false
                    } else {
                        cameraState.remainingShots = max(0, cameraState.remainingShots - 1)
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(cameraState.isRecordingVideo ? NikonTheme.tallyRed : NikonTheme.nikonYellow, lineWidth: 3.5)
                            .frame(width: 58, height: 58)
                        Circle()
                            .fill(cameraState.isRecordingVideo ? NikonTheme.tallyRed : Color.white)
                            .frame(width: 44, height: 44)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    isShowingGrid.toggle()
                }) {
                    Image(systemName: isShowingGrid ? "grid" : "grid.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .frame(width: 72)
        }
    }
    
    // MARK: - 顶部精密 OSD 状态栏
    private var topStatusBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(cameraState.isConnected ? NikonTheme.readyGreen : Color.gray)
                    .frame(width: 7, height: 7)
                Text(cameraState.modelName)
                    .proHUDText(size: 11, weight: .bold)
                    .foregroundColor(.white)
            }
            
            Text("16mm")
                .proHUDText(size: 11)
                .foregroundColor(NikonTheme.textSecondary)
            
            Spacer()
            
            Text("[\(cameraState.remainingShots)]")
                .proHUDText(size: 11, weight: .semibold)
                .foregroundColor(.white)
            
            HStack(spacing: 2) {
                Image(systemName: "battery.75")
                    .font(.system(size: 11))
                Text("\(cameraState.batteryPercentage)%")
                    .proHUDText(size: 10)
            }
            .foregroundColor(.white)
        }
    }
    
    // MARK: - 动态交互式监看视口 (支持手势触控对焦)
    private var cameraViewportBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.15, green: 0.16, blue: 0.18)
                
                // 动态触控对焦框
                if let pos = touchFocusPosition {
                    Rectangle()
                        .stroke(isFocusPulsing ? NikonTheme.nikonYellow : NikonTheme.readyGreen, lineWidth: 1.5)
                        .frame(width: isFocusPulsing ? 52 : 44, height: isFocusPulsing ? 52 : 44)
                        .position(pos)
                        .animation(.easeInOut(duration: 0.2), value: isFocusPulsing)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard !isLocked else { return }
                NikonTheme.triggerHaptic(style: .light)
                
                // 记录点击位置
                self.touchFocusPosition = location
                self.isFocusPulsing = true
                
                // 计算归一化坐标发送给相机 PTP
                let normX = Float(location.x / geo.size.width)
                let normY = Float(location.y / geo.size.height)
                CameraConnectionService.shared.client.setTouchFocus(x: normX, y: normY)
                
                // 0.2 秒后完成收缩，1.5 秒后渐隐
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isFocusPulsing = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.touchFocusPosition == location {
                        withAnimation { self.touchFocusPosition = nil }
                    }
                }
            }
        }
    }
    
    private var horizonLevelIndicator: some View {
        HStack(spacing: 8) {
            Rectangle().fill(NikonTheme.readyGreen).frame(width: 45, height: 1.5)
            Circle().stroke(NikonTheme.readyGreen, lineWidth: 1.5).frame(width: 6, height: 6)
            Rectangle().fill(NikonTheme.readyGreen).frame(width: 45, height: 1.5)
        }
    }
    
    private var focusTargetBox: some View {
        Rectangle()
            .stroke(NikonTheme.readyGreen, lineWidth: 1.5)
            .frame(width: 44, height: 44)
    }
    
    private var compositionGridOverlay: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: w * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: h * 2 / 3))
                path.addLine(to: CGPoint(x: w, y: h * 2 / 3))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        }
    }
    
    private var viewportBottomSpecBar: some View {
        HStack {
            Text(cameraState.resolution)
            Text("·")
            Text(cameraState.imageQuality)
            Text("·")
            Text(cameraState.focusMode.rawValue)
            Spacer()
            if let lut = streamService.activeFilter, streamService.isLUTEnabled {
                Text("LUT: \(lut.name)").foregroundColor(NikonTheme.nikonYellow)
            }
        }
        .proHUDText(size: 10, weight: .medium)
        .foregroundColor(NikonTheme.textSecondary)
    }
    
    private var shutterDeckBar: some View {
        HStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "photo").foregroundColor(.white))
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .medium)
                streamService.toggleLUT()
            }) {
                Image(systemName: "square.3.layers.3d.down.right.fill")
                    .font(.system(size: 18))
                    .foregroundColor(streamService.isLUTEnabled ? NikonTheme.nikonYellow : .gray)
            }
            
            Spacer()
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
                if cameraState.isRecordingVideo {
                    cameraState.isRecordingVideo = false
                } else {
                    cameraState.remainingShots = max(0, cameraState.remainingShots - 1)
                    // 触发拍摄后全屏快速预览 2 秒
                    let newPhotoName = "DSC_\(Int.random(in: 2700...2999)).JPG"
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.instantPreviewName = newPhotoName
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            if self.instantPreviewName == newPhotoName {
                                self.instantPreviewName = nil
                            }
                        }
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(cameraState.isRecordingVideo ? NikonTheme.tallyRed : NikonTheme.nikonYellow, lineWidth: 3.5)
                        .frame(width: 68, height: 68)
                    Circle()
                        .fill(cameraState.isRecordingVideo ? NikonTheme.tallyRed : Color.white)
                        .frame(width: 54, height: 54)
                }
            }
            
            Spacer()
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                isShowingGrid.toggle()
            }) {
                Image(systemName: isShowingGrid ? "grid" : "grid.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            
            Button(action: {
                NikonTheme.triggerHaptic(style: .light)
                isLocked.toggle()
            }) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 18))
                    .foregroundColor(isLocked ? NikonTheme.nikonYellow : .white)
            }
        }
        .frame(height: 72)
    }
    
    // MARK: - 拍摄后即时大图回放浮层
    private func instantPreviewOverlay(filename: String) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 12) {
                HStack {
                    Text("拍摄回放 (2s)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NikonTheme.nikonYellow)
                        .cornerRadius(4)
                    Spacer()
                    Text(filename)
                        .proHUDText(size: 12, weight: .bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                Image(systemName: "photo.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("合焦良好 · 5568x3712 · RAW+JPG")
                    .proHUDText(size: 11)
                    .foregroundColor(NikonTheme.readyGreen)
                
                Spacer()
            }
        }
        .transition(.opacity)
    }
}
