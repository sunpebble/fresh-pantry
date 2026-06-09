import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for `MealPlanMissing` — the meal-plan shortfall derivation that
/// powers the "本周还缺 N 样食材" card.
struct MealPlanMissingTests {
    private func recipe(_ id: String, _ ingredients: [String]) -> Recipe {
        Recipe(
            id: id, name: id, category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "",
            ingredients: ingredients.map { RecipeIngredient(name: $0, quantity: "1", unit: "份") },
            steps: [], tags: []
        )
    }

    private func entry(_ id: String, recipeId: String, done: Bool = false) -> MealPlanEntry {
        MealPlanEntry(id: id, date: Date(), recipeId: recipeId, recipeName: recipeId, servings: 1, done: done)
    }

    @Test func collectsDedupedMissingFromPendingEntries() {
        let recipes = ["r1": recipe("r1", ["番茄", "鸡蛋"]), "r2": recipe("r2", ["鸡蛋", "葱"])]
        let entries = [entry("e1", recipeId: "r1"), entry("e2", recipeId: "r2")]
        let inventory: Set<String> = ["番茄"] // only 番茄 in stock
        let missing = MealPlanMissing.missingIngredientNames(
            entries: entries, recipesById: recipes, inventoryNames: inventory
        )
        // 鸡蛋 appears in both recipes but is deduped; 番茄 is in stock; order = first-seen.
        #expect(missing == ["鸡蛋", "葱"])
    }

    @Test func skipsDoneEntriesAndUnresolvableRecipes() {
        let recipes = ["r1": recipe("r1", ["鸡蛋"])]
        let entries = [
            entry("e1", recipeId: "r1", done: true), // done → skipped
            entry("e2", recipeId: "missing"),         // recipe not found → skipped
        ]
        let missing = MealPlanMissing.missingIngredientNames(
            entries: entries, recipesById: recipes, inventoryNames: []
        )
        #expect(missing.isEmpty)
    }

    @Test func emptyWhenAllInStock() {
        let recipes = ["r1": recipe("r1", ["番茄", "鸡蛋"])]
        let entries = [entry("e1", recipeId: "r1")]
        let missing = MealPlanMissing.missingIngredientNames(
            entries: entries, recipesById: recipes, inventoryNames: ["番茄", "鸡蛋"]
        )
        #expect(missing.isEmpty)
    }
}
