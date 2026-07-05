import Foundation
import Testing
@testable import FreshPantry

/// JSON round-trip + defaults for ShoppingItem, Recipe/RecipeIngredient,
/// FoodLogEntry, FoodDetails, AiSettings, ReminderSettings.
struct EntityRoundTripTests {
    // MARK: ShoppingItem

    @Test func shoppingItemDefaultsAndRoundTrip() throws {
        let decoded = try DomainJSON.decode(ShoppingItem.self, from: #"{"name":"牛奶"}"#)
        #expect(decoded.id == "")
        #expect(decoded.detail == "")
        #expect(decoded.category == FoodCategories.other)
        #expect(decoded.isChecked == false)
        #expect(decoded.imageUrl == nil)

        let item = ShoppingItem(
            id: "si_1", name: "鸡蛋", detail: "12 个", imageUrl: "x",
            category: "乳品蛋类", isChecked: true, remoteVersion: 3
        )
        let json = try DomainJSON.encodeToString(item)
        #expect(try DomainJSON.decode(ShoppingItem.self, from: json) == item)
    }

    @Test func shoppingItemNewIdIsUuid() {
        // Sync-clean: a freshly minted shopping id is a UUID, so the household
        // sync engine reconciles it by id remotely without duplicating.
        #expect(ProposalApply.isUuid(ShoppingItem.newId()))
    }

    @Test func shoppingItemFromIngredient() {
        let ingredient = Ingredient(
            name: "番茄", quantity: "3", unit: "个", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: "果蔬生鲜"
        )
        let item = ShoppingItem.fromIngredient(ingredient, id: "si_x")
        #expect(item.detail == "3 个")
        #expect(item.imageUrl == nil) // empty imageUrl -> nil
        #expect(item.category == "果蔬生鲜")
    }

    @Test func shoppingItemFromIngredientCategoryFallback() {
        let ingredient = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: nil
        )
        #expect(ShoppingItem.fromIngredient(ingredient).category == FoodCategories.other)
    }

    // MARK: Recipe

    @Test func recipeDefaults() throws {
        let recipe = try DomainJSON.decode(Recipe.self, from: #"{"name":"汤"}"#)
        #expect(recipe.difficulty == 0)
        #expect(recipe.cookingMinutes == 30) // default differs from difficulty
        #expect(recipe.tags.isEmpty)
        #expect(recipe.ingredients.isEmpty)
    }

    @Test func recipeRoundTrip() throws {
        let recipe = Recipe(
            id: "r_1", name: "番茄炒蛋", category: "家常", difficulty: 2,
            cookingMinutes: 15, description: "经典",
            ingredients: [
                RecipeIngredient(name: "番茄", quantity: 2, unit: "个"),
                RecipeIngredient(name: "鸡蛋", quantity: 3, unit: "个"),
            ],
            steps: ["切番茄", "打蛋"], tags: ["快手"], imageUrl: "x", remoteVersion: 1
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded == recipe) // identity by id
        #expect(decoded.ingredients.count == 2)
        #expect(decoded.ingredients[0].quantity == 2)
        #expect(decoded.ingredients[0].unit == "个")
        #expect(decoded.ingredients[0].displayAmount == "2个")
    }

    @Test func recipeVideoUrlRoundTrip() throws {
        let recipe = Recipe(
            id: "r_v", name: "红烧肉", category: "荤菜", difficulty: 3,
            cookingMinutes: 60, description: "下饭",
            ingredients: [], steps: ["焯水", "炖"], tags: [],
            imageUrl: "img", videoUrl: "https://b23.tv/abc"
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded.videoUrl == "https://b23.tv/abc")
    }

    @Test func recipeMissingVideoUrlDecodesNil() throws {
        // 老数据没有 videoUrl 键 → 向后兼容解码为 nil。
        let legacy = #"{"id":"r1","name":"n","category":"荤菜","difficulty":1,"cookingMinutes":10,"description":"d","ingredients":[],"steps":[],"tags":[],"imageUrl":null,"remoteVersion":0,"clientUpdatedAt":null,"deletedAt":null}"#
        let decoded = try DomainJSON.decode(Recipe.self, from: legacy)
        #expect(decoded.videoUrl == nil)
    }

    @Test func recipeNotesRoundTrip() throws {
        // 烹饪贴士/备注:自由文本随菜谱往返编解码。
        let recipe = Recipe(
            id: "r_n", name: "红烧肉", category: "荤菜", difficulty: 3,
            cookingMinutes: 60, description: "下饭",
            ingredients: [], steps: ["焯水", "炖"], tags: [],
            notes: "焯水后冲冷水,肉质更紧实"
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded.notes == "焯水后冲冷水,肉质更紧实")
    }

    @Test func recipeMissingNotesDecodesNil() throws {
        // 老数据没有 notes 键 → 向后兼容解码为 nil(lenient)。
        let legacy = #"{"id":"r1","name":"n","category":"荤菜","difficulty":1,"cookingMinutes":10,"description":"d","ingredients":[],"steps":[],"tags":[],"imageUrl":null,"remoteVersion":0}"#
        let decoded = try DomainJSON.decode(Recipe.self, from: legacy)
        #expect(decoded.notes == nil)
    }

    @Test func recipeNutritionRoundTrip() throws {
        // 每份营养(pipeline LLM 估算)随菜谱往返。
        let recipe = Recipe(
            id: "r_nut", name: "番茄炒蛋", category: "家常", difficulty: 2,
            cookingMinutes: 15, description: "", ingredients: [], steps: [],
            nutrition: NutritionFacts(energyKcal: 220, protein: 12, carbs: 8, fat: 14)
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded.nutrition?.energyKcal == 220)
        #expect(decoded.nutrition?.protein == 12)
        #expect(decoded.nutrition?.carbs == 8)
        #expect(decoded.nutrition?.fat == 14)
    }

    @Test func recipeMissingNutritionDecodesNil() throws {
        // 老数据无 nutrition 键 → 向后兼容解码为 nil。
        let legacy = #"{"id":"r1","name":"n","category":"荤菜","difficulty":1,"cookingMinutes":10,"description":"d","ingredients":[],"steps":[],"tags":[],"remoteVersion":0}"#
        let decoded = try DomainJSON.decode(Recipe.self, from: legacy)
        #expect(decoded.nutrition == nil)
    }

    @Test func recipeStepDurationsRoundTrip() throws {
        // 每步时长(秒,与 steps 索引对齐;某步无时长为 null)随菜谱往返。
        let recipe = Recipe(
            id: "r_sd", name: "炖肉", category: "荤菜", difficulty: 3,
            cookingMinutes: 40, description: "", ingredients: [],
            steps: ["焯水", "炖煮"], stepDurations: [nil, 1800]
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded.stepDurations == [nil, 1800])
    }

    @Test func recipeMissingStepDurationsDecodesNil() throws {
        // 老数据无 stepDurations 键 → 向后兼容解码为 nil(steps 仍是纯字符串)。
        let legacy = #"{"id":"r1","name":"n","category":"荤菜","difficulty":1,"cookingMinutes":10,"description":"d","ingredients":[],"steps":["a"],"tags":[],"remoteVersion":0}"#
        let decoded = try DomainJSON.decode(Recipe.self, from: legacy)
        #expect(decoded.stepDurations == nil)
        #expect(decoded.steps == ["a"])
    }

    @Test func difficultyLabel() {
        func recipe(_ d: Int) -> Recipe {
            Recipe(id: "x", name: "n", category: "", difficulty: d,
                   cookingMinutes: 30, description: "", ingredients: [], steps: [])
        }
        #expect(recipe(0).difficultyLabel == String(localized: "recipe.difficulty.unset"))
        #expect(recipe(-1).difficultyLabel == String(localized: "recipe.difficulty.unset"))
        #expect(recipe(3).difficultyLabel == String(localized: "recipe.difficulty.level \(3)"))
        #expect(recipe(9).difficultyLabel == String(localized: "recipe.difficulty.level \(5)")) // clamp to 5
    }

    // MARK: Backward-compatible decode (LOSSLESS) — the highest-risk path.

    @Test func recipeIngredientLegacyStringRangeDecodesLossless() throws {
        // Old all-string shape persisted by an older install / synced to
        // Supabase: string `quantity` "6-15", a unit, and a redundant `amount`.
        // The range MUST survive into quantity/quantityMax with no loss.
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self,
            from: #"{"name":"白糖","quantity":"6-15","unit":"克","amount":"6-15克"}"#
        )
        #expect(decoded.name == "白糖")
        #expect(decoded.quantity == 6)
        #expect(decoded.quantityMax == 15)
        #expect(decoded.unit == "克")
        #expect(decoded.note == nil) // numeric quantity present → legacy amount ignored
        #expect(decoded.displayAmount == "6-15克")
    }

    @Test func recipeIngredientLegacyStringQuantityDecodesNumber() throws {
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self,
            from: #"{"name":"洋葱","quantity":"200","unit":"克","amount":"200克"}"#
        )
        #expect(decoded.quantity == 200)
        #expect(decoded.quantityMax == nil)
        #expect(decoded.unit == "克")
        #expect(decoded.note == nil)
        #expect(decoded.displayAmount == "200克")
    }

    @Test func recipeIngredientLegacyFuzzyAmountPreservedInNote() throws {
        // Old fuzzy amount-only ingredient ("一小把") — no number anywhere. The
        // word MUST be preserved (into `note`), never dropped.
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self, from: #"{"name":"葱","amount":"一小把"}"#
        )
        #expect(decoded.quantity == nil)
        #expect(decoded.unit == nil)
        #expect(decoded.note == "一小把")
        #expect(decoded.displayAmount == "一小把")
    }

    @Test func recipeIngredientLegacyEmptyStringsDecodeToNothing() throws {
        // The bundled corpus's "no amount" rows: quantity/unit/amount all "".
        // Empty strings must NOT become quantity 0 or a blank unit.
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self, from: #"{"name":"生粉","quantity":"","unit":"","amount":""}"#
        )
        #expect(decoded.name == "生粉")
        #expect(decoded.quantity == nil)
        #expect(decoded.quantityMax == nil)
        #expect(decoded.unit == nil)
        #expect(decoded.note == nil)
        #expect(decoded.displayAmount == "")
    }

    @Test func recipeIngredientNewNumberShapeRoundTrips() throws {
        // The new on-disk shape: real JSON numbers, no `amount`, omitted keys.
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self,
            from: #"{"name":"白糖","quantity":6,"quantityMax":15,"unit":"克"}"#
        )
        #expect(decoded.quantity == 6)
        #expect(decoded.quantityMax == 15)
        #expect(decoded.unit == "克")
        #expect(decoded.displayAmount == "6-15克")
    }

    @Test func recipeIngredientEncodeOmitsAbsentKeysAndAmount() throws {
        let json = try DomainJSON.encodeToString(RecipeIngredient(name: "桂皮", note: "一小片"))
        #expect(json.contains("\"name\":\"桂皮\""))
        #expect(json.contains("\"note\":\"一小片\""))
        #expect(!json.contains("amount"))
        #expect(!json.contains("quantity"))
        #expect(!json.contains("unit"))
    }

    @Test func recipeIngredientDisplayAmount() {
        #expect(RecipeIngredient(name: "糖", quantity: 10, unit: "g").displayAmount == "10g")
        #expect(RecipeIngredient(name: "糖", quantity: 6, quantityMax: 15, unit: "克").displayAmount == "6-15克")
        #expect(RecipeIngredient(name: "桂皮", note: "一小片").displayAmount == "一小片")
        #expect(RecipeIngredient(name: "蒜", unit: "瓣").displayAmount == "瓣")  // 仅单位无数量:仍显示单位
        #expect(RecipeIngredient(name: "生粉").displayAmount == "")
    }

    @Test func recipeIngredientScaledBy() {
        let ingredient = RecipeIngredient(name: "糖", quantity: 10, unit: "g")
        #expect(ingredient.scaledBy(2).quantity == 20)
        #expect(ingredient.scaledBy(1) == ingredient) // factor==1 no-op
        // Range scales both bounds.
        let ranged = RecipeIngredient(name: "糖", quantity: 6, quantityMax: 15, unit: "克")
        let scaled = ranged.scaledBy(2)
        #expect(scaled.quantity == 12)
        #expect(scaled.quantityMax == 30)
        // Fuzzy (no numeric quantity) is unchanged.
        let nonNumeric = RecipeIngredient(name: "盐", note: "适量")
        #expect(nonNumeric.scaledBy(3) == nonNumeric)
    }

    // MARK: FoodDetails

    @Test func foodDetailsWritesCacheVersion6() throws {
        let details = FoodDetails(
            displayName: "牛奶", description: "d", imageUrl: nil, category: "乳品蛋类",
            storage: .fridge, shelfLifeDays: 7, source: "off",
            fetchedAt: Date(timeIntervalSince1970: 1000),
            nutrition: NutritionFacts(energyKcal: 42)
        )
        let json = try DomainJSON.encodeToString(details)
        #expect(json.contains("\"cacheVersion\":6"))
        let decoded = try DomainJSON.decode(FoodDetails.self, from: json)
        #expect(decoded.nutrition?.energyKcal == 42)
    }

    @Test func foodDetailsFetchedAtEpochFallback() throws {
        let decoded = try DomainJSON.decode(FoodDetails.self, from: #"{"displayName":"x"}"#)
        #expect(decoded.fetchedAt == Date(timeIntervalSince1970: 0))
    }

    @Test func nutritionFromOffNutriments() {
        let facts = NutritionFacts.fromOffNutriments([
            "energy-kcal_100g": 52,
            "proteins_100g": "0.3",
        ])
        #expect(facts?.energyKcal == 52)
        #expect(facts?.protein == 0.3)
        #expect(NutritionFacts.fromOffNutriments([:]) == nil) // empty -> nil
    }

    // MARK: AiSettings / ReminderSettings

    @Test func aiSettingsTimeoutSeconds() throws {
        let settings = AiSettings(baseUrl: "u", apiKey: "k", model: "m", timeout: 90)
        let json = try DomainJSON.encodeToString(settings)
        #expect(json.contains("\"timeoutSeconds\":90"))
        #expect(try DomainJSON.decode(AiSettings.self, from: json).timeout == 90)
        #expect(AiSettings.empty.isConfigured == false)
        #expect(settings.isConfigured == true)
    }

    @Test func aiSettingsDefaultTimeout() throws {
        let decoded = try DomainJSON.decode(AiSettings.self, from: #"{"baseUrl":"u"}"#)
        #expect(decoded.timeout == 60)
    }

    @Test func reminderSettingsDefaultsAndOffsets() throws {
        let decoded = try DomainJSON.decode(ReminderSettings.self, from: "{}")
        #expect(decoded.remindD1 == true)
        #expect(decoded.remindD3 == true)
        #expect(decoded.remindD7 == false)
        #expect(decoded.remindDaily == true)
        #expect(decoded.enabledOffsetDays == [3, 1]) // largest-first, D7 off
    }
}
