import Foundation

/// Pure recipe ↔ inventory matching ported VERBATIM from
/// `lib/providers/recipe_provider.dart`. Drives the ingredient-availability
/// highlight, the "已有 m/total" / "缺 N 件" counts, the 用临期 ranking, and the
/// 忌口 (excluded-ingredient) filter. No SwiftUI / SwiftData dependency so it's
/// unit-testable.
enum RecipeMatching {
    /// Lower-cased, trimmed, non-empty inventory names (the match corpus).
    static func inventoryNameSet(_ inventory: [Ingredient]) -> Set<String> {
        Set(
            inventory
                .map { $0.name.trimmed.lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    /// Names eligible for the 「已有」 match — excludes expired rows (still on
    /// shelf but no longer considered usable for cooking).
    static func availableInventoryNameSet(_ inventory: [Ingredient]) -> Set<String> {
        inventoryNameSet(inventory.filter { $0.state != .expired })
    }

    private static func matchCandidates(_ ingredient: RecipeIngredient) -> [String] {
        ingredient.matchingNames.map { $0.trimmed.lowercased() }.filter { !$0.isEmpty }
    }

    private static func exactlyMatchesInventoryName(_ ingredient: RecipeIngredient, _ inventoryNames: Set<String>) -> Bool {
        matchCandidates(ingredient).contains { inventoryNames.contains($0) }
    }

    /// A recipe ingredient is "in stock" when its name is a substring of (or
    /// contains) any inventory name — a forgiving two-way contains match.
    static func ingredientMatchesInventory(_ ingredient: RecipeIngredient, _ inventoryNames: Set<String>) -> Bool {
        matchCandidates(ingredient).contains { name in
            inventoryNames.contains { $0.contains(name) || name.contains($0) }
        }
    }

    /// How many of the recipe's ingredients are in stock.
    static func matchedCount(_ inventoryNames: Set<String>, _ recipe: Recipe) -> Int {
        guard !inventoryNames.isEmpty, !recipe.ingredients.isEmpty else { return 0 }
        return recipe.ingredients.filter { ingredientMatchesInventory($0, inventoryNames) }.count
    }

    /// The recipe ingredients NOT currently in stock (the shopping candidates).
    static func missingIngredients(_ inventoryNames: Set<String>, _ recipe: Recipe) -> [RecipeIngredient] {
        recipe.ingredients.filter { !ingredientMatchesInventory($0, inventoryNames) }
    }

    /// Add to a shopping list for the recipe's missing ingredients, carrying the
    /// SCALED amount as the row detail (so the shopping row shows the quantity and
    /// same-name/same-unit re-adds merge via `ShoppingStore.mergeQuantity`). Uses
    /// the decimal `displayAmount` (not `fractionAmount`) so the detail stays
    /// parseable. `scaleFactor == 1` carries the unscaled amount.
    static func missingShoppingDetails(
        _ inventoryNames: Set<String>,
        _ recipe: Recipe,
        scaleFactor: Double = 1
    ) -> [(name: String, detail: String)] {
        missingIngredients(inventoryNames, recipe).map { ingredient in
            (name: ingredient.name, detail: ingredient.scaledBy(scaleFactor).displayAmount)
        }
    }

    /// How many distinct expiring/expired inventory names the recipe would use up.
    static func expiringCount(_ expiringNames: Set<String>, _ recipe: Recipe) -> Int {
        guard !expiringNames.isEmpty, !recipe.ingredients.isEmpty else { return 0 }
        return expiringNames.filter { name in
            recipe.ingredients.contains { ingredientMatchesInventory($0, [name]) }
        }.count
    }

    /// The "现有" (available) tab order — a faithful port of
    /// `recommendedRecipesProvider`: each recipe is scored `matched/total` with a
    /// `+0.5` boost when any ingredient EXACTLY matches an expiring/expired name
    /// (so perishable-clearing dishes surface first), recipes with score 0
    /// (nothing in stock) are dropped, and the rest sort by score desc. Ties keep
    /// the input order (a deterministic refinement over the Dart `List.sort`,
    /// never changing membership). Empty when no inventory context.
    ///
    /// NOTE the boost uses EXACT expiring-name membership (matching the Dart
    /// `expiringNameSet.contains(...)`), while `matchedCount` / the 用临期 tab use
    /// the forgiving two-way contains — intentionally mirrored from Flutter.
    static func rankedByAvailability(
        _ recipes: [Recipe],
        inventoryNames: Set<String>,
        expiringNames: Set<String>,
        prefs: Set<String> = []
    ) -> [Recipe] {
        guard !inventoryNames.isEmpty else { return [] }
        let scored = recipes.enumerated().map { offset, recipe -> (offset: Int, recipe: Recipe, score: Double) in
            let matched = matchedCount(inventoryNames, recipe)
            guard matched > 0, !recipe.ingredients.isEmpty else { return (offset, recipe, 0) }
            let base = Double(matched) / Double(recipe.ingredients.count)
            let usesExpiring = recipe.ingredients.contains { exactlyMatchesInventoryName($0, expiringNames) }
            // 饮食偏好 boost only REORDERS in-stock recipes (matched > 0) — never
            // resurrects a score-0 recipe, so it can't bury 临期 dishes.
            return (offset, recipe, base + (usesExpiring ? 0.5 : 0) + preferenceBoost(recipe, prefs))
        }
        return scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.offset < rhs.offset
            }
            .map(\.recipe)
    }

    /// Recipes that use ≥1 expiring item, ranked by how many distinct perishables
    /// each clears (desc); ties keep the input order. Empty when nothing expires.
    static func rankedByExpiringUse(_ recipes: [Recipe], _ expiringNames: Set<String>) -> [Recipe] {
        guard !expiringNames.isEmpty else { return [] }
        let scored = recipes.enumerated()
            .map { (offset: $0.offset, recipe: $0.element, count: expiringCount(expiringNames, $0.element)) }
            .filter { $0.count > 0 }
        return scored.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.offset < rhs.offset
        }.map(\.recipe)
    }

    /// Signals that map a 饮食偏好 preset label to recipe features. Because the
    /// catalog tags/category never literally equal the 7 preset labels, a
    /// label is matched via category synonyms, tag-keyword substrings, ingredient
    /// keywords, or a cooking-time bound — NOT raw tag-overlap (which would be a
    /// silent no-op).
    struct PreferenceSignal {
        var categories: Set<String> = []
        var tagKeywords: [String] = []
        var ingredientKeywords: [String] = []
        var maxMinutes: Int?
    }

    /// Label → signal map (iOS-only enhancement; Flutter never consumes prefs).
    /// 低脂/低碳水 are the weakest signals — the corpus has no nutrition data, so
    /// they key only off category synonyms.
    static let preferenceSignals: [String: PreferenceSignal] = [
        "高蛋白": PreferenceSignal(ingredientKeywords: ["鸡蛋", "鸡胸", "鸡肉", "牛肉", "猪肉", "羊肉", "虾", "鱼", "豆腐", "牛奶", "豆"]), // i18n:ignore domain matching data, not UI text
        "低脂": PreferenceSignal(categories: ["素菜", "汤羹"]), // i18n:ignore domain matching data, not UI text
        "素食": PreferenceSignal(categories: ["素菜"]), // i18n:ignore domain matching data, not UI text
        "家常菜": PreferenceSignal(categories: ["荤菜", "素菜", "主食"]), // i18n:ignore domain matching data, not UI text
        "快手菜": PreferenceSignal(maxMinutes: 15), // i18n:ignore domain matching data, not UI text
        "儿童餐": PreferenceSignal(categories: ["甜品", "主食"], ingredientKeywords: ["鸡蛋", "牛奶", "番茄"]), // i18n:ignore domain matching data, not UI text
        "低碳水": PreferenceSignal(categories: ["荤菜", "水产"]), // i18n:ignore domain matching data, not UI text
    ]

    /// Additive 饮食偏好 boost for a recipe: +0.15 per selected pref the recipe
    /// matches (category synonym / tag keyword / ingredient keyword / cook-time),
    /// capped at 0.45 so it stays below the 临期 +0.5 emphasis. 0 for empty prefs.
    /// Pure (no SwiftData/SwiftUI). iOS-only — NO Flutter counterpart.
    static func preferenceBoost(_ recipe: Recipe, _ prefs: Set<String>) -> Double {
        guard !prefs.isEmpty else { return 0 }
        let category = recipe.category.trimmed
        let tagsLower = recipe.tags.map { $0.trimmed.lowercased() }
        let ingredientNames = recipe.ingredients.flatMap(matchCandidates)
        var total = 0.0
        for pref in prefs {
            guard let signal = preferenceSignals[pref] else { continue }
            var matched = signal.categories.contains(category)
            if !matched {
                matched = signal.tagKeywords.contains { kw in tagsLower.contains { $0.contains(kw.lowercased()) } }
            }
            if !matched {
                matched = signal.ingredientKeywords.contains { kw in ingredientNames.contains { $0.contains(kw.lowercased()) } }
            }
            if !matched, let maxMinutes = signal.maxMinutes {
                matched = recipe.cookingMinutes <= maxMinutes
            }
            if matched { total += 0.15 }
        }
        return min(total, 0.45)
    }

    /// The single recipe covering the MOST distinct expiring/expired names — the
    /// Dashboard "用临期食材今天就能做" fallback. Uses EXACT lowercase membership
    /// (mirrors the Dart `expiringFallbackRecipeProvider`), returns the recipe plus
    /// the covered names. nil when nothing expires or no recipe covers any. Ties
    /// keep the first recipe in input order (strictly-greater comparison).
    static func expiringFallback(
        _ recipes: [Recipe],
        _ expiringNames: Set<String>
    ) -> (recipe: Recipe, covered: Set<String>)? {
        guard !expiringNames.isEmpty else { return nil }
        var best: (recipe: Recipe, covered: Set<String>)?
        for recipe in recipes {
            var covered = Set<String>()
            for ingredient in recipe.ingredients {
                for name in matchCandidates(ingredient) where expiringNames.contains(name) {
                    covered.insert(name)
                }
            }
            guard !covered.isEmpty else { continue }
            if best == nil || covered.count > best!.covered.count {
                best = (recipe, covered)
            }
        }
        return best
    }

    /// Whether the recipe contains any avoided ingredient (忌口). `exclusions` are
    /// pre-normalized (trim + lowercase) keywords; substring match so "花生" also
    /// hides "花生油". Empty exclusions never hide anything.
    static func hasExcludedIngredient(_ recipe: Recipe, _ exclusions: Set<String>) -> Bool {
        guard !exclusions.isEmpty else { return false }
        return recipe.ingredients.contains { ingredient in
            matchCandidates(ingredient).contains { name in
                exclusions.contains { !$0.isEmpty && name.contains($0) }
            }
        }
    }
}
