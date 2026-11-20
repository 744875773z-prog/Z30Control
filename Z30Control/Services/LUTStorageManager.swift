//
//  LUTStorageManager.swift
//  Z30Control
//
//  用户外部 3D LUT (.cube) 文件导入、沙盒持久化与文件选择器
//

import SwiftUI
import UniformTypeIdentifiers

public final class LUTStorageManager: ObservableObject {
    public static let shared = LUTStorageManager()
    
    @Published public var customFilters: [LUTFilter] = []
    
    private var userLUTsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let lutsDir = docs.appendingPathComponent("UserLUTs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: lutsDir.path) {
            try? FileManager.default.createDirectory(at: lutsDir, withIntermediateDirectories: true)
        }
        return lutsDir
    }
    
    private init() {
        reloadCustomFilters()
    }
    
    // MARK: - 重新加载沙盒中的全部用户自定义 LUT
    public func reloadCustomFilters() {
        var results: [LUTFilter] = []
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: userLUTsDirectory.path) else {
            return
        }
        
        for file in files where file.lowercased().hasSuffix(".cube") {
            let filterName = file.replacingOccurrences(of: ".cube", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .uppercased()
            let filePath = userLUTsDirectory.appendingPathComponent(file).path
            
            let filter = LUTFilter(
                id: "custom_\(file)",
                name: filterName,
                category: .custom,
                subtitle: "用户导入 3D LUT",
                intensity: 1.0,
                cubeFileName: filePath,
                isBuiltIn: false
            )
            results.append(filter)
        }
        
        DispatchQueue.main.async {
            self.customFilters = results
        }
    }
    
    // MARK: - 从外部 URL (微信/文件App/iCloud) 导入并写入沙盒
    public func importCube(from sourceURL: URL) -> Bool {
        // 请求安全作用域访问权限
        let isAccessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessGranted { sourceURL.stopAccessingSecurityScopedResource() }
        }
        
        do {
            let content = try String(contentsOf: sourceURL, encoding: .utf8)
            // 简单校验是否为合法的 .cube 文件
            guard content.contains("LUT_3D_SIZE") || content.contains("TITLE") else {
                return false
            }
            
            let fileName = sourceURL.lastPathComponent
            let targetURL = userLUTsDirectory.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            reloadCustomFilters()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - 删除自定义 LUT
    public func deleteCustomFilter(id: String) {
        guard let item = customFilters.first(where: { $0.id == id }),
              let path = item.cubeFileName else { return }
        
        try? FileManager.default.removeItem(atPath: path)
        reloadCustomFilters()
    }
}

// MARK: - 系统文件选择器 (UIDocumentPickerViewController 桥接)
#if canImport(UIKit)
public struct DocumentPickerSheet: UIViewControllerRepresentable {
    public var onDocumentPicked: (URL) -> Void
    
    public init(onDocumentPicked: @escaping (URL) -> Void) {
        self.onDocumentPicked = onDocumentPicked
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 支持所有数据文件或 .cube 扩展名
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerSheet
        
        init(_ parent: DocumentPickerSheet) {
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
