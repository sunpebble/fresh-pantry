import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Pure shelf-aisle category ordering (#19) + the ShoppingStore integration that
/// makes `displaySections` follow the user's custom order.
struct ShoppingCategoryOrderTests {
    @Test func emptyStoredFallsBackToCanonical() {
        #expect(ShoppingCategoryOrder.normalizedOrder([]) == ShoppingCategoryOrder.canonical)
    }

    @Test func fullPermutationIsKept() {
        let reversed = Array(ShoppingCategoryOrder.canonical.reversed())
        #expect(ShoppingCategoryOrder.normalizedOrder(reversed) == reversed)
    }

    @Test func partialStoredAppendsMissingInCanonicalOrder() {
        let order = ShoppingCategoryOrder.normalizedOrder([FoodCategories.other])
        #expect(order.first == FoodCategories.other)
        #expect(Set(order) == Set(ShoppingCategoryOrder.canonical))
        #expect(order.count == ShoppingCategoryOrder.canonical.count)
    }

    @Test func invalidAndDuplicateEntriesAreCleaned() {
        let order = ShoppingCategoryOrder.normalizedOrder([
            FoodCategories.meatAndSeafood, "不存在的分类", FoodCategories.meatAndSeafood,
        ])
        #expect(order.first == FoodCategories.meatAndSeafood)
        #expect(order.count == ShoppingCategoryOrder.canonical.count)
        #expect(Set(order) == Set(ShoppingCategoryOrder.canonical))
    }

    @Test func rankFollowsCustomOrderAndUnknownMapsToOtherBucket() {
        let order = [FoodCategories.dairyAndEggs, FoodCategories.other]
        #expect(ShoppingCategoryOrder.rank(FoodCategories.dairyAndEggs, order: order) == 0)
        #expect(ShoppingCategoryOrder.rank(FoodCategories.other, order: order) == 1)
        // Unknown/blank normalizes to the 其他 bucket (mirrors displaySections
        // grouping), so it ranks with 其他 — not an arbitrary "last".
        #expect(ShoppingCategoryOrder.rank("没见过", order: order) == ShoppingCategoryOrder.rank(FoodCategories.other, order: order))
    }

    @Test func categoryMissingFromOrderSortsLast() {
        // A real category not present in a (hypothetical partial) order sorts last.
        let order = [FoodCategories.dairyAndEggs]
        #expect(ShoppingCategoryOrder.rank(FoodCategories.meatAndSeafood, order: order) == order.count)
    }

    @Test func saveLoadRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "test.catorder.\(UUID().uuidString)")!
        let custom = Array(ShoppingCategoryOrder.canonical.reversed())
        ShoppingCategoryOrder.save(custom, to: defaults)
        #expect(ShoppingCategoryOrder.load(defaults) == custom)
    }

    @MainActor
    @Test func storeDisplaySectionsFollowCustomOrder() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.saveItems("home", [
            ShoppingItem(id: "1", name: "牛奶", detail: "", category: FoodCategories.dairyAndEggs),
            ShoppingItem(id: "2", name: "酱油", detail: "", category: FoodCategories.other),
            ShoppingItem(id: "3", name: "牛肉", detail: "", category: FoodCategories.meatAndSeafood),
        ])
        let store = ShoppingStore(repository: repo, householdID: "home")
        await store.load()
        // Put 其他 first — overriding canonical (where it's last).
        store.categoryOrder = ShoppingCategoryOrder.normalizedOrder([FoodCategories.other])
        let sections = store.displaySections.map(\.category)
        #expect(sections.first == FoodCategories.other)
        #expect(sections.firstIndex(of: FoodCategories.other)! < sections.firstIndex(of: FoodCategories.dairyAndEggs)!)
    }
}
