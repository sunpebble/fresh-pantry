import Foundation

/// 食谱译文覆盖层(id → 译文),由 DB 读取后套在共享语料上;中文界面不加载。
/// overlay 缺某 id(远程新增、翻译失败)→ 该条保持中文原文。
struct RecipeOverlayEntry: Decodable, Sendable {
    struct IngredientOverlay: Decodable, Sendable {
        let name: String
        let unit: String?
        let note: String?
    }

    let name: String
    let description: String
    let category: String
    let steps: [String]
    let tags: [String]
    let ingredients: [IngredientOverlay]
}

enum RecipeLocalizer {
    static let supported: Set<String> = ["en", "ja", "fr"]

    /// App 实际界面语言对应的 overlay 语言;中文或不支持的语言 → nil(用原文)。
    static func overlayLanguage(
        preferred: [String] = Bundle.main.preferredLocalizations
    ) -> String? {
        for identifier in preferred {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier else { continue }
            if code == "zh" { return nil }
            if supported.contains(code) { return code }
        }
        return nil
    }

    /// 按 id 套用译文;食材/步骤按下标对齐,数量不齐则该条整体保持原文。
    static func apply(_ overlay: [String: RecipeOverlayEntry]?, to recipes: [Recipe]) -> [Recipe] {
        guard let overlay else { return recipes }
        return recipes.map { recipe in
            guard let entry = overlay[recipe.id],
                  entry.ingredients.count == recipe.ingredients.count,
                  entry.steps.count == recipe.steps.count else {
                return recipe
            }

            var out = recipe
            out.name = entry.name
            out.description = entry.description
            out.category = entry.category
            out.steps = entry.steps
            out.tags = entry.tags
            out.ingredients = zip(recipe.ingredients, entry.ingredients).map { original, translated in
                var ingredient = original
                ingredient.name = translated.name
                if let unit = translated.unit { ingredient.unit = unit }
                if let note = translated.note { ingredient.note = note }
                return ingredient
            }
            return out
        }
    }
}
