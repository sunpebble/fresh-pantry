import Foundation

/// 「今天做什么」推荐选取:库存驱动地挑一道菜——优先能用掉临期食材的,其次现有
/// 食材最齐的,最后退回菜谱库第一道。纯逻辑(复用已测的 `RecipeMatching`),所以
/// 既能在后台 App Intent 进程里直接调,也能脱离 Intent 运行时单测。
///
/// 这是 Fresh Pantry 版「今天做什么」与懒饭随机推荐的差异点:推荐由库存(尤其临期)
/// 驱动,而非纯随机——更贴合「用掉手里的菜、别浪费」的产品定位。
enum TodayRecipeSelector {
    /// 一条推荐:菜 + 它能用掉几件临期食材 + 已有几种食材(驱动对话文案分级)。
    struct Pick: Equatable {
        let recipe: Recipe
        let expiringUseCount: Int
        let matchedCount: Int
    }

    /// 临期优先 → 现有可做 → 菜谱库第一道。`nil` 仅当 `recipes` 为空。临期名集 =
    /// 库存里非 `fresh` 的(对齐 `RecipesStore` 的「用临期」tab);现有名集排除已过期。
    static func pick(recipes: [Recipe], inventory: [Ingredient]) -> Pick? {
        guard let first = recipes.first else { return nil }
        let expiringNames = RecipeMatching.inventoryNameSet(inventory.filter { $0.state != .fresh })
        let availableNames = RecipeMatching.availableInventoryNameSet(inventory)

        if let r = RecipeMatching.rankedByExpiringUse(recipes, expiringNames).first {
            return Pick(
                recipe: r,
                expiringUseCount: RecipeMatching.expiringCount(expiringNames, r),
                matchedCount: RecipeMatching.matchedCount(availableNames, r)
            )
        }
        if let r = RecipeMatching.rankedByAvailability(
            recipes, inventoryNames: availableNames, expiringNames: expiringNames
        ).first {
            return Pick(recipe: r, expiringUseCount: 0, matchedCount: RecipeMatching.matchedCount(availableNames, r))
        }
        return Pick(recipe: first, expiringUseCount: 0, matchedCount: 0)
    }

    /// Siri / 快捷指令 对话文案,按推荐理由分级(临期 > 现有 > 兜底)。
    static func dialog(for pick: Pick) -> String {
        let name = pick.recipe.name
        if pick.expiringUseCount > 0 {
            return String(localized: "intent.today.result.expiring \(name) \(pick.expiringUseCount)")
        }
        if pick.matchedCount > 0 {
            return String(localized: "intent.today.result.matched \(name) \(pick.matchedCount) \(pick.recipe.ingredients.count)")
        }
        return String(localized: "intent.today.result.default \(name)")
    }
}
