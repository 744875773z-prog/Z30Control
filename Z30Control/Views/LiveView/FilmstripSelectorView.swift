//
//  FilmstripSelectorView.swift
//  Z30Control
//
//  胶卷暗盒式 3D LUT 滤镜滑轨选择器 (支持内置滤镜与外部导入真实持久化)
//

import SwiftUI

public struct FilmstripSelectorView: View {
    @ObservedObject var streamService: LiveViewStreamService
    @ObservedObject var lutStorage = LUTStorageManager.shared
    @State private var showingImportPicker = false
    @State private var importErrorMessage: String? = nil
    
    public init(streamService: LiveViewStreamService) {
        self.streamService = streamService
    }
    
    // 合并内置经典预设与用户沙盒导入的自定义预设
    private var allDisplayFilters: [LUTFilter] {
        return LUTFilter.builtinPresets + lutStorage.customFilters
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 原画直出按钮 (关闭 LUT)
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    streamService.isLUTEnabled = false
                    streamService.setFilter(nil)
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "camera.filters")
                            .font(.system(size: 14))
                        Text("ORIGINAL")
                            .proHUDText(size: 10, weight: .bold)
                    }
                    .frame(width: 76, height: 42)
                    .background(streamService.activeFilter == nil || !streamService.isLUTEnabled ? NikonTheme.nikonYellow.opacity(0.2) : Color.white.opacity(0.06))
                    .foregroundColor(streamService.activeFilter == nil || !streamService.isLUTEnabled ? NikonTheme.nikonYellow : .white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(streamService.activeFilter == nil || !streamService.isLUTEnabled ? NikonTheme.nikonYellow : Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                
                // 经典胶片与用户导入的全部 LUT 列表
                ForEach(allDisplayFilters, id: \.id) { (filter: LUTFilter) in
                    let isSelected = streamService.activeFilter?.id == filter.id && streamService.isLUTEnabled
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        streamService.isLUTEnabled = true
                        streamService.setFilter(filter)
                    }) {
                        VStack(spacing: 1) {
                            Text(filter.name)
                                .proHUDText(size: 10, weight: .heavy)
                                .lineLimit(1)
                            Text(filter.category.rawValue)
                                .font(.system(size: 8))
                                .foregroundColor(isSelected ? NikonTheme.nikonYellow.opacity(0.9) : .gray)
                        }
                        .frame(width: 86, height: 42)
                        .background(isSelected ? NikonTheme.nikonYellow.opacity(0.18) : Color.white.opacity(0.05))
                        .foregroundColor(isSelected ? NikonTheme.nikonYellow : .white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? NikonTheme.nikonYellow : Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                }
                
                // 导入外部 .cube 滤镜按钮
                Button(action: {
                    NikonTheme.triggerHaptic(style: .medium)
                    showingImportPicker = true
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                        Text("导入LUT")
                            .proHUDText(size: 9, weight: .bold)
                    }
                    .frame(width: 65, height: 42)
                    .background(Color.white.opacity(0.05))
                    .foregroundColor(.white.opacity(0.7))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 50)
        .sheet(isPresented: $showingImportPicker) {
            #if canImport(UIKit)
            DocumentPickerSheet { url in
                let success = lutStorage.importCube(from: url)
                if success {
                    NikonTheme.triggerHaptic(style: .heavy)
                    // 自动选中新导入的滤镜
                    if let newest = lutStorage.customFilters.last {
                        streamService.isLUTEnabled = true
                        streamService.setFilter(newest)
                    }
                } else {
                    importErrorMessage = "导入失败：选中的文件非合法的 .cube 3D LUT"
                }
            }
            #endif
        }
    }
}
