//
//  PermissionManager.swift
//  Z30Control
//
//  iOS 系统权限主动唤起与健康诊断管理器
//  负责：
//  1. 启动时主动触发 iOS“本地网络 (Local Network)”权限弹窗
//  2. 触发国行 iPhone“无线局域网与蜂窝数据”联网权限
//  3. 检测与请求系统相册读写权限
//  4. 提供一键跳转系统【设置 -> Z30 影控】能力
//

import Foundation
import Network
import Photos
import UIKit
import Combine

public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    // 权限状态监控
    @Published public var isLocalNetworkGranted: Bool = true
    @Published public var isPhotoLibraryGranted: Bool = false
    @Published public var hasPromptedPermissions: Bool = false
    
    private var netBrowser: NWBrowser?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        checkPhotoLibraryPermission()
    }
    
    // MARK: - 主动触发所有系统核心权限 (在 App 启动主页调用)
    public func requestAllRequiredPermissions() {
        guard !hasPromptedPermissions else { return }
        hasPromptedPermissions = true
        
        // 1. 触发国行网络权限 (发起轻量探测，唤起国行系统 WLAN 授权弹窗)
        triggerCellularAndWlanPrompt()
        
        // 2. 触发本地网络权限 (使用 NWBrowser 探测 _ptp-ip._tcp 服务，强力触发系统弹窗)
        triggerLocalNetworkPrompt()
        
        // 3. 请求相册保存权限 (速传即拍即存必需)
        requestPhotoLibraryPermission()
    }
    
    // MARK: - 触发国行网络弹窗
    private func triggerCellularAndWlanPrompt() {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        let session = URLSession(configuration: config)
        session.dataTask(with: url) { _, _, _ in }.resume()
    }
    
    // MARK: - 触发本地网络权限弹窗 (Apple 官方推荐的 NWBrowser 机制)
    public func triggerLocalNetworkPrompt() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_ptp-ip._tcp", domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.netBrowser = browser
        
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isLocalNetworkGranted = true
                    print("[PermissionManager] 本地网络权限就绪 (Ready)")
                case .failed(let error):
                    print("[PermissionManager] 本地网络探测异常: \(error)")
                    // 如果被系统拒绝，提示用户
                    if error.localizedDescription.contains("denied") || error.localizedDescription.contains("blocked") {
                        self?.isLocalNetworkGranted = false
                    }
                case .waiting(let error):
                    print("[PermissionManager] 本地网络正在等待系统授权: \(error)")
                default:
                    break
                }
            }
        }
        
        browser.start(queue: DispatchQueue.global(qos: .userInitiated))
        
        // 5秒后停止探测，避免持续消耗资源
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.netBrowser?.cancel()
            self?.netBrowser = nil
        }
    }
    
    // MARK: - 相册读写权限
    public func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        DispatchQueue.main.async {
            self.isPhotoLibraryGranted = (status == .authorized || status == .limited)
        }
    }
    
    public func requestPhotoLibraryPermission(completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                let granted = (status == .authorized || status == .limited)
                self?.isPhotoLibraryGranted = granted
                completion?(granted)
            }
        }
    }
    
    // MARK: - 一键跳转到系统【设置】页面
    public static func openSystemSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsUrl) else { return }
        UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil)
    }
}
