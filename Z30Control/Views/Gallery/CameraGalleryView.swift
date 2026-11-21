//
//  CameraGalleryView.swift
//  Z30Control
//
//  相机 SD 卡与手机已存素材图库 (蓝白纯净现代工业设计版)
//

import SwiftUI
import UIKit

public struct CameraGalleryView: View {
    @ObservedObject var syncService = MediaSyncService.shared
    @ObservedObject var connectionService = CameraConnectionService.shared
    @State private var isGridView = false
    @State private var selectedFilterType = "全部"
    @State private var selectedItemForDetail: CameraMediaItem?
    // v1.0.18：图库多选——选图后批量保存到相册 / 批量分享（速传删了，图库是唯一入口）
    @State private var isSelecting = false
    @State private var selectedFilenames: Set<String> = []
    @State private var batchSaving = false
    @State private var batchProgress: (Int, Int) = (0, 0)
    @State private var batchResult: (Int, Int)?
    @State private var showBatchResult = false
    @State private var batchShare: ShareBatch?
    @State private var isBatchSharing = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // 1. 顶部 Navigation 栏 (纯净白底，无双层导航栏冲突)
            HStack {
                Text("图库")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(NikonTheme.textPrimary)
                
                Spacer()
                
                // v1.0.3：手动刷新相机卡内文件列表
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    syncService.refreshIndexFromCamera()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(connectionService.isConnected ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(NikonTheme.accentBlueLight)
                        .cornerRadius(10)
                }
                .disabled(!connectionService.isConnected || syncService.isSyncingIndex)
                
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
                
                // v1.0.18：多选开关（选图后批量保存/分享）
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    isSelecting.toggle()
                    if !isSelecting { selectedFilenames.removeAll() }
                }) {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isSelecting ? .white : NikonTheme.accentBlue)
                        .frame(width: 36, height: 36)
                        .background(isSelecting ? NikonTheme.accentBlue : NikonTheme.accentBlueLight)
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
            
            // 4. 内容展示 (网格 / 列表 / 空状态)
            ScrollView(showsIndicators: false) {
                if filteredItems.isEmpty {
                    emptyGalleryStateView
                        .padding(.horizontal, 18)
                        .padding(.top, 20)
                } else if isGridView {
                    mediaGridView
                        .padding(.horizontal, 18)
                } else {
                    mediaListView
                        .padding(.horizontal, 18)
                }
                
                Spacer(minLength: 100)
            }
            
            // v1.0.18：多选操作条（选图后批量保存到相册 / 批量分享）
            if isSelecting {
                HStack(spacing: 10) {
                    Text(batchSaving ? "正在保存 \(batchProgress.0)/\(batchProgress.1)…" : isBatchSharing ? "正在取原图…" : "已选 \(selectedFilenames.count) 张")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                    Spacer()
                    Button("取消") {
                        NikonTheme.triggerHaptic(style: .light)
                        isSelecting = false
                        selectedFilenames.removeAll()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NikonTheme.textSecondary)
                    Button("分享") {
                        NikonTheme.triggerHaptic(style: .light)
                        shareSelected()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(NikonTheme.accentBlue)
                    .disabled(selectedFilenames.isEmpty || batchSaving || isBatchSharing)
                    Button("保存到相册") {
                        NikonTheme.triggerHaptic(style: .light)
                        saveSelected()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedFilenames.isEmpty || batchSaving || isBatchSharing ? NikonTheme.textTertiary.opacity(0.4) : NikonTheme.accentBlue)
                    .cornerRadius(10)
                    .disabled(selectedFilenames.isEmpty || batchSaving || isBatchSharing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(NikonTheme.surfaceCard)
                .overlay(Rectangle().frame(height: 1).foregroundColor(NikonTheme.borderDim), alignment: .top)
            }
        }
        .background(NikonTheme.bgPure.ignoresSafeArea())
        .onAppear {
            // v1.0.3：进图库页时若已连相机，拉取卡内真实文件列表
            //（之前没有任何地方调用拉取，图库永远是空的）
            if connectionService.isConnected {
                syncService.refreshIndexFromCamera()
            }
        }
        .sheet(item: $selectedItemForDetail) { item in
            PhotoExportSheet(item: item)
        }
        .sheet(item: $batchShare) { batch in
            ActivityShareView(activityItems: batch.urls)
        }
        .alert("保存完成", isPresented: $showBatchResult) {
            Button("好的", role: .cancel) { batchResult = nil }
        } message: {
            if let r = batchResult {
                Text(r.0 == r.1 ? "已存入手机 \(r.0) 张。" : "已存入手机 \(r.0) 张，失败 \(r.1 - r.0) 张（相机连接可能断了，可以再选一次）。")
            }
        }
    }
    
    // MARK: - v1.0.18：多选批量保存 / 分享
    private var selectedItems: [CameraMediaItem] {
        syncService.mediaItems.filter { selectedFilenames.contains($0.filename) }
    }

    private func cellTapped(_ item: CameraMediaItem) {
        NikonTheme.triggerHaptic(style: .light)
        if isSelecting {
            if selectedFilenames.contains(item.filename) {
                selectedFilenames.remove(item.filename)
            } else {
                selectedFilenames.insert(item.filename)
            }
        } else {
            selectedItemForDetail = item
        }
    }

    private func saveSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        batchSaving = true
        batchProgress = (0, items.count)
        syncService.saveItems(items, progress: { done, total in
            DispatchQueue.main.async { self.batchProgress = (done, total) }
        }, completion: { succeeded, total in
            DispatchQueue.main.async {
                self.batchSaving = false
                self.batchResult = (succeeded, total)
                self.showBatchResult = true
                if succeeded == total {
                    self.isSelecting = false
                    self.selectedFilenames.removeAll()
                }
            }
        })
    }

    private func shareSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isBatchSharing = true
        syncService.downloadItemsData(items) { results in
            DispatchQueue.main.async {
                self.isBatchSharing = false
                guard !results.isEmpty else { return }
                var urls: [URL] = []
                for (filename, data) in results {
                    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
                    if (try? data.write(to: url)) != nil { urls.append(url) }
                }
                guard !urls.isEmpty else { return }
                self.batchShare = ShareBatch(urls: urls)
            }
        }
    }
    
    // MARK: - 无照片时的纯净空状态
    private var emptyGalleryStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sdcard")
                .font(.system(size: 50))
                .foregroundColor(NikonTheme.accentBlue.opacity(0.4))
                .padding(.top, 40)
            
            VStack(spacing: 6) {
                Text(!connectionService.isConnected ? "未连接相机" : syncService.mediaItems.isEmpty ? (syncService.isSyncingIndex ? "正在读取相机存储卡…" : "相机卡内暂无照片") : "当前分类暂无素材")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                
                Text(!connectionService.isConnected ? "请先在「连接」页连上相机（USB-C 或 Wi-Fi 热点）" : syncService.mediaItems.isEmpty ? "请确认相机已开机、卡内有照片" : "请切换上方分类查看其他照片")
                    .font(.system(size: 13))
                    .foregroundColor(NikonTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background(NikonTheme.surfaceCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.2))
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
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
                    cellTapped(item)
                }) {
                    ZStack(alignment: .bottomLeading) {
                        GalleryThumbImage(item: item)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .cornerRadius(10)
                        
                        Text(item.format.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelecting {
                            Image(systemName: selectedFilenames.contains(item.filename) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedFilenames.contains(item.filename) ? NikonTheme.accentBlue : .white)
                                .shadow(color: .black.opacity(0.35), radius: 3)
                                .padding(6)
                        }
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
                    cellTapped(item)
                }) {
                    HStack(spacing: 12) {
                        GalleryThumbImage(item: item)
                            .frame(width: 54, height: 54)
                            .clipped()
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.filename)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(NikonTheme.textPrimary)
                            Text("\(item.format.rawValue) · \(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 11))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        if isSelecting {
                            Image(systemName: selectedFilenames.contains(item.filename) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedFilenames.contains(item.filename) ? NikonTheme.accentBlue : NikonTheme.textTertiary)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
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
    @ObservedObject var syncService = MediaSyncService.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var isSavedAlert = false
    @State private var isSaving = false
    @State private var savedOK: Bool?
    // v1.0.17：详情预览图 + 系统分享
    @State private var previewImage: UIImage?
    @State private var shareItem: ShareItem?
    @State private var isSharing = false
    
    public init(item: CameraMediaItem) {
        self.item = item
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // v1.0.17：有缩略图就显示真图（点进来的格子一般已经取到了），
                // 没取到就显示占位信息。文件名和时间是相机给的——相机时钟
                // 快几分钟，显示的时间就比手机快几分钟（去相机设定菜单校准）。
                Group {
                    if let previewImage = previewImage {
                        VStack(spacing: 8) {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .background(Color(red: 0.94, green: 0.95, blue: 0.97))
                                .cornerRadius(12)
                            Text(item.filename)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(NikonTheme.textPrimary)
                            Text("\(item.formattedSize) · \(item.formattedTime)")
                                .font(.system(size: 11))
                                .foregroundColor(NikonTheme.textTertiary)
                        }
                    } else {
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .onAppear {
                    syncService.thumbnail(for: item) { data in
                        guard let data = data, let image = UIImage(data: data) else { return }
                        DispatchQueue.main.async { previewImage = image }
                    }
                }
                
                // 核心导出保存按钮
                VStack(spacing: 12) {
                    Button(action: {
                        // v1.0.3：之前点保存只弹“保存成功”，其实什么都没存。
                        // 现在真实从相机下载原图再存入相册。
                        NikonTheme.triggerHaptic(style: .heavy)
                        guard !isSaving else { return }
                        isSaving = true
                        syncService.downloadAndSaveToPhotos(item: item) { ok in
                            DispatchQueue.main.async {
                                isSaving = false
                                savedOK = ok
                                isSavedAlert = true
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text(isSaving ? "正在从相机下载…" : "无损保存原图到系统相册")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(NikonTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: NikonTheme.accentBlue.opacity(0.3), radius: 8, x: 0, y: 3)
                    }
                    .disabled(isSaving)
                    
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        guard !isSharing else { return }
                        isSharing = true
                        // v1.0.17：之前这个按钮只震一下，什么都不干。现在先把原图
                        // 下到临时文件，再调系统分享（隔空投送/微信/保存到文件都在里面）。
                        // 下不下来就不弹分享，不静默假装成功。
                        syncService.downloadOriginalData(item: item) { data in
                            DispatchQueue.main.async {
                                isSharing = false
                                guard let data = data else { return }
                                let url = URL(fileURLWithPath: NSTemporaryDirectory())
                                    .appendingPathComponent(item.filename)
                                do {
                                    try data.write(to: url)
                                    shareItem = ShareItem(url: url)
                                } catch {
                                    // 写临时文件失败就不弹分享
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text(isSharing ? "正在准备分享文件…" : "隔空投送 / 系统分享")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(NikonTheme.bgSubtle)
                        .foregroundColor(NikonTheme.textPrimary)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                    }
                    .disabled(isSharing)
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
                    title: Text(savedOK == true ? "保存成功" : "保存失败"),
                    message: Text(savedOK == true ? "已将 \(item.filename) 成功存入 iPhone 系统相册！" : "下载失败，请确认相机仍处于连接状态后重试。"),
                    dismissButton: .default(Text("好的"))
                )
            }
            .sheet(item: $shareItem) { item in
                ActivityShareView(activityItems: [item.url])
            }
        }
    }
}

/// v1.0.17：图库格子/列表/详情共用的缩略图。之前格子只画占位图标，
/// 是因为根本没人取过缩略图；现在格子露出来时懒加载取一张，取到就显示。
/// v1.0.17：图库缩略图（懒加载 GetThumb）。v1.0.18 起模块内可见，
/// 取景页的本次拍摄条也用它显示缩略图。
struct GalleryThumbImage: View {
    let item: CameraMediaItem
    @ObservedObject var syncService = MediaSyncService.shared
    @State private var thumb: UIImage?

    var body: some View {
        Group {
            if let thumb = thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                    .overlay(
                        Image(systemName: item.format == .rawNEF ? "camera.metering.matrix" : "photo")
                            .font(.system(size: 24))
                            .foregroundColor(NikonTheme.accentBlue.opacity(0.5))
                    )
            }
        }
        .onAppear {
            guard thumb == nil else { return }
            syncService.thumbnail(for: item) { data in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { thumb = image }
            }
        }
    }
}

/// v1.0.17：系统分享用的临时文件包装。
/// v1.0.18：多选分享的临时文件包
struct ShareBatch: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// v1.0.17：UIActivityViewController 的 SwiftUI 包装。之前分享按钮
/// 只有震动没有分享，就是缺了这层。
private struct ActivityShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
