import SwiftUI

/// Per-category color pair: `tint` (avatar background / soft fill) and `ink`
/// (stroke / text / icon). Light values ported from Flutter `FkCategoryPalette`
/// (ids match `data.jsx::FK_CATEGORIES`); dark values follow the design-system
/// soft+ink rule — deep-toned tint, brightened ink.
struct FkCategoryColors: Sendable {
    let tint: Color
    let ink: Color
}

enum FkCategoryPalette {
    static let veg = FkCategoryColors(
        tint: Color(light: 0xE8F3E1, dark: 0x243321),
        ink: Color(light: 0x4F7A3A, dark: 0x9DC785)
    )
    static let fruit = FkCategoryColors(
        tint: Color(light: 0xFBE0D7, dark: 0x3E2620),
        ink: Color(light: 0xB5523A, dark: 0xE99C84)
    )
    static let meat = FkCategoryColors(
        tint: Color(light: 0xFDD6CE, dark: 0x42231C),
        ink: Color(light: 0xA8442C, dark: 0xEF9379)
    )
    static let sea = FkCategoryColors(
        tint: Color(light: 0xD6EBF2, dark: 0x1E3038),
        ink: Color(light: 0x3F7691, dark: 0x8CC1D9)
    )
    static let dairy = FkCategoryColors(
        tint: Color(light: 0xE5ECFA, dark: 0x252F47),
        ink: Color(light: 0x3F60B5, dark: 0x9FB5E9)
    )
    static let drink = FkCategoryColors(
        tint: Color(light: 0xE2EAF5, dark: 0x242B3C),
        ink: Color(light: 0x4A5E91, dark: 0xA4B5DD)
    )
    static let sauce = FkCategoryColors(
        tint: Color(light: 0xF0EBE3, dark: 0x332C23),
        ink: Color(light: 0x7A6748, dark: 0xC9AF8C)
    )
    static let grain = FkCategoryColors(
        tint: Color(light: 0xFFF3D6, dark: 0x3D331D),
        ink: Color(light: 0x9B7A2A, dark: 0xE0C375)
    )
    static let snack = FkCategoryColors(
        tint: Color(light: 0xFBE3CE, dark: 0x3C2A1C),
        ink: Color(light: 0xA85F2C, dark: 0xE3A271)
    )

    static let all: [String: FkCategoryColors] = [
        "veg": veg, "fruit": fruit, "meat": meat, "sea": sea, "dairy": dairy,
        "drink": drink, "sauce": sauce, "grain": grain, "snack": snack,
    ]

    /// Falls back to `grain` for unknown ids (matches Flutter behavior).
    static func of(_ categoryId: String) -> FkCategoryColors {
        all[categoryId] ?? grain
    }
}
