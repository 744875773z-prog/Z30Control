//
//  OrientationLock.swift
//  Z30Control
//
//  v1.0.19：取景器强制横屏——用户横着拿手机当取景器，不想一直开系统
//  方向锁定。进取景页就转横，离页恢复竖屏（图库/控制页是竖的）。
//  做法：AppDelegate 按这个开关决定 App 支持的方向；进页时再用
//  UIDevice 强制转一下方向（系统方向锁定也拦不住 App 自己的请求）。
//  注意：这是 iOS 上通用的做法，但强制旋转在极少数系统版本上可能
//  需要点一下屏幕才转——真机以用户实测为准。
//

import UIKit

enum OrientationLock {
    /// true = 只允许横屏（取景页在前台时）
    static var landscapeOnly = false

    static func lockLandscape() {
        landscapeOnly = true
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }

    static func unlockToPortrait() {
        landscapeOnly = false
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.landscapeOnly ? .landscape : .allButUpsideDown
    }
}
