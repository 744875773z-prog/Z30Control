//
//  FastTransferView.swift
//  Z30Control
//
//  “相机按保护键自动速传”雷达监听与状态看板视图 (对齐原厂体验)
//

import SwiftUI

public struct FastTransferView: View {
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var isPulsing = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 1. 顶部当前存储与格式偏好设置条
                settingsSummaryBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                Spacer()
                
                // 2. 中央动态雷达呼吸动画 (等待相机保护事件)
                radarAnimationView
                
                // 3. 核心指引文本
                VStack(spacing: 6) {
                    Text("准备接收")
                        .proHUDText(size: 16, weight: .bold)
                        .foregroundColor(Color.primary)
                    Text("在相机上将照片标记为保护 🔒，即可自动发送到这里。")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // 4. 四联传输统计看板
                statsCounterGrid
                    .padding(.horizontal, 20)
                
                // 5. 底部文件索引状态
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11))
                    Text("已索引 \(syncService.stats.indexedTotalFiles) 个相机文件")
                        .proHUDText(size: 11)
                }
                .foregroundColor(.gray.opacity(0.8))
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("速传")
                            .proHUDText(size: 16, weight: .bold)
                        Text("新")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(NikonTheme.nikonYellow)
                            .cornerRadius(4)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(Color.primary)
                    }
                }
            }
            .onAppear {
                isPulsing = true
            }
        }
    }
    
    // MARK: - 顶部设置摘要条
    private var settingsSummaryBar: some View {
        HStack {
            Image(systemName: "slider.horizontal.2.square")
                .foregroundColor(NikonTheme.readyGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前设置")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Text("应用图库 · JPEG · NEF (RAW) · MOV/MP4")
                    .proHUDText(size: 11, weight: .semibold)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    // MARK: - 动态雷达呼吸动画
    private var radarAnimationView: some View {
        ZStack {
            // 外圈扩散水波纹
            Circle()
                .fill(NikonTheme.readyGreen.opacity(0.12))
                .frame(width: 170, height: 170)
                .scaleEffect(isPulsing ? 1.15 : 0.95)
                .animation(Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isPulsing)
            
            Circle()
                .fill(NikonTheme.readyGreen.opacity(0.2))
                .frame(width: 120, height: 120)
            
            // 核心相机同心圆
            ZStack {
                Circle()
                    .stroke(NikonTheme.nikonYellow, lineWidth: 2.5)
                    .frame(width: 72, height: 72)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color.primary)
                
                // 信号小标
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "wifi")
                            .font(.system(size: 10))
                            .foregroundColor(NikonTheme.readyGreen)
                            .padding(4)
                            .background(Color(UIColor.systemBackground))
                            .clipShape(Circle())
                    }
                }
                .frame(width: 72, height: 72)
            }
        }
        .frame(height: 200)
    }
    
    // MARK: - 统计看板
    private var statsCounterGrid: some View {
        HStack(spacing: 0) {
            statItem(count: syncService.stats.completedCount, title: "已完成", color: NikonTheme.readyGreen)
            Spacer()
            statItem(count: syncService.stats.pendingCount, title: "待处理", color: Color.primary)
            Spacer()
            statItem(count: syncService.stats.failedCount, title: "失败", color: NikonTheme.tallyRed)
            Spacer()
            statItem(count: syncService.stats.protectedCount, title: "标记保护", color: NikonTheme.nikonYellow)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private func statItem(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .proHUDText(size: 16, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
    }
}
