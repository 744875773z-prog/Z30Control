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
    // v1.0.19：批量删除机内照片（删了就真没了，先弹确认框）
    @State private var batchDeleting = false
    @State private var showDeleteConfirm = false
    @State private var batchDeleteResult: (Int, Int)?
    @State private var showBatchDeleteResult = false
    
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
            // v1.0.19：加了批量删除（删机内照片，先弹确认框）
            if isSelecting {
                HStack(spacing: 10) {
                    Text(batchSaving ? "正在保存 \(batchProgress.0)/\(batchProgress.1)…" : batchDeleting ? "正在删除 \(batchProgress.0)/\(batchProgress.1)…" : isBatchSharing ? "正在取原图…" : "已选 \(selectedFilenames.count) 张")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                    Spacer()
                    Button("删除") {
                        NikonTheme.triggerHaptic(style: .light)
                        showDeleteConfirm = true
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .disabled(selectedFilenames.isEmpty || batchSaving || isBatchSharing || batchDeleting)
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
                    .disabled(selectedFilenames.isEmpty || batchSaving || isBatchSharing || batchDeleting)
                    Button("保存到相册") {
                        NikonTheme.triggerHaptic(style: .light)
                        saveSelected()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedFilenames.isEmpty || batchSaving || isBatchSharing || batchDeleting ? NikonTheme.textTertiary.opacity(0.4) : NikonTheme.accentBlue)
                    .cornerRadius(10)
                    .disabled(selectedFilenames.isEmpty || batchSaving || isBatchSharing || batchDeleting)
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
        // v1.0.26：新式 alert（带 actions/message 闭包）是 iOS 15 才有的；
        // 14 上用老式 Alert。
        .alert(isPresented: $showBatchResult) {
            Alert(
                title: Text("保存完成"),
                message: Text(batchResult.map { r in
                    r.0 == r.1 ? "已存入手机 \(r.0) 张。" : "已存入手机 \(r.0) 张，失败 \(r.1 - r.0) 张（相机连接可能断了，可以再选一次）。"
                } ?? ""),
                dismissButton: .default(Text("好的")) { batchResult = nil }
            )
        }
        // v1.0.19：批量删除确认 + 结果汇总（删了就真没了）
        // v1.0.26：新式 alert 是 iOS 15 才有的；14 上用老式 Alert。
        .alert(isPresented: $showDeleteConfirm) {
            Alert(
                title: Text("删除照片"),
                message: Text("将从相机存储卡中永久删除选中的 \(selectedFilenames.count) 张照片，无法恢复。"),
                primaryButton: .destructive(Text("删除 \(selectedFilenames.count) 张")) {
                    deleteSelected()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(isPresented: $showBatchDeleteResult) {
            Alert(
                title: Text("删除完成"),
                message: Text(batchDeleteResult.map { r in
                    r.0 == r.1 ? "已删除 \(r.0) 张。" : "已删除 \(r.0) 张，失败 \(r.1 - r.0) 张（句柄映射表可能还没建好，或相机断了，可以再选一次）。"
                } ?? ""),
                dismissButton: .default(Text("好的")) { batchDeleteResult = nil }
            )
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

    // v1.0.19：批量删除机内照片（先弹确认框，进来时已经确认过了）
    private func deleteSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        batchDeleting = true
        batchProgress = (0, items.count)
        syncService.deleteItems(items, progress: { done, total in
            DispatchQueue.main.async { self.batchProgress = (done, total) }
        }, completion: { succeeded, total in
            DispatchQueue.main.async {
                self.batchDeleting = false
                self.batchDeleteResult = (succeeded, total)
                self.showBatchDeleteResult = true
                if succeeded == total {
                    self.isSelecting = false
                    self.selectedFilenames.removeAll()
                }
            }
        })
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
                    // v1.0.26：闭包式 overlay(alignment:) 是 iOS 15 才有的；
                    // 14 上把内容包进 Group 当普通视图传进去。
                    .overlay(Group {
                        if isSelecting {
                            Image(systemName: selectedFilenames.contains(item.filename) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedFilenames.contains(item.filename) ? NikonTheme.accentBlue : .white)
                                .shadow(color: .black.opacity(0.35), radius: 3)
                                .padding(6)
                        }
                    }, alignment: .topTrailing)
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

/// v1.0.19：照片显示方向固定——点开一张图后转横/转竖，记下来，
/// 切页面、退后台、重启 App 都不变，直到再点旋转。存在 UserDefaults，
/// 按文件名记（DSC_xxxx 不重名）。
enum PhotoRotationStore {
    static func rotation(for filename: String) -> Int {
        UserDefaults.standard.integer(forKey: "z30.photoRotation.\(filename)")
    }
    static func setRotation(_ degrees: Int, for filename: String) {
        UserDefaults.standard.set(degrees % 360, forKey: "z30.photoRotation.\(filename)")
    }
}

/// 照片原图查看器（v1.0.19 重写）
/// 点开一张图直接下原图显示（之前只显示 160px 小缩略图，糊）；保存和
/// 分享不在这里——只在图库总页面多选里做。NEF 原图手机解不出来时退回
/// 内嵌预览图。旋转按钮转 90°，记下来固定住，切页面也不变。
public struct PhotoExportSheet: View {
    public let item: CameraMediaItem
    @ObservedObject var syncService = MediaSyncService.shared
    @Environment(\.presentationMode) var presentationMode
    // v1.0.19：原图 + 旋转 + 双指缩放
    @State private var fullImage: UIImage?
    @State private var isLoadingOriginal = true
    @State private var loadFailed = false
    @State private var rotation: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    public init(item: CameraMediaItem) {
        self.item = item
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Group {
                    if let fullImage = fullImage {
                        Image(uiImage: fullImage)
                            .resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(Double(rotation)))
                            .scaleEffect(scale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, min(4.0, lastScale * value))
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .cornerRadius(12)
                            .onTapGesture(count: 2) {
                                withAnimation { scale = 1.0; lastScale = 1.0 }
                            }
                    } else if isLoadingOriginal {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                            .frame(height: 320)
                            .overlay(
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在从相机下载原图…")
                                        .font(.system(size: 13))
                                        .foregroundColor(NikonTheme.textSecondary)
                                }
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                            .frame(height: 320)
                            .overlay(
                                VStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundColor(NikonTheme.textTertiary)
                                    Text("原图没下下来，相机可能断了")
                                        .font(.system(size: 13))
                                        .foregroundColor(NikonTheme.textSecondary)
                                    Button("再试一次") { loadOriginal() }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(NikonTheme.accentBlue)
                                }
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .onAppear {
                    rotation = PhotoRotationStore.rotation(for: item.filename)
                    loadOriginal()
                }

                VStack(spacing: 6) {
                    Text(item.filename)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(NikonTheme.textPrimary)
                    Text("\(item.formattedSize) · \(item.formattedTime)")
                        .font(.system(size: 11))
                        .foregroundColor(NikonTheme.textTertiary)
                }

                // 旋转：横/竖显示切换后固定住（记下来，切页面也不变）
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    rotation = (rotation + 90) % 360
                    PhotoRotationStore.setRotation(rotation, for: item.filename)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rotate.right")
                        Text("旋转 90°（已转 \(rotation)°）")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(NikonTheme.bgSubtle)
                    .foregroundColor(NikonTheme.textPrimary)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                }
                .padding(.horizontal, 16)

                Text("保存和分享在图库总页面：右上角“选择”，勾上照片后批量保存/分享。")
                    .font(.system(size: 12))
                    .foregroundColor(NikonTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .background(NikonTheme.bgPure.ignoresSafeArea())
            .navigationTitle(item.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func loadOriginal() {
        isLoadingOriginal = true
        loadFailed = false
        fullImage = nil
        syncService.downloadOriginalData(item: item) { data in
            guard let data = data, let image = UIImage(data: data) else {
                // 原图下不来或解不出来（NEF）：退回小缩略图，别空着
                syncService.thumbnail(for: item) { thumbData in
                    DispatchQueue.main.async {
                        if let thumbData = thumbData, let thumb = UIImage(data: thumbData) {
                            self.fullImage = thumb
                            self.isLoadingOriginal = false
                        } else {
                            self.isLoadingOriginal = false
                            self.loadFailed = true
                        }
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.fullImage = image
                self.isLoadingOriginal = false
            }
        }
    }
}

/// v1.0.17：图库格子/列表/详情共用的缩略图。之前格子只画占位图标，
/// 是因为根本没人取过缩略图；现在格子露出来时懒加载取一张，取到就显示。
/// v1.0.17：图库缩略图（懒加载 GetThumb）。v1.0.18 起模块内可见，
/// 取景页的本次拍摄条也用它显示缩略图。
/// v1.0.19：GetThumb 下不来时退回原图（下原图再缩到格子大小），不然
/// 格子永久占位；显示方向跟详情页的旋转设置走（转了就固定住）。
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
                    .rotationEffect(.degrees(Double(PhotoRotationStore.rotation(for: item.filename))))
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
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async { thumb = image }
                    return
                }
                // v1.0.19：缩略图下不来（新照片句柄还没进映射表、NEF 没内嵌
                // 预览），直接下原图缩到格子大小，总比占位图强。
                syncService.downloadOriginalData(item: item) { raw in
                    guard let raw = raw, let image = UIImage(data: raw) else { return }
                    let small = Self.downscaled(image, maxDimension: 360)
                    DispatchQueue.main.async { thumb = small }
                }
            }
        }
    }

    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// v1.0.17：系统分享用的临时文件包装。
/// v1.0.18：多选分享的临时文件包
struct ShareBatch: Identifiable {
    let id = UUID()
    let urls: [URL]
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
