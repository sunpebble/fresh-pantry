import Foundation
import SwiftData

/// Shopping-list CRUD with category normalization + case-insensitive name dedup
/// applied on BOTH load and remote-merge (the original divergence bug was
/// deduping in only one path). Mirrors `lib/storage/shopping_repo.dart`.
@ModelActor
actor ShoppingRepository {
    /// SELECT scope; per-row decode + category-normalize (skip malformed); then
    /// dedupe by case-insensitive name.
    func loadAllFor(_ householdID: String) throws -> [ShoppingItem] {
        // Sorted by id so the case-insensitive name dedup ("keep first") is
        // deterministic — SwiftData fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        let items = rows.compactMap { row -> ShoppingItem? in
            guard let item = try? row.item() else { return nil }
            return ShoppingItemNormalizer.normalizeCategory(item)
        }
        return ShoppingItemNormalizer.deduplicate(items)
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: ShoppingItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    /// Replace the whole household scope. `id` is the natural key (unique).
    func saveItems(_ householdID: String, _ items: [ShoppingItem]) throws {
        try modelContext.delete(
            model: ShoppingItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for item in items {
            let id = item.id.trimmed
            if id.isEmpty || seenIds.contains(id) { continue }
            seenIds.insert(id)
            modelContext.insert(ShoppingItemRecord(householdID: householdID, item: item))
        }
        try modelContext.save()
    }

    /// Atomic load→transform→save in one actor call — the concurrent-write-safe
    /// sync write path (see `InventoryRepository.mutateItems`).
    func mutateItems(_ householdID: String, _ transform: @Sendable ([ShoppingItem]) -> [ShoppingItem]) throws {
        try saveItems(householdID, transform(loadAllFor(householdID)))
    }

    // MARK: Single-row writes (the offline-first optimistic path)
    //
    // The store applies a tap to its in-memory `items` SYNCHRONOUSLY (instant UI)
    // then lands it through ONE of these. Unlike `saveItems` (whole-scope
    // delete+reinsert, O(N)/tap) each touches only the addressed row, so it (a) is
    // O(1) and (b) can't clobber a peer store instance's concurrent write to a
    // DIFFERENT row — which is the entire reason the old whole-scope path needed a
    // 写前重读. `id` is the unique natural key, so addressing by it is exact.

    /// Updates the single row identified by `item.id`, touching no other row.
    /// Returns false (a no-op, NOT an insert) when no such row exists — the caller
    /// reads that as "a peer deleted this row" and self-heals. Used by the
    /// check-off / 数量编辑 taps, which only ever edit an existing row.
    @discardableResult
    func updateRow(_ householdID: String, _ item: ShoppingItem) throws -> Bool {
        let id = item.id.trimmed
        guard !id.isEmpty else { return false }
        let descriptor = FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.householdID == householdID && $0.id == id }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return false }
        record.apply(item)
        try modelContext.save()
        return true
    }

    /// Inserts `item`, or updates it in place when its id already exists (the
    /// add / restore-from-undo re-insert path). Single-row, never a whole-scope
    /// rewrite.
    func upsert(_ householdID: String, _ item: ShoppingItem) throws {
        let id = item.id.trimmed
        guard !id.isEmpty else { return }
        let descriptor = FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.householdID == householdID && $0.id == id }
        )
        if let record = try modelContext.fetch(descriptor).first {
            record.apply(item)
        } else {
            modelContext.insert(ShoppingItemRecord(householdID: householdID, item: item))
        }
        try modelContext.save()
    }

    /// Deletes the rows whose ids are in `ids` (a no-op for ids not present),
    /// leaving every other row untouched — the single delete / 清空已完成 /
    /// 一键入库 drop path.
    func delete(_ householdID: String, ids: [String]) throws {
        let idSet = Set(ids.map { $0.trimmed }.filter { !$0.isEmpty })
        guard !idSet.isEmpty else { return }
        let idList = Array(idSet)
        try modelContext.delete(
            model: ShoppingItemRecord.self,
            where: #Predicate { $0.householdID == householdID && idList.contains($0.id) }
        )
        try modelContext.save()
    }
}
