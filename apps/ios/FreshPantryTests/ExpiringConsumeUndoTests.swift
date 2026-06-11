import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Closed-loop tests for the 临期 screen's consume / undo / refresh wiring: the
/// 用了 quick action removes through `InventoryStore` while the tiers render
/// `ExpiringStore`'s independent snapshot of the SAME repository. These verify
/// that the reloads ExpiringView performs (after consume, after 撤销, and on
/// `onChange(of: inventoryStore.items)` when popping back from the detail)
/// converge the two stores — and that the undo reverses BOTH sides (row +
/// food-log entry), matching IngredientDetailView's banner contract.
@MainActor
struct ExpiringConsumeUndoTests {
    private struct Context {
        let expiring: ExpiringStore
        let inventory: InventoryStore
        let log: FoodLogRepository
    }

    /// Both stores share one in-memory repository, mirroring ExpiringView's
    /// setup (one InventoryRepository injected into both).
    private func makeContext(_ items: [Ingredient], household: String = "home") async throws -> Context {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let expiring = ExpiringStore(repository: repo, householdID: household)
        let inventory = InventoryStore(repository: repo, foodLogRepository: log, householdID: household)
        await expiring.load()
        await inventory.load()
        return Context(expiring: expiring, inventory: inventory, log: log)
    }

    /// Stable, expiry-free item so its state isn't recomputed by the loader's
    /// freshness normalization (no expiry date → state preserved as given).
    private func item(id: String, name: String, state: FreshnessState) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: FoodCategories.other, storage: .fridge
        )
    }

    @Test func consumeReturnsUndoHandleAndReloadDropsRowFromTiers() async throws {
        let ctx = try await makeContext([
            item(id: "u", name: "鸡肉", state: .urgent),
            item(id: "s", name: "酸奶", state: .expiringSoon),
        ])
        let target = ctx.inventory.items.first { $0.id == "u" }!

        // The handle the 撤销 banner consumes must exist for a matched row.
        let undo = await ctx.inventory.remove(target, outcome: .consumed)
        #expect(undo != nil)

        await ctx.expiring.load()
        #expect(ctx.expiring.sortedItems.map(\.id) == ["s"]) // row dropped off

        // The waste-stats side landed: exactly one consumed departure.
        let entries = try await ctx.log.loadAllFor("home")
        #expect(entries.map(\.outcome) == [.consumed])
        let entry = try #require(entries.first)
        #expect(entry.wasExpiring) // urgent → not fresh
    }

    @Test func undoConsumeRestoresRowToItsTierAndPointDeletesLog() async throws {
        let ctx = try await makeContext([
            item(id: "u", name: "鸡肉", state: .urgent),
            item(id: "s", name: "酸奶", state: .expiringSoon),
        ])
        let target = ctx.inventory.items.first { $0.id == "u" }!
        let undo = try #require(await ctx.inventory.remove(target, outcome: .consumed))
        await ctx.expiring.load()
        #expect(ctx.expiring.sortedItems.map(\.id) == ["s"]) // gone pre-undo

        // 撤销: both sides reverse, and the post-undo reload re-tiers the row.
        #expect(await ctx.inventory.undoRemove(undo))
        await ctx.expiring.load()
        #expect(ctx.expiring.sortedItems.map(\.id).sorted() == ["s", "u"])
        let urgentTier = try #require(ctx.expiring.tiers.first { $0.state == .urgent })
        #expect(urgentTier.items.map(\.id) == ["u"]) // back in its own tier

        let entries = try await ctx.log.loadAllFor("home")
        #expect(entries.isEmpty) // the consumed departure was point-deleted
    }

    @Test func consumeGhostRowYieldsNoUndoAndReloadSelfHeals() async throws {
        // A row deleted elsewhere (e.g. via the pushed detail) can linger in the
        // expiring snapshot; 用了 on it must not log, and the follow-up reload
        // drops the ghost.
        let ctx = try await makeContext([item(id: "u", name: "鸡肉", state: .urgent)])
        let target = ctx.expiring.sortedItems.first { $0.id == "u" }!
        #expect(await ctx.inventory.delete(target)) // out-of-band removal
        #expect(ctx.expiring.sortedItems.map(\.id) == ["u"]) // snapshot is stale

        let undo = await ctx.inventory.remove(target, outcome: .consumed)
        #expect(undo == nil) // no banner — nothing matched
        await ctx.expiring.load()
        #expect(ctx.expiring.sortedItems.isEmpty) // ghost dropped
        #expect(try await ctx.log.loadAllFor("home").isEmpty) // nothing logged
    }

    @Test func detailMutationsConvergeExpiringSnapshotAfterReload() async throws {
        // The detail's 仅移除 / edit only touch InventoryStore.items; the reload
        // ExpiringView's onChange(of: inventoryStore.items) performs must drop /
        // refresh the corresponding expiring rows.
        let ctx = try await makeContext([
            item(id: "u", name: "鸡肉", state: .urgent),
            item(id: "s", name: "酸奶", state: .expiringSoon),
        ])
        let target = ctx.inventory.items.first { $0.id == "u" }!
        #expect(await ctx.inventory.delete(target))
        #expect(ctx.expiring.sortedItems.count == 2) // stale until reload

        await ctx.expiring.load()
        #expect(ctx.expiring.sortedItems.map(\.id) == ["s"])
        #expect(try await ctx.log.loadAllFor("home").isEmpty) // 仅移除 logs nothing
    }
}
