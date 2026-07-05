import Foundation

/// Category canonicalization + perishability source. Ported VERBATIM from
/// `lib/data/food_categories.dart` (alias map + perishable set must match for
/// sync parity).
enum FoodCategories {
    // These Chinese literals are the STORAGE/matching identity — persisted in
    // SwiftData/sync payloads and compared by exact string identity across the
    // whole domain layer (Flutter parity) — so they must never be localized or
    // renamed (would silently break existing users' saved categories). Display
    // is a SEPARATE concern, see `displayLabel(for:)` below.
    static let dairyAndEggs = "乳品蛋类" // i18n:ignore data identity, not UI text
    static let freshProduce = "果蔬生鲜" // i18n:ignore data identity, not UI text
    static let meatAndSeafood = "肉类海鲜" // i18n:ignore data identity, not UI text
    static let herbsAndSpices = "香料草本" // i18n:ignore data identity, not UI text
    static let other = "其他" // i18n:ignore data identity, not UI text

    static let removedPantryStaples = "食品柜常备" // i18n:ignore data identity, not UI text

    /// Legacy/synonym Chinese labels → 5 canonical. Unmapped non-empty → other.
    private static let aliases: [String: String] = [
        dairyAndEggs: dairyAndEggs,
        "乳制品与蛋类": dairyAndEggs, // i18n:ignore data identity, not UI text
        "乳制品与干货": dairyAndEggs, // i18n:ignore data identity, not UI text
        "乳制品": dairyAndEggs, // i18n:ignore data identity, not UI text
        "乳品": dairyAndEggs, // i18n:ignore data identity, not UI text
        "蛋类": dairyAndEggs, // i18n:ignore data identity, not UI text
        "蛋": dairyAndEggs, // i18n:ignore data identity, not UI text
        freshProduce: freshProduce,
        "新鲜蔬果": freshProduce, // i18n:ignore data identity, not UI text
        "蔬菜": freshProduce, // i18n:ignore data identity, not UI text
        "水果": freshProduce, // i18n:ignore data identity, not UI text
        "果蔬": freshProduce, // i18n:ignore data identity, not UI text
        "生鲜": freshProduce, // i18n:ignore data identity, not UI text
        meatAndSeafood: meatAndSeafood,
        "肉类与海鲜": meatAndSeafood, // i18n:ignore data identity, not UI text
        "肉类": meatAndSeafood, // i18n:ignore data identity, not UI text
        "海鲜": meatAndSeafood, // i18n:ignore data identity, not UI text
        "蛋白质": meatAndSeafood, // i18n:ignore data identity, not UI text
        herbsAndSpices: herbsAndSpices,
        "香料与草本": herbsAndSpices, // i18n:ignore data identity, not UI text
        "香料": herbsAndSpices, // i18n:ignore data identity, not UI text
        "草本": herbsAndSpices, // i18n:ignore data identity, not UI text
        "调味品": herbsAndSpices, // i18n:ignore data identity, not UI text
        "调味料": herbsAndSpices, // i18n:ignore data identity, not UI text
        other: other,
        removedPantryStaples: other,
        "谷物": other, // i18n:ignore data identity, not UI text
        "主食": other, // i18n:ignore data identity, not UI text
        "干货": other, // i18n:ignore data identity, not UI text
    ]

    static let values = [
        dairyAndEggs,
        freshProduce,
        meatAndSeafood,
        herbsAndSpices,
        other,
    ]

    /// Localization keys for the 5 canonical values + `removedPantryStaples`,
    /// keyed by the Chinese storage identity — the display-only counterpart to
    /// the storage constants above. Mirrors `DietPreferenceStore.displayKeys`.
    private static let displayKeys: [String: String] = [
        dairyAndEggs: "inventory.category.dairyAndEggs",
        freshProduce: "inventory.category.freshProduce",
        meatAndSeafood: "inventory.category.meatAndSeafood",
        herbsAndSpices: "inventory.category.herbsAndSpices",
        other: "inventory.category.other",
        removedPantryStaples: "inventory.category.removedPantryStaples",
    ]

    /// Localized display text for a canonical (or `removedPantryStaples`) value,
    /// for UI rendering only. Falls back to the raw value for anything else
    /// (defensive; callers should normalize first).
    static func displayLabel(for category: String) -> String {
        guard let key = displayKeys[category] else { return category }
        return String(localized: String.LocalizationValue(key))
    }

    /// nil/empty → nil; mapped alias or `other` for any unmapped non-empty value.
    static func normalize(_ category: String?) -> String? {
        guard let trimmed = category?.trimmed, !trimmed.isEmpty else { return nil }
        return aliases[trimmed] ?? other
    }

    static func dropdownValue(_ category: String?) -> String {
        normalize(category) ?? other
    }

    /// Perishable categories track each intake as a new batch (per ADR-0001).
    private static let perishable: Set<String> = [
        freshProduce,
        meatAndSeafood,
        dairyAndEggs,
    ]

    static func isPerishable(_ category: String?) -> Bool {
        guard let normalized = normalize(category) else { return false }
        return perishable.contains(normalized)
    }
}
