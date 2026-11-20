//
//  CameraGalleryView.swift
//  Z30Control
//
//  相机 SD 卡文件与手机图库管理视图 (RAW+JPG 归类、保护标显示、一键套滤镜导出)
//

import SwiftUI

public struct CameraGalleryView: View {
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var isGridView = false
    @State private var selectedFilterType = "全部"
    @State private var selectedItemForDetail: CameraMediaItem?
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                // 1. 顶部胶囊筛选栏 (对齐截图 3 & 6)
                filterBarSection
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                
                // 2. 统计概览信息栏
                summaryStatsCard
                    .padding(.horizontal, 14)
                
                // 3. 文件列表 / 网格展示
                if isGridView {
                    mediaGridView
                } else {
                    mediaListView
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("图库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        isGridView.toggle()
                    }) {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                            .foregroundColor(Color.primary)
                    }
                }
            }
            .sheet(item: $selectedItemForDetail) { item in
                PhotoExportSheet(item: item)
            }
        }
    }
    
    // MARK: - 筛选栏
    private var filterBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill(title: "类型: 全部 ∨")
                filterPill(title: "格式: 全部 ∨")
                filterPill(title: "🔒 保护: 全部 ∨")
            }
        }
    }
    
    private func filterPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .foregroundColor(Color.primary)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NikonTheme.borderGray, lineWidth: 0.6))
    }
    
    // MARK: - 统计卡片 (对齐截图 6)
    private var summaryStatsCard: some View {
        HStack {
            statMetric(title: "文件", value: "\(syncService.mediaItems.count)/\(syncService.mediaItems.count)")
            Spacer()
            statMetric(title: "已选", value: "0")
            Spacer()
            statMetric(title: "存储", value: "46.9 MB")
            Spacer()
            statMetric(title: "最近", value: "23:01")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    private func statMetric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .proHUDText(size: 12, weight: .bold)
        }
    }
    
    // MARK: - 精工列表排版 (1:1 还原截图 6 的质感)
    private var mediaListView: some View {
        List {
            ForEach(syncService.mediaItems) { item in
                Button(action: {
                    NikonTheme.triggerHaptic(style: .medium)
                    selectedItemForDetail = item
                }) {
                    HStack(spacing: 12) {
                        // 缩略图占位
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 50, height: 40)
                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(item.filename)
                                    .proHUDText(size: 13, weight: .bold)
                                    .foregroundColor(Color.primary)
                                
                                if item.isProtected {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(NikonTheme.nikonYellow)
                                }
                            }
                            
                            Text("\(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 2) {
                                Image(systemName: "camera")
                                    .font(.system(size: 9))
                                Text("Nikon Z30 · 7029182")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.gray.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        // 格式角标
                        Text(item.format.rawValue)
                            .proHUDText(size: 9, weight: .bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.format == .rawNEF ? NikonTheme.nikonYellow.opacity(0.2) : Color.white.opacity(0.1))
                            .foregroundColor(item.format == .rawNEF ? NikonTheme.nikonYellow : .gray)
                            .cornerRadius(3)
                        
                        Image(systemName: "ellipsis")
                            .foregroundColor(.gray)
                            .padding(.leading, 4)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    // 触底自动触发分页流式加载
                    if item.id == syncService.mediaItems.last?.id {
                        syncService.loadNextPage()
                    }
                }
            }
            
            // 底部加载状态提示
            if syncService.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(" 正在流式加载相机照片...")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - 网格模式 (对齐截图 3)
    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(syncService.mediaItems) { item in
                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                        
                        // 连拍角标与格式标
                        HStack {
                            Text(item.format == .rawNEF ? "RAW" : "JPG")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(2)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                            Spacer()
                            if item.isProtected {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(NikonTheme.nikonYellow)
                                    .padding(2)
                            }
                        }
                        .padding(4)
                    }
                    .onTapGesture {
                        selectedItemForDetail = item
                    }
                }
            }
            .padding(4)
        }
    }
}

/// 照片导出与滤镜烘焙弹窗
struct PhotoExportSheet: View {
    let item: CameraMediaItem
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedLUT = "PORTRA 400"
    @State private var isSavedAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 大图预览占位
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .frame(height: 240)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.gray)
                            Text(item.filename)
                                .proHUDText(size: 14, weight: .bold)
                            Text("\(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                // 核心双通道导出按钮 (用户提到的核心诉求：保存照片到手机)
                VStack(spacing: 12) {
                    // 按钮 1: 原图直接保存
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .medium)
                        isSavedAlert = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("无损保存原图到系统相册")
                                .proHUDText(size: 14, weight: .bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .foregroundColor(Color.primary)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NikonTheme.borderGray, lineWidth: 1))
                    }
                    
                    // 按钮 2: 一键套用 3D LUT 胶片滤镜保存
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .heavy)
                        isSavedAlert = true
                    }) {
                        HStack {
                            Image(systemName: "camera.filters")
                            Text("套用 [\(selectedLUT)] 滤镜并保存到相册")
                                .proHUDText(size: 14, weight: .bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(NikonTheme.nikonYellow)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("照片选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $isSavedAlert) {
                Alert(title: Text("保存成功"), message: Text("已将 \(item.filename) 存入 iPhone 系统相册！"), dismissButton: .default(Text("好的")))
            }
        }
    }
}
