import SwiftUI

struct LinkupTheme {
    var bg: Color
    var bgSecondary: Color
    var bgTertiary: Color
    var surface: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var textQuaternary: Color
    var border: Color
    var rowDivider: Color
    var primary: Color
    var primaryGradientEnd: Color
    var primaryLight: Color
    var primaryDark: Color
    var mapBg1: Color
    var mapBg2: Color
    var mapBooth: Color
    var mapBoothAlt: Color
    var mapHall: Color
    var mapDetail: Color
    var mapLabel: Color
    var youPin: Color
    var chatBubbleThem: Color
    var chatBannerBg: Color
    var slateAction: Color

    static let light = LinkupTheme(
        bg: Color(hex: 0xFFFBF6),
        bgSecondary: Color(hex: 0xF5EFE7),
        bgTertiary: Color(hex: 0xECE4D6),
        surface: .white,
        textPrimary: Color(hex: 0x0F1726),
        textSecondary: Color(hex: 0x64748B),
        textTertiary: Color(hex: 0x94A3B8),
        textQuaternary: Color(hex: 0xC9C2B5),
        border: .black.opacity(0.08),
        rowDivider: .black.opacity(0.06),
        primary: Color(hex: 0xFF5E3A),
        primaryGradientEnd: Color(hex: 0xFF8B5C),
        primaryLight: Color(hex: 0xFFF1EA),
        primaryDark: Color(hex: 0xC03A1A),
        mapBg1: Color(hex: 0xF2EAE0),
        mapBg2: Color(hex: 0xEDE3D3),
        mapBooth: Color(hex: 0xE8DCC9),
        mapBoothAlt: Color(hex: 0xDDD0BC),
        mapHall: Color(hex: 0xFAF5EE),
        mapDetail: Color(hex: 0xC5B496),
        mapLabel: Color(hex: 0x8B6E4A),
        youPin: Color(hex: 0x0066FF),
        chatBubbleThem: Color(hex: 0xF5EFE7),
        chatBannerBg: Color(hex: 0xFFF1EA),
        slateAction: Color(hex: 0x94A3B8)
    )

    static let dark = LinkupTheme(
        bg: Color(hex: 0x0F1419),
        bgSecondary: Color(hex: 0x1A2230),
        bgTertiary: Color(hex: 0x243349),
        surface: Color(hex: 0x1E293B),
        textPrimary: Color(hex: 0xF1F5F9),
        textSecondary: Color(hex: 0x94A3B8),
        textTertiary: Color(hex: 0x64748B),
        textQuaternary: Color(hex: 0x475569),
        border: .white.opacity(0.08),
        rowDivider: .white.opacity(0.06),
        primary: Color(hex: 0xFF7050),
        primaryGradientEnd: Color(hex: 0xFF9C76),
        primaryLight: Color(hex: 0x2E1814),
        primaryDark: Color(hex: 0xFFB69E),
        mapBg1: Color(hex: 0x1A2230),
        mapBg2: Color(hex: 0x20293A),
        mapBooth: Color(hex: 0x2A364D),
        mapBoothAlt: Color(hex: 0x344158),
        mapHall: Color(hex: 0x1F2937),
        mapDetail: Color(hex: 0x4B5A75),
        mapLabel: Color(hex: 0x8B97AC),
        youPin: Color(hex: 0x4D9FFF),
        chatBubbleThem: Color(hex: 0x2A364D),
        chatBannerBg: Color(hex: 0x2E1814),
        slateAction: Color(hex: 0x475569)
    )
}

private struct LinkupThemeKey: EnvironmentKey {
    static let defaultValue = LinkupTheme.light
}

extension EnvironmentValues {
    var linkupTheme: LinkupTheme {
        get { self[LinkupThemeKey.self] }
        set { self[LinkupThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
