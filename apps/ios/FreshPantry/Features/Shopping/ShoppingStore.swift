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

    /// Three-state outcome for `addItem`/`restoreItem`. The legacy `Bool` return
    /// conflated "duplicate" with "read/write failed", which feedback UIs then
    /// rendered as the affirmative「已在购物清单中」— asserting a fact the store
    /// never verified. Callers branch copy on this instead:
    /// `.duplicate` →「已在购物清单中」, `.failed` →「添加失败，请重试」.
    enum AddOutcome: Equatable, Sendable {
        /// A row was appended, quantity-merged (同名自动聚合), or re-inserted.
        case added
        /// The same name (or, for `restoreItem`, the same id) is already on the
        /// list and couldn't merge — nothing was written, but the user's goal
        /// is already satisfied.
        case duplicate
        /// 写前重读 or persist threw (or the name was blank): nothing was
        /// written. Surface a retryable failure, never a duplicate message.
        case failed
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

    /// Collapsed category section keys (the 分类分组折叠态). View state kept here
    /// like `filter`; in-memory only (load/reload never touch it), matching the
    /// Flutter non-persistent behavior. String keys tolerate a category vanishing
    /// + reappearing across filters (a stale key is harmless).
    private(set) var collapsedCategories: Set<String> = []

    func isCollapsed(_ category: String) -> Bool { collapsedCategories.contains(category) }

    func toggleCollapsed(_ category: String) {
        if collapsedCategories.remove(category) == nil { collapsedCategories.insert(category) }
    }

    /// Ensures a category section is visible (e.g. after global-search handoff).
    func ensureExpanded(_ category: String) {
        collapsedCategories.remove(category)
    }

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

    /// FIFO mutation chain: every mutation awaits its predecessor before its
    /// read-modify-write runs. Each mutation suspends twice (写前重读 + persist)
    /// and `persist` replaces the WHOLE household scope — without the chain, two
    /// quick check-off taps could both load the same snapshot and the second
    /// persist would silently drop the first one's write.
    @ObservationIgnored
    private var lastMutation: Task<Void, Never>?

    /// Runs `body` after every previously-enqueued mutation finished, and makes
    /// the next mutation wait for `body` in turn. MainActor-only, so reading +
    /// relinking `lastMutation` between two mutations is race-free.
    private func serializedMutation<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = lastMutation
        let task: Task<T, Never> = Task {
            await previous?.value
            return await body()
        }
        lastMutation = Task { _ = await task.value }
        return await task.value
    }

    /// Flips a row's checked state by stable id identity, persists, and updates
    /// local state. Returns whether a row was toggled.
    @discardableResult
    func toggleChecked(_ target: ShoppingItem) async -> Bool {
        await serializedMutation { await self.performToggleChecked(target) }
    }

    private func performToggleChecked(_ target: ShoppingItem) async -> Bool {
        guard await refreshBeforeMutate() else { return false }
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

    /// Compatibility shim over `addItem` — true ONLY when a row was actually
    /// added/merged. Kept so legacy call sites/tests that only branch on
    /// "did something land" keep compiling; prefer `addItem` wherever the
    /// duplicate/failure split reaches user-facing copy.
    @discardableResult
    func add(name: String, detail: String = "", category: String? = nil) async -> Bool {
        await addItem(name: name, detail: detail, category: category) == .added
    }

    /// Adds a new item (name required; detail optional; category defaulted via
    /// `FoodKnowledge` when not supplied). Name-unique per the repo's
    /// case-insensitive dedup — but a duplicate name no longer always rejects:
    /// when both details parse to the same unit the quantities merge into the
    /// existing row (see `mergeQuantity`). Returns `.added` for an appended or
    /// merged row, `.duplicate` for a same-name row that couldn't merge, and
    /// `.failed` when nothing was written (blank name, read or persist error).
    func addItem(name: String, detail: String = "", category: String? = nil) async -> AddOutcome {
        await serializedMutation { await self.performAdd(name: name, detail: detail, category: category) }
    }

    private func performAdd(name: String, detail: String, category: String?) async -> AddOutcome {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return .failed }
        guard await refreshBeforeMutate() else { return .failed }
        let key = ShoppingItemNormalizer.nameKey(trimmedName)
        if let duplicateIndex = items.firstIndex(where: { ShoppingItemNormalizer.nameKey($0.name) == key }) {
            return await mergeQuantity(into: duplicateIndex, addedDetail: detail.trimmed)
        }
        let resolvedCategory = FoodCategories.normalize(category) ?? FoodKnowledge.categoryFor(trimmedName)
        let item = ShoppingItem(
            id: ShoppingItem.newId(),
            name: trimmedName,
            detail: detail.trimmed,
            category: resolvedCategory
        )
        guard await persist(items + [item]) else { return .failed }
        if let patch = DomainJSON.valueMap(item) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: item.id,
                operation: .create,
                patch: patch,
                baseVersion: nil
            )
        }
        return .added
    }

    /// 同名自动聚合: a duplicate-name add merges into the existing row instead
    /// of appending — the repo's name-unique dedup means a second row with the
    /// same name must never reach `saveItems`. Merges ONLY when both details
    /// parse via `QuantityText` AND the unit remainders match (trimmed,
    /// case-insensitive); anything else (blank/free-text detail, unit mismatch)
    /// keeps the historical duplicate rejection (`.duplicate`) so quantities
    /// are never guessed. A persist error is `.failed` — NOT a duplicate.
    private func mergeQuantity(into index: Int, addedDetail: String) async -> AddOutcome {
        guard !addedDetail.isEmpty else { return .duplicate }
        let existing = items[index]
        guard
            let current = QuantityText.parseLeadingQuantity(existing.detail.trimmed),
            let added = QuantityText.parseLeadingQuantity(addedDetail),
            current.remainder.lowercased() == added.remainder.lowercased(),
            let currentValue = Double(current.magnitude),
            let addedValue = Double(added.magnitude)
        else { return .duplicate }

        let summed = QuantityText.formatQuantity(currentValue + addedValue)
        // The existing row's unit spelling wins — we're updating that row.
        // Re-adding means "need to buy again": a checked (已购) row flips back
        // to unchecked, or the merged quantity would hide at the bottom of the
        // 已购 bucket (invisible under the 待购 filter) and later inflate the
        // 入库 amount.
        let merged = existing.copyWith(
            detail: current.remainder.isEmpty ? summed : "\(summed) \(current.remainder)",
            isChecked: false
        )
        var next = items
        next[index] = merged
        guard await persist(next) else { return .failed }
        if let patch = DomainJSON.valueMap(merged) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: merged.id,
                operation: .update,
                patch: patch,
                baseVersion: existing.remoteVersion
            )
        }
        return .added
    }

    /// Rewrites a row's free-text detail (数量/备注) by stable id identity —
    /// blank is allowed (clearing the quantity is a legitimate edit). Persists
    /// and enqueues a full-row `.update` carrying the prior `remoteVersion` for
    /// optimistic-concurrency merge. Returns whether a row was updated.
    @discardableResult
    func updateDetail(_ target: ShoppingItem, detail: String) async -> Bool {
        await serializedMutation { await self.performUpdateDetail(target, detail: detail) }
    }

    private func performUpdateDetail(_ target: ShoppingItem, detail: String) async -> Bool {
        guard await refreshBeforeMutate() else { return false }
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let current = items[index]
        let updated = current.copyWith(detail: detail.trimmed)
        var next = items
        next[index] = updated
        guard await persist(next) else { return false }
        if let patch = DomainJSON.valueMap(updated) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: updated.id,
                operation: .update,
                patch: patch,
                baseVersion: current.remoteVersion
            )
        }
        return true
    }

    /// Compatibility shim over `restoreItem` — true ONLY when the row was
    /// actually re-inserted. Prefer `restoreItem` where the already-present /
    /// failure split reaches user-facing copy (the undo banner).
    @discardableResult
    func restore(_ item: ShoppingItem) async -> Bool {
        await restoreItem(item) == .added
    }

    /// Re-inserts a previously-deleted row (preserving its id), persisting and
    /// enqueuing a full-row `.update` to clear the soft-delete remotely — the undo
    /// path for a swipe-delete. Mirrors the inventory undo (a `.update` un-deletes
    /// the row the prior `.delete` soft-removed). Returns `.added` when the row
    /// was re-inserted, `.duplicate` when the same id is already present (the
    /// undo's goal is met — benign), `.failed` on a read/persist error.
    func restoreItem(_ item: ShoppingItem) async -> AddOutcome {
        await serializedMutation { await self.performRestore(item) }
    }

    private func performRestore(_ item: ShoppingItem) async -> AddOutcome {
        guard await refreshBeforeMutate() else { return .failed }
        // Already present (same id) — nothing to restore.
        guard !items.contains(where: { $0.id == item.id }) else { return .duplicate }
        guard await persist(items + [item]) else { return .failed }
        if let patch = DomainJSON.valueMap(item) {
            await syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: item.id,
                operation: .update,
                patch: patch,
                baseVersion: item.remoteVersion
            )
        }
        return .added
    }

    /// Deletes a row by stable id identity, persists the survivors, and updates
    /// local state. Returns whether a row was removed.
    @discardableResult
    func delete(_ target: ShoppingItem) async -> Bool {
        await serializedMutation { await self.performDelete(target) }
    }

    private func performDelete(_ target: ShoppingItem) async -> Bool {
        guard await refreshBeforeMutate() else { return false }
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

    /// Deletes every row in `targets` (by stable id) in ONE read-modify-write —
    /// the 清空已完成 path. Returns the rows actually removed (fresh copies from
    /// the repo, so a later `restore` undo re-inserts exactly what was lost);
    /// EMPTY when none of the ids are present anymore (benign — another entry
    /// point already took them); NIL when the 写前重读 or persist threw (nothing
    /// was deleted; the caller should surface a retryable failure, not silence).
    func deleteAll(_ targets: [ShoppingItem]) async -> [ShoppingItem]? {
        await serializedMutation { await self.performDeleteAll(targets) }
    }

    private func performDeleteAll(_ targets: [ShoppingItem]) async -> [ShoppingItem]? {
        guard !targets.isEmpty else { return [] }
        guard await refreshBeforeMutate() else { return nil }
        let ids = Set(targets.map(\.id))
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        guard await persist(items.filter { !ids.contains($0.id) }) else { return nil }
        // Same soft-delete propagation as the single `delete` (see note there).
        for item in removed {
            if let patch = DomainJSON.valueMap(item) {
                await syncWriter?.enqueue(
                    entityType: .shoppingItem,
                    entityId: item.id,
                    operation: .delete,
                    patch: patch,
                    baseVersion: item.remoteVersion
                )
            }
        }
        return removed
    }

    /// 写前重读: re-syncs `items` from the repo before a mutation applies its
    /// delta, because `persist` replaces the WHOLE household scope — a stale
    /// snapshot would silently drop rows another store instance wrote since our
    /// last load (Dashboard 加购 / Siri drain / 缺料卡 each build their own
    /// session-scoped store over the same repo). A refresh failure aborts the
    /// mutation (`false`) rather than proceeding on a possibly-stale snapshot.
    private func refreshBeforeMutate() async -> Bool {
        do {
            items = try await repository.loadAllFor(householdID)
            return true
        } catch {
            return false
        }
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
