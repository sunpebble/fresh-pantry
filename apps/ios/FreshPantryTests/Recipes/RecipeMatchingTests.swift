import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for the pure `RecipeMatching` rules (ingredient availability, the
/// match/missing counts, 临期 ranking, and the 忌口 exclusion filter).
struct RecipeMatchingTests {
    private func ingredient(_ name: String) -> RecipeIngredient {
        RecipeIngredient(name: name, quantity: "1", unit: "份")
    }

    private func recipe(_ name: String, _ ingredients: [String]) -> Recipe {
        Recipe(
            id: name, name: name, category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: ingredients.map(ingredient), steps: [], tags: []
        )
    }

    private func inv(_ name: String, state: FreshnessState = .fresh) -> Ingredient {
        Ingredient(id: name, name: name, quantity: "1", unit: "份", imageUrl: "", freshnessPercent: 1, state: state)
    }

    @Test func inventoryNameSetNormalizes() {
        let names = RecipeMatching.inventoryNameSet([inv("  Egg "), inv("牛奶"), inv("")])
        #expect(names == ["egg", "牛奶"])
    }

    @Test func ingredientMatchesTwoWayContains() {
        let names: Set<String> = ["鸡蛋", "milk"]
        #expect(RecipeMatching.ingredientMatchesInventory(ingredient("鸡蛋"), names))
        // recipe ingredient is a substring of inventory name
        #expect(RecipeMatching.ingredientMatchesInventory(ingredient("蛋"), ["鸡蛋"]))
        // inventory name is a substring of recipe ingredient
        #expect(RecipeMatching.ingredientMatchesInventory(ingredient("全脂牛奶"), ["牛奶"]))
        #expect(!RecipeMatching.ingredientMatchesInventory(ingredient("豆腐"), names))
    }

    @Test func matchedAndMissingCounts() {
        let r = recipe("番茄炒蛋", ["番茄", "鸡蛋", "葱"])
        let names = RecipeMatching.inventoryNameSet([inv("番茄"), inv("鸡蛋")])
        #expect(RecipeMatching.matchedCount(names, r) == 2)
        #expect(RecipeMatching.missingIngredients(names, r).map(\.name) == ["葱"])
    }

    @Test func expiringCountAndRanking() {
        let a = recipe("A", ["番茄", "鸡蛋"]) // uses 2 expiring
        let b = recipe("B", ["鸡蛋", "盐"])   // uses 1 expiring
        let c = recipe("C", ["米", "油"])     // uses 0
        let expiring: Set<String> = RecipeMatching.inventoryNameSet([
            inv("番茄", state: .urgent), inv("鸡蛋", state: .expired),
        ])
        #expect(RecipeMatching.expiringCount(expiring, a) == 2)
        #expect(RecipeMatching.expiringCount(expiring, c) == 0)
        // Ranked: A (clears 2) before B (clears 1); C dropped.
        #expect(RecipeMatching.rankedByExpiringUse([c, b, a], expiring).map(\.id) == ["A", "B"])
    }

    @Test func rankedByAvailabilityScoresAndBoostsExpiring() {
        let a = recipe("A", ["番茄", "鸡蛋"])      // matched 2/2 = 1.0 + 临期 boost 0.5 = 1.5
        let b = recipe("B", ["番茄", "盐", "油"])  // matched 1/3 ≈ 0.33 + boost 0.5 = 0.83
        let c = recipe("C", ["米", "面"])          // matched 0 → dropped
        let inventory = [inv("番茄", state: .urgent), inv("鸡蛋")]
        let names = RecipeMatching.inventoryNameSet(inventory)
        let expiring = RecipeMatching.inventoryNameSet(inventory.filter { $0.state != .fresh })
        let ranked = RecipeMatching.rankedByAvailability(
            [c, b, a], inventoryNames: names, expiringNames: expiring
        )
        #expect(ranked.map(\.id) == ["A", "B"]) // A (1.5) before B (0.83); C dropped
    }

    @Test func rankedByAvailabilityEmptyWithoutInventory() {
        let a = recipe("A", ["番茄"])
        #expect(
            RecipeMatching.rankedByAvailability([a], inventoryNames: [], expiringNames: []).isEmpty
        )
    }

    @Test func expiringFallbackPicksMaxCoverage() {
        let a = recipe("A", ["番茄", "鸡蛋", "盐"]) // covers 2 expiring (番茄, 鸡蛋)
        let b = recipe("B", ["番茄", "油"])         // covers 1 expiring
        let c = recipe("C", ["米", "面"])           // covers 0
        let expiring: Set<String> = RecipeMatching.inventoryNameSet([
            inv("番茄", state: .urgent), inv("鸡蛋", state: .expired),
        ])
        let fallback = RecipeMatching.expiringFallback([c, b, a], expiring)
        #expect(fallback?.recipe.id == "A")
        #expect(fallback?.covered == ["番茄", "鸡蛋"])
    }

    @Test func expiringFallbackNilWhenNothingExpires() {
        let a = recipe("A", ["番茄"])
        #expect(RecipeMatching.expiringFallback([a], []) == nil)
    }

    @Test func excludedIngredientSubstringMatch() {
        let r = recipe("花生鸡丁", ["花生油", "鸡肉"])
        #expect(RecipeMatching.hasExcludedIngredient(r, ["花生"])) // substring hides 花生油
        #expect(!RecipeMatching.hasExcludedIngredient(r, ["牛肉"]))
        #expect(!RecipeMatching.hasExcludedIngredient(r, [])) // empty never hides
    }
}
