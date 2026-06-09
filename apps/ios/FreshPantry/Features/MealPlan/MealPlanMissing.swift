import Foundation

/// Pure derivation of the meal-plan shortfall — the deduped ingredient names that
/// the not-yet-cooked planned dishes need but the pantry lacks. Ported from
/// `mealPlanMissingIngredientsProvider`. No SwiftUI / SwiftData dependency.
enum MealPlanMissing {
    /// Names (display-cased, deduped case-insensitively, in first-seen order) of
    /// ingredients required by pending (not `done`) entries that aren't in stock.
    /// Entries whose recipe can't be resolved are skipped.
    static func missingIngredientNames(
        entries: [MealPlanEntry],
        recipesById: [String: Recipe],
        inventoryNames: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        var missing: [String] = []
        for entry in entries where !entry.done {
            guard let recipe = recipesById[entry.recipeId] else { continue }
            for ingredient in recipe.ingredients {
                let name = ingredient.name.trimmed
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                if seen.contains(key) { continue }
                if RecipeMatching.ingredientMatchesInventory(ingredient, inventoryNames) { continue }
                seen.insert(key)
                missing.append(name)
            }
        }
        return missing
    }
}
