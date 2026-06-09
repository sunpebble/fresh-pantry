import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Dashboard feature store: urgency-tier counts, the
/// soonest-expiring ordering + preview cap, fresh / unchecked-shopping counts,
/// and empty cases. Backed by real in-memory repositories so the load path is
/// exercised end-to-end.
@MainActor
struct DashboardStoreTests {
    private func makeStore(
        inventory: [Ingredient] = [],
        shopping: [ShoppingItem] = [],
        household: String = "home"
    ) async throws -> DashboardStore {
        let container = try ModelContainerFactory.makeInMemory()
        let inventoryRepo = InventoryRepository(modelContainer: container)
        let shoppingRepo = ShoppingRepository(modelContainer: container)
        try await inventoryRepo.saveItems(household, inventory)
        try await shoppingRepo.saveItems(household, shopping)
        let store = DashboardStore(
            inventoryRepository: inventoryRepo,
            shoppingRepository: shoppingRepo,
            householdID: household
        )
        await store.load()
        return store
    }

    /// Stable, expiry-free item so its state isn't recomputed by the loader's
    /// freshness normalization (no expiry date → state preserved as given).
    private func item(
        id: String,
        name: String,
        state: FreshnessState,
        storage: IconType = .fridge
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: FoodCategories.other, storage: storage
        )
    }

    /// Item with an explicit expiry offset (drives loader-recomputed urgency +
    /// soonest-first ordering).
    private func dated(id: String, name: String, daysUntilExpiry: Int, shelfLife: Int = 30) -> Ingredient {
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: daysUntilExpiry, to: now)!
        return Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .pantry, expiryDate: expiry, addedAt: now, shelfLifeDays: shelfLife
        )
    }

    private func shoppingItem(id: String, name: String, isChecked: Bool) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: "", category: FoodCategories.other, isChecked: isChecked)
    }

    // MARK: Loading

    @Test func loadPopulatesBothScopesAndSetsFlags() async throws {
        let store = try await makeStore(
            inventory: [item(id: "a", name: "牛奶", state: .fresh)],
            shopping: [shoppingItem(id: "s1", name: "鸡蛋", isChecked: false)]
        )
        #expect(store.inventory.count == 1)
        #expect(store.shopping.count == 1)
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Urgency-tier counts

    @Test func summaryCountsEachUrgencyTier() async throws {
        let store = try await makeStore(inventory: [
            item(id: "f1", name: "苹果", state: .fresh),
            item(id: "f2", name: "酱油", state: .fresh),
            item(id: "soon1", name: "酸奶", state: .expiringSoon),
            item(id: "u1", name: "鸡肉", state: .urgent),
            item(id: "u2", name: "三文鱼", state: .urgent),
            item(id: "x1", name: "菠菜", state: .expired),
        ])
        let summary = store.summary
        #expect(summary.totalItems == 6)
        #expect(summary.soonCount == 1)
        #expect(summary.urgentCount == 2)
        #expect(summary.expiredCount == 1)
        // soon + urgent + expired
        #expect(summary.needsAttentionCount == 4)
        // total - needsAttention
        #expect(summary.freshCount == 2)
    }

    // MARK: Soonest-expiring ordering + preview cap

    @Test func sortedNonFreshOrdersByTierThenSoonestExpiry() async throws {
        // All three carry an expiry: expired (-1) → urgent (1) → soon are tiered
        // by the loader. Within a tier, soonest expiry sorts first.
        let store = try await makeStore(inventory: [
            item(id: "fresh", name: "苹果", state: .fresh), // excluded (fresh)
            dated(id: "expired", name: "菠菜", daysUntilExpiry: -1),
            dated(id: "urgentLater", name: "鸡肉", daysUntilExpiry: 2),
            dated(id: "urgentSooner", name: "三文鱼", daysUntilExpiry: 1),
        ])
        // expired first, then urgent tier soonest-first (1 day before 2 days).
        #expect(store.sortedNonFresh.map(\.id) == ["expired", "urgentSooner", "urgentLater"])
    }

    @Test func expiringPreviewCapsAtPreviewLimit() async throws {
        // Six expired items — preview must cap at DashboardStore.previewLimit (4).
        let many = (0..<6).map { item(id: "x\($0)", name: "菜\($0)", state: .expired) }
        let store = try await makeStore(inventory: many)
        #expect(store.summary.expiringPreview.count == DashboardStore.previewLimit)
        #expect(store.sortedNonFresh.count == 6) // full list is uncapped
    }

    @Test func freshItemsAreExcludedFromExpiringPreview() async throws {
        let store = try await makeStore(inventory: [
            item(id: "f1", name: "苹果", state: .fresh),
            item(id: "f2", name: "酱油", state: .fresh),
        ])
        #expect(store.summary.expiringPreview.isEmpty)
        #expect(store.summary.hasNoExpiring)
    }

    // MARK: Unchecked shopping count

    @Test func uncheckedShoppingCountIgnoresCheckedRows() async throws {
        let store = try await makeStore(shopping: [
            shoppingItem(id: "s1", name: "牛奶", isChecked: false),
            shoppingItem(id: "s2", name: "鸡蛋", isChecked: true),
            shoppingItem(id: "s3", name: "番茄", isChecked: false),
        ])
        #expect(store.summary.uncheckedShoppingCount == 2)
    }

    // MARK: Empty cases

    @Test func emptyScopesProduceZeroedSummary() async throws {
        let store = try await makeStore()
        let summary = store.summary
        #expect(summary.totalItems == 0)
        #expect(summary.needsAttentionCount == 0)
        #expect(summary.freshCount == 0)
        #expect(summary.uncheckedShoppingCount == 0)
        #expect(summary.expiringPreview.isEmpty)
        #expect(summary.hasNoExpiring)
    }

    @Test func freshOnlyPantryHasNoExpiringButCountsTotal() async throws {
        let store = try await makeStore(inventory: [
            item(id: "f1", name: "苹果", state: .fresh),
            item(id: "f2", name: "酱油", state: .fresh),
            item(id: "f3", name: "鸡蛋", state: .fresh),
        ])
        let summary = store.summary
        #expect(summary.totalItems == 3)
        #expect(summary.freshCount == 3)
        #expect(summary.hasNoExpiring)
    }

    // MARK: Classification helper

    @Test func isNonFreshMatchesExpiringTiersOnly() {
        #expect(!DashboardStore.isNonFresh(.fresh))
        #expect(DashboardStore.isNonFresh(.expiringSoon))
        #expect(DashboardStore.isNonFresh(.urgent))
        #expect(DashboardStore.isNonFresh(.expired))
    }

    // MARK: 食材分类 grid counts

    @Test func categoryCountsGroupByCanonicalInValuesOrder() async throws {
        func it(_ id: String, _ category: String) -> Ingredient {
            Ingredient(id: id, name: id, quantity: "1", unit: "份", imageUrl: "",
                       freshnessPercent: 1, state: .fresh, category: category, storage: .fridge)
        }
        // Use canonical category values so dropdownValue maps to itself.
        let catA = FoodCategories.values[0]
        let catB = FoodCategories.values[1]
        let store = try await makeStore(inventory: [it("a", catA), it("b", catA), it("c", catB)])
        let counts = store.categoryCounts
        let dict = Dictionary(uniqueKeysWithValues: counts.map { ($0.category, $0.count) })
        #expect(dict[catA] == 2)
        #expect(dict[catB] == 1)
        // Ordered by FoodCategories.values (catA at index 0 precedes catB), empty buckets dropped.
        #expect(counts.map(\.category) == [catA, catB])
    }
}
