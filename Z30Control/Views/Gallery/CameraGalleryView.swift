//
//  CameraGalleryView.swift
//  Z30Control
//
//  相机 SD 卡与手机已存素材图库 (蓝白纯净现代工业设计版)
//

import SwiftUI

public struct CameraGalleryView: View {
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var isGridView = false
    @State private var selectedFilterType = "全部"
    @State private var selectedItemForDetail: CameraMediaItem?
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // 1. 顶部 Navigation 栏 (纯净白底，无双层导航栏冲突)
            HStack {
                Text("图库")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(NikonTheme.textPrimary)
                
                Spacer()
                
                // 网格 / 列表切换按钮
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    isGridView.toggle()
                }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(NikonTheme.accentBlue)
                        .frame(width: 36, height: 36)
                        .background(NikonTheme.accentBlueLight)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            
            // 2. 胶囊筛选栏 (全部 / RAW / JPEG)
            filterBarSection
                .padding(.horizontal, 18)
            
            // 3. 文件统计信息栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .foregroundColor(NikonTheme.accentBlue)
                    Text("共 \(filteredItems.count) 项素材")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                }
                Spacer()
                Text("已存入手机 \(syncService.stats.completedCount) 张")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NikonTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            
            // 4. 内容展示 (网格 / 列表)
            ScrollView(showsIndicators: false) {
                if isGridView {
                    mediaGridView
                        .padding(.horizontal, 18)
                } else {
                    mediaListView
                        .padding(.horizontal, 18)
                }
                
                Spacer(minLength: 100)
            }
        }
        .background(NikonTheme.bgPure.ignoresSafeArea())
        .sheet(item: $selectedItemForDetail) { item in
            PhotoExportSheet(item: item)
        }
    }
    
    // MARK: - 筛选栏
    private var filterBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["全部", "RAW (NEF)", "JPEG", "视频"], id: \.self) { filter in
                    let isSelected = (selectedFilterType == filter)
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        selectedFilterType = filter
                    }) {
                        Text(filter)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : NikonTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isSelected ? NikonTheme.accentBlue : NikonTheme.bgSubtle)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NikonTheme.borderDim, lineWidth: isSelected ? 0 : 1))
                    }
                }
            }
        }
    }
    
    // MARK: - 网格视图
    private var mediaGridView: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredItems) { item in
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    selectedItemForDetail = item
                }) {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: item.format == .rawNEF ? "camera.metering.matrix" : "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(NikonTheme.accentBlue.opacity(0.5))
                            )
                        
                        Text(item.format.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
            }
        }
    }
    
    // MARK: - 列表视图
    private var mediaListView: some View {
        LazyVStack(spacing: 10) {
            ForEach(filteredItems) { item in
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    selectedItemForDetail = item
                }) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                            .frame(width: 54, height: 54)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundColor(NikonTheme.accentBlue)
                            )
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.filename)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(NikonTheme.textPrimary)
                            Text("\(item.format.rawValue) · \(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 11))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(NikonTheme.textTertiary)
                    }
                    .padding(12)
                    .background(NikonTheme.surfaceCard)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NikonTheme.borderDim, lineWidth: 1))
                }
            }
        }
    }
    
    private var filteredItems: [CameraMediaItem] {
        if selectedFilterType == "全部" {
            return syncService.mediaItems
        } else if selectedFilterType == "RAW (NEF)" {
            return syncService.mediaItems.filter { $0.format == .rawNEF }
        } else if selectedFilterType == "JPEG" {
            return syncService.mediaItems.filter { $0.format == .jpeg }
        } else if selectedFilterType == "视频" {
            return syncService.mediaItems.filter { $0.format == .videoMOV || $0.format == .videoMP4 }
        } else {
            return syncService.mediaItems
        }
    }
}

/// 照片导出与保存详情弹窗
public struct PhotoExportSheet: View {
    public let item: CameraMediaItem
    @Environment(\.presentationMode) var presentationMode
    @State private var isSavedAlert = false
    
    public init(item: CameraMediaItem) {
        self.item = item
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 大图预览占位
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                    .frame(height: 240)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 44))
                                .foregroundColor(NikonTheme.accentBlue.opacity(0.6))
                            Text(item.filename)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(NikonTheme.textPrimary)
                            Text("\(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 11))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                // 核心导出保存按钮
                VStack(spacing: 12) {
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .heavy)
                        isSavedAlert = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("无损保存原图到系统相册")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(NikonTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: NikonTheme.accentBlue.opacity(0.3), radius: 8, x: 0, y: 3)
                    }
                    
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("隔空投送 / 系统分享")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(NikonTheme.bgSubtle)
                        .foregroundColor(NikonTheme.textPrimary)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .background(NikonTheme.bgPure.ignoresSafeArea())
            .navigationTitle("素材选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $isSavedAlert) {
                Alert(
                    title: Text("保存成功"),
                    message: Text("已将 \(item.filename) 成功存入 iPhone 系统相册！"),
                    dismissButton: .default(Text("好的"))
                )
            }
        }
    }
}
