import Foundation

/// Display-only localization for Chinese unit literals used as persisted
/// inventory identity (mirrors `FoodCategories.displayLabel(for:)`). The raw
/// unit remains the stored/matching value for `Ingredient.unit`; only UI labels
/// are translated here.
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
        "根": "inventory.unit.gen", // i18n:ignore data identity, not UI text
        "颗": "inventory.unit.ke", // i18n:ignore data identity, not UI text
        "片": "inventory.unit.pian", // i18n:ignore data identity, not UI text
        "杯": "inventory.unit.bei", // i18n:ignore data identity, not UI text
        "勺": "inventory.unit.shao", // i18n:ignore data identity, not UI text
        "适量": "inventory.unit.shiliang", // i18n:ignore data identity, not UI text
    ]

    /// Localized display text for a unit. Falls back to the raw value for
    /// anything unmapped (e.g. ASCII units like "kg"/"g"/"L"/"ml", which need
    /// no translation).
    static func displayLabel(for unit: String) -> String {
        guard let key = displayKeys[unit] else { return unit }
        return String(localized: String.LocalizationValue(key))
    }
}
