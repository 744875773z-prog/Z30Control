//
//  OrientationLock.swift
//  Z30Control
//
//  v1.0.19：取景器强制横屏——用户横着拿手机当取景器，不想一直开系统
//  方向锁定。进取景页就转横，离页恢复竖屏（图库/控制页是竖的）。
//  v1.0.22：改主意了——整页锁定竖屏，底栏在原来位置不动，只有中间
//  取景画面在页内转 90°。手机横过来拿，画面正过来铺满；底栏、参数
//  条、快门键都在竖屏原位置，不动也不消失。强制横屏那套（lockLandscape）
//  留着备用，取景页不再用它。
//  做法：AppDelegate 按这个开关决定 App 支持的方向；进页时再用
//  UIDevice 强制转一下方向（系统方向锁定也拦不住 App 自己的请求）。
//  注意：这是 iOS 上通用的做法，但强制旋转在极少数系统版本上可能
//  需要点一下屏幕才转——真机以用户实测为准.
//

import UIKit

enum OrientationLock {
    /// true = 只允许横屏（取景页在前台时）
    static var landscapeOnly = false

    /// true = 只允许竖屏（取景页在前台时，v1.0.22）
    static var portraitOnly = false

    static func lockLandscape() {
        landscapeOnly = true
        portraitOnly = false
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }

    /// v1.0.22：取景页锁定竖屏——整页不转，只有取景画面在页内转 90°。
    static func lockPortrait() {
        portraitOnly = true
        landscapeOnly = false
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }

    static func unlockToPortrait() {
        landscapeOnly = false
        portraitOnly = false
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if OrientationLock.landscapeOnly { return .landscape }
        if OrientationLock.portraitOnly { return .portrait }
        return .allButUpsideDown
    }
}
