import Foundation

/// Feature store for the Inventory slice — the reusable `@Observable @MainActor`
/// template later features copy.
///
/// Owns the household's ingredients (kept in repo/insertion order — the
/// parity-critical source order is never mutated by display concerns) plus the
/// filter / search state, and exposes `displayItems`: a derived, urgency-sorted,
/// storage-filtered, name-searched projection. All domain mapping, scoping, and
/// sorting live here (or the repo); views never touch SwiftData directly.
@Observable
@MainActor
final class InventoryStore {
    /// Storage-area filter. `nil` = 全部 (all locations).
    enum StorageFilter: Equatable {
        case all
        case area(IconType)
    }

    /// Category/state filter row (mirrors Flutter's 全部 / 不新鲜 / 5 大类 chips).
    enum CategoryFilter: Equatable {
        case all
        case notFresh
        case category(String)
    }

    private let repository: InventoryRepository
    /// Append-only food-departure log — the waste-stats source of truth. A manual
    /// removal-with-outcome appends one entry here (the ONLY non-cook log path).
    private let foodLogRepository: FoodLogRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?

    /// Repo/insertion-ordered items (the source of truth — never reordered here).
    private(set) var items: [Ingredient] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var storageFilter: StorageFilter = .all
    var categoryFilter: CategoryFilter = .all
    var searchQuery: String = ""

    init(
        repository: InventoryRepository,
        foodLogRepository: FoodLogRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil
    ) {
        self.repository = repository
        self.foodLogRepository = foodLogRepository
        self.householdID = householdID
        self.syncWriter = syncWriter
    }

    // MARK: Loading

    /// Loads the household scope off the repo actor and assigns on the main actor.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            items = try await repository.loadAllFor(householdID)
        } catch {
            // Surface an empty scope rather than crashing; a load error simply
            // means "nothing to show" for this read-only slice.
            items = []
        }
    }

    // MARK: Mutations

    /// Deletes a row by stable identity (id first, else name-guarded positional
    /// match), persists the survivors, and updates local state. Returns whether
    /// a row was removed. The plain delete logs NO departure (kept intact for
    /// callers that don't want an outcome).
    @discardableResult
    func delete(_ target: Ingredient) async -> Bool {
        guard let index = indexOf(target) else { return false }
        let removed = items[index]
        var survivors = items
        survivors.remove(at: index)
        do {
            try await repository.saveItems(householdID, survivors)
            items = survivors
        } catch {
            return false
        }
        await enqueueDelete(removed)
        return true
    }

    /// Describes a completed removal-with-outcome so the caller can offer an undo
    /// that reverses BOTH sides (re-add the row + reverse the food-log append).
    struct RemovalUndo: Sendable {
        /// The removed row (re-inserted at its original index on undo).
        let ingredient: Ingredient
        let originalIndex: Int
        /// The logged departure's id, to point-delete on undo. Empty when nothing
        /// was logged (a defensive append no-op never happens here, but stays safe).
        let loggedEntryId: String
    }

    /// Removes a row AND appends a matching `FoodLogEntry` for the chosen outcome
    /// (吃完了 → `.consumed`, 扔掉了/过期 → `.wasted`). This is the manual-removal
    /// waste-stats input — the cook flow logs its own consumed departures, so a
    /// row is never double-logged. `wasExpiring` snapshots whether the batch was
    /// already past fresh. Returns a `RemovalUndo` (nil if no row matched) so the
    /// caller can reverse both sides.
    @discardableResult
    func remove(_ target: Ingredient, outcome: FoodLogOutcome, now: Date = Date()) async -> RemovalUndo? {
        guard let index = indexOf(target) else { return nil }
        let removed = items[index]
        var survivors = items
        survivors.remove(at: index)
        do {
            try await repository.saveItems(householdID, survivors)
            items = survivors
        } catch {
            return nil
        }

        // Log AFTER the inventory save lands (mirrors the cook flow's ordering).
        let entry = FoodLogEntry(
            id: FoodLogEntry.newId(),
            name: removed.name,
            category: FoodCategories.normalize(removed.category) ?? FoodCategories.other,
            outcome: outcome,
            loggedAt: now,
            wasExpiring: removed.state != .fresh
        )
        try? await foodLogRepository.append(householdID, entry)
        await enqueueDelete(removed)
        return RemovalUndo(ingredient: removed, originalIndex: index, loggedEntryId: entry.id)
    }

    /// Reverses a removal-with-outcome: re-inserts the row at its original index
    /// and point-deletes the logged departure via `FoodLogRepository.deleteEntry`
    /// (NEVER `saveEntries`, which would drop window-outside history). Returns
    /// whether the row was re-added.
    @discardableResult
    func undoRemove(_ undo: RemovalUndo) async -> Bool {
        var restored = items
        let index = min(max(undo.originalIndex, 0), restored.count)
        restored.insert(undo.ingredient, at: index)
        do {
            try await repository.saveItems(householdID, restored)
            items = restored
        } catch {
            return false
        }
        if !undo.loggedEntryId.isEmpty {
            try? await foodLogRepository.deleteEntry(householdID, undo.loggedEntryId)
        }
        // Undelete path: re-assert the restored row remotely via a full-row write
        // (`.update`), which clears the soft-delete the original `.delete` set.
        if let patch = DomainJSON.valueMap(undo.ingredient) {
            await syncWriter?.enqueue(
                entityType: .inventoryItem,
                entityId: undo.ingredient.id,
                operation: .update,
                patch: patch,
                baseVersion: undo.ingredient.remoteVersion
            )
        }
        return true
    }

    /// Replaces an existing row IN PLACE (never a merge — an edit keeps its batch
    /// identity) by stable identity, recomputing freshness/state/label from the
    /// possibly-changed expiry/shelf-life, persisting the full scope, and enqueuing
    /// a sync `.update` against the original's `remoteVersion`. Mirrors the Flutter
    /// `InventoryNotifier.update`. `original` resolves the row (its unchanged fields
    /// survive a rename); `edited` carries the new values. Returns whether a row
    /// matched.
    @discardableResult
    func update(_ original: Ingredient, to edited: Ingredient) async -> Bool {
        guard let index = indexOf(original) else { return false }
        let base = items[index]
        // Identity + provenance the editor must never change come from the live
        // row; freshness/state/label are recomputed from the (new) expiry below.
        let next = IngredientNormalizer.normalizeInventoryIngredient(
            edited.copyWith(
                id: base.id,
                barcode: base.barcode,
                addedAt: edited.addedAt ?? base.addedAt,
                remoteVersion: base.remoteVersion
            )
        )
        var updated = items
        updated[index] = next
        do {
            try await repository.saveItems(householdID, updated)
            items = updated
        } catch {
            return false
        }
        await enqueueUpdate(next, baseVersion: base.remoteVersion)
        return true
    }

    /// Enqueues a full-row `.update` outbox op for an edited row, carrying the
    /// prior `baseVersion` for optimistic-concurrency merge. Skipped — still a
    /// successful local edit — when the row can't be serialized to a wire patch.
    private func enqueueUpdate(_ row: Ingredient, baseVersion: Int) async {
        guard let patch = DomainJSON.valueMap(row) else { return }
        await syncWriter?.enqueue(
            entityType: .inventoryItem,
            entityId: row.id,
            operation: .update,
            patch: patch,
            baseVersion: baseVersion
        )
    }

    /// Enqueues a soft-delete outbox op for `removed` (the gateway derives
    /// `deleted_at`). Skipped — still a successful local delete — when the row
    /// can't be serialized to a wire patch.
    private func enqueueDelete(_ removed: Ingredient) async {
        guard let patch = DomainJSON.valueMap(removed) else { return }
        await syncWriter?.enqueue(
            entityType: .inventoryItem,
            entityId: removed.id,
            operation: .delete,
            patch: patch,
            baseVersion: removed.remoteVersion
        )
    }

    /// Deletes ALL rows for the household (顶栏「清空全部」), persisting the empty
    /// scope and enqueuing a soft-delete per removed row. Returns whether anything
    /// was cleared.
    @discardableResult
    func clearAll() async -> Bool {
        let removed = items
        guard !removed.isEmpty else { return false }
        do {
            try await repository.saveItems(householdID, [])
            items = []
        } catch {
            return false
        }
        for row in removed { await enqueueDelete(row) }
        return true
    }

    // MARK: Multi-select (批量删除 / 合并批次)

    /// One removed row + its original index, captured so a batch delete can be
    /// fully undone (re-inserted at position). Nested struct (vs a tuple) so the
    /// undo handle is cleanly `Sendable`.
    struct RemovedRow: Sendable {
        let index: Int
        let ingredient: Ingredient
    }

    /// Undo handle for a batch delete — the removed rows in ascending index order.
    /// Carries a fresh `id` so the banner's auto-dismiss timer restarts on every
    /// new deletion, even two consecutive ones that removed the same row count.
    struct BatchRemovalUndo: Sendable, Identifiable {
        let id = UUID()
        let removed: [RemovedRow]
    }

    /// Removes every `targets` row at once (the multi-select 批量删除). Resolves
    /// each to its live index by stable identity, removes optimistically, and
    /// enqueues a soft-delete per row. Plain delete (no food-log — mirrors the
    /// single `delete`). Returns an undo handle, or nil when nothing matched.
    @discardableResult
    func deleteMany(_ targets: [Ingredient]) async -> BatchRemovalUndo? {
        let ascending = Set(targets.compactMap { indexOf($0) }).sorted()
        guard !ascending.isEmpty else { return nil }
        let removedRows = ascending.map { RemovedRow(index: $0, ingredient: items[$0]) }
        var survivors = items
        for index in ascending.reversed() { survivors.remove(at: index) }
        do {
            try await repository.saveItems(householdID, survivors)
            items = survivors
        } catch {
            return nil
        }
        for row in removedRows { await enqueueDelete(row.ingredient) }
        return BatchRemovalUndo(removed: removedRows)
    }

    /// Reverses a batch delete: re-inserts each removed row at its original index
    /// (ascending) and re-asserts it remotely via `.update` (clearing the
    /// soft-delete). Returns whether the rows were restored.
    @discardableResult
    func undoBatchRemoval(_ undo: BatchRemovalUndo) async -> Bool {
        var restored = items
        for row in undo.removed.sorted(by: { $0.index < $1.index }) {
            let index = min(max(row.index, 0), restored.count)
            restored.insert(row.ingredient, at: index)
        }
        do {
            try await repository.saveItems(householdID, restored)
            items = restored
        } catch {
            return false
        }
        for row in undo.removed {
            await enqueueUpdate(row.ingredient, baseVersion: row.ingredient.remoteVersion)
        }
        return true
    }

    /// Whether `rows` form one mergeable batch: ≥2 rows sharing normalized name +
    /// unit + storage (mirrors the Flutter `_canMerge` gate on `mergeBatch`).
    static func canMerge(_ rows: [Ingredient]) -> Bool {
        guard rows.count >= 2 else { return false }
        let first = rows[0]
        let name = first.name.trimmed.lowercased()
        let unit = first.unit.trimmed
        return rows.allSatisfy {
            $0.name.trimmed.lowercased() == name
                && $0.unit.trimmed == unit
                && $0.storage == first.storage
        }
    }

    /// Merges ≥2 same-batch rows into one (合并批次): sums numeric quantities, takes
    /// the EARLIEST expiry, recomputes freshness, keeps the earliest-positioned
    /// row's identity as the merged target, and soft-deletes the rest. Ports
    /// `InventoryNotifier.mergeBatch`. Returns whether it merged.
    @discardableResult
    func mergeBatch(_ targets: [Ingredient]) async -> Bool {
        guard Self.canMerge(targets) else { return false }
        let resolved = targets
            .compactMap { target -> RemovedRow? in
                guard let index = indexOf(target) else { return nil }
                return RemovedRow(index: index, ingredient: items[index])
            }
            .sorted { $0.index < $1.index }
        guard resolved.count >= 2 else { return false }

        let target = resolved[0].ingredient
        let sources = resolved.dropFirst().map(\.ingredient)
        let summed = resolved.reduce(0.0) { $0 + (Double($1.ingredient.quantity.trimmed) ?? 0) }
        let earliest = resolved.compactMap { $0.ingredient.expiryDate }.min()
        let merged = IngredientNormalizer.refreshFreshness(
            target.copyWith(quantity: QuantityText.formatQuantity(summed), expiryDate: earliest)
        )

        // Replace the target row in place; drop the source rows (descending so the
        // earlier removals don't shift later indices).
        var next = items
        next[resolved[0].index] = merged
        for row in resolved.dropFirst().sorted(by: { $0.index > $1.index }) {
            next.remove(at: row.index)
        }
        do {
            try await repository.saveItems(householdID, next)
            items = next
        } catch {
            return false
        }
        await enqueueUpdate(merged, baseVersion: target.remoteVersion)
        for source in sources { await enqueueDelete(source) }
        return true
    }

    // MARK: Derived view data

    /// The list the view renders: category/state filter → storage filter → name
    /// search → urgency sort.
    var displayItems: [Ingredient] {
        let filtered = items
            .filter(matchesCategoryFilter)
            .filter(matchesStorageFilter)
            .filter(matchesSearch)
        return sortByUrgency(filtered)
    }

    /// Count of items matching a category filter, for the chip badges.
    func count(for filter: CategoryFilter) -> Int {
        items.filter { matchesCategoryFilter($0, filter) }.count
    }

    /// True when there are stored items but the active filter/search hides them
    /// (drives the "no results" vs "empty pantry" copy).
    var hasActiveQuery: Bool {
        !searchQuery.trimmed.isEmpty || storageFilter != .all || categoryFilter != .all
    }

    /// Count of items in each storage area, for the filter-chip badges.
    func count(for filter: StorageFilter) -> Int {
        switch filter {
        case .all: return items.count
        case let .area(area): return items.filter { $0.storage == area }.count
        }
    }

    // MARK: Filtering / sorting internals

    private func matchesStorageFilter(_ item: Ingredient) -> Bool {
        switch storageFilter {
        case .all: return true
        case let .area(area): return item.storage == area
        }
    }

    private func matchesCategoryFilter(_ item: Ingredient) -> Bool {
        matchesCategoryFilter(item, categoryFilter)
    }

    private func matchesCategoryFilter(_ item: Ingredient, _ filter: CategoryFilter) -> Bool {
        switch filter {
        case .all: return true
        case .notFresh: return item.state != .fresh
        case let .category(category): return FoodCategories.dropdownValue(item.category) == category
        }
    }

    private func matchesSearch(_ item: Ingredient) -> Bool {
        let query = searchQuery.trimmed.lowercased()
        if query.isEmpty { return true }
        return item.name.lowercased().contains(query)
    }

    /// Sort: most-severe state first (expired→urgent→expiringSoon→fresh), then
    /// soonest expiry first (nil expiry last), stable by original index.
    private func sortByUrgency(_ list: [Ingredient]) -> [Ingredient] {
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ state: FreshnessState) -> Int { order.firstIndex(of: state) ?? order.count }

        return list.enumerated().sorted { lhs, rhs in
            let lRank = rank(lhs.element.state)
            let rRank = rank(rhs.element.state)
            if lRank != rRank { return lRank < rRank }

            switch (lhs.element.expiryDate, rhs.element.expiryDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.offset < rhs.offset // stable by source order
            }
        }.map(\.element)
    }

    /// Stable identity resolution: id first (when non-empty), else the first
    /// name-matching positional row (mirrors `inventoryIndexOf`).
    private func indexOf(_ target: Ingredient) -> Int? {
        if !target.id.isEmpty, let byId = items.firstIndex(where: { $0.id == target.id }) {
            return byId
        }
        return items.firstIndex(where: { $0 == target })
            ?? items.firstIndex(where: { $0.name == target.name })
    }
}
