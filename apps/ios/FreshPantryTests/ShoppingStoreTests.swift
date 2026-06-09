import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Shopping feature store: category-canonical sort,
/// checked-to-bottom ordering, and the toggle / add / delete mutations. Backed
/// by a real in-memory repository so the load / persist path (with its
/// category-normalize + name-dedup) is exercised end-to-end.
@MainActor
struct ShoppingStoreTests {
    private func makeStore(_ items: [ShoppingItem], household: String = "home") async throws -> ShoppingStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = ShoppingStore(repository: repo, householdID: household)
        await store.load()
        return store
    }

    private func item(
        id: String,
        name: String,
        category: String,
        isChecked: Bool = false,
        detail: String = ""
    ) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, category: category, isChecked: isChecked)
    }

    // MARK: Loading

    @Test func loadPopulatesItemsAndSetsFlags() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs)])
        #expect(store.items.count == 1)
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Category sort

    @Test func displayItemsSortByCanonicalCategoryOrder() async throws {
        // Inserted out of canonical order; display must follow
        // dairyAndEggs → freshProduce → meatAndSeafood → herbsAndSpices → other.
        let store = try await makeStore([
            item(id: "other", name: "米", category: FoodCategories.other),
            item(id: "meat", name: "猪肉", category: FoodCategories.meatAndSeafood),
            item(id: "dairy", name: "牛奶", category: FoodCategories.dairyAndEggs),
            item(id: "herb", name: "盐", category: FoodCategories.herbsAndSpices),
            item(id: "produce", name: "苹果", category: FoodCategories.freshProduce),
        ])
        #expect(store.displayItems.map(\.id) == ["dairy", "produce", "meat", "herb", "other"])
    }

    @Test func displaySectionsFollowCanonicalCategoryOrder() async throws {
        let store = try await makeStore([
            item(id: "meat", name: "猪肉", category: FoodCategories.meatAndSeafood),
            item(id: "dairy", name: "牛奶", category: FoodCategories.dairyAndEggs),
            item(id: "produce", name: "苹果", category: FoodCategories.freshProduce),
        ])
        #expect(store.displaySections.map(\.category) == [
            FoodCategories.dairyAndEggs,
            FoodCategories.freshProduce,
            FoodCategories.meatAndSeafood,
        ])
        #expect(store.displaySections.first?.items.map(\.id) == ["dairy"])
    }

    // MARK: Checked-to-bottom

    @Test func checkedItemsSortAfterUncheckedRegardlessOfCategory() async throws {
        // A checked dairy item (earliest category) must still sort after an
        // unchecked "other" item — checked-to-bottom dominates the category rank.
        let store = try await makeStore([
            item(id: "dairyChecked", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "otherTodo", name: "米", category: FoodCategories.other, isChecked: false),
        ])
        #expect(store.displayItems.map(\.id) == ["otherTodo", "dairyChecked"])
    }

    @Test func checkedAndUncheckedEachKeepCanonicalOrderWithinBucket() async throws {
        let store = try await makeStore([
            item(id: "p_todo", name: "苹果", category: FoodCategories.freshProduce, isChecked: false),
            item(id: "d_done", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "d_todo", name: "鸡蛋", category: FoodCategories.dairyAndEggs, isChecked: false),
            item(id: "m_done", name: "猪肉", category: FoodCategories.meatAndSeafood, isChecked: true),
        ])
        // unchecked (dairy, produce) first then checked (dairy, meat)
        #expect(store.displayItems.map(\.id) == ["d_todo", "p_todo", "d_done", "m_done"])
    }

    @Test func derivingDisplayItemsDoesNotMutateSourceList() async throws {
        let store = try await makeStore([
            item(id: "checked", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "todo", name: "米", category: FoodCategories.other, isChecked: false),
        ])
        let before = store.items.map(\.id)
        _ = store.displayItems
        _ = store.displayItems // idempotent
        #expect(store.items.map(\.id) == before) // source order untouched
        #expect(store.displayItems.map(\.id) == ["todo", "checked"]) // display reordered
    }

    // MARK: Counts

    @Test func checkedAndUncheckedCounts() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "b", name: "鸡蛋", category: FoodCategories.dairyAndEggs, isChecked: false),
            item(id: "c", name: "苹果", category: FoodCategories.freshProduce, isChecked: false),
        ])
        #expect(store.checkedCount == 1)
        #expect(store.uncheckedCount == 2)
    }

    // MARK: Toggle

    @Test func toggleFlipsCheckedAndPersists() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs)])
        let target = store.items.first { $0.id == "a" }!
        #expect(!target.isChecked)

        let toggled = await store.toggleChecked(target)
        #expect(toggled)
        #expect(store.items.first { $0.id == "a" }?.isChecked == true)

        // Survives a reload (persisted, not just local mutation).
        await store.load()
        #expect(store.items.first { $0.id == "a" }?.isChecked == true)

        // Toggling back un-checks.
        let again = store.items.first { $0.id == "a" }!
        _ = await store.toggleChecked(again)
        #expect(store.items.first { $0.id == "a" }?.isChecked == false)
    }

    @Test func toggleUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs)])
        let ghost = item(id: "zzz", name: "幽灵", category: FoodCategories.other)
        let toggled = await store.toggleChecked(ghost)
        #expect(!toggled)
    }

    // MARK: Add

    @Test func addAppendsNewItemWithDefaultedCategory() async throws {
        let store = try await makeStore([])
        let added = await store.add(name: "牛奶", detail: "2 盒")
        #expect(added)
        #expect(store.items.count == 1)
        let item = store.items.first!
        #expect(item.name == "牛奶")
        #expect(item.detail == "2 盒")
        // 牛奶 → 乳品蛋类 via FoodKnowledge.
        #expect(item.category == FoodCategories.dairyAndEggs)
        #expect(ProposalApply.isUuid(item.id)) // sync-clean UUID id
    }

    @Test func addHonorsExplicitCategory() async throws {
        let store = try await makeStore([])
        let added = await store.add(name: "神秘食材", detail: "", category: FoodCategories.meatAndSeafood)
        #expect(added)
        #expect(store.items.first?.category == FoodCategories.meatAndSeafood)
    }

    @Test func addRejectsBlankName() async throws {
        let store = try await makeStore([])
        let added = await store.add(name: "   ")
        #expect(!added)
        #expect(store.items.isEmpty)
    }

    @Test func addRejectsDuplicateNameCaseInsensitively() async throws {
        let store = try await makeStore([item(id: "a", name: "Milk", category: FoodCategories.dairyAndEggs)])
        let added = await store.add(name: "  milk ")
        #expect(!added)
        #expect(store.items.count == 1)
    }

    // MARK: Delete

    @Test func deleteRemovesByIdAndPersists() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "鸡蛋", category: FoodCategories.dairyAndEggs),
        ])
        let target = store.items.first { $0.id == "a" }!
        let removed = await store.delete(target)
        #expect(removed)
        #expect(store.items.map(\.id) == ["b"])

        await store.load()
        #expect(store.items.map(\.id) == ["b"])
    }

    @Test func deleteUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs)])
        let ghost = item(id: "zzz", name: "幽灵", category: FoodCategories.other)
        let removed = await store.delete(ghost)
        #expect(!removed)
        #expect(store.items.count == 1)
    }

    // MARK: Filter / progress / restore

    @Test func filterNarrowsDisplaySectionsToCheckedState() async throws {
        let store = try await makeStore([
            item(id: "todo", name: "鸡蛋", category: FoodCategories.dairyAndEggs, isChecked: false),
            item(id: "done", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
        ])
        // all → both rows
        #expect(store.displaySections.flatMap { $0.items }.map(\.id).sorted() == ["done", "todo"])
        store.filter = .todo
        #expect(store.displaySections.flatMap { $0.items }.map(\.id) == ["todo"])
        store.filter = .done
        #expect(store.displaySections.flatMap { $0.items }.map(\.id) == ["done"])
    }

    @Test func progressAndTotalReflectCheckedRatio() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "b", name: "鸡蛋", category: FoodCategories.dairyAndEggs, isChecked: true),
            item(id: "c", name: "苹果", category: FoodCategories.freshProduce, isChecked: false),
            item(id: "d", name: "梨", category: FoodCategories.freshProduce, isChecked: false),
        ])
        #expect(store.total == 4)
        #expect(store.progress == 0.5)
    }

    @Test func progressIsZeroForEmptyList() async throws {
        let store = try await makeStore([])
        #expect(store.total == 0)
        #expect(store.progress == 0)
    }

    @Test func restoreReAddsDeletedRowAndPersists() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "鸡蛋", category: FoodCategories.dairyAndEggs),
        ])
        let target = store.items.first { $0.id == "a" }!
        #expect(await store.delete(target))
        #expect(store.items.map(\.id) == ["b"])

        #expect(await store.restore(target))
        #expect(store.items.map(\.id).sorted() == ["a", "b"])
        await store.load()
        #expect(store.items.map(\.id).sorted() == ["a", "b"]) // persisted
    }

    @Test func restoreIsNoOpWhenRowStillPresent() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", category: FoodCategories.dairyAndEggs)])
        let present = store.items.first { $0.id == "a" }!
        #expect(!(await store.restore(present)))
        #expect(store.items.count == 1)
    }

    @Test func deleteEnqueuesSoftDeleteSyncOp() async throws {
        // Regression: a shopping delete MUST enqueue a `.delete` so it propagates
        // to other household members (it was previously a silent local-only drop —
        // the row stayed on the server and re-appeared on the next pull).
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        let uuid = UUID().uuidString.lowercased()
        let target = ShoppingItem(
            id: uuid, name: "牛奶", detail: "", category: FoodCategories.dairyAndEggs
        ).copyWith(remoteVersion: 3)
        try await repo.saveItems("home", [target])

        let outbox = SyncOutboxRepository(modelContainer: container)
        let session = SyncSession(
            selectedHouseholdId: "home",
            defaults: UserDefaults(suiteName: "test.shopping.delete.\(UUID().uuidString)")!
        )
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let store = ShoppingStore(repository: repo, householdID: "home", syncWriter: writer)
        await store.load()

        #expect(await store.delete(store.items.first { $0.id == uuid }!))

        let pending = try await outbox.loadPending()
        #expect(pending.count == 1)
        let op = try #require(pending.first)
        #expect(op.entityType == .shoppingItem)
        #expect(op.operation == .delete)
        #expect(op.entityId == uuid)
        #expect(op.baseVersion == 3)
    }
}
