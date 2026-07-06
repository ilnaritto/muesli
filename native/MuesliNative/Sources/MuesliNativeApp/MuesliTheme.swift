import SwiftUI
import MuesliCore

enum MuesliTheme {
    // MARK: - Colors — Backgrounds (layered)
    //
    // In dark mode every background layer is blended with the accent color
    // (Telegram-style tinted dark theme), so the whole app picks up the hue
    // of the selected theme. Raised layers get proportionally more tint.
    // `darkTintStrength` scales how much tint is mixed in (0 = plain grays).
    // `darkTintSaturation` controls how colorful that tint is: the accent is
    // first desaturated toward a gray of the same lightness, so the layers
    // read as "lifted" rather than "colored" (1 = pure accent hue).

    static var darkTintStrength: CGFloat = 2.0
    static var darkTintSaturation: CGFloat = 0.10

    static var backgroundDeep: Color   { tintedAdaptive(dark: 0x111214, light: 0xF5F5F7, tint: 0.05) }
    static var backgroundBase: Color   { tintedAdaptive(dark: 0x161719, light: 0xFFFFFF, tint: 0.06) }
    static var backgroundRaised: Color { tintedAdaptive(dark: 0x1C1D20, light: 0xF0F0F2, tint: 0.08) }
    static var backgroundHover: Color  { tintedAdaptive(dark: 0x232528, light: 0xE8E8EC, tint: 0.10) }

    // MARK: - Surfaces (interactive elements)

    static var surfacePrimary: Color   { tintedAdaptive(dark: 0x262830, light: 0xE5E5EA, tint: 0.12) }
    static var surfaceSelected: Color  { tintedAdaptive(dark: 0x2E3340, light: 0xD6DFFE, tint: 0.18) }
    static let surfaceBorder    = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.07,
        light: .black, lightAlpha: 0.08
    )

    // MARK: - Text hierarchy

    static let textPrimary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.92,
        light: .black, lightAlpha: 0.88
    )
    static let textSecondary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.62,
        light: .black, lightAlpha: 0.55
    )
    static let textTertiary = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.40,
        light: .black, lightAlpha: 0.33
    )

    // MARK: - Accent

    static let defaultAccentDarkHex = 0x6BA3F7
    static let defaultAccentLightHex = 0x2563EB
    static let defaultAccent    = Color.adaptive(dark: defaultAccentDarkHex, light: defaultAccentLightHex)
    static var accentOverrideHex: String?
    static var accent: Color {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            return Color(hex: Int(val))
        }
        return defaultAccent
    }
    static var accentSubtle: Color { accent.opacity(0.15) }
    /// Muted selection fill for list rows: theme-colored but far less
    /// saturated than the raw accent.
    static var selectionFill: Color { accent.opacity(0.30) }

    /// The accent hex used for tinting dark surfaces, honoring the user override.
    private static func resolvedDarkAccentHex() -> Int {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            return Int(val)
        }
        return defaultAccentDarkHex
    }

    /// Dark mode: base gray blended toward the accent by `tint * darkTintStrength`.
    /// Light mode: plain light hex, untouched.
    private static func tintedAdaptive(dark darkHex: Int, light lightHex: Int, tint fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            func channel(_ hex: Int, _ shift: Int) -> CGFloat {
                CGFloat((hex >> shift) & 0xFF) / 255.0
            }
            guard appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else {
                return NSColor(
                    red: channel(lightHex, 16),
                    green: channel(lightHex, 8),
                    blue: channel(lightHex, 0),
                    alpha: 1.0
                )
            }
            let accentHex = resolvedDarkAccentHex()
            let f = max(0, min(1, fraction * darkTintStrength))
            // Desaturate the accent toward a gray of equal perceived lightness
            // before mixing, so the tint lifts brightness more than it colors.
            let accentR = channel(accentHex, 16)
            let accentG = channel(accentHex, 8)
            let accentB = channel(accentHex, 0)
            let gray = 0.299 * accentR + 0.587 * accentG + 0.114 * accentB
            let sat = max(0, min(1, darkTintSaturation))
            func blended(_ shift: Int, _ accentChannel: CGFloat) -> CGFloat {
                let tint = gray + (accentChannel - gray) * sat
                let base = channel(darkHex, shift)
                return base + (tint - base) * f
            }
            return NSColor(
                red: blended(16, accentR),
                green: blended(8, accentG),
                blue: blended(0, accentB),
                alpha: 1.0
            )
        })
    }

    // MARK: - Semantic

    static let recording        = Color(hex: 0xEF4444)
    static let transcribing     = Color(hex: 0xF59E0B)
    static let success          = Color(hex: 0x34D399)

    // MARK: - Typography (SF Pro via .system())

    /// Small content-page heading — the tab-title feel, not a big poster.
    static func pageTitle() -> Font { .system(size: 15, weight: .semibold) }
    static func title1() -> Font { .system(size: 28, weight: .bold) }
    static func title2() -> Font { .system(size: 22, weight: .semibold) }
    static func title3() -> Font { .system(size: 18, weight: .semibold) }
    static func headline() -> Font { .system(size: 15, weight: .semibold) }
    static func body() -> Font { .system(size: 14, weight: .regular) }
    static func callout() -> Font { .system(size: 13, weight: .regular) }
    static func caption() -> Font { .system(size: 12, weight: .regular) }
    static func captionMedium() -> Font { .system(size: 12, weight: .medium) }

    // MARK: - Spacing (4pt grid)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radii

    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let cornerLarge: CGFloat = 14
    static let cornerXL: CGFloat = 20
}

// MARK: - Color Helpers

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }

    static func adaptiveAlpha(dark: NSColor, darkAlpha: CGFloat, light: NSColor, lightAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.withAlphaComponent(darkAlpha)
                : light.withAlphaComponent(lightAlpha)
        })
    }
}
