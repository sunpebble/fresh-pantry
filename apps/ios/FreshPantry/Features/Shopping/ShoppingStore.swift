import Foundation

/// Feature store for the Shopping slice — the same `@Observable @MainActor`
/// template the Inventory store established.
///
/// Owns the household's shopping items (kept in repo/insertion order — the
/// source order is never mutated by display concerns) and exposes
/// `displayItems`: a derived, category-sorted projection with checked rows
/// pushed to the bottom. All scoping, normalization, sorting, and persistence
/// live here (or the repo); views never touch SwiftData directly.
@Observable
@MainActor
final class ShoppingStore {
    /// Purchased-state filter for the list (mirrors Flutter's `ShoppingFilter`).
    enum ShoppingFilter: Equatable {
        case all
        case todo
        case done
    }

    private let repository: ShoppingRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?

    /// Repo/insertion-ordered items (the source of truth — never reordered here;
    /// already category-normalized + name-deduped by the repo on every load).
    private(set) var items: [ShoppingItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    /// 待购/已购/全部 filter driving `displaySections`. `all` is the default so
    /// existing behavior (and tests) are unchanged.
    var filter: ShoppingFilter = .all

    init(
        repository: ShoppingRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil
    ) {
        self.repository = repository
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
            // A load failure simply means "nothing to show"; never crash the tab.
            items = []
        }
    }

    // MARK: Mutations

    /// Flips a row's checked state by stable id identity, persists, and updates
    /// local state. Returns whether a row was toggled.
    @discardableResult
    func toggleChecked(_ target: ShoppingItem) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let toggled = items[index]
        let newChecked = !toggled.isChecked
        var next = items
        next[index] = toggled.copyWith(isChecked: newChecked)
        guard await persist(next) else { return false }
        await syncWriter?.enqueue(
            entityType: .shoppingItem,
            entityId: toggled.id,
            operation: .toggleChecked,
            patch: ["isChecked": .bool(newChecked)],
            baseVersion: toggled.remoteVersion
        )
        return true
    }

    /// Adds a new item (name required; detail optional; category defaulted via
    /// `FoodKnowledge` when not supplied). Name-unique per the repo's
    /// case-insensitive dedup. Returns whether a row was added (false when the
    /// name is blank or already present).
    @discardableResult
    func add(name: String, detail: String = "", category: String? = nil) async -> Bool {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return false }
        let key = ShoppingItemNormalizer.nameKey(trimmedName)
        guard !items.contains(where: { ShoppingItemNormalizer.nameKey($0.name) == key }) else {
            return false
        }
        let resolvedCategory = FoodCategories.normalize(category) ?? FoodKnowledge.categoryFor(trimmedName)
        let item = ShoppingItem(
            id: ShoppingItem.newId(),
            name: trimmedName,
            detail: detail.trimmed,
            category: resolvedCategory
        )
        guard await persist(items + [item]) else { return false }
        if let patch = DomainJSON.valueMap(item) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: item.id,
                operation: .create,
                patch: patch,
                baseVersion: nil
            )
        }
        return true
    }

    /// Re-inserts a previously-deleted row (preserving its id), persisting and
    /// enqueuing a full-row `.update` to clear the soft-delete remotely — the undo
    /// path for a swipe-delete. Mirrors the inventory undo (a `.update` un-deletes
    /// the row the prior `.delete` soft-removed). Returns whether the row was added.
    @discardableResult
    func restore(_ item: ShoppingItem) async -> Bool {
        // Already present (same id) — nothing to restore.
        guard !items.contains(where: { $0.id == item.id }) else { return false }
        guard await persist(items + [item]) else { return false }
        if let patch = DomainJSON.valueMap(item) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: item.id,
                operation: .update,
                patch: patch,
                baseVersion: item.remoteVersion
            )
        }
        return true
    }

    /// Deletes a row by stable id identity, persists the survivors, and updates
    /// local state. Returns whether a row was removed.
    @discardableResult
    func delete(_ target: ShoppingItem) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let removed = items[index]
        var survivors = items
        survivors.remove(at: index)
        guard await persist(survivors) else { return false }
        // Enqueue the soft-delete so it propagates to other members (the gateway
        // routes shoppingItem/.delete to a soft-delete). Without this the row
        // stays on the server and re-appears on the next pull (remote wins).
        if let patch = DomainJSON.valueMap(removed) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: removed.id,
                operation: .delete,
                patch: patch,
                baseVersion: removed.remoteVersion
            )
        }
        return true
    }

    /// Persists `next` through the repo actor (which re-normalizes + de-dupes),
    /// then re-syncs local state from the canonical reload. Returns success.
    private func persist(_ next: [ShoppingItem]) async -> Bool {
        do {
            try await repository.saveItems(householdID, next)
            items = try await repository.loadAllFor(householdID)
            return true
        } catch {
            return false
        }
    }

    // MARK: Derived view data

    /// The list the view renders: canonical category order, then unchecked
    /// before checked, stable by source order within each bucket.
    var displayItems: [ShoppingItem] {
        sortForDisplay(items)
    }

    /// `displayItems` grouped into category sections in canonical order, narrowed
    /// to the active `filter` (todo→unchecked, done→checked, all→both). Each
    /// section's rows keep the unchecked-before-checked ordering. Drives the
    /// per-category section headers.
    var displaySections: [(category: String, items: [ShoppingItem])] {
        let sorted = sortForDisplay(items).filter(matchesFilter)
        var order: [String] = []
        var buckets: [String: [ShoppingItem]] = [:]
        for item in sorted {
            let category = FoodCategories.normalize(item.category) ?? FoodCategories.other
            if buckets[category] == nil { order.append(category) }
            buckets[category, default: []].append(item)
        }
        return order.map { (category: $0, items: buckets[$0] ?? []) }
    }

    var checkedCount: Int { items.filter(\.isChecked).count }
    var uncheckedCount: Int { items.count - checkedCount }
    var total: Int { items.count }

    /// Purchase progress (checked / total), 0 when the list is empty. Drives the
    /// progress card's percent + bar.
    var progress: Double {
        total == 0 ? 0 : Double(checkedCount) / Double(total)
    }

    private func matchesFilter(_ item: ShoppingItem) -> Bool {
        switch filter {
        case .all: return true
        case .todo: return !item.isChecked
        case .done: return item.isChecked
        }
    }

    // MARK: Sorting internals

    /// Category canonical order (rank), then unchecked first, then stable by the
    /// item's original source index so reordering never reshuffles peers.
    private func sortForDisplay(_ list: [ShoppingItem]) -> [ShoppingItem] {
        list.enumerated().sorted { lhs, rhs in
            let lChecked = lhs.element.isChecked
            let rChecked = rhs.element.isChecked
            if lChecked != rChecked { return !lChecked } // unchecked first

            let lRank = categoryRank(lhs.element.category)
            let rRank = categoryRank(rhs.element.category)
            if lRank != rRank { return lRank < rRank }

            return lhs.offset < rhs.offset // stable by source order
        }.map(\.element)
    }

    /// Index of the item's normalized category in `FoodCategories.values`;
    /// unknown/blank categories sort last.
    private func categoryRank(_ category: String) -> Int {
        let normalized = FoodCategories.normalize(category) ?? FoodCategories.other
        return FoodCategories.values.firstIndex(of: normalized) ?? FoodCategories.values.count
    }
}
