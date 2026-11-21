//
//  FastTransferView.swift
//  Z30Control
//
//  拍立得式即时速传 (快门按下即刻秒传，真实捕获相机成片，自由保存至相册)
//  纯净蓝白工业设计版，100% 真实数据，无任何模拟假照片
//

import SwiftUI
import Photos

public struct FastTransferView: View {
    @ObservedObject var usbCamera = UsbCameraManager.shared
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var autoSaveToAlbum = true
    @State private var showingSaveSuccessAlert = false
    @State private var alertMessage = "照片已无损存入您的 iPhone 系统相册！"
    @State private var currentSelectedPhotoIndex: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部 Header
            HStack {
                Text("速传")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(NikonTheme.textPrimary)
                Spacer()
                
                // 自动存相册开关药丸
                HStack(spacing: 6) {
                    Text("拍摄自动存相册")
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
            .padding(.top, 4)
            .padding(.bottom, 10)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 2. 状态提示条
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.accentBlue)
                        Text(usbCamera.isUsbConnected ? "已连接 \(usbCamera.connectedDeviceName)，按快门即刻秒传" : "请先连接相机，拍摄后照片将实时传输到此处")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(NikonTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NikonTheme.accentBlueLight)
                    .cornerRadius(8)
                    
                    // 3. 速传诊断行 + 手动重新扫描（v1.0.14：之前速传空了没有任何
                    // 原因可看，也没有手动补救的入口。现在诊断直接显示在这里，
                    // 拍完没进来就点“重新扫描卡内照片”，直接问卡里最新的 5 张。）
                    if usbCamera.isUsbConnected {
                        HStack(spacing: 8) {
                            Text("诊断：\(usbCamera.ptpDiagnostic.isEmpty ? "就绪" : usbCamera.ptpDiagnostic)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(NikonTheme.textSecondary)
                                .lineLimit(2)
                            Spacer()
                            Button(action: {
                                NikonTheme.triggerHaptic(style: .light)
                                usbCamera.rescanCardForNewPhotos()
                            }) {
                                Text("重新扫描卡内照片")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(NikonTheme.accentBlue)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(NikonTheme.bgSubtle)
                        .cornerRadius(8)
                    }

                    // 4. 照片展示区：无照片时显示纯净等待拍摄，有照片时显示真实最新成片
                    if usbCamera.sessionCapturedPhotos.isEmpty {
                        emptyWaitingCaptureView
                    } else {
                        realCapturedPhotoCard
                        saveActionButtonsSection
                        recentShotsStreamSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 18)
            }
        }
        .background(NikonTheme.bgPure.ignoresSafeArea())
        .alert(isPresented: $showingSaveSuccessAlert) {
            Alert(
                title: Text("保存成功"),
                message: Text(alertMessage),
                dismissButton: .default(Text("好的"))
            )
        }
    }
    
    // MARK: - 无照片时的纯净等待状态 (绝无假照片)
    private var emptyWaitingCaptureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 54))
                .foregroundColor(NikonTheme.accentBlue.opacity(0.4))
                .padding(.top, 20)
            
            VStack(spacing: 6) {
                Text("等待快门拍摄")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                
                Text("使用 Type-C 连接相机并开启电源，在机身每按一次快门，新拍摄的照片将瞬间高速回传到这里供您查看与保存。")
                    .font(.system(size: 13))
                    .foregroundColor(NikonTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(NikonTheme.surfaceCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.2))
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - 真实拍摄最新照片卡片
    private var realCapturedPhotoCard: some View {
        let currentItem = (currentSelectedPhotoIndex < usbCamera.sessionCapturedPhotos.count) ? usbCamera.sessionCapturedPhotos[currentSelectedPhotoIndex] : usbCamera.sessionCapturedPhotos.first
        
        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let img = currentItem?.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.03))
                } else {
                    Rectangle()
                        .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                        .frame(height: 240)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(NikonTheme.accentBlue.opacity(0.4))
                                Text(currentItem?.filename ?? "正在传输...")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(NikonTheme.textSecondary)
                            }
                        )
                }
                
                Text("最新成片")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem?.filename ?? "")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(NikonTheme.textPrimary)
                    Text(currentItem?.sizeString ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(NikonTheme.textTertiary)
                }
                Spacer()
                Text("传自 \(usbCamera.connectedDeviceName.isEmpty ? "Z 30" : usbCamera.connectedDeviceName)")
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
    
    // MARK: - 真实保存大按钮
    private var saveActionButtonsSection: some View {
        let currentItem = (currentSelectedPhotoIndex < usbCamera.sessionCapturedPhotos.count) ? usbCamera.sessionCapturedPhotos[currentSelectedPhotoIndex] : usbCamera.sessionCapturedPhotos.first
        
        return VStack(spacing: 10) {
            Button(action: {
                if let img = currentItem?.image {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    NikonTheme.triggerHaptic(style: .heavy)
                    alertMessage = "照片 [\(currentItem?.filename ?? "")] 已保存至 iPhone 系统相册！"
                    showingSaveSuccessAlert = true
                }
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
            
            Button(action: {
                var savedCount = 0
                for item in usbCamera.sessionCapturedPhotos {
                    if let img = item.image {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                        savedCount += 1
                    }
                }
                NikonTheme.triggerHaptic(style: .heavy)
                alertMessage = "已将本次拍摄的全部 \(savedCount) 张照片保存至相册！"
                showingSaveSuccessAlert = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                    Text("一键保存本次全部 \(usbCamera.sessionCapturedPhotos.count) 张照片")
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
    
    // MARK: - 本次拍摄流水横排列表 (真实数据)
    private var recentShotsStreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本次拍摄流水")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                Spacer()
                Text("共 \(usbCamera.sessionCapturedPhotos.count) 张")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NikonTheme.textTertiary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(usbCamera.sessionCapturedPhotos.enumerated()), id: \.element.id) { idx, item in
                        let isCur = (currentSelectedPhotoIndex == idx)
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .light)
                            currentSelectedPhotoIndex = idx
                        }) {
                            VStack(spacing: 4) {
                                if let img = item.image {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isCur ? NikonTheme.accentBlue : Color.clear, lineWidth: 2)
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.92, green: 0.94, blue: 0.96))
                                        .frame(width: 72, height: 72)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 20))
                                                .foregroundColor(isCur ? NikonTheme.accentBlue : .gray)
                                        )
                                }
                                
                                Text(item.filename)
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
