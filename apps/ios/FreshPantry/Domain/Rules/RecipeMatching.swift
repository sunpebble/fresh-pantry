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

    /// A recipe ingredient is "in stock" when its name is a substring of (or
    /// contains) any inventory name — a forgiving two-way contains match.
    static func ingredientMatchesInventory(_ ingredient: RecipeIngredient, _ inventoryNames: Set<String>) -> Bool {
        let name = ingredient.name.trimmed.lowercased()
        guard !name.isEmpty else { return false }
        return inventoryNames.contains { $0.contains(name) || name.contains($0) }
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
        expiringNames: Set<String>
    ) -> [Recipe] {
        guard !inventoryNames.isEmpty else { return [] }
        let scored = recipes.enumerated().map { offset, recipe -> (offset: Int, recipe: Recipe, score: Double) in
            let matched = matchedCount(inventoryNames, recipe)
            guard matched > 0, !recipe.ingredients.isEmpty else { return (offset, recipe, 0) }
            let base = Double(matched) / Double(recipe.ingredients.count)
            let usesExpiring = recipe.ingredients.contains { expiringNames.contains($0.name.trimmed.lowercased()) }
            return (offset, recipe, base + (usesExpiring ? 0.5 : 0))
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
                let name = ingredient.name.trimmed.lowercased()
                if expiringNames.contains(name) { covered.insert(name) }
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
            let name = ingredient.name.trimmed.lowercased()
            guard !name.isEmpty else { return false }
            return exclusions.contains { !$0.isEmpty && name.contains($0) }
        }
    }
}
