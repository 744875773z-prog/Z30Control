//
//  Theme.swift
//  Z30Control
//
//  蓝白纯净现代工业设计版 (Clean Blue-White Studio Edition)
//  100% 极简纯净白 (#FFFFFF) + 科技蔚蓝 (#007AFF) 重点点缀，彻底对齐网页版视觉规范
//

import SwiftUI

public enum AppThemePreference: String, CaseIterable {
    case system = "跟随系统"
    case light = "日间明亮白 (Studio Light)"
    case dark = "专业暗夜黑 (Pitch Black)"
}

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    @Published public var preference: AppThemePreference = .light {
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
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public struct NikonTheme {
    // MARK: - 核心色彩体系 (对齐网页版 CSS 根变量)
    public static let bgPure          = Color.white                                           // #FFFFFF 纯净白底
    public static let bgSubtle        = Color(red: 0.973, green: 0.980, blue: 0.988)          // #F8FAFC 极浅灰工作区底
    public static let surfaceCard     = Color.white                                           // #FFFFFF 纯白卡片
    public static let borderDim       = Color(red: 0.886, green: 0.910, blue: 0.941)          // #E2E8F0 浅灰边框
    public static let borderLight     = Color(red: 0.945, green: 0.961, blue: 0.976)          // #F1F5F9 极浅边框
    public static let borderGray      = Color(red: 0.886, green: 0.910, blue: 0.941)          // 兼容历史命名
    
    // 品牌科技蔚蓝 (#007AFF)
    public static let accentBlue      = Color(red: 0.0, green: 0.478, blue: 1.0)              // #007AFF 科技蔚蓝
    public static let accentBlueLight = Color(red: 0.922, green: 0.961, blue: 1.0)            // #EBF5FF 浅蓝药丸背景
    public static let accentBlueBorder = Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.3)
    
    // 文本色阶 (深蓝灰优雅排版)
    public static let textPrimary     = Color(red: 0.059, green: 0.090, blue: 0.165)          // #0F172A 主文字
    public static let textSecondary   = Color(red: 0.278, green: 0.333, blue: 0.412)          // #475569 次要文字
    public static let textTertiary    = Color(red: 0.580, green: 0.639, blue: 0.722)          // #94A3B8 辅助提示文字
    
    // 辅助状态色
    public static let readyGreen      = Color(red: 0.063, green: 0.725, blue: 0.506)          // #10B981 就绪绿
    public static let tallyRed        = Color(red: 0.937, green: 0.267, blue: 0.267)          // #EF4444 录像/告警红
    public static let accentAmber     = Color(red: 0.961, green: 0.620, blue: 0.043)          // #F59E0B 琥珀警告黄
    
    // 兼容历史命名
    public static let nikonYellow     = Color(red: 0.0, green: 0.478, blue: 1.0)              // 蔚蓝替代旧黄
    public static let pitchBlack      = Color(red: 0.05, green: 0.05, blue: 0.05)
    public static let surfaceDark     = Color(red: 0.11, green: 0.11, blue: 0.12)
    
    // MARK: - 触觉震动反馈
    public static func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

// MARK: - 等宽排版修饰符
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
