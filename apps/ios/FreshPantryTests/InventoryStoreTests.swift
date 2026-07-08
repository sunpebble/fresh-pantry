import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Inventory feature store: urgency sort, storage filter,
/// name search, and delete. Backed by a real in-memory repository so the load /
/// persist path is exercised end-to-end.
@MainActor
struct InventoryStoreTests {
    private func makeStore(_ items: [Ingredient], household: String = "home") async throws -> InventoryStore {
        try await makeStoreWithLog(items, household: household).store
    }

    /// Builds a store backed by real in-memory inventory + food-log repos, and
    /// returns the food-log repo too so the removal-with-outcome tests can assert
    /// the logged departure (and its reversal on undo).
    private func makeStoreWithLog(
        _ items: [Ingredient],
        household: String = "home"
    ) async throws -> (store: InventoryStore, log: FoodLogRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = InventoryStore(repository: repo, foodLogRepository: log, householdID: household)
        await store.load()
        return (store, log)
    }

    /// Builds a store backed by a real in-memory repo AND hands back the repo, so
    /// a test can land a concurrent sync write (an atomic `mutateItems`) in the
    /// repo AFTER the store loaded — reproducing the load→save window the
    /// sync-apply race exploits (the store's `items` snapshot goes stale).
    private func makeStoreWithRepo(
        _ items: [Ingredient],
        household: String = "home"
    ) async throws -> (store: InventoryStore, repo: InventoryRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = InventoryStore(repository: repo, foodLogRepository: log, householdID: household)
        await store.load()
        return (store, repo)
    }

    /// Stable, expiry-free item so its state isn't recomputed by the loader's
    /// freshness normalization (no expiry date → state preserved as given).
    private func item(
        id: String,
        name: String,
        state: FreshnessState,
        quantity: String = "1",
        storage: IconType = .fridge,
        category: String? = nil,
        tags: [String] = []
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: quantity, unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: category,
            storage: storage, tags: tags
        )
    }

    /// Item with an explicit expiry offset (drives loader-recomputed urgency).
    private func dated(id: String, name: String, daysUntilExpiry: Int, shelfLife: Int = 30) -> Ingredient {
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: daysUntilExpiry, to: now)!
        return Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .pantry, expiryDate: expiry, addedAt: now, shelfLifeDays: shelfLife
        )
    }

    // MARK: Loading

    @Test func loadPopulatesItemsAndSetsFlags() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        #expect(store.items.count == 1)
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Urgency sort

    @Test func displayItemsSortByUrgencyMostSevereFirst() async throws {
        let store = try await makeStore([
            item(id: "fresh", name: "苹果", state: .fresh),
            item(id: "expired", name: "菠菜", state: .expired),
            item(id: "soon", name: "酸奶", state: .expiringSoon),
            item(id: "urgent", name: "鸡肉", state: .urgent),
        ])
        // expired → urgent → expiringSoon → fresh
        #expect(store.displayItems.map(\.id) == ["expired", "urgent", "soon", "fresh"])
    }

    @Test func sameTierSortsBySoonestExpiryFirst() async throws {
        // Both land in `.fresh` (far-out expiry); soonest expiry sorts first.
        let store = try await makeStore([
            dated(id: "later", name: "B", daysUntilExpiry: 25),
            dated(id: "sooner", name: "A", daysUntilExpiry: 20),
        ])
        #expect(store.displayItems.map(\.id) == ["sooner", "later"])
    }

    @Test func derivingDisplayItemsDoesNotMutateSourceList() async throws {
        let store = try await makeStore([
            item(id: "fresh", name: "苹果", state: .fresh),
            item(id: "expired", name: "菠菜", state: .expired),
        ])
        let before = store.items.map(\.id)
        _ = store.displayItems // urgency sort must not touch the source list
        _ = store.displayItems // idempotent
        #expect(store.items.map(\.id) == before) // source order untouched by derivation
        // And display order IS reordered (expired first), proving sort is display-only.
        #expect(store.displayItems.map(\.id) == ["expired", "fresh"])
    }

    // MARK: Storage filter

    @Test func storageFilterRestrictsToArea() async throws {
        let store = try await makeStore([
            item(id: "f1", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "z1", name: "三文鱼", state: .fresh, storage: .freezer),
            item(id: "p1", name: "酱油", state: .fresh, storage: .pantry),
        ])
        store.storageFilter = .area(.freezer)
        #expect(store.displayItems.map(\.id) == ["z1"])
        store.storageFilter = .all
        #expect(store.displayItems.count == 3)
    }

    @Test func storageCountsPerArea() async throws {
        let store = try await makeStore([
            item(id: "f1", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "f2", name: "鸡蛋", state: .fresh, storage: .fridge),
            item(id: "p1", name: "盐", state: .fresh, storage: .pantry),
        ])
        #expect(store.count(for: InventoryStore.StorageFilter.all) == 3)
        #expect(store.count(for: .area(.fridge)) == 2)
        #expect(store.count(for: .area(.pantry)) == 1)
        #expect(store.count(for: .area(.freezer)) == 0)
    }

    // MARK: Category filter

    @Test func categoryFilterNarrowsToCategoryAndNotFresh() async throws {
        let store = try await makeStore([
            item(id: "milk", name: "牛奶", state: .fresh, category: FoodCategories.dairyAndEggs),
            item(id: "egg", name: "鸡蛋", state: .urgent, category: FoodCategories.dairyAndEggs),
            item(id: "apple", name: "苹果", state: .fresh, category: FoodCategories.freshProduce),
        ])
        store.categoryFilter = .category(FoodCategories.dairyAndEggs)
        #expect(store.displayItems.map(\.id).sorted() == ["egg", "milk"])
        store.categoryFilter = .notFresh
        #expect(store.displayItems.map(\.id) == ["egg"]) // only the urgent row
        store.categoryFilter = .all
        #expect(store.displayItems.count == 3)
        #expect(store.count(for: .notFresh) == 1)
        #expect(store.count(for: .category(FoodCategories.freshProduce)) == 1)
    }

    // MARK: Tag filter

    @Test func tagFilterRestrictsToSelectedTagCaseInsensitively() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh, tags: ["囤货"]),
            item(id: "b", name: "鸡蛋", state: .fresh, tags: ["待用完"]),
            item(id: "c", name: "酸奶", state: .fresh, tags: ["囤货", "孩子的"]),
            item(id: "d", name: "盐", state: .fresh, tags: []),
        ])
        store.selectedTag = "囤货"
        #expect(store.displayItems.map(\.id).sorted() == ["a", "c"])

        // A differently-cased selection still matches the canonical tag.
        store.selectedTag = "ATAG"
        #expect(store.displayItems.isEmpty) // unknown tag → nothing
        store.selectedTag = nil
        #expect(store.displayItems.count == 4) // 全部标签 → no restriction
    }

    @Test func tagFilterComposesWithCategoryStorageAndSearch() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh, storage: .fridge,
                 category: FoodCategories.dairyAndEggs, tags: ["囤货"]),
            item(id: "b", name: "牛肉", state: .fresh, storage: .freezer,
                 category: FoodCategories.meatAndSeafood, tags: ["囤货"]),
            item(id: "c", name: "牛奶糖", state: .fresh, storage: .fridge,
                 category: FoodCategories.dairyAndEggs, tags: ["零食"]),
        ])
        store.selectedTag = "囤货"
        store.storageFilter = .area(.fridge)
        store.searchQuery = "牛"
        // 囤货 ∩ fridge ∩ name~牛 → only the milk row (牛肉 is freezer, 牛奶糖 lacks 囤货).
        #expect(store.displayItems.map(\.id) == ["a"])
    }

    @Test func tagOptionsOrderByFrequencyThenName() async throws {
        let store = try await makeStore([
            item(id: "a", name: "A", state: .fresh, tags: ["囤货", "孩子的"]),
            item(id: "b", name: "B", state: .fresh, tags: ["囤货"]),
            item(id: "c", name: "C", state: .fresh, tags: ["待用完"]),
        ])
        // 囤货 used twice → first; 孩子的 / 待用完 each once → name-asc tie-break.
        #expect(store.tagOptions == ["囤货", "孩子的", "待用完"])
    }

    @Test func tagOptionsEmptyWhenNoRowTagged() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        #expect(store.tagOptions.isEmpty) // drives the view to hide the whole row
    }

    @Test func tagOptionsDedupeAcrossRowsCaseInsensitively() async throws {
        let store = try await makeStore([
            item(id: "a", name: "A", state: .fresh, tags: ["BBQ"]),
            item(id: "b", name: "B", state: .fresh, tags: ["bbq"]), // model lowercases-key dedup
        ])
        // Two rows, same logical tag (different casing) → one option, count 2.
        #expect(store.tagOptions == ["BBQ"]) // first-seen casing wins
    }

    @Test func hasActiveQueryReflectsTagSelection() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh, tags: ["囤货"])])
        #expect(!store.hasActiveQuery)
        store.selectedTag = "囤货"
        #expect(store.hasActiveQuery)
    }

    @Test func clearAllRemovesEveryRowAndPersists() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        #expect(await store.clearAll())
        #expect(store.items.isEmpty)
        await store.load()
        #expect(store.items.isEmpty) // persisted
        // No-op on an already-empty scope.
        #expect(!(await store.clearAll()))
    }

    // MARK: Search

    @Test func searchMatchesNameCaseInsensitively() async throws {
        let store = try await makeStore([
            item(id: "a", name: "Salmon", state: .fresh),
            item(id: "b", name: "牛奶", state: .fresh),
        ])
        store.searchQuery = "  SALM "
        #expect(store.displayItems.map(\.id) == ["a"])
    }

    @Test func searchAndStorageFilterCompose() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "b", name: "牛肉", state: .fresh, storage: .freezer),
        ])
        store.searchQuery = "牛"
        store.storageFilter = .area(.fridge)
        #expect(store.displayItems.map(\.id) == ["a"]) // both name-match, storage narrows
    }

    @Test func hasActiveQueryReflectsFilterAndSearch() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        #expect(!store.hasActiveQuery)
        store.searchQuery = "牛"
        #expect(store.hasActiveQuery)
        store.searchQuery = ""
        store.storageFilter = .area(.fridge)
        #expect(store.hasActiveQuery)
    }

    // MARK: Delete

    @Test func deleteRemovesByIdAndPersists() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        let removed = await store.delete(target)
        #expect(removed)
        #expect(store.items.map(\.id) == ["b"])

        // Survives a reload (persisted, not just local mutation).
        await store.load()
        #expect(store.items.map(\.id) == ["b"])
    }

    @Test func deleteUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        let ghost = item(id: "zzz", name: "幽灵", state: .fresh)
        let removed = await store.delete(ghost)
        #expect(!removed)
        #expect(store.items.count == 1)
    }

    // MARK: Remove-with-outcome (manual-removal waste-stats log path)

    @Test func removeConsumedLogsConsumedDepartureAndRemovesRow() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh, category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!

        let undo = await store.remove(target, outcome: .consumed)
        #expect(undo != nil)
        #expect(store.items.map(\.id) == ["b"]) // row removed
        await store.load()
        #expect(store.items.map(\.id) == ["b"]) // persisted

        let entries = try await log.loadAllFor("home")
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.name == "牛奶")
        #expect(entry.outcome == .consumed)
        #expect(entry.category == FoodCategories.dairyAndEggs) // snapshot
        #expect(!entry.wasExpiring) // fresh → false
    }

    @Test func removeWastedSnapshotsWasExpiringFromNonFreshState() async throws {
        // An urgent (non-fresh) row removed as 扔掉了 must log wasted + wasExpiring.
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "三文鱼", state: .urgent, category: FoodCategories.meatAndSeafood),
        ])
        let target = store.items.first { $0.id == "a" }!

        let undo = await store.remove(target, outcome: .wasted)
        #expect(undo != nil)

        let entry = try #require(try await log.loadAllFor("home").first)
        #expect(entry.outcome == .wasted)
        #expect(entry.wasExpiring) // urgent → not fresh → true
    }

    @Test func removeUnknownItemDoesNotLog() async throws {
        let (store, log) = try await makeStoreWithLog([item(id: "a", name: "牛奶", state: .fresh)])
        let ghost = item(id: "zzz", name: "幽灵", state: .fresh)

        let undo = await store.remove(ghost, outcome: .consumed)
        #expect(undo == nil)
        #expect(store.items.count == 1)
        let entries = try await log.loadAllFor("home")
        #expect(entries.isEmpty) // nothing matched → nothing logged
    }

    @Test func undoRemoveReAddsRowAndReversesLogViaPointDelete() async throws {
        // The undo MUST reverse BOTH sides: the row returns and the logged
        // departure is point-deleted (NOT a saveEntries replace-all).
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        // Pre-seed an UNRELATED out-of-band food-log entry; a correct undo (point
        // delete) must leave it intact (a saveEntries replace-all would drop it).
        let survivor = FoodLogEntry(
            id: "fl_survivor", name: "苹果", outcome: .consumed, loggedAt: Date()
        )
        try await log.append("home", survivor)

        let target = store.items.first { $0.id == "a" }!
        let undo = try #require(await store.remove(target, outcome: .wasted))
        #expect(store.items.map(\.id) == ["b"]) // row gone
        #expect(try await log.loadAllFor("home").count == 2) // survivor + new

        let reversed = await store.undoRemove(undo)
        #expect(reversed)
        // The row is back (order-agnostic — the repo fetch is unordered).
        #expect(store.items.map(\.id).sorted() == ["a", "b"])
        await store.load()
        #expect(store.items.map(\.id).sorted() == ["a", "b"]) // persisted

        // The logged departure is gone, but the unrelated survivor remains —
        // proving a point-delete, not a saveEntries replace-all (which would have
        // dropped the survivor too).
        let remaining = try await log.loadAllFor("home")
        #expect(remaining.map(\.id) == ["fl_survivor"])
    }

    @Test func removeEnqueuesFoodLogCreateAndUndoEnqueuesDelete() async throws {
        // With a sync writer present, a removal-with-outcome enqueues the logged
        // departure as a `.foodLogEntry` create; undoing it enqueues a `.delete`
        // (soft delete) for the same id — FoodLog now participates in household sync.
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let defaults = UserDefaults(suiteName: "test.invstore.\(UUID().uuidString)")!
        let session = SyncSession(selectedHouseholdId: "home", defaults: defaults)
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let apple = item(id: "11111111-1111-4111-8111-111111111111", name: "苹果", state: .fresh)
        try await repo.saveItems("home", [apple])
        let store = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home", syncWriter: writer)
        await store.load()

        let target = store.items.first { $0.id == apple.id }!
        let undo = try #require(await store.remove(target, outcome: .wasted))

        let afterRemove = try await outbox.loadPending()
        #expect(afterRemove.contains { $0.entityType == .foodLogEntry && $0.operation == .create && $0.entityId == undo.loggedEntryId })

        _ = await store.undoRemove(undo)
        let afterUndo = try await outbox.loadPending()
        #expect(afterUndo.contains { $0.entityType == .foodLogEntry && $0.operation == .delete && $0.entityId == undo.loggedEntryId })
    }

    // MARK: Update (in-place edit)

    @Test func updateChangesEditableFieldsPreservesIdAddedAtAndPersists() async throws {
        let addedAt = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let original = Ingredient(
            id: "a", name: "牛奶", quantity: "1", unit: "盒", imageUrl: "img://milk",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.dairyAndEggs,
            barcode: "690", storage: .fridge, addedAt: addedAt, remoteVersion: 4
        )
        let store = try await makeStore([original, item(id: "b", name: "鸡蛋", state: .fresh)])

        let edited = original.copyWith(
            name: "酸奶", quantity: "2", unit: "瓶", category: FoodCategories.freshProduce, storage: .pantry
        )
        let ok = await store.update(original, to: edited)
        #expect(ok)

        let row = try #require(store.items.first { $0.id == "a" })
        #expect(row.name == "酸奶")
        #expect(row.quantity == "2")
        #expect(row.unit == "瓶")
        #expect(row.storage == .pantry)
        #expect(row.id == "a") // identity preserved
        #expect(row.addedAt == addedAt) // provenance preserved
        #expect(row.imageUrl == "img://milk") // editor doesn't touch image
        #expect(row.barcode == "690") // barcode preserved

        // Survives a reload (persisted, not just local mutation).
        await store.load()
        let reloaded = try #require(store.items.first { $0.id == "a" })
        #expect(reloaded.name == "酸奶")
        #expect(reloaded.storage == .pantry)
    }

    @Test func updateRecomputesFreshnessFromNewExpiry() async throws {
        // A far-out, fresh item edited to expire tomorrow flips to urgent via the
        // store's freshness refresh (days-until <= 2 ⇒ urgent regardless of ratio).
        let store = try await makeStore([dated(id: "a", name: "三文鱼", daysUntilExpiry: 25, shelfLife: 30)])
        let original = try #require(store.items.first { $0.id == "a" })
        #expect(original.state == .fresh)

        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let edited = original.copyWith(expiryDate: soon) // shelf-life 30 retained
        #expect(await store.update(original, to: edited))

        let row = try #require(store.items.first { $0.id == "a" })
        #expect(row.state == .urgent)
        #expect(row.expiryLabel == String(localized: "expiry.tomorrow")) // label refreshed too
    }

    @Test func updateRenameStillResolvesById() async throws {
        // The row is resolved by the ORIGINAL (id), so a rename still finds it.
        let original = item(id: "a", name: "牛奶", state: .fresh)
        let store = try await makeStore([original])
        let edited = original.copyWith(name: "全脂牛奶")
        #expect(await store.update(original, to: edited))
        #expect(store.items.map(\.name) == ["全脂牛奶"])
        #expect(store.items.map(\.id) == ["a"])
    }

    @Test func updateClearingExpiryKeepsNoExpiry() async throws {
        let store = try await makeStore([dated(id: "a", name: "酸奶", daysUntilExpiry: 1, shelfLife: 14)])
        let original = try #require(store.items.first { $0.id == "a" })

        // Rebuild WITHOUT expiry/shelf-life (copyWith can't clear them) — the 不过期 case.
        let edited = Ingredient(
            id: original.id, name: original.name, quantity: original.quantity,
            unit: original.unit, imageUrl: original.imageUrl, freshnessPercent: 0.85,
            state: .fresh, category: original.category, barcode: original.barcode,
            storage: original.storage, expiryDate: nil, addedAt: original.addedAt,
            shelfLifeDays: nil, remoteVersion: original.remoteVersion
        )
        #expect(await store.update(original, to: edited))

        let row = try #require(store.items.first { $0.id == "a" })
        #expect(row.expiryDate == nil)
        #expect(row.shelfLifeDays == nil)
        #expect(row.state == .fresh) // no expiry ⇒ freshness left as set
    }

    @Test func updateUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        let ghost = item(id: "zzz", name: "幽灵", state: .fresh)
        let ok = await store.update(ghost, to: ghost.copyWith(name: "改名"))
        #expect(!ok)
        #expect(store.items.map(\.name) == ["牛奶"]) // untouched
    }

    // MARK: Partial consume — plan (pure)

    @Test func planDecrementsWhenAmountBelowAvailable() {
        #expect(InventoryStore.planPartialConsume(quantity: "500", amount: 100) == .decrement("400"))
    }

    @Test func planDepletesWhenAmountMeetsOrExceedsAvailable() {
        #expect(InventoryStore.planPartialConsume(quantity: "2", amount: 2) == .deplete)
        #expect(InventoryStore.planPartialConsume(quantity: "2", amount: 5) == .deplete)
    }

    @Test func planInvalidForNonNumericQuantityOrNonPositiveAmount() {
        #expect(InventoryStore.planPartialConsume(quantity: "适量", amount: 1) == .invalid)
        #expect(InventoryStore.planPartialConsume(quantity: "500", amount: 0) == .invalid)
        #expect(InventoryStore.planPartialConsume(quantity: "500", amount: -3) == .invalid)
    }

    @Test func planFormatsDecimalRemainderWithoutFloatNoise() {
        #expect(InventoryStore.planPartialConsume(quantity: "1.5", amount: 0.3) == .decrement("1.2"))
    }

    @Test func planTreatsSubResolutionRemainderAsDeplete() {
        // A remainder below the 2-decimal display step (float noise) is nothing left.
        #expect(InventoryStore.planPartialConsume(quantity: "1", amount: 0.999) == .deplete)
    }

    @Test func planPreservesUnitTextEmbeddedInQuantityString() {
        // Rare: the unit normally lives in the separate `unit` field, but a quantity
        // string that carries it ("3 个") must keep it through the decrement.
        #expect(InventoryStore.planPartialConsume(quantity: "3 个", amount: 1) == .decrement("2 个"))
    }

    // MARK: Partial consume — apply

    @Test func consumePartialDecrementsInPlaceWithoutLogging() async throws {
        let (store, log) = try await makeStoreWithLog([
            Ingredient(id: "a", name: "面粉", quantity: "500", unit: "g", imageUrl: "",
                       freshnessPercent: 1, state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        guard case .decremented = await store.consumePartial(target, amount: 100) else {
            Issue.record("expected .decremented"); return
        }
        #expect(store.items.first { $0.id == "a" }?.quantity == "400") // in place
        await store.load()
        #expect(store.items.first { $0.id == "a" }?.quantity == "400") // persisted
        #expect(try await log.loadAllFor("home").isEmpty) // partial use is no departure
    }

    @Test func consumePartialDepletingRemovesRowAndLogsConsumed() async throws {
        let (store, log) = try await makeStoreWithLog([
            Ingredient(id: "a", name: "牛奶", quantity: "1", unit: "瓶", imageUrl: "",
                       freshnessPercent: 1, state: .fresh, category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        guard case .depleted = await store.consumePartial(target, amount: 1) else {
            Issue.record("expected .depleted"); return
        }
        #expect(store.items.map(\.id) == ["b"]) // row removed
        let entries = try await log.loadAllFor("home")
        #expect(entries.count == 1)
        #expect(entries.first?.outcome == .consumed)
    }

    @Test func consumePartialInvalidForNonNumericQuantityLeavesRowAndLog() async throws {
        let (store, log) = try await makeStoreWithLog([
            Ingredient(id: "a", name: "盐", quantity: "适量", unit: "", imageUrl: "",
                       freshnessPercent: 1, state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        guard case .invalid = await store.consumePartial(target, amount: 1) else {
            Issue.record("expected .invalid"); return
        }
        #expect(store.items.count == 1) // unchanged
        #expect(try await log.loadAllFor("home").isEmpty)
    }

    @Test func consumePartialDepletingUndoRestoresRow() async throws {
        let (store, _) = try await makeStoreWithLog([
            Ingredient(id: "a", name: "牛奶", quantity: "1", unit: "瓶", imageUrl: "",
                       freshnessPercent: 1, state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        guard case let .depleted(undo) = await store.consumePartial(target, amount: 2) else {
            Issue.record("expected .depleted"); return
        }
        #expect(store.items.isEmpty)
        #expect(await store.undoRemove(undo))
        #expect(store.items.map(\.id) == ["a"]) // restored
    }

    // MARK: Household re-scoping

    /// Regression for the live-sync bug where a feature view built its store ONCE
    /// and never rebuilt it on a household change, so the list kept showing the old
    /// scope's rows. The fix rebuilds the store with the current `householdID`; this
    /// asserts the underlying invariant — a store built for household B loads B's
    /// rows, not A's — against a single shared repository (the two scopes are
    /// disjoint).
    @Test func storeRebuiltForNewHouseholdLoadsThatScope() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems("home-a", [item(id: "a", name: "牛奶", state: .fresh)])
        try await repo.saveItems("home-b", [item(id: "b", name: "鸡蛋", state: .fresh)])

        // The store the view built for the first scope.
        let storeA = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home-a")
        await storeA.load()
        #expect(storeA.items.map(\.id) == ["a"])

        // After the household switches, `.task(id:)` rebuilds the store for the new
        // scope — it must surface B's rows, never A's.
        let storeB = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home-b")
        await storeB.load()
        #expect(storeB.items.map(\.id) == ["b"])
    }

    // MARK: Multi-select (批量删除 / 合并批次)

    @Test func deleteManyRemovesSelectedRows() async throws {
        let store = try await makeStore([
            item(id: "a", name: "A", state: .fresh),
            item(id: "b", name: "B", state: .fresh),
            item(id: "c", name: "C", state: .fresh),
        ])
        let undo = await store.deleteMany([store.items[0], store.items[2]]) // A, C
        #expect(undo != nil)
        #expect(store.items.map(\.id) == ["b"])
    }

    @Test func undoBatchRemovalRestoresAtOriginalIndices() async throws {
        let store = try await makeStore([
            item(id: "a", name: "A", state: .fresh),
            item(id: "b", name: "B", state: .fresh),
            item(id: "c", name: "C", state: .fresh),
        ])
        guard let undo = await store.deleteMany([store.items[0], store.items[2]]) else {
            Issue.record("expected an undo handle"); return
        }
        #expect(await store.undoBatchRemoval(undo))
        #expect(store.items.map(\.id) == ["a", "b", "c"]) // re-inserted at original slots
    }

    @Test func canMergeRequiresTwoPlusSameBatch() {
        let a = item(id: "a", name: "牛奶", state: .fresh, storage: .fridge)
        let b = item(id: "b", name: "牛奶", state: .fresh, storage: .fridge)
        let other = item(id: "c", name: "牛奶", state: .fresh, storage: .pantry)
        #expect(InventoryStore.canMerge([a, b]))
        #expect(!InventoryStore.canMerge([a, other])) // storage differs
        #expect(!InventoryStore.canMerge([a]))        // need ≥2
    }

    @Test func mergeBatchSumsQuantitiesAndKeepsEarliestExpiry() async throws {
        let store = try await makeStore([
            dated(id: "a", name: "牛奶", daysUntilExpiry: 5),
            dated(id: "b", name: "牛奶", daysUntilExpiry: 2),
        ])
        // Both rows are the same batch (same name/unit/storage from `dated`).
        #expect(InventoryStore.canMerge(store.items))
        #expect(await store.mergeBatch(store.items))
        #expect(store.items.count == 1)
        #expect(store.items[0].quantity == "2") // 1 + 1 summed
        // Earliest expiry survives: the merged row is urgent (2 days), not the 5-day one.
        let earliest = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let merged = store.items[0].expiryDate
        #expect(merged != nil)
        if let merged {
            #expect(abs(merged.timeIntervalSince(earliest)) < 60 * 60 * 24) // within a day of the 2-day expiry
        }
    }

    @Test func mergeBatchRejectsNonMergeableSelection() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "b", name: "鸡蛋", state: .fresh, storage: .fridge), // different name
        ])
        #expect(!(await store.mergeBatch(store.items)))
        #expect(store.items.count == 2) // untouched
    }

    @Test func canMergeRejectsNonNumericQuantity() {
        // 「米 适量 袋」+「米 2 袋」must NOT be mergeable — the sum would coerce
        // "适量" to 0 and silently drop that row's stock.
        let some = item(id: "a", name: "米", state: .fresh, quantity: "适量")
        let two = item(id: "b", name: "米", state: .fresh, quantity: "2")
        #expect(!InventoryStore.canMerge([some, two]))
        #expect(InventoryStore.canMerge([two, item(id: "c", name: "米", state: .fresh, quantity: "3")]))
    }

    @Test func mergeBatchRefusesNonNumericQuantityAndLeavesRowsIntact() async throws {
        let store = try await makeStore([
            item(id: "a", name: "米", state: .fresh, quantity: "适量"),
            item(id: "b", name: "米", state: .fresh, quantity: "2"),
        ])
        #expect(!(await store.mergeBatch(store.items)))
        #expect(store.items.count == 2)
        #expect(Set(store.items.map(\.quantity)) == ["适量", "2"]) // 适量+2 ≠ 2
    }

    @Test func mergeBatchReGatesLiveRowsWhenSelectionIsStale() async throws {
        // The SELECTION passed in is numeric (canMerge passes), but the LIVE row
        // behind id "a" has since become "适量" — the live re-gate must bail
        // instead of summing it as 0.
        let store = try await makeStore([
            item(id: "a", name: "米", state: .fresh, quantity: "适量"),
            item(id: "b", name: "米", state: .fresh, quantity: "2"),
        ])
        let staleSelection = [
            item(id: "a", name: "米", state: .fresh, quantity: "1"), // stale numeric snapshot
            item(id: "b", name: "米", state: .fresh, quantity: "2"),
        ]
        #expect(InventoryStore.canMerge(staleSelection)) // the UI gate passes
        #expect(!(await store.mergeBatch(staleSelection)))
        #expect(store.items.count == 2) // untouched
        #expect(Set(store.items.map(\.quantity)) == ["适量", "2"])
    }

    // MARK: load→save 窗口竞态(并发 sync 写不得被陈旧整域 save 回退)

    @Test func deleteDoesNotResurrectARowTombstonedAfterLoad() async throws {
        // 确诊的僵尸复活序列:store.load() 后,并发 sync 用原子 mutate 给 X 落墓碑
        // (从仓库删除)。用户此刻删另一行 Y——若整域 save 从仍含 X 的陈旧快照派生,
        // X 会被整域重插复活;cursor 已越过墓碑,delta 重叠窗口外永不再拉,X 跨启动僵尸。
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "x", name: "被远端删除", state: .fresh),
            item(id: "y", name: "本地删这行", state: .fresh),
        ])
        // 并发 sync:X 的墓碑直接落盘(sync apply 走原子 mutate)。
        try await repo.mutateItems("home") { $0.filter { $0.id != "x" } }

        #expect(await store.delete(store.items.first { $0.id == "y" }!))

        let persisted = try await repo.loadAllFor("home").map(\.id)
        #expect(persisted.isEmpty) // X 保持删除,Y 也删除 —— 无僵尸
    }

    @Test func deleteDoesNotRevertARowAddedBySyncAfterLoad() async throws {
        // 对称序列(丢远端写):store.load() 后,并发 sync 新增远端行 Z。用户删 Y
        // 时的陈旧整域 save 会把 Z 一并抹掉,updated_at≤cursor 永不重投 → 跨设备永久丢。
        let z = item(id: "z", name: "远端新增", state: .fresh)
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "y", name: "本地删这行", state: .fresh),
        ])
        try await repo.mutateItems("home") { $0 + [z] }

        #expect(await store.delete(store.items.first { $0.id == "y" }!))

        let persisted = try await repo.loadAllFor("home").map(\.id)
        #expect(persisted == ["z"]) // Z 幸存
    }

    @Test func updateDoesNotRevertARowAddedBySyncAfterLoad() async throws {
        // 编辑路径同一窗口:编辑 Y 的整域 save 不得抹掉 load 后 sync 新增的 Z。
        let z = item(id: "z", name: "远端新增", state: .fresh)
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "y", name: "牛奶", state: .fresh),
        ])
        try await repo.mutateItems("home") { $0 + [z] }

        let y = store.items.first { $0.id == "y" }!
        #expect(await store.update(y, to: y.copyWith(name: "酸奶")))

        let persisted = try await repo.loadAllFor("home")
        #expect(persisted.contains { $0.id == "z" }) // Z 幸存
        #expect(persisted.first { $0.id == "y" }?.name == "酸奶") // 编辑照常落地
    }

    @Test func deleteManyDoesNotRevertARowAddedBySyncAfterLoad() async throws {
        // 批量删除同一窗口:删 A 的整域 save 不得抹掉 load 后 sync 新增的 Z。
        let z = item(id: "z", name: "远端新增", state: .fresh)
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "a", name: "A", state: .fresh),
            item(id: "b", name: "B", state: .fresh),
        ])
        try await repo.mutateItems("home") { $0 + [z] }

        #expect(await store.deleteMany([store.items.first { $0.id == "a" }!]) != nil)

        let persisted = try await repo.loadAllFor("home").map(\.id).sorted()
        #expect(persisted == ["b", "z"]) // A 删除,B 与并发新增 Z 都幸存
    }

    @Test func deleteDoesNotRemoveASameNameSiblingWhenTargetWasTombstoned() async throws {
        // 目标带非空 id 但已被并发墓碑:transform 在 live 行上按 id 找不到它时,
        // 绝不能跌到 name 兜底命中同名的另一行 —— 否则删掉用户没选的无辜兄弟。
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "y", name: "牛奶", state: .fresh),
            item(id: "z", name: "牛奶", state: .fresh), // 同名不同批
        ])
        try await repo.mutateItems("home") { $0.filter { $0.id != "y" } } // sync 墓碑 Y

        #expect(await store.delete(store.items.first { $0.id == "y" }!))

        let persisted = try await repo.loadAllFor("home").map(\.id)
        #expect(persisted == ["z"]) // Y 保持删除,同名兄弟 Z 幸存(未被 name 兜底误删)
    }

    @Test func updateDoesNotClobberASameNameSiblingOrResurrectTombstonedTarget() async throws {
        // 编辑路径更糟:name 兜底会把同名兄弟 Z 覆盖成携带被墓碑目标 id 的 next,
        // 既丢 Z 又把墓碑 Y 复活成僵尸。非空 id 找不到 → 必须 no-op。
        let (store, repo) = try await makeStoreWithRepo([
            item(id: "y", name: "牛奶", state: .fresh, quantity: "1"),
            item(id: "z", name: "牛奶", state: .fresh, quantity: "5"),
        ])
        try await repo.mutateItems("home") { $0.filter { $0.id != "y" } } // sync 墓碑 Y

        let y = store.items.first { $0.id == "y" }!
        _ = await store.update(y, to: y.copyWith(quantity: "9"))

        let persisted = try await repo.loadAllFor("home")
        #expect(persisted.map(\.id) == ["z"]) // 只剩 Z,Y 未被复活
        #expect(persisted.first?.quantity == "5") // Z 保留自己的量,未被 Y 的编辑覆盖
    }
}
