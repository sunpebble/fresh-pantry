import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Concurrent-write regression tests. `ShoppingStore.persist` replaces the
/// WHOLE household scope, so writes are guarded twice:
/// 1. 写前重读 — every mutation re-reads the repo first, otherwise a
///    session-scoped second instance (Dashboard 加购 / Siri drain / 缺料卡 each
///    build their own store) silently loses rows the other instance wrote after
///    this one's last load. Backed by TWO stores over the same in-memory repo.
/// 2. FIFO mutation chain — two interleaved mutations on the SAME store (quick
///    successive taps) must not load the same snapshot and overwrite each
///    other's persist; each mutation awaits its predecessor.
/// Plus the three-state `AddOutcome` split (added/duplicate/failed) feedback
/// UIs branch their copy on.
@MainActor
struct ShoppingStoreConcurrentWriteTests {
    private let household = "home"

    private func makeRepo(_ items: [ShoppingItem] = []) async throws -> ShoppingRepository {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        if !items.isEmpty {
            try await repo.saveItems(household, items)
        }
        return repo
    }

    private func makeStore(_ repo: ShoppingRepository, syncWriter: SyncWriter? = nil) async -> ShoppingStore {
        let store = ShoppingStore(repository: repo, householdID: household, syncWriter: syncWriter)
        await store.load()
        return store
    }

    private func item(
        id: String,
        name: String,
        isChecked: Bool = false,
        detail: String = ""
    ) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, category: FoodCategories.other, isChecked: isChecked)
    }

    // MARK: 跨实例写不互相覆盖

    @Test func addPreservesRowsWrittenByAnotherStoreInstance() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let stale = await makeStore(repo) // snapshot frozen here
        let other = await makeStore(repo)
        #expect(await other.add(name: "面包")) // the row a stale persist would drop

        #expect(await stale.add(name: "鸡蛋"))

        let names = Set(try await repo.loadAllFor(household).map(\.name))
        #expect(names == ["牛奶", "面包", "鸡蛋"])
        // The stale store itself caught up too (写前重读 re-synced it).
        #expect(Set(stale.items.map(\.name)) == ["牛奶", "面包", "鸡蛋"])
    }

    @Test func toggleCheckedPreservesRowsWrittenByAnotherStoreInstance() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let stale = await makeStore(repo)
        let staleMilk = stale.items[0]
        let other = await makeStore(repo)
        #expect(await other.add(name: "面包"))

        #expect(await stale.toggleChecked(staleMilk))

        let rows = try await repo.loadAllFor(household)
        #expect(Set(rows.map(\.name)) == ["牛奶", "面包"])
        #expect(rows.first { $0.name == "牛奶" }?.isChecked == true)
    }

    @Test func deletePreservesRowsWrittenByAnotherStoreInstance() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶"), item(id: "egg", name: "鸡蛋")])
        let stale = await makeStore(repo)
        let staleMilk = stale.items.first { $0.id == "milk" }!
        let other = await makeStore(repo)
        #expect(await other.add(name: "面包"))

        #expect(await stale.delete(staleMilk))

        let names = Set(try await repo.loadAllFor(household).map(\.name))
        #expect(names == ["鸡蛋", "面包"]) // only the target died
    }

    @Test func updateDetailPreservesRowsWrittenByAnotherStoreInstance() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶", detail: "1 盒")])
        let stale = await makeStore(repo)
        let staleMilk = stale.items[0]
        let other = await makeStore(repo)
        #expect(await other.add(name: "面包"))

        #expect(await stale.updateDetail(staleMilk, detail: "3 盒"))

        let rows = try await repo.loadAllFor(household)
        #expect(Set(rows.map(\.name)) == ["牛奶", "面包"])
        #expect(rows.first { $0.name == "牛奶" }?.detail == "3 盒")
    }

    @Test func addDedupesAgainstRowAddedByAnotherStoreInstance() async throws {
        let repo = try await makeRepo()
        let stale = await makeStore(repo) // loaded empty
        let other = await makeStore(repo)
        #expect(await other.add(name: "牛奶"))

        // A detail-less duplicate can't merge → rejected against the FRESH list,
        // not appended next to the row the other instance just wrote.
        #expect(!(await stale.add(name: "牛奶")))
        #expect(try await repo.loadAllFor(household).count == 1)
    }

    @Test func mutatingRowDeletedByAnotherStoreInstanceReturnsFalse() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let stale = await makeStore(repo)
        let staleMilk = stale.items[0]
        let other = await makeStore(repo)
        #expect(await other.delete(other.items[0]))

        #expect(!(await stale.toggleChecked(staleMilk)))
        #expect(!(await stale.updateDetail(staleMilk, detail: "2 盒")))
        #expect(try await repo.loadAllFor(household).isEmpty)
    }

    // MARK: deleteAll（清空已完成）

    @Test func deleteAllRemovesOnlyTargetsAndReturnsRemoved() async throws {
        let repo = try await makeRepo([
            item(id: "a", name: "牛奶", isChecked: true),
            item(id: "b", name: "鸡蛋", isChecked: true),
            item(id: "c", name: "苹果"),
        ])
        let store = await makeStore(repo)
        let checked = store.items.filter(\.isChecked)
        let other = await makeStore(repo)
        #expect(await other.add(name: "面包")) // must survive the batch delete

        let removed = try #require(await store.deleteAll(checked))

        #expect(Set(removed.map(\.id)) == ["a", "b"])
        let names = Set(try await repo.loadAllFor(household).map(\.name))
        #expect(names == ["苹果", "面包"])
    }

    @Test func deleteAllThenRestoreRoundTrips() async throws {
        let repo = try await makeRepo([
            item(id: "a", name: "牛奶", isChecked: true, detail: "2 盒"),
            item(id: "b", name: "鸡蛋", isChecked: true),
            item(id: "c", name: "苹果"),
        ])
        let store = await makeStore(repo)

        let removed = try #require(await store.deleteAll(store.items.filter(\.isChecked)))
        #expect(removed.count == 2)
        for item in removed {
            #expect(await store.restore(item)) // the undo banner's loop
        }

        let rows = try await repo.loadAllFor(household)
        #expect(Set(rows.map(\.id)) == ["a", "b", "c"])
        #expect(rows.first { $0.id == "a" }?.detail == "2 盒") // 数量信息没丢
    }

    @Test func deleteAllOnAlreadyGoneIdsReturnsEmpty() async throws {
        // EMPTY (not nil) — the benign no-op: the rows were already gone, which
        // the caller must NOT surface as a「清理失败」.
        let repo = try await makeRepo([item(id: "a", name: "牛奶")])
        let store = await makeStore(repo)
        let ghost = item(id: "zzz", name: "幽灵")

        #expect(await store.deleteAll([ghost]) == [])
        #expect(await store.deleteAll([]) == [])
        #expect(try await repo.loadAllFor(household).count == 1)
    }

    @Test func deleteAllEnqueuesOneSoftDeletePerRemovedRow() async throws {
        // Same propagation contract as the single `delete`: without the `.delete`
        // ops the rows stay on the server and re-appear on the next pull.
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        let idA = UUID().uuidString.lowercased()
        let idB = UUID().uuidString.lowercased()
        try await repo.saveItems(household, [
            ShoppingItem(id: idA, name: "牛奶", detail: "", category: FoodCategories.other, isChecked: true)
                .copyWith(remoteVersion: 3),
            ShoppingItem(id: idB, name: "鸡蛋", detail: "", category: FoodCategories.other, isChecked: true)
                .copyWith(remoteVersion: 5),
        ])

        let outbox = SyncOutboxRepository(modelContainer: container)
        let session = SyncSession(
            selectedHouseholdId: household,
            defaults: UserDefaults(suiteName: "test.shopping.deleteAll.\(UUID().uuidString)")!
        )
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let store = await makeStore(repo, syncWriter: writer)

        let removed = try #require(await store.deleteAll(store.items))
        #expect(removed.count == 2)

        let pending = try await outbox.loadPending()
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.entityType == .shoppingItem && $0.operation == .delete })
        #expect(Set(pending.map(\.entityId)) == [idA, idB])
    }

    // MARK: 三态 add/restore（duplicate ≠ failed）

    @Test func addItemReportsAddedForNewRow() async throws {
        let repo = try await makeRepo()
        let store = await makeStore(repo)

        #expect(await store.addItem(name: "牛奶") == .added)
        #expect(try await repo.loadAllFor(household).count == 1)
    }

    @Test func addItemReportsAddedWhenQuantityMerges() async throws {
        let repo = try await makeRepo([item(id: "milk", name: "牛奶", detail: "1 盒")])
        let store = await makeStore(repo)

        #expect(await store.addItem(name: "牛奶", detail: "2 盒") == .added)
        let rows = try await repo.loadAllFor(household)
        #expect(rows.count == 1)
        #expect(rows[0].detail == "3 盒")
    }

    @Test func addItemReportsDuplicateForUnmergeableName() async throws {
        // The case UIs render as「已在购物清单中」— it must be distinguishable
        // from a write failure (which never wrote anything).
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let store = await makeStore(repo)

        #expect(await store.addItem(name: "牛奶") == .duplicate)
        #expect(try await repo.loadAllFor(household).count == 1)
    }

    @Test func addItemReportsFailedForBlankName() async throws {
        // Nothing was written and nothing is "already on the list" — blank input
        // maps to `.failed`, never to the affirmative duplicate copy.
        let repo = try await makeRepo()
        let store = await makeStore(repo)

        #expect(await store.addItem(name: "   ") == .failed)
        #expect(try await repo.loadAllFor(household).isEmpty)
    }

    @Test func boolAddShimIsTrueOnlyForAdded() async throws {
        // The legacy Bool surface (non-feedback call sites + older tests) keeps
        // its exact semantics: true == a row actually landed.
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let store = await makeStore(repo)

        #expect(await store.add(name: "鸡蛋")) // .added → true
        #expect(!(await store.add(name: "牛奶"))) // .duplicate → false
        #expect(!(await store.add(name: "  "))) // .failed → false
    }

    @Test func restoreItemDistinguishesAlreadyPresentFromRestored() async throws {
        // `.duplicate` (the row is already back) is the undo banner's benign
        // case — only `.failed` may surface a retry toast.
        let repo = try await makeRepo([item(id: "milk", name: "牛奶")])
        let store = await makeStore(repo)
        let milk = store.items[0]

        #expect(await store.restoreItem(milk) == .duplicate)
        #expect(await store.delete(milk))
        #expect(await store.restoreItem(milk) == .added)
        #expect(try await repo.loadAllFor(household).count == 1)
    }

    // MARK: 同实例交错 mutation 串行化（FIFO 链）

    @Test func interleavedAddsAllLand() async throws {
        // Two quick adds run as separate MainActor tasks whose 写前重读/persist
        // suspension points interleave. Without the FIFO mutation chain both
        // could load the same snapshot and the second whole-scope persist would
        // silently drop the first row.
        let repo = try await makeRepo()
        let store = await makeStore(repo)

        let t1 = Task { await store.add(name: "面包") }
        let t2 = Task { await store.add(name: "鸡蛋") }
        let t3 = Task { await store.add(name: "牛奶") }
        #expect(await t1.value)
        #expect(await t2.value)
        #expect(await t3.value)

        #expect(Set(try await repo.loadAllFor(household).map(\.name)) == ["面包", "鸡蛋", "牛奶"])
    }

    @Test func interleavedTogglesBothPersist() async throws {
        // 逛超市连点两个勾选框: each tap spawns its own Task (the view's exact
        // pattern). Neither check-off may be lost to the other's persist.
        let repo = try await makeRepo([item(id: "a", name: "牛奶"), item(id: "b", name: "鸡蛋")])
        let store = await makeStore(repo)
        let milk = store.items.first { $0.id == "a" }!
        let egg = store.items.first { $0.id == "b" }!

        let t1 = Task { await store.toggleChecked(milk) }
        let t2 = Task { await store.toggleChecked(egg) }
        #expect(await t1.value)
        #expect(await t2.value)

        let rows = try await repo.loadAllFor(household)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.isChecked })
    }

    @Test func interleavedToggleAndDeleteBothApply() async throws {
        // Mixed mutations chain FIFO too: the toggle's persist must not resurrect
        // the row the delete removed, and the delete must not drop the toggle.
        let repo = try await makeRepo([item(id: "a", name: "牛奶"), item(id: "b", name: "鸡蛋")])
        let store = await makeStore(repo)
        let milk = store.items.first { $0.id == "a" }!
        let egg = store.items.first { $0.id == "b" }!

        let t1 = Task { await store.toggleChecked(milk) }
        let t2 = Task { await store.delete(egg) }
        #expect(await t1.value)
        #expect(await t2.value)

        let rows = try await repo.loadAllFor(household)
        #expect(rows.map(\.id) == ["a"])
        #expect(rows[0].isChecked)
    }
}
