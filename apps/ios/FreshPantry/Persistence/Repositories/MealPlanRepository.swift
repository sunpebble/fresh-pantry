import Foundation
import SwiftData

/// Weekly meal-plan entry CRUD. Filters rows missing id or recipeId; a dirty
/// date throws on decode and the row is skipped. Mirrors
/// `lib/storage/meal_plan_repo.dart`.
@ModelActor
actor MealPlanRepository {
    func loadAllFor(_ householdID: String) throws -> [MealPlanEntry] {
        // Sorted by id so fetch order is deterministic across reloads — SwiftData
        // fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<MealPlanRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row -> MealPlanEntry? in
            // A malformed date throws inside decode -> skip the row.
            guard let entry = try? row.entry() else { return nil }
            guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { return nil }
            return entry
        }
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: MealPlanRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    func saveEntries(_ householdID: String, _ entries: [MealPlanEntry]) throws {
        try modelContext.delete(
            model: MealPlanRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for entry in entries {
            guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { continue }
            if seenIds.contains(entry.id) { continue }
            seenIds.insert(entry.id)
            modelContext.insert(MealPlanRecord(householdID: householdID, entry: entry))
        }
        try modelContext.save()
    }

    /// Atomic load→transform→save in one actor call — the concurrent-write-safe
    /// sync write path (see `InventoryRepository.mutateItems`).
    func mutateEntries(_ householdID: String, _ transform: @Sendable ([MealPlanEntry]) -> [MealPlanEntry]) throws {
        try saveEntries(householdID, transform(loadAllFor(householdID)))
    }

    // MARK: Single-row writes (the offline-first optimistic path)
    //
    // The store mutates its in-memory `entries` SYNCHRONOUSLY (instant UI) then
    // lands the change through ONE of these — O(1), and addressing only the
    // tapped row means a peer instance's concurrent write to another day isn't
    // clobbered (so no 写前重读 is needed). Mirrors `ShoppingRepository`.

    /// Updates the single entry identified by `entry.id`, touching no other row.
    /// Returns false (a no-op, NOT an insert) when no such row exists — the 完成
    /// toggle only ever edits an existing entry; absence means a peer removed it.
    @discardableResult
    func updateRow(_ householdID: String, _ entry: MealPlanEntry) throws -> Bool {
        guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { return false }
        let id = entry.id
        let descriptor = FetchDescriptor<MealPlanRecord>(
            predicate: #Predicate { $0.householdID == householdID && $0.id == id }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return false }
        record.apply(entry)
        try modelContext.save()
        return true
    }

    /// Inserts `entry`, or updates it in place when its id already exists (the
    /// 加菜 path). Single-row; honours the same non-empty id/recipeId guard
    /// `saveEntries` applies.
    func upsert(_ householdID: String, _ entry: MealPlanEntry) throws {
        guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { return }
        let id = entry.id
        let descriptor = FetchDescriptor<MealPlanRecord>(
            predicate: #Predicate { $0.householdID == householdID && $0.id == id }
        )
        if let record = try modelContext.fetch(descriptor).first {
            record.apply(entry)
        } else {
            modelContext.insert(MealPlanRecord(householdID: householdID, entry: entry))
        }
        try modelContext.save()
    }

    /// Deletes the entries whose ids are in `ids` (a no-op for ids not present),
    /// leaving every other entry untouched — the 删除 path.
    func delete(_ householdID: String, ids: [String]) throws {
        let idSet = Set(ids.filter { !$0.isEmpty })
        guard !idSet.isEmpty else { return }
        let idList = Array(idSet)
        try modelContext.delete(
            model: MealPlanRecord.self,
            where: #Predicate { $0.householdID == householdID && idList.contains($0.id) }
        )
        try modelContext.save()
    }
}
