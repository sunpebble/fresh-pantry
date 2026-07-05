import Foundation
import SwiftData

/// Inventory CRUD + non-synced add-history (frequency memory) + FrequentItem
/// derivation. Mirrors `lib/storage/inventory_repo.dart` minus the Riverpod
/// one-shot hydrate/loadAll seed (a Flutter build() workaround, dropped here).
@ModelActor
actor InventoryRepository {
    /// SELECT WHERE household_id == householdID; per-row decode + normalize;
    /// malformed rows are skipped, survivors preserved.
    func loadAllFor(_ householdID: String) throws -> [Ingredient] {
        // Sorted by id so the fetch order the stores rely on as a stable display
        // tiebreaker (`.enumerated().offset`) is deterministic across reloads —
        // SwiftData fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<InventoryItemRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row in
            guard let ingredient = try? row.ingredient() else { return nil }
            return IngredientNormalizer.normalizeInventoryIngredient(ingredient)
        }
    }

    /// DELETE WHERE household_id == householdID (used when adopting local '' data).
    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: InventoryItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    /// Replace the whole household scope: delete scope, then insert all items.
    /// Non-empty ids must be unique within a household (mirrors the partial
    /// unique index); blank ids legitimately repeat (each is a distinct row).
    func saveItems(_ householdID: String, _ items: [Ingredient]) throws {
        try modelContext.delete(
            model: InventoryItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for item in items {
            let trimmedId = item.id.trimmed
            // Enforce non-empty-id uniqueness in code; blank ids always insert.
            if !trimmedId.isEmpty {
                if seenIds.contains(trimmedId) { continue }
                seenIds.insert(trimmedId)
            }
            modelContext.insert(InventoryItemRecord(householdID: householdID, ingredient: item))
        }
        try modelContext.save()
    }

    // MARK: Add-history (frequency memory)

    /// In-memory + persisted history map: name -> AddHistoryEntry.
    func loadHistory() throws -> [String: AddHistoryEntry] {
        let rows = try modelContext.fetch(FetchDescriptor<AddHistoryRecord>())
        var map: [String: AddHistoryEntry] = [:]
        for row in rows {
            if let entry = try? row.entry() { map[row.name] = entry }
        }
        return map
    }

    /// Replace-all history persistence.
    func saveHistory(_ history: [String: AddHistoryEntry]) throws {
        try modelContext.delete(model: AddHistoryRecord.self)
        for (name, entry) in history {
            modelContext.insert(AddHistoryRecord(name: name, entry: entry))
        }
        try modelContext.save()
    }

    func clearHistory() throws { try saveHistory([:]) }

    /// Bump the history count for an added item and store its remembered defaults.
    func recordAddition(_ item: Ingredient) throws {
        try recordAdditions([item])
    }

    /// Bumps the add-history count for MANY items in ONE read + ONE write — the
    /// batch-intake path. Calling `recordAddition` per item re-reads and
    /// whole-rewrites the history on every call (delete-all + reinsert-all ×N =
    /// O(N²) over a batch); this loads once, folds every item into the map (a
    /// repeated name accumulates correctly), then saves once. No-op for an empty
    /// batch.
    func recordAdditions(_ items: [Ingredient]) throws {
        guard !items.isEmpty else { return }
        var history = try loadHistory()
        for item in items {
            let existingCount = history[item.name]?.count ?? 0
            history[item.name] = AddHistoryEntry(
                count: existingCount + 1,
                category: FoodCategories.normalize(item.category) ?? "",
                storage: item.storage.rawValue,
                unit: item.unit
            )
        }
        try saveHistory(history)
    }

    func forgetAddition(_ name: String) throws {
        var history = try loadHistory()
        guard history[name] != nil else { return }
        history.removeValue(forKey: name)
        try saveHistory(history)
    }

    /// Derive `FrequentItem`s from the persisted history.
    func loadFrequentItems() throws -> [FrequentItem] {
        let history = try loadHistory()
        return history.map { name, entry in
            let rememberedCategory = entry.category.isEmpty ? nil : entry.category
            let category = FoodCategories.dropdownValue(
                rememberedCategory ?? FoodKnowledge.lookup(name)?.category
            )
            let storage = IconType.fromName(entry.storage.isEmpty ? "fridge" : entry.storage)
            let unit = entry.unit.isEmpty ? "个" : entry.unit // i18n:ignore data identity, not UI text
            return FrequentItem(
                name: name,
                category: category,
                storage: storage,
                unit: unit,
                shelfLifeDays: FoodKnowledge.lookup(name)?.shelfLifeDays,
                count: entry.count
            )
        }
    }
}
