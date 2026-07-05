import Foundation
import Testing
@testable import FreshPantry

/// 「今天做什么」推荐选取逻辑:临期优先 → 现有可做 → 任意第一道。纯函数,复用
/// 已测的 `RecipeMatching` 原语,所以可在 Intent 运行时之外独立测。
struct TodayRecipeSelectorTests {
    private func recipe(id: String, name: String, ingredients: [String]) -> Recipe {
        Recipe(
            id: id, name: name, category: "家常", difficulty: 2, cookingMinutes: 15,
            description: "", ingredients: ingredients.map { RecipeIngredient(name: $0) }, steps: ["做"]
        )
    }

    private func item(_ name: String, _ state: FreshnessState) -> Ingredient {
        Ingredient(
            name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 0.5, state: state, category: "果蔬生鲜"
        )
    }

    @Test func picksRecipeUsingExpiringFirst() {
        let recipes = [
            recipe(id: "a", name: "清炒时蔬", ingredients: ["青菜"]),
            recipe(id: "b", name: "番茄炒蛋", ingredients: ["番茄", "鸡蛋"]),
        ]
        // 番茄临期(urgent),青菜不在库存 → 应推番茄炒蛋(用掉临期番茄)。
        let inventory = [item("番茄", .urgent), item("鸡蛋", .fresh)]
        let pick = TodayRecipeSelector.pick(recipes: recipes, inventory: inventory)
        #expect(pick?.recipe.id == "b")
        #expect((pick?.expiringUseCount ?? 0) >= 1)
    }

    @Test func fallsBackToAvailableWhenNothingExpiring() {
        let recipes = [
            recipe(id: "a", name: "番茄炒蛋", ingredients: ["番茄", "鸡蛋"]),
            recipe(id: "b", name: "白灼虾", ingredients: ["虾"]),
        ]
        // 全 fresh → 无临期;番茄炒蛋两样都在库存,白灼虾一样都没有。
        let inventory = [item("番茄", .fresh), item("鸡蛋", .fresh)]
        let pick = TodayRecipeSelector.pick(recipes: recipes, inventory: inventory)
        #expect(pick?.recipe.id == "a")
        #expect(pick?.expiringUseCount == 0)
        #expect((pick?.matchedCount ?? 0) >= 1)
    }

    @Test func fallsBackToFirstRecipeWhenNoInventory() {
        let recipes = [
            recipe(id: "a", name: "红烧肉", ingredients: ["五花肉"]),
            recipe(id: "b", name: "番茄炒蛋", ingredients: ["番茄"]),
        ]
        let pick = TodayRecipeSelector.pick(recipes: recipes, inventory: [])
        #expect(pick?.recipe.id == "a")
        #expect(pick?.expiringUseCount == 0)
        #expect(pick?.matchedCount == 0)
    }

    @Test func returnsNilWhenNoRecipes() {
        #expect(TodayRecipeSelector.pick(recipes: [], inventory: []) == nil)
    }

    @Test func dialogMentionsExpiringWhenClearingPerishables() {
        let pick = TodayRecipeSelector.Pick(
            recipe: recipe(id: "b", name: "番茄炒蛋", ingredients: ["番茄", "鸡蛋"]),
            expiringUseCount: 2, matchedCount: 2
        )
        let dialog = TodayRecipeSelector.dialog(for: pick)
        #expect(dialog == String(localized: "intent.today.result.expiring \("番茄炒蛋") \(2)"))
    }
}
