import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for `GlobalSearchStore` — the cross-domain (库存 + 购物) filter
/// (ports `filteredInventoryProvider` / `filteredShoppingProvider`).
@MainActor
struct GlobalSearchStoreTests {
    private func makeStore(
        inventory: [Ingredient] = [],
        shopping: [ShoppingItem] = [],
        household: String = "home"
    ) async throws -> GlobalSearchStore {
        let container = try ModelContainerFactory.makeInMemory()
        let invRepo = InventoryRepository(modelContainer: container)
        let shopRepo = ShoppingRepository(modelContainer: container)
        try await invRepo.saveItems(household, inventory)
        try await shopRepo.saveItems(household, shopping)
        let store = GlobalSearchStore(
            inventoryRepository: invRepo,
            shoppingRepository: shopRepo,
            localRecipeRepository: LocalRecipeRepository(payload: Data("[]".utf8)),
            customRecipeRepository: CustomRecipeRepository(modelContainer: container),
            householdID: household
        )
        await store.load()
        return store
    }

    private func inv(_ id: String, _ name: String, category: String = "其他") -> Ingredient {
        Ingredient(id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
                   freshnessPercent: 1, state: .fresh, category: category, storage: .fridge)
    }

    private func shop(_ id: String, _ name: String, category: String = "其他") -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: "", category: category, isChecked: false)
    }

    @Test func emptyQueryYieldsNoResults() async throws {
        let store = try await makeStore(inventory: [inv("a", "番茄")], shopping: [shop("s", "鸡蛋")])
        #expect(!store.isSearching)
        #expect(store.filteredInventory.isEmpty)
        #expect(store.filteredShopping.isEmpty)
        #expect(!store.hasResults)
    }

    @Test func matchesNameAcrossBothDomains() async throws {
        let store = try await makeStore(
            inventory: [inv("a", "番茄"), inv("b", "黄瓜")],
            shopping: [shop("s", "番茄酱"), shop("t", "牛奶")]
        )
        store.query = "番茄"
        #expect(store.filteredInventory.map(\.id) == ["a"])
        #expect(store.filteredShopping.map(\.id) == ["s"])
        #expect(store.hasResults)
    }

    @Test func matchesCategoryAndIsCaseInsensitive() async throws {
        // Use a canonical category so the inventory loader's normalization keeps it.
        let cat = FoodCategories.values.first { $0 != FoodCategories.other } ?? FoodCategories.other
        let store = try await makeStore(
            inventory: [inv("a", "Milk", category: cat)],
            shopping: [shop("s", "酸奶", category: cat)]
        )
        store.query = cat // category match, neither name contains it
        #expect(store.filteredInventory.map(\.id) == ["a"])
        #expect(store.filteredShopping.map(\.id) == ["s"])
        store.query = "milk" // case-insensitive name match
        #expect(store.filteredInventory.map(\.id) == ["a"])
    }
}
