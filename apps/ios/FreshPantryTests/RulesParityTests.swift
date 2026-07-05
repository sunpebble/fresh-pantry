import Foundation
import Testing
@testable import FreshPantry

/// Pure-rule parity: IngredientIdentity, QuantityText, ExpiryCalculator,
/// FoodCategories, FoodKnowledge.
struct RulesParityTests {
    private func row(
        name: String, unit: String, quantity: String = "1",
        storage: IconType = .pantry, category: String? = nil
    ) -> Ingredient {
        Ingredient(
            name: name, quantity: quantity, unit: unit, imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: category, storage: storage
        )
    }

    // MARK: IngredientIdentity

    @Test func perishableAlwaysNewBatch() {
        // 猪肉 is a knowledge-base perishable even with category 其他.
        let inventory = [row(name: "猪肉", unit: "份", storage: .fridge, category: "其他")]
        let index = IngredientIdentity.resolveMergeTarget(
            name: "猪肉", unit: "份", storage: .fridge, category: "其他", inventory: inventory
        )
        #expect(index == -1)
    }

    @Test func nonPerishableCaseInsensitiveNameMatch() {
        let inventory = [row(name: "Salt", unit: "g", quantity: "100", storage: .pantry)]
        let index = IngredientIdentity.resolveMergeTarget(
            name: "  salt ", unit: "g", storage: .pantry, category: "其他", inventory: inventory
        )
        #expect(index == 0) // name match is case-insensitive + trimmed
    }

    @Test func unitMatchIsCaseSensitive() {
        let inventory = [row(name: "米", unit: "G", quantity: "100", storage: .pantry)]
        let index = IngredientIdentity.resolveMergeTarget(
            name: "米", unit: "g", storage: .pantry, category: "其他", inventory: inventory
        )
        #expect(index == -1) // "g" != "G" -> new row
    }

    @Test func nonNumericExistingQuantityYieldsNewBatch() {
        let inventory = [row(name: "盐", unit: "g", quantity: "适量", storage: .pantry)]
        let index = IngredientIdentity.resolveMergeTarget(
            name: "盐", unit: "g", storage: .pantry, category: "香料草本", inventory: inventory
        )
        #expect(index == -1) // merging would discard the non-numeric stock
    }

    @Test func storageMismatchYieldsNewBatch() {
        let inventory = [row(name: "米", unit: "g", quantity: "100", storage: .pantry)]
        let index = IngredientIdentity.resolveMergeTarget(
            name: "米", unit: "g", storage: .fridge, category: "其他", inventory: inventory
        )
        #expect(index == -1)
    }

    @Test func blankNameOrUnitYieldsNewBatch() {
        let inventory = [row(name: "米", unit: "g", quantity: "100", storage: .pantry)]
        #expect(IngredientIdentity.resolveMergeTarget(
            name: "  ", unit: "g", storage: .pantry, inventory: inventory) == -1)
        #expect(IngredientIdentity.resolveMergeTarget(
            name: "米", unit: "  ", storage: .pantry, inventory: inventory) == -1)
    }

    // MARK: QuantityText

    @Test func formatQuantityWholeNumber() {
        #expect(QuantityText.formatQuantity(2.0) == "2")
        #expect(QuantityText.formatQuantity(10.0) == "10")
    }

    @Test func formatQuantityStripsFloatArtifacts() {
        #expect(QuantityText.formatQuantity(1.2000000000000002) == "1.2")
        #expect(QuantityText.formatQuantity(0.5) == "0.5")
        #expect(QuantityText.formatQuantity(1.25) == "1.25")
    }

    @Test func parseLeadingQuantity() {
        let parsed = QuantityText.parseLeadingQuantity("1.5 kg")
        #expect(parsed?.magnitude == "1.5")
        #expect(parsed?.remainder == "kg")
        #expect(QuantityText.parseLeadingQuantity("3个")?.magnitude == "3")
        #expect(QuantityText.parseLeadingQuantity("适量") == nil) // no leading number
    }

    // MARK: ExpiryCalculator

    @Test func expiryLabelStrings() {
        let now = MealPlanEntry.parseDate("2026-06-08")!
        func label(_ offsetDays: Int) -> String {
            let expiry = now.addingTimeInterval(TimeInterval(offsetDays * 86400))
            return ExpiryCalculator.expiryLabelFor(expiry, now: now)
        }
        #expect(label(-3) == String(localized: "expiry.expiredDays \(3)"))
        #expect(label(0) == String(localized: "expiry.today"))
        #expect(label(1) == String(localized: "expiry.tomorrow"))
        #expect(label(5) == String(localized: "expiry.inDays \(5)"))
    }

    @Test func freshnessStateTiers() {
        let now = MealPlanEntry.parseDate("2026-06-08")!
        func state(offsetDays: Int, freshness: Double) -> FreshnessState {
            let expiry = now.addingTimeInterval(TimeInterval(offsetDays * 86400))
            return ExpiryCalculator.freshnessStateForExpiry(
                freshness: freshness, expiryDate: expiry, now: now
            )
        }
        #expect(state(offsetDays: -1, freshness: 1.0) == .expired)
        #expect(state(offsetDays: 2, freshness: 1.0) == .urgent) // urgentWithinDays=2
        #expect(state(offsetDays: 1, freshness: 1.0) == .urgent)
        #expect(state(offsetDays: 10, freshness: 0.8) == .fresh)
        #expect(state(offsetDays: 10, freshness: 0.3) == .expiringSoon)
        // No expiry date: pure ratio tier.
        #expect(ExpiryCalculator.freshnessStateForExpiry(
            freshness: 0.6, expiryDate: nil) == .fresh)
        #expect(ExpiryCalculator.freshnessStateForExpiry(
            freshness: 0.4, expiryDate: nil) == .expiringSoon)
    }

    @Test func expiryFreshnessClampAndZeroShelfLife() {
        let now = MealPlanEntry.parseDate("2026-06-08")!
        let expiry = now.addingTimeInterval(TimeInterval(5 * 86400))
        #expect(ExpiryCalculator.expiryFreshness(
            expiryDate: expiry, totalShelfLifeDays: 10, now: now) == 0.5)
        #expect(ExpiryCalculator.expiryFreshness(
            expiryDate: expiry, totalShelfLifeDays: 0, now: now) == 0.0)
        // Past expiry clamps to 0.
        let past = now.addingTimeInterval(TimeInterval(-3 * 86400))
        #expect(ExpiryCalculator.expiryFreshness(
            expiryDate: past, totalShelfLifeDays: 10, now: now) == 0.0)
    }

    @Test func urgentWithinDaysConstant() {
        #expect(ExpiryCalculator.urgentWithinDays == 2)
    }

    // MARK: FoodCategories

    @Test func foodCategoriesNormalizeAliases() {
        #expect(FoodCategories.normalize("蔬菜") == FoodCategories.freshProduce)
        #expect(FoodCategories.normalize("肉类") == FoodCategories.meatAndSeafood)
        #expect(FoodCategories.normalize("乳制品") == FoodCategories.dairyAndEggs)
        #expect(FoodCategories.normalize("调味料") == FoodCategories.herbsAndSpices)
        #expect(FoodCategories.normalize("食品柜常备") == FoodCategories.other)
        #expect(FoodCategories.normalize("未知分类xyz") == FoodCategories.other) // unmapped non-empty
        #expect(FoodCategories.normalize("") == nil)
        #expect(FoodCategories.normalize(nil) == nil)
    }

    @Test func foodCategoriesIsPerishable() {
        #expect(FoodCategories.isPerishable("果蔬生鲜"))
        #expect(FoodCategories.isPerishable("蔬菜")) // via alias
        #expect(!FoodCategories.isPerishable("其他"))
        #expect(!FoodCategories.isPerishable(nil))
    }

    // MARK: FoodKnowledge

    @Test func foodKnowledgeLongestKeyWins() {
        // 五花肉 must win over 肉/猪肉 substrings; 鸡胸 over 鸡.
        #expect(FoodKnowledge.lookup("五花肉")?.shelfLifeDays == 3)
        #expect(FoodKnowledge.lookup("鸡胸肉")?.shelfLifeDays == 2)
        #expect(FoodKnowledge.lookup("牛奶")?.category == FoodCategories.dairyAndEggs)
    }

    @Test func foodKnowledgeSingleCharKeyExactMatch() {
        // length-1 key "蛋" only matches the whole name; "蛋糕" must NOT resolve to egg.
        #expect(FoodKnowledge.lookup("蛋")?.category == FoodCategories.dairyAndEggs)
        #expect(FoodKnowledge.lookup("蛋糕") == nil)
    }

    @Test func foodKnowledgeIsPerishableName() {
        #expect(FoodKnowledge.isPerishableName("猪肉"))
        #expect(FoodKnowledge.isPerishableName("番茄"))
        #expect(!FoodKnowledge.isPerishableName("盐"))
        #expect(!FoodKnowledge.isPerishableName("未知食材xyz"))
    }

    @Test func foodKnowledgeEnglishName() {
        #expect(FoodKnowledge.englishName("牛奶") == "milk")
        #expect(FoodKnowledge.englishName("五花肉") == "pork belly")
    }

    @Test func foodKnowledgePresetsAndUnits() {
        #expect(FoodKnowledge.shelfLifePresets == [3, 7, 14, 30])
        #expect(FoodKnowledge.units == ["个", "瓶", "袋", "盒", "包", "g", "kg", "ml", "L"])
    }
}
