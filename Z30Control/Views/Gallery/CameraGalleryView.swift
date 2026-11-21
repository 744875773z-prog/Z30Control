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
            
            // 2. 胶囊筛选栏 (全部 / 已存手机 / RAW / JPEG)
            filterBarSection
                .padding(.horizontal, 18)
            
            // 3. 文件统计信息栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .foregroundColor(NikonTheme.accentBlue)
                    Text("共 \(syncService.mediaItems.count) 项素材")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                }
                Spacer()
                Text("相机卡容量已用 \(syncService.stats.completedCount) 张")
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
                ForEach(["全部", "已存手机", "RAW (NEF)", "JPEG", "视频"], id: \.self) { filter in
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
                                Image(systemName: item.fileType.contains("RAW") ? "camera.metering.matrix" : "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(NikonTheme.accentBlue.opacity(0.5))
                            )
                        
                        Text(item.fileType)
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
                            Text("\(item.fileType) · \(item.fileSizeMB) · \(item.formattedDate)")
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
            return syncService.mediaItems.filter { $0.fileType.contains("RAW") }
        } else if selectedFilterType == "JPEG" {
            return syncService.mediaItems.filter { $0.fileType.contains("JPG") || $0.fileType.contains("JPEG") }
        } else {
            return syncService.mediaItems
        }
    }
}
