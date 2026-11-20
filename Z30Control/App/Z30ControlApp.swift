//
//  Z30ControlApp.swift
//  Z30Control
//
//  应用程序主入口 (集成全局主题管理器)
//

import SwiftUI

@main
public struct Z30ControlApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(themeManager.colorScheme)
        }
    }
}
