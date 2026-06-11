import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Closed-loop tests for the batch-delete 去向追问: `deleteMany` with an outcome
/// must log one departure per removed row (the waste-stats input the plain batch
/// delete used to skip entirely), and `undoBatchRemoval` must reverse BOTH sides
/// (re-insert the rows + point-delete the logged departures), mirroring the
/// single `remove` / `undoRemove` pair.
@MainActor
struct BatchDeleteOutcomeTests {
    /// Builds a store backed by real in-memory inventory + food-log repos so the
    /// persist path is exercised end-to-end (the `InventoryStoreTests` pattern).
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

    /// Stable, expiry-free item so its state isn't recomputed by the loader's
    /// freshness normalization (no expiry date → state preserved as given).
    private func item(
        id: String,
        name: String,
        state: FreshnessState,
        category: String? = nil
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: category, storage: .fridge
        )
    }

    @Test func deleteManyWithOutcomeLogsOneDeparturePerRow() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh, category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "三文鱼", state: .urgent, category: FoodCategories.meatAndSeafood),
            item(id: "c", name: "盐", state: .fresh),
        ])
        let targets = store.items.filter { ["a", "b"].contains($0.id) }

        let undo = try #require(await store.deleteMany(targets, outcome: .consumed))
        #expect(store.items.map(\.id) == ["c"]) // rows removed
        await store.load()
        #expect(store.items.map(\.id) == ["c"]) // persisted

        // One CONSUMED departure per removed row, snapshots intact.
        let entries = try await log.loadAllFor("home")
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.outcome == .consumed })
        let milk = try #require(entries.first { $0.name == "牛奶" })
        #expect(milk.category == FoodCategories.dairyAndEggs)
        #expect(!milk.wasExpiring) // fresh → false
        let salmon = try #require(entries.first { $0.name == "三文鱼" })
        #expect(salmon.wasExpiring) // urgent → not fresh → true

        // Every removed row's undo handle points at its logged entry.
        #expect(undo.removed.count == 2)
        #expect(Set(undo.removed.map(\.loggedEntryId)) == Set(entries.map(\.id)))
    }

    @Test func deleteManyWithoutOutcomeStaysPlain() async throws {
        // The 仅移除 batch path keeps the existing plain-delete behavior: no log.
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let undo = try #require(await store.deleteMany([store.items[0]]))
        #expect(try await log.loadAllFor("home").isEmpty)
        #expect(undo.removed.allSatisfy { $0.loggedEntryId.isEmpty })
    }

    @Test func undoBatchRemovalRestoresRowsAndPointDeletesLoggedDepartures() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
            item(id: "c", name: "盐", state: .fresh),
        ])
        // Pre-seed an UNRELATED out-of-band entry; a correct undo (point delete)
        // must leave it intact (a saveEntries replace-all would drop it).
        let survivor = FoodLogEntry(
            id: "fl_survivor", name: "苹果", outcome: .consumed, loggedAt: Date()
        )
        try await log.append("home", survivor)

        let targets = store.items.filter { ["a", "c"].contains($0.id) }
        let undo = try #require(await store.deleteMany(targets, outcome: .wasted))
        #expect(try await log.loadAllFor("home").count == 3) // survivor + 2 logged

        #expect(await store.undoBatchRemoval(undo))
        #expect(store.items.map(\.id) == ["a", "b", "c"]) // original slots
        await store.load()
        #expect(store.items.map(\.id).sorted() == ["a", "b", "c"]) // persisted

        // The two logged departures are gone; the unrelated survivor remains.
        let remaining = try await log.loadAllFor("home")
        #expect(remaining.map(\.id) == ["fl_survivor"])
    }

    // MARK: RemoveResult (notFound vs failed vs removed)

    // `.failed` (saveItems throwing) isn't reachable with a real in-memory repo
    // (the IntakeReviewApplyErrorTests precedent), so these pin the two
    // reachable branches + the shim's collapse to nil.

    @Test func removeWithResultReturnsNotFoundForGhostRow() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
        ])
        let ghost = item(id: "ghost", name: "不存在", state: .fresh)

        let result = await store.removeWithResult(ghost, outcome: .consumed)

        guard case .notFound = result else {
            Issue.record("expected .notFound, got \(result)"); return
        }
        #expect(store.items.map(\.id) == ["a"]) // untouched
        #expect(try await log.loadAllFor("home").isEmpty) // nothing logged
    }

    @Test func removeWithResultReturnsRemovedWithUndoHandleOnSuccess() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])

        let result = await store.removeWithResult(store.items[0], outcome: .consumed)

        guard case let .removed(undo) = result else {
            Issue.record("expected .removed, got \(result)"); return
        }
        #expect(store.items.map(\.id) == ["b"])
        #expect(undo.ingredient.id == "a")
        #expect(undo.originalIndex == 0)
        // The departure was logged and the handle points at it (undo-able).
        #expect(try await log.loadAllFor("home").map(\.id) == [undo.loggedEntryId])
    }

    @Test func removeShimCollapsesNonSuccessToNil() async throws {
        // The optional-returning `remove` keeps its old contract for callers
        // that don't distinguish the failure modes (IngredientDetailView).
        let (store, _) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
        ])
        let ghost = item(id: "ghost", name: "不存在", state: .fresh)
        #expect(await store.remove(ghost, outcome: .consumed) == nil)
        #expect(await store.remove(store.items[0], outcome: .consumed) != nil)
    }

    @Test func deleteManyReturnsNilWhenNothingMatches() async throws {
        // The view's failure heuristic (nil handle + non-empty selection →
        // 删除失败 toast) relies on nil ALSO meaning "nothing matched"; pin
        // that a no-match batch is a harmless nil that leaves rows intact.
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
        ])
        let ghost = item(id: "ghost", name: "不存在", state: .fresh)

        #expect(await store.deleteMany([ghost], outcome: .consumed) == nil)
        #expect(store.items.map(\.id) == ["a"]) // untouched
        #expect(try await log.loadAllFor("home").isEmpty) // nothing logged
    }

    @Test func deleteManyWithOutcomeEnqueuesCreatesAndUndoEnqueuesDeletes() async throws {
        // With a sync writer present, the batch去向 path mirrors the single
        // `remove`: a `.foodLogEntry` create per logged departure, and a `.delete`
        // (soft delete) per entry on undo.
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let defaults = UserDefaults(suiteName: "test.batchdelete.\(UUID().uuidString)")!
        let session = SyncSession(selectedHouseholdId: "home", defaults: defaults)
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let rows = [
            item(id: "11111111-1111-4111-8111-111111111111", name: "苹果", state: .fresh),
            item(id: "22222222-2222-4222-8222-222222222222", name: "香蕉", state: .fresh),
        ]
        try await repo.saveItems("home", rows)
        let store = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home", syncWriter: writer)
        await store.load()

        let undo = try #require(await store.deleteMany(store.items, outcome: .wasted))
        let loggedIds = Set(undo.removed.map(\.loggedEntryId))
        #expect(loggedIds.count == 2)

        let afterDelete = try await outbox.loadPending()
        for id in loggedIds {
            #expect(afterDelete.contains { $0.entityType == .foodLogEntry && $0.operation == .create && $0.entityId == id })
        }

        _ = await store.undoBatchRemoval(undo)
        let afterUndo = try await outbox.loadPending()
        for id in loggedIds {
            #expect(afterUndo.contains { $0.entityType == .foodLogEntry && $0.operation == .delete && $0.entityId == id })
        }
    }
}
