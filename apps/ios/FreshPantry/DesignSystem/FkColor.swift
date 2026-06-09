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

/// Fresh Pantry brand palette — a warm, cream-surfaced light theme with a
/// cornflower-blue primary, plus a warm plum-charcoal dark counterpart. Light
/// values are ported 1:1 from the Flutter `AppColors` tokens; dark values keep
/// the brand character (warm undertones, cornflower accent) while inverting
/// the surface ramp (containers get LIGHTER with elevation in dark).
///
/// Mid-tone accents that host white/dark-ink content in both modes (`fkPrimary`,
/// `fkDanger`, `fkWarn`, …) stay fixed so every shipped pairing keeps its
/// contrast; "soft + ink" pairs adapt together (deep-toned soft fill + brightened
/// ink in dark).
extension Color {
    // Primary · cornflower blue. The mid-tone `fkPrimary` is fixed (reads on
    // both modes; white-on-primary buttons keep today's contrast). In dark,
    // `fkPrimaryContainer` brightens — every feature usage is ink on
    // `fkPrimarySoft`; saturated brand surfaces use `fkPrimaryDeep` instead.
    static let fkPrimary = Color(hex: 0x5B7FD4)
    static let fkPrimaryContainer = Color(light: 0x3F60B5, dark: 0xAFC2EF)
    /// Saturated deep brand blue in BOTH modes — gradient ends / hero surfaces
    /// that host white text (unlike `fkPrimaryContainer`, which is ink in dark).
    static let fkPrimaryDeep = Color(hex: 0x3F60B5)
    static let fkOnPrimary = Color(hex: 0xFFFFFF)
    static let fkOnPrimaryContainer = Color(light: 0xE5ECFA, dark: 0x1B2A50)
    static let fkPrimaryLight = Color(light: 0x8AA3E0, dark: 0x9FB4E8)
    static let fkPrimarySoft = Color(light: 0xE5ECFA, dark: 0x2A3450)

    // Warn · butter yellow (临期 soon) — the chip bg + dark ink pair is fixed
    // (yellow pops on dark too); soft/ink adapt.
    static let fkWarn = Color(hex: 0xFFC857)
    static let fkWarnSoft = Color(light: 0xFFF3D6, dark: 0x423420)
    static let fkOnWarn = Color(hex: 0x2D2438)
    static let fkOnWarnContainer = Color(light: 0x9B7A2A, dark: 0xE6C36F)
    /// 「用临期」火苗强调色 — 比 soon ink 更暖的橙,刻意区分。
    static let fkWarnInk = Color(light: 0xB26A1F, dark: 0xE89E55)

    // Danger · coral (过期 / 不足) — coral is mid-tone, fixed; soft/ink adapt.
    static let fkDanger = Color(hex: 0xE76F51)
    static let fkDangerSoft = Color(light: 0xFBE0D7, dark: 0x44251D)
    static let fkOnDanger = Color(hex: 0xFFFFFF)
    static let fkOnDangerContainer = Color(light: 0xB5523A, dark: 0xF2A28D)

    // Success green — 完成态 / toast check(mid-tone,两模式通用)
    static let fkSuccess = Color(hex: 0x5CC9A7)
    // Alert red — 邀请角标 / 未读徽章(纯红,有别于 danger 珊瑚)
    static let fkAlert = Color(hex: 0xE5484D)

    // Surface · warm cream ramp ⇄ warm plum-charcoal ramp. NOTE the inversion:
    // in light, containers get darker/warmer with elevation (lowest = white);
    // in dark, containers get LIGHTER with elevation (lowest = card tone just
    // above the background).
    static let fkSurface = Color(light: 0xFBF8F3, dark: 0x17141C)
    static let fkSurfaceDim = Color(light: 0xE8E3DA, dark: 0x100E13)
    static let fkSurfaceBright = Color(light: 0xFFFFFF, dark: 0x3A3442)
    static let fkSurfaceContainerLowest = Color(light: 0xFFFFFF, dark: 0x201C26)
    static let fkSurfaceContainerLow = Color(light: 0xF6F2EB, dark: 0x251F2B)
    static let fkSurfaceContainer = Color(light: 0xF0EBE3, dark: 0x2A2430)
    static let fkSurfaceContainerHigh = Color(light: 0xE9E2D6, dark: 0x332C3B)
    static let fkSurfaceContainerHighest = Color(light: 0xE3DCCB, dark: 0x3D3546)

    // On-surface · deep plum-ink ⇄ plum-tinted cream
    static let fkOnSurface = Color(light: 0x2D2438, dark: 0xEDE7F2)
    static let fkOnSurfaceVariant = Color(light: 0x4F4358, dark: 0xBFB4C9)
    static let fkOutline = Color(light: 0x9B92A5, dark: 0x8D8398)
    static let fkOutlineVariant = Color(light: 0xC7C1CE, dark: 0x49414F)
    static let fkHair = Color(light: 0x2D2438, dark: 0xEDE7F2, lightAlpha: 0.078, darkAlpha: 0.08)

    // Switch off-track
    static let fkSwitchTrackOff = Color(light: 0xD9DDD8, dark: 0x4A4452)

    // Overlays / scrims. Image scrims stay fixed (they sit on photos, not on
    // themed surfaces); the modal barrier deepens in dark so sheets still read.
    static let fkOnImageScrim = Color(hex: 0x000000, alpha: 0.2)
    static let fkModalBarrier = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.278, darkAlpha: 0.5)
    static let fkSubtleShadow = Color(hex: 0x000000, alpha: 0.059)

    // Warm shadow tints — fixed; in dark, elevation reads from the lighter
    // container ramp rather than shadows.
    static let fkShadowWarm = Color(hex: 0x3C2D1E, alpha: 0.161)
    static let fkShadowSoft = Color(hex: 0x263A34, alpha: 0.039)
}
