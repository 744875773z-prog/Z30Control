//
//  NP3FilterView.swift
//  Z30Control
//
//  v1.0.27：图库照片详情页的“滤镜”入口。
//  选一份已导入的 .NP3 配方，在当前照片上预览效果，
//  再点“保存滤镜版”把套用后的照片存到系统相册。
//  只做色彩（色调、饱和、调色），锐化/清晰度这次不渲染；
//  效果接近相机直出，不是 100% 一样。
//

import SwiftUI

public struct NP3FilterView: View {
    public let item: CameraMediaItem
    public let originalImage: UIImage

    @ObservedObject var store = NP3RecipeStore.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var selectedRecipeID: String?
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var renderToken = 0
    @State private var showImporter = false
    @State private var isSaving = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    public init(item: CameraMediaItem, originalImage: UIImage) {
        self.item = item
        self.originalImage = originalImage
    }

    private var selectedRecipe: NP3Recipe? {
        guard let id = selectedRecipeID else { return nil }
        return store.recipes.first { $0.id == id }
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // 预览图（选配方后渲，渲好之前显示原图）
                ZStack {
                    Image(uiImage: previewImage ?? originalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .background(Color.black)
                        .cornerRadius(12)
                    if isRendering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // 导入 / 保存
                HStack(spacing: 10) {
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        showImporter = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("导入 .NP3 文件")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(NikonTheme.bgSubtle)
                        .foregroundColor(NikonTheme.textPrimary)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NikonTheme.borderDim, lineWidth: 1))
                    }
                    Button(action: { saveFiltered() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text(isSaving ? "保存中…" : "保存滤镜版")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selectedRecipe == nil || isRendering || isSaving ? NikonTheme.textTertiary.opacity(0.4) : NikonTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedRecipe == nil || isRendering || isSaving)
                }
                .padding(.horizontal, 16)

                // 配方列表（第一行是原图）
                List {
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .light)
                        selectRecipe(nil)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("原图（不套滤镜）")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(NikonTheme.textPrimary)
                                Text("对比一下效果")
                                    .font(.system(size: 11))
                                    .foregroundColor(NikonTheme.textTertiary)
                            }
                            Spacer()
                            if selectedRecipeID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(NikonTheme.accentBlue)
                            }
                        }
                    }
                    ForEach(store.recipes) { recipe in
                        Button(action: {
                            NikonTheme.triggerHaptic(style: .light)
                            selectRecipe(recipe)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(NikonTheme.textPrimary)
                                    Text(recipeSummary(recipe))
                                        .font(.system(size: 11))
                                        .foregroundColor(NikonTheme.textTertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if selectedRecipeID == recipe.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(NikonTheme.accentBlue)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteRecipes)
                }
                .listStyle(PlainListStyle())

                Text("只做色彩，锐化/清晰度这次不渲；效果接近相机直出，不是 100% 一样。")
                    .font(.system(size: 11))
                    .foregroundColor(NikonTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .background(NikonTheme.bgPure.ignoresSafeArea())
            .navigationTitle("滤镜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                NP3DocumentPickerSheet { url in
                    importPickedFile(url)
                }
            }
            // v1.0.26：新式 alert 是 iOS 15 才有的；14 上用老式 Alert，
            // 一个 alert 盖住导入失败和保存结果两种情况。
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("好的"))
                )
            }
            .onAppear {
                if store.recipes.isEmpty {
                    // 第一次进来没配方也别空着，等用户导入
                }
            }
        }
    }

    private func recipeSummary(_ recipe: NP3Recipe) -> String {
        var parts: [String] = []
        if let control = store.control(for: recipe) {
            parts.append(store.paramSummary(for: control))
        }
        if let comment = recipe.comment, !comment.isEmpty {
            parts.append(comment)
        }
        return parts.joined(separator: " · ")
    }

    private func selectRecipe(_ recipe: NP3Recipe?) {
        selectedRecipeID = recipe?.id
        renderPreview(for: recipe)
    }

    private func renderPreview(for recipe: NP3Recipe?) {
        renderToken += 1
        let token = renderToken
        guard let recipe = recipe,
              let control = store.control(for: recipe) else {
            previewImage = originalImage
            isRendering = false
            return
        }
        isRendering = true
        let base = originalImage
        DispatchQueue.global(qos: .userInitiated).async {
            let out = NP3LUTRenderer.shared.apply(control: control, to: base)
            DispatchQueue.main.async {
                guard token == self.renderToken else { return }
                self.previewImage = out ?? base
                self.isRendering = false
            }
        }
    }

    private func importPickedFile(_ url: URL) {
        switch store.importRecipe(from: url) {
        case .success(let recipe):
            selectRecipe(recipe)
        case .failure(let error):
            presentAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            let recipe = store.recipes[index]
            if recipe.id == selectedRecipeID {
                selectRecipe(nil)
            }
            store.deleteRecipe(recipe)
        }
    }

    private func saveFiltered() {
        guard let recipe = selectedRecipe,
              let image = previewImage else { return }
        isSaving = true
        let baseName = (item.filename as NSString).deletingPathExtension
        let safeRecipeName = recipe.name
            .map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " ") ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: " ", with: "-")
        let outName = "\(baseName)-\(safeRecipeName).jpg"
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = NP3LUTRenderer.shared.jpegData(of: image) else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.presentAlert(title: "没存上", message: "图片压成 JPEG 失败了，再试一次。")
                }
                return
            }
            MediaSyncService.shared.saveFilteredImageData(data, filename: outName) { ok in
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.presentAlert(
                        title: ok ? "已保存到相册" : "没存上",
                        message: ok ? "滤镜版已存入系统相册。" : "相册写入失败，检查一下相册权限。"
                    )
                }
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
