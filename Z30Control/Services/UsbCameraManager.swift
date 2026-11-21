//
//  UsbCameraManager.swift
//  Z30Control
//
//  基于 Apple 原生 ImageCaptureCore 框架的 USB 数码相机硬件级直连管理器 (像素蛋糕/Capture One 同款底层)
//  优势：
//  1. 纯硬件总线枚举，无需 IP 地址，无需 192.168.1.1 虚拟网卡，插入 Type-C 即秒级识别
//  2. 完美支持尼康 Z 30 等微单在 MTP/PTP 标准模式下的硬件直连
//  3. 完美支持联机拍摄 (Tethering)：机身按下快门，iOS 立即通过 didAddItems 回调新照片，实现零延迟速传
//

import Foundation
import ImageCaptureCore
import UIKit
import Combine
import Photos

public final class UsbCameraManager: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate, ICCameraDeviceDownloadDelegate {
    
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
            browser.browsingTypeMask = [.camera]
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
    
    // MARK: - ICDeviceBrowserDelegate 回调 (硬件插入即被捕获)
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
                CameraState.shared.isConnected = false
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
    
    // MARK: - ICCameraDeviceDelegate 会话与联机
    public func deviceDidOpenSession(_ device: ICDevice) {
        print("[UsbCameraManager] 成功打开硬件会话: \(device.name ?? "")")
        guard let camera = device as? ICCameraDevice else { return }
        
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
            CameraState.shared.isConnected = true
            CameraState.shared.modelName = devName
            
            NikonTheme.triggerHaptic(style: .heavy)
        }
        
        // 请求联机拍摄通知 (Tethering: 相机按快门，iOS 即时捕获新照片)
        camera.requestEnableTethering()
    }
    
    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        print("[UsbCameraManager] 设备会话关闭: \(String(describing: error))")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUsbConnected = false
            CameraConnectionService.shared.isConnected = false
            CameraState.shared.isConnected = false
            CameraConnectionService.shared.statusMessage = "相机连接已断开"
        }
    }
    
    // MARK: - 即拍即传核心：相机产生新照片 (didAddItems)
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("[UsbCameraManager] 相机捕获到新素材，数量: \(items.count)")
        for item in items {
            guard let file = item as? ICCameraFile else { continue }
            print("[UsbCameraManager] 新拍摄照片: \(file.name ?? "未命名")")
            
            // 异步请求下载或提取缩略图
            let options: [ICDownloadOption: Any] = [
                .targetDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                .saveAsFilename: file.name ?? "capture.jpg",
                .overwriteLowResolutionFile: true
            ]
            
            camera.requestDownloadFile(file, options: options, downloadDelegate: self)
        }
    }
    
    // MARK: - ICCameraDeviceDownloadDelegate 下载完成
    public func didDownloadFile(_ file: ICCameraFile, options: [ICDownloadOption : Any] = [:], contextInfo: UnsafeMutableRawPointer?) {
        let savedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(file.name ?? "capture.jpg")
        print("[UsbCameraManager] 照片成功传输到手机本地: \(savedPath)")
        
        let loadedImage = UIImage(contentsOfFile: savedPath)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let name = file.name ?? "DSC_NEW.JPG"
            let sizeStr = "\(file.fileSize / 1024 / 1024) MB"
            
            self.lastCapturedPhoto = loadedImage
            self.lastCapturedFilename = name
            self.lastCapturedExif = "原片传输 · \(sizeStr)"
            
            let item = CapturedPhotoItem(filename: name, image: loadedImage, date: Date(), sizeString: sizeStr)
            self.sessionCapturedPhotos.insert(item, at: 0)
            
            // 触感反馈提示用户新照片已到
            NikonTheme.triggerHaptic(style: .medium)
            
            // 自动存入系统相册 (如果用户开启或调用)
            if let img = loadedImage {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
        }
    }
}
