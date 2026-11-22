//
//  NP3RecipeStore.swift
//  Z30Control
//
//  v1.0.27：用户自己导入的 .NP3 配方文件：沙盒持久化、列表、删除。
//  做法照着 LUTStorageManager（Documents/UserLUTs）抄：
//  配方存在 Documents/NP3Recipes，App 重启还在。
//  注意：App 里不内置任何配方文件（版权原因——配方是各作者的创作，
//  免费下载不等于可以打包分发），只做用户自己导入。
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 一份已导入的配方（列表行用；参数现用现解析，不另外存一份）
public struct NP3Recipe: Identifiable, Equatable {
    public let id: String
    public let fileName: String
    public let name: String
    public let comment: String?
    public let importedAt: Date
}

public enum NP3ImportError: Error, LocalizedError {
    case unreadable
    case parseFailed(String)
    case copyFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            return "这个文件打不开，换个位置再试一次。"
        case .parseFailed(let detail):
            return detail
        case .copyFailed:
            return "文件存不进 App，可能是存储空间满了。"
        }
    }
}

public final class NP3RecipeStore: ObservableObject {
    public static let shared = NP3RecipeStore()

    @Published public private(set) var recipes: [NP3Recipe] = []

    public var recipesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("NP3Recipes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        reload()
    }

    // MARK: - 重新扫描沙盒里的 .NP3（解析不出来的跳过，不删用户文件）
    public func reload() {
        var results: [NP3Recipe] = []
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recipesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            DispatchQueue.main.async { self.recipes = [] }
            return
        }
        for url in files where url.pathExtension.lowercased() == "np3" {
            guard let data = try? Data(contentsOf: url),
                  let control = try? NP3Parser.parse(data) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            results.append(NP3Recipe(
                id: url.lastPathComponent,
                fileName: url.lastPathComponent,
                name: control.name,
                comment: control.comment,
                importedAt: date
            ))
        }
        results.sort { $0.importedAt > $1.importedAt }
        let sorted = results
        DispatchQueue.main.async { self.recipes = sorted }
    }

    // MARK: - 从文件选择器导入一份配方
    public func importRecipe(from sourceURL: URL) -> Result<NP3Recipe, NP3ImportError> {
        let isAccessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessGranted { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: sourceURL) else {
            return .failure(.unreadable)
        }
        let control: NP3PictureControl
        do {
            control = try NP3Parser.parse(data)
        } catch let err as NP3ParseError {
            return .failure(.parseFailed(err.localizedDescription))
        } catch {
            return .failure(.parseFailed(NP3ParseError.badMagic.localizedDescription))
        }
        var fileName = sourceURL.lastPathComponent
        if !fileName.lowercased().hasSuffix(".np3") {
            fileName += ".np3"
        }
        var targetURL = recipesDirectory.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: targetURL.path) {
            let stem = (fileName as NSString).deletingPathExtension
            targetURL = recipesDirectory.appendingPathComponent("\(stem)-\(n).np3")
            n += 1
        }
        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            return .failure(.copyFailed)
        }
        let recipe = NP3Recipe(
            id: targetURL.lastPathComponent,
            fileName: targetURL.lastPathComponent,
            name: control.name,
            comment: control.comment,
            importedAt: Date()
        )
        reload()
        return .success(recipe)
    }

    /// 取一份配方的全部参数（现解析）
    public func control(for recipe: NP3Recipe) -> NP3PictureControl? {
        let url = recipesDirectory.appendingPathComponent(recipe.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NP3Parser.parse(data)
    }

    /// 列表行里的一行参数摘要（让人一眼看出这个配方是啥风格）
    public func paramSummary(for control: NP3PictureControl) -> String {
        var parts: [String] = []
        if control.contrast != 0 { parts.append("对比 \(control.contrast)") }
        if control.saturation != 0 { parts.append("饱和 \(control.saturation)") }
        if control.colorBlender.green.chroma != 0 {
            parts.append("绿色 \(control.colorBlender.green.chroma)")
        }
        if control.toneCurve != nil { parts.append("自定义曲线") }
        if parts.isEmpty { parts.append("标准配方") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 删除一份配方
    public func deleteRecipe(_ recipe: NP3Recipe) {
        let url = recipesDirectory.appendingPathComponent(recipe.fileName)
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}

// MARK: - 只选 .NP3 的系统文件选择器（照着 LUTStorageManager 的 DocumentPickerSheet 抄）
#if canImport(UIKit)
public struct NP3DocumentPickerSheet: UIViewControllerRepresentable {
    public var onDocumentPicked: (URL) -> Void

    public init(onDocumentPicked: @escaping (URL) -> Void) {
        self.onDocumentPicked = onDocumentPicked
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // iOS 14 就有的初始化方法；.np3 没有系统类型，用扩展名现取，取不到退回 .data
        let np3Type = UTType(filenameExtension: "np3") ?? UTType.data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [np3Type], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NP3DocumentPickerSheet

        init(_ parent: NP3DocumentPickerSheet) {
            self.parent = parent
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let firstURL = urls.first {
                parent.onDocumentPicked(firstURL)
            }
        }
    }
}
#endif
