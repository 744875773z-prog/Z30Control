//
//  UsbCameraManager.swift
//  Z30Control
//
//  基于 Apple 原生 ImageCaptureCore 框架的 USB 数码相机硬件级直连管理器 (像素蛋糕同款底层)
//  适配 iOS 16/17/18 严格协议签名
//

import Foundation
import ImageCaptureCore
import UIKit
import Combine

public final class UsbCameraManager: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    
    public static let shared = UsbCameraManager()
    
    // 状态发布
    @Published public var isUsbConnected: Bool = false
    @Published public var connectedDeviceName: String = ""
    @Published public var lastCapturedPhoto: UIImage? = nil
    @Published public var lastCapturedFilename: String = ""
    @Published public var lastCapturedExif: String = ""
    @Published public var sessionCapturedPhotos: [CapturedPhotoItem] = []
    
    // 设备浏览器与当前相机实例
    private var deviceBrowser: ICDeviceBrowser?
    public private(set) var activeCamera: ICCameraDevice?
    
    public struct CapturedPhotoItem: Identifiable {
        public let id = UUID()
        public let filename: String
        public let image: UIImage?
        public let date: Date
        public let sizeString: String
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - 启动 USB 硬件相机设备监听
    public func startListening() {
        if deviceBrowser == nil {
            let browser = ICDeviceBrowser()
            browser.delegate = self
            self.deviceBrowser = browser
        }
        deviceBrowser?.start()
        print("[UsbCameraManager] 已启动 ImageCaptureCore USB 相机总线监听...")
    }
    
    public func stopListening() {
        deviceBrowser?.stop()
        activeCamera?.requestCloseSession()
        activeCamera = nil
        isUsbConnected = false
        print("[UsbCameraManager] 已停止 USB 监听")
    }
    
    // MARK: - ICDeviceBrowserDelegate 回调
    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        print("[UsbCameraManager] 发现外接硬件设备: \(device.name ?? "未知设备")")
        guard let camera = device as? ICCameraDevice else { return }
        
        self.activeCamera = camera
        camera.delegate = self
        
        // 自动开启相机通信会话 (像素蛋糕同款握手逻辑)
        camera.requestOpenSession()
    }
    
    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        print("[UsbCameraManager] 外接设备已拔出: \(device.name ?? "")")
        if device == activeCamera {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activeCamera = nil
                self.isUsbConnected = false
                self.connectedDeviceName = ""
                CameraConnectionService.shared.isConnected = false
                CameraConnectionService.shared.statusMessage = "有线连接已断开"
                CameraConnectionService.shared.cameraState.isConnected = false
            }
        }
    }
    
    public func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
        if device == activeCamera {
            DispatchQueue.main.async {
                self.connectedDeviceName = device.name ?? "尼康相机"
            }
        }
    }
    
    // MARK: - ICDeviceDelegate (会话生命周期)
    public func deviceDidBecomeReady(_ device: ICDevice) {
        print("[UsbCameraManager] 设备已就绪: \(device.name ?? "")")
    }
    
    public func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error = error {
            print("[UsbCameraManager] 打开会话失败: \(error)")
            return
        }
        
        guard let camera = device as? ICCameraDevice else { return }
        print("[UsbCameraManager] 成功打开硬件会话: \(device.name ?? "")")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUsbConnected = true
            let devName = camera.name ?? "Nikon Z 30"
            self.connectedDeviceName = devName
            
            // 同步全局状态
            CameraConnectionService.shared.isConnected = true
            CameraConnectionService.shared.isConnecting = false
            CameraConnectionService.shared.statusMessage = "已通过 USB 硬件连接: \(devName)"
            CameraConnectionService.shared.selectedModel = devName
            CameraConnectionService.shared.cameraState.isConnected = true
            CameraConnectionService.shared.cameraState.modelName = devName
            
            NikonTheme.triggerHaptic(style: .heavy)
        }
    }
    
    public func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        print("[UsbCameraManager] 设备会话关闭: \(String(describing: error))")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUsbConnected = false
            CameraConnectionService.shared.isConnected = false
            CameraConnectionService.shared.cameraState.isConnected = false
            CameraConnectionService.shared.statusMessage = "相机连接已断开"
        }
    }
    
    // MARK: - ICCameraDeviceDelegate 必须实现的协议方法
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("[UsbCameraManager] 相机捕获到新素材，数量: \(items.count)")
        for item in items {
            guard let file = item as? ICCameraFile else { continue }
            print("[UsbCameraManager] 新拍摄照片: \(file.name ?? "未命名")")
            
            // 请求提取缩略图与元数据
            file.requestThumbnailData(options: nil)
            file.requestMetadata()
            
            // 请求下载文件到临时目录
            let dirUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            let downloadOptions: [String: Any] = [
                "ICDownloadsDirectoryURL": dirUrl,
                "ICSaveAsFilename": file.name ?? "capture.jpg"
            ]
            
            camera.requestDownloadFile(
                file,
                options: downloadOptions,
                downloadDelegate: self,
                didDownloadSelector: #selector(didDownloadPhoto(_:error:options:contextInfo:)),
                contextInfo: nil
            )
        }
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        print("[UsbCameraManager] 相机移除了素材: \(items.count)")
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {
        if let cgImg = thumbnail {
            let uiImg = UIImage(cgImage: cgImg)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastCapturedPhoto = uiImg
                self.lastCapturedFilename = item.name ?? "NEW_PHOTO.JPG"
            }
        }
    }
    
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: (any Error)?) {
        print("[UsbCameraManager] 收到照片元数据")
    }
    
    // MARK: - 下载完成 Selector 回调
    @objc private func didDownloadPhoto(_ file: ICCameraFile, error: Error?, options: [String: Any], contextInfo: UnsafeMutableRawPointer?) {
        if let error = error {
            print("[UsbCameraManager] 照片下载出错: \(error)")
            return
        }
        
        let savedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(file.name ?? "capture.jpg")
        print("[UsbCameraManager] 照片成功保存到本地临时路径: \(savedPath)")
        
        let loadedImage = UIImage(contentsOfFile: savedPath)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let name = file.name ?? "DSC_NEW.JPG"
            let sizeMb = Double(file.fileSize) / 1024.0 / 1024.0
            let sizeStr = String(format: "%.1f MB", sizeMb)
            
            if let img = loadedImage {
                self.lastCapturedPhoto = img
            }
            self.lastCapturedFilename = name
            self.lastCapturedExif = "原片传输 · \(sizeStr)"
            
            let item = CapturedPhotoItem(filename: name, image: loadedImage, date: Date(), sizeString: sizeStr)
            self.sessionCapturedPhotos.insert(item, at: 0)
            
            // 触感反馈提示
            NikonTheme.triggerHaptic(style: .medium)
            
            // 自动存入系统相册
            if let img = loadedImage {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
        }
    }
}
