import Foundation

/// Static preset values surfaced in the custom-recipe authoring form. Ported from
/// `lib/data/recipe_presets.dart`. These are recipe-domain presets (cuisine
/// categories / cooking-time chips / ingredient units) and are deliberately
/// SEPARATE from `FoodCategories` (the inventory perishability taxonomy) — a
/// recipe's category is a freeform cuisine label, not one of the five inventory
/// buckets.
enum RecipePresets {
    /// Cuisine category presets. A custom value the user typed is appended ahead
    /// of these by the form; the trailing "其他" sentinel opens a freeform entry.
    static let categories = ["家常", "川菜", "粤菜", "西式", "烘焙", "汤羹"] // i18n:ignore data identity, not UI text

    /// Cooking-time presets (minutes). The last value (120) renders as "120+" but
    /// still writes 120 on tap.
    static let cookingMinutes = [15, 30, 45, 60, 90, 120]

    /// Ingredient unit presets. A "自定义…" entry is appended by the picker.
    static let units = ["g", "ml", "kg", "个", "把", "根", "颗", "片", "杯", "勺", "适量"] // i18n:ignore data identity, not UI text

    private static let categoryDisplayKeys: [String: String] = [
        "家常": "recipe.preset.category.home", // i18n:ignore data identity, not UI text
        "川菜": "recipe.preset.category.sichuan", // i18n:ignore data identity, not UI text
        "粤菜": "recipe.preset.category.cantonese", // i18n:ignore data identity, not UI text
        "西式": "recipe.preset.category.western", // i18n:ignore data identity, not UI text
        "烘焙": "recipe.preset.category.baking", // i18n:ignore data identity, not UI text
        "汤羹": "recipe.preset.category.soup", // i18n:ignore data identity, not UI text
    ]

    static func categoryDisplayLabel(for category: String) -> String {
        guard let key = categoryDisplayKeys[category] else { return category }
        return String(localized: String.LocalizationValue(key))
    }
}
