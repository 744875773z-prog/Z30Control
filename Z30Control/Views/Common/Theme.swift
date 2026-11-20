//
//  Theme.swift
//  Z30Control
//
//  专业摄影级 UI 主题规范：支持日间明亮 (Studio White) 与暗房深黑 (Pitch Black) 双模切换
//

import SwiftUI

public enum AppThemePreference: String, CaseIterable {
    case system = "跟随系统"
    case dark = "专业暗夜黑 (Pitch Black)"
    case light = "日间明亮白 (Studio Light)"
}

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    @Published public var preference: AppThemePreference = .dark {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: "app_theme_pref")
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "app_theme_pref"),
           let pref = AppThemePreference(rawValue: saved) {
            self.preference = pref
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch preference {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

public struct NikonTheme {
    // MARK: - 核心色彩体系
    public static let nikonYellow   = Color(red: 1.0, green: 0.816, blue: 0.0)      // #FFD000 尼康明黄
    public static let tallyRed      = Color(red: 1.0, green: 0.231, blue: 0.188)    // #FF3B30 录制/告警红
    public static let readyGreen    = Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759 就绪/合焦绿
    
    // 背景与容器色 (纯黑 OLED 与专业深灰)
    public static let pitchBlack    = Color(red: 0.05, green: 0.05, blue: 0.05)     // #0D0D0D 深色底
    public static let surfaceDark   = Color(red: 0.11, green: 0.11, blue: 0.12)     // #1C1C1E 深色卡片
    
    public static let bgLight       = Color(red: 0.96, green: 0.96, blue: 0.97)     // #F5F5F7 浅色底
    public static let surfaceWhite  = Color.white                                    // 浅色纯白卡片
    public static let borderGray    = Color.gray.opacity(0.2)
    public static let textSecondary = Color(white: 0.55)
    
    // MARK: - 触觉震动反馈
    public static func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

// MARK: - 等宽瑞士腕表 HUD 排版修饰符
public struct MonospacedHUDModifier: ViewModifier {
    var size: CGFloat = 13
    var weight: Font.Weight = .medium
    
    public func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .monospaced))
    }
}

extension View {
    public func proHUDText(size: CGFloat = 13, weight: Font.Weight = .medium) -> some View {
        self.modifier(MonospacedHUDModifier(size: size, weight: weight))
    }
}
