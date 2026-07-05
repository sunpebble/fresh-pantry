import Foundation

/// Display-only localization for the Chinese unit literals used as picker
/// option identity in `AddIngredientForm`/`EditIngredientForm`/`IntakeReviewView`
/// (mirrors `FoodCategories.displayLabel(for:)`). The Chinese strings remain
/// the stored/matching identity for `Ingredient.unit` — only the picker label
/// is translated here.
///
/// ponytail: scope is the picker option list only. Once a unit is saved, its
/// rendering elsewhere (inventory list, notifications, etc.) still shows the
/// raw stored value — full cross-app unit localization is out of scope for
/// this pass.
enum UnitLabels {
    private static let displayKeys: [String: String] = [
        "个": "inventory.unit.ge", // i18n:ignore data identity, not UI text
        "只": "inventory.unit.zhi", // i18n:ignore data identity, not UI text
        "把": "inventory.unit.ba", // i18n:ignore data identity, not UI text
        "盒": "inventory.unit.he", // i18n:ignore data identity, not UI text
        "袋": "inventory.unit.dai", // i18n:ignore data identity, not UI text
        "瓶": "inventory.unit.ping", // i18n:ignore data identity, not UI text
        "罐": "inventory.unit.guan", // i18n:ignore data identity, not UI text
        "包": "inventory.unit.bao", // i18n:ignore data identity, not UI text
        "份": "inventory.unit.fen", // i18n:ignore data identity, not UI text
    ]

    /// Localized display text for a unit. Falls back to the raw value for
    /// anything unmapped (e.g. ASCII units like "kg"/"g"/"L"/"ml", which need
    /// no translation).
    static func displayLabel(for unit: String) -> String {
        guard let key = displayKeys[unit] else { return unit }
        return String(localized: String.LocalizationValue(key))
    }
}
