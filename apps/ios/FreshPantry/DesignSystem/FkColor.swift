import SwiftUI
import UIKit

extension Color {
    /// Builds a color from a packed `0xRRGGBB` literal (optionally with a
    /// separate alpha) in the sRGB space, mirroring how the Flutter design
    /// tokens were authored.
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    /// Builds a trait-adaptive color: resolves to the `light` / `dark` packed
    /// `0xRRGGBB` literal per the active interface style (driven by the system
    /// or the in-app 外观 override via `preferredColorScheme`).
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1.0, darkAlpha: Double = 1.0) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    /// sRGB color from a packed `0xRRGGBB` literal (the UIKit twin of
    /// `Color(hex:)`, needed by the dynamic-trait provider above).
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha)
        )
    }
}

/// Fresh Pantry palette — the Sunpebble brand family: cream surfaces
/// (#FFF6E8), ink text (#232733) and the sun-gold primary (#F7B733) shared
/// with the sibling apps and sunpebble.github.io. Dark mode mirrors
/// Sleeptab's night navy (#161928 bg / #232733 card / cream foreground)
/// while inverting the surface ramp (containers get LIGHTER with elevation
/// in dark).
///
/// Mid-tone accents that host fixed content in both modes (`fkPrimary`,
/// `fkDanger`, `fkWarn`, …) stay fixed so every shipped pairing keeps its
/// contrast; "soft + ink" pairs adapt together (deep-toned soft fill +
/// brightened ink in dark).
extension Color {
    // Primary · sun gold (brand accent). The mid-tone `fkPrimary` is fixed —
    // sun gold is light, so it hosts INK content (`fkOnPrimary`), never white
    // (white on #F7B733 fails contrast in both modes). In dark,
    // `fkPrimaryContainer` brightens — every feature usage is ink on
    // `fkPrimarySoft`; saturated brand surfaces use `fkPrimaryDeep` instead.
    static let fkPrimary = Color(hex: 0xF7B733)
    static let fkPrimaryContainer = Color(light: 0x8A5F0B, dark: 0xF2CE79)
    /// Saturated deep brand gold in BOTH modes — the one primary tone dark
    /// enough to host white text (unlike `fkPrimaryContainer`, which is ink
    /// in dark, and `fkPrimary`, which is too light for white).
    static let fkPrimaryDeep = Color(hex: 0x8A5F0B)
    static let fkOnPrimary = Color(hex: 0x232733)
    static let fkPrimarySoft = Color(light: 0xFDEECB, dark: 0x3E3213)

    // Warn · amber orange (临期 soon) — shifted off yellow so it can't be
    // confused with the sun-gold primary; the chip bg + dark ink pair is
    // fixed (amber pops on dark too); soft/ink adapt.
    static let fkWarn = Color(hex: 0xEE8A2F)
    static let fkWarnSoft = Color(light: 0xFCEBD7, dark: 0x442E18)
    static let fkOnWarnContainer = Color(light: 0x9A5A14, dark: 0xEDAC6C)
    /// 「用临期」火苗强调色 — 比 soon ink 更暖偏红的橙,刻意区分。
    static let fkWarnInk = Color(light: 0xB25412, dark: 0xEF9448)

    // Danger · coral (过期 / 不足) — coral is mid-tone, fixed; soft/ink adapt.
    static let fkDanger = Color(hex: 0xE76F51)
    static let fkDangerSoft = Color(light: 0xFBE0D7, dark: 0x44251D)
    static let fkOnDanger = Color(hex: 0xFFFFFF)
    static let fkOnDangerContainer = Color(light: 0xB5523A, dark: 0xF2A28D)

    // Success green — 完成态 / toast check(mid-tone,两模式通用)。
    // soft/ink 对是「新鲜」状态的底色与文字(见 FkStatusStyle)。
    static let fkSuccess = Color(hex: 0x5CC9A7)
    static let fkSuccessSoft = Color(light: 0xDCF1E7, dark: 0x1C3A30)
    static let fkOnSuccessContainer = Color(light: 0x2F7D5F, dark: 0x8FD9BD)

    // Surface · brand cream ramp ⇄ night navy ramp. NOTE the inversion:
    // in light, containers get darker/warmer with elevation (lowest = white);
    // in dark, containers get LIGHTER with elevation (lowest = card tone just
    // above the background).
    static let fkSurface = Color(light: 0xFFF6E8, dark: 0x161928)
    static let fkSurfaceContainerLowest = Color(light: 0xFFFFFF, dark: 0x1D2130)
    static let fkSurfaceContainerLow = Color(light: 0xFAF0DC, dark: 0x232733)
    static let fkSurfaceContainer = Color(light: 0xF4E9D1, dark: 0x2A2F40)
    static let fkSurfaceContainerHighest = Color(light: 0xE8D9B8, dark: 0x3B4155)

    // On-surface · brand ink ⇄ brand cream; secondary text is pebble-family.
    static let fkOnSurface = Color(light: 0x232733, dark: 0xFFF6E8)
    static let fkOnSurfaceVariant = Color(light: 0x63646C, dark: 0xC2BFB3)
    static let fkOutline = Color(light: 0x9C9AA0, dark: 0x8A8D99)
    static let fkOutlineVariant = Color(light: 0xDCD2BE, dark: 0x454B61)
    static let fkHair = Color(light: 0x232733, dark: 0xFFF6E8, lightAlpha: 0.078, darkAlpha: 0.08)

    // Overlays / scrims. Image scrims stay fixed (they sit on photos, not on
    // themed surfaces).
    static let fkOnImageScrim = Color(hex: 0x000000, alpha: 0.2)

    // Warm shadow tint — fixed; in dark, elevation reads from the lighter
    // container ramp rather than shadows.
    static let fkShadowSoft = Color(hex: 0x3A2F16, alpha: 0.039)
}
