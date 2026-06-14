import Foundation
import Testing
@testable import FreshPantry

/// `RecipeMatching.missingShoppingDetails` — the scaled (name, detail) pairs
/// fed to the shopping list when adding a recipe's missing ingredients. Detail
/// must carry the SCALED decimal amount so the row shows a quantity and same-unit
/// re-adds merge.
struct MissingShoppingDetailTests {
    private func recipe(_ ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(
            id: "r", name: "r", category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: ingredients, steps: [], tags: []
        )
    }

    @Test func carriesUnscaledAmountAtFactorOne() {
        let r = recipe([RecipeIngredient(name: "番茄", quantity: 200, unit: "克")])
        let adds = RecipeMatching.missingShoppingDetails([], r, scaleFactor: 1)
        #expect(adds.count == 1)
        #expect(adds[0].name == "番茄")
        #expect(adds[0].detail == "200克")
    }

    @Test func scalesQuantityIntoDetail() {
        let r = recipe([RecipeIngredient(name: "番茄", quantity: 200, unit: "克")])
        let adds = RecipeMatching.missingShoppingDetails([], r, scaleFactor: 2)
        #expect(adds[0].detail == "400克")
    }

    @Test func detailIsMergeableByQuantityText() {
        // The whole point of #1: the detail re-parses so ShoppingStore.mergeQuantity
        // can sum same-unit re-adds across recipes.
        let r = recipe([RecipeIngredient(name: "牛奶", quantity: 1, quantityMax: nil, unit: "盒")])
        let detail = RecipeMatching.missingShoppingDetails([], r, scaleFactor: 3)[0].detail
        let parsed = QuantityText.parseLeadingQuantity(detail)
        #expect(parsed?.magnitude == "3")
        #expect(parsed?.remainder == "盒")
    }

    @Test func onlyMissingIngredientsIncluded() {
        let r = recipe([
            RecipeIngredient(name: "番茄", quantity: 2, unit: "个"),
            RecipeIngredient(name: "鸡蛋", quantity: 3, unit: "个"),
        ])
        // 鸡蛋 is in stock → excluded.
        let adds = RecipeMatching.missingShoppingDetails(["鸡蛋"], r, scaleFactor: 1)
        #expect(adds.map(\.name) == ["番茄"])
    }

    @Test func fuzzyAmountPassesThroughNote() {
        let r = recipe([RecipeIngredient(name: "盐", note: "适量")])
        let adds = RecipeMatching.missingShoppingDetails([], r, scaleFactor: 2)
        // 适量 has no number → scaledBy no-op → note flows through as the detail.
        #expect(adds[0].detail == "适量")
    }
}
