//
//  FastTransferView.swift
//  Z30Control
//
//  拍立得式即时速传 (快门按下即刻秒传，自由选择保存至手机相册)
//  纯净蓝白工业设计版，彻底删除“新”徽标与无用设置键
//

import SwiftUI

public struct FastTransferView: View {
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var autoSaveToAlbum = false
    @State private var showingSaveSuccessAlert = false
    @State private var currentSelectedPhotoIndex: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部 Header (只有简洁大标题“速传”，绝无“新”徽标和无用按键)
            HStack {
                Text("速传")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(NikonTheme.textPrimary)
                Spacer()
                
                // 自动存相册开关药丸
                HStack(spacing: 6) {
                    Text("自动存入相册")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(autoSaveToAlbum ? NikonTheme.accentBlue : NikonTheme.textSecondary)
                    Toggle("", isOn: $autoSaveToAlbum)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: NikonTheme.accentBlue))
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(NikonTheme.bgSubtle)
                .cornerRadius(16)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 2. 状态提示条
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.accentBlue)
                        Text("每按一次快门，照片将瞬间传输到这里，供您即刻挑选保存")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(NikonTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NikonTheme.accentBlueLight)
                    .cornerRadius(8)
                    
                    // 3. 最新快门拍摄成片大图卡片 (即拍即看)
                    latestCapturedPhotoCard
                    
                    // 4. 保存控制大按钮
                    saveActionButtonsSection
                    
                    // 5. 本次拍摄流水瀑布 (最近快门列表)
                    recentShotsStreamSection
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 18)
            }
        }
        .background(NikonTheme.bgPure.ignoresSafeArea())
        .alert(isPresented: $showingSaveSuccessAlert) {
            Alert(
                title: Text("保存成功"),
                message: Text("照片已无损存入您的 iPhone 系统相册！"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
    
    // MARK: - 3. 最新快门拍摄大卡片
    private var latestCapturedPhotoCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // 模拟照片视口
                Rectangle()
                    .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                    .frame(height: 240)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 48))
                                .foregroundColor(NikonTheme.accentBlue.opacity(0.4))
                            Text(syncService.currentTransferFileName.isEmpty ? "DSC_8921.JPG" : syncService.currentTransferFileName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(NikonTheme.textSecondary)
                            Text("5568 × 3712 · RAW+JPG · 24.5 MB")
                                .font(.system(size: 11))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
                    )
                
                // 右上角“刚刚传输”药丸
                Text("刚刚拍摄")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NikonTheme.accentBlue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(10)
            }
            .cornerRadius(14)
            .clipped()
            
            // 下方参数说明行
            HStack {
                HStack(spacing: 12) {
                    paramBadge(icon: "timer", text: "1/125s")
                    paramBadge(icon: "camera.aperture", text: "f/4.0")
                    paramBadge(icon: "sun.max", text: "ISO 400")
                }
                Spacer()
                Text("传自 Z 30")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(NikonTheme.accentBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(NikonTheme.surfaceCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NikonTheme.borderDim, lineWidth: 1.2))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
    
    private func paramBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(.gray)
            Text(text).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(NikonTheme.textPrimary)
        }
    }
    
    // MARK: - 4. 保存控制大按钮
    private var saveActionButtonsSection: some View {
        VStack(spacing: 10) {
            Button(action: {
                NikonTheme.triggerHaptic(style: .heavy)
                showingSaveSuccessAlert = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("保存这张照片到手机相册")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(NikonTheme.accentBlue)
                .cornerRadius(25)
                .shadow(color: NikonTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    showingSaveSuccessAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                        Text("保存本次全部照片")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(NikonTheme.bgSubtle)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                }
                
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("隔空投送 / 分享")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(NikonTheme.bgSubtle)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - 5. 本次快门拍摄流水预览
    private var recentShotsStreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本次快门拍摄流水")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                Spacer()
                Text("共 8 张")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NikonTheme.textTertiary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<8) { idx in
                        let isCur = (currentSelectedPhotoIndex == idx)
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .light)
                            currentSelectedPhotoIndex = idx
                        }) {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.92, green: 0.94, blue: 0.96))
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 20))
                                            .foregroundColor(isCur ? NikonTheme.accentBlue : .gray)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isCur ? NikonTheme.accentBlue : Color.clear, lineWidth: 2)
                                    )
                                
                                Text("DSC_892\(8 - idx).JPG")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isCur ? NikonTheme.accentBlue : NikonTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(NikonTheme.surfaceCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NikonTheme.borderDim, lineWidth: 1.2))
    }
}
