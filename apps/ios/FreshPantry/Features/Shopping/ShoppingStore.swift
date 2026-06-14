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

    /// User shelf-aisle order for the category sections (device-local; defaults to
    /// canonical). Reloaded from `ShoppingCategoryOrder` on every `load()` so a
    /// change made in settings takes effect when the Shopping tab reappears.
    var categoryOrder: [String] = ShoppingCategoryOrder.canonical

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
        categoryOrder = ShoppingCategoryOrder.load()
        do {
            items = try await repository.loadAllFor(householdID)
        } catch {
            // A load failure simply means "nothing to show"; never crash the tab.
            items = []
        }
    }

    // MARK: Mutations (offline-first / optimistic)
    //
    // OFFLINE-FIRST CONTRACT: every list-tap mutation updates the observable
    // `items` SYNCHRONOUSLY — before the first `await` — so SwiftUI re-renders the
    // check / strikethrough / row-drop THIS tick, not after a SwiftData
    // round-trip. The repo write then lands the SINGLE touched row in the
    // background (no whole-scope rewrite, no 写前重读, no post-save reload), and a
    // persist failure rolls back just that row. Single-row writes can't clobber a
    // peer store instance's concurrent write to a DIFFERENT row — exactly what the
    // old whole-scope `persist` needed the 写前重读 to guard against.

    /// FIFO serialization of the BACKGROUND single-row persists. The optimistic
    /// in-memory edit already ran before this, so the chain no longer gates the
    /// visual change — it only keeps the repo writes ordered (a row toggled then
    /// re-toggled lands in tap order; a delete after a toggle doesn't resurrect
    /// the row). MainActor-only, so reading + relinking `lastMutation` is race-free.
    @ObservationIgnored
    private var lastMutation: Task<Void, Never>?

    private func serializedPersist<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = lastMutation
        let task: Task<T, Never> = Task {
            await previous?.value
            return await body()
        }
        lastMutation = Task { _ = await task.value }
        return await task.value
    }

    /// Reverts row `id` to `prior` in `items` — the surgical rollback for a failed
    /// optimistic UPDATE. Touches only that row, so a later tap that changed a
    /// different row in the meantime survives.
    private func revertRow(_ id: String, to prior: ShoppingItem) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i] = prior }
    }

    /// Flips a row's checked state OPTIMISTICALLY (the check fills + the row
    /// re-sorts the instant the tap lands), then persists the single row in the
    /// background. Returns whether a row was toggled; a persist failure rolls the
    /// flip back, and a row a peer already deleted is dropped locally. Resolves by
    /// stable id identity.
    @discardableResult
    func toggleChecked(_ target: ShoppingItem) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let prior = items[index]
        let toggled = prior.copyWith(isChecked: !prior.isChecked)
        items[index] = toggled // optimistic — SwiftUI re-renders this tick
        return await serializedPersist {
            do {
                guard try await self.repository.updateRow(self.householdID, toggled) else {
                    // A peer deleted the row since our tap — drop it locally
                    // (don't reload: that would clobber other pending taps).
                    self.items.removeAll { $0.id == toggled.id }
                    return false
                }
            } catch {
                self.revertRow(toggled.id, to: prior)
                return false
            }
            await self.syncWriter?.enqueue(
                entityType: .shoppingItem,
                entityId: toggled.id,
                operation: .toggleChecked,
                patch: ["isChecked": .bool(toggled.isChecked)],
                baseVersion: prior.remoteVersion
            )
            return true
        }
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
    /// `FoodKnowledge` when not supplied). Name-unique per a case-insensitive
    /// dedup — but a duplicate name no longer always rejects: when both details
    /// parse to the same unit the quantities merge into the existing row (see
    /// `mergeQuantity`). Returns `.added` for an appended or merged row,
    /// `.duplicate` for a same-name row that couldn't merge, and `.failed` when
    /// nothing was written (blank name, read or persist error).
    func addItem(name: String, detail: String = "", category: String? = nil) async -> AddOutcome {
        await serializedPersist { await self.performAdd(name: name, detail: detail, category: category) }
    }

    private func performAdd(name: String, detail: String, category: String?) async -> AddOutcome {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return .failed }
        // 按名去重必须比对 CANONICAL 列表(可能含别的 store 实例刚写的同名行,
        // id 唯一约束按名拦不住),所以读进 LOCAL 变量——绝不灌回 `items`,否则会冲
        // 掉别的点击尚未落库的乐观态。这是 add 与 toggle/delete 的关键差异。
        let fresh: [ShoppingItem]
        do { fresh = try await repository.loadAllFor(householdID) } catch { return .failed }
        let key = ShoppingItemNormalizer.nameKey(trimmedName)
        if let duplicate = fresh.first(where: { ShoppingItemNormalizer.nameKey($0.name) == key }) {
            return await mergeQuantity(into: duplicate, addedDetail: detail.trimmed)
        }
        let resolvedCategory = FoodCategories.normalize(category) ?? FoodKnowledge.categoryFor(trimmedName)
        let item = ShoppingItem(
            id: ShoppingItem.newId(),
            name: trimmedName,
            detail: detail.trimmed,
            category: resolvedCategory
        )
        do {
            try await repository.upsert(householdID, item)
        } catch {
            return .failed
        }
        // Reflect locally without a whole-scope reload (append if not already shown).
        if !items.contains(where: { $0.id == item.id }) { items.append(item) }
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

    /// 同名自动聚合: a duplicate-name add merges into the existing (freshly-read)
    /// row instead of appending. Merges ONLY when both details parse via
    /// `QuantityText` AND the unit remainders match (trimmed, case-insensitive);
    /// anything else (blank/free-text detail, unit mismatch) keeps the historical
    /// duplicate rejection (`.duplicate`). A persist error is `.failed`.
    private func mergeQuantity(into existing: ShoppingItem, addedDetail: String) async -> AddOutcome {
        guard !addedDetail.isEmpty else { return .duplicate }
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
        do {
            guard try await repository.updateRow(householdID, merged) else { return .failed }
        } catch {
            return .failed
        }
        if let i = items.firstIndex(where: { $0.id == merged.id }) {
            items[i] = merged
        } else {
            items.append(merged)
        }
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

    /// Rewrites a row's free-text detail (数量/备注) OPTIMISTICALLY by stable id
    /// identity — blank is allowed (clearing the quantity is a legitimate edit).
    /// Persists the single row + enqueues a full-row `.update` carrying the prior
    /// `remoteVersion`. Returns whether a row was updated (false rolls back).
    @discardableResult
    func updateDetail(_ target: ShoppingItem, detail: String) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let prior = items[index]
        let updated = prior.copyWith(detail: detail.trimmed)
        items[index] = updated // optimistic
        return await serializedPersist {
            do {
                guard try await self.repository.updateRow(self.householdID, updated) else {
                    self.items.removeAll { $0.id == updated.id }
                    return false
                }
            } catch {
                self.revertRow(updated.id, to: prior)
                return false
            }
            if let patch = DomainJSON.valueMap(updated) {
                await self.syncWriter?.enqueue(
                    entityType: .shoppingItem,
                    entityId: updated.id,
                    operation: .update,
                    patch: patch,
                    baseVersion: prior.remoteVersion
                )
            }
            return true
        }
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
    /// path for a swipe-delete. Returns `.added` when the row was re-inserted,
    /// `.duplicate` when the same id is already present (the undo's goal is met —
    /// benign), `.failed` on a persist error.
    func restoreItem(_ item: ShoppingItem) async -> AddOutcome {
        await serializedPersist { await self.performRestore(item) }
    }

    private func performRestore(_ item: ShoppingItem) async -> AddOutcome {
        // Already present (same id) — nothing to restore.
        guard !items.contains(where: { $0.id == item.id }) else { return .duplicate }
        let snapshot = items
        items.append(item) // optimistic re-insert
        do {
            try await repository.upsert(householdID, item)
        } catch {
            items = snapshot
            return .failed
        }
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

    /// Deletes a row OPTIMISTICALLY by stable id identity (it leaves the list +
    /// the undo banner shows the instant the swipe lands), then soft-deletes the
    /// single row in the background. Returns whether a row was removed; a persist
    /// failure re-inserts it.
    @discardableResult
    func delete(_ target: ShoppingItem) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return false }
        let removed = items[index]
        let snapshot = items
        items.remove(at: index) // optimistic
        return await serializedPersist {
            do {
                try await self.repository.delete(self.householdID, ids: [removed.id])
            } catch {
                self.items = snapshot
                return false
            }
            // Enqueue the soft-delete so it propagates to other members (the gateway
            // routes shoppingItem/.delete to a soft-delete). Without this the row
            // stays on the server and re-appears on the next pull (remote wins).
            if let patch = DomainJSON.valueMap(removed) {
                await self.syncWriter?.enqueue(
                    entityType: .shoppingItem,
                    entityId: removed.id,
                    operation: .delete,
                    patch: patch,
                    baseVersion: removed.remoteVersion
                )
            }
            return true
        }
    }

    /// Deletes every row in `targets` (by stable id) OPTIMISTICALLY — the
    /// 清空已完成 / 一键入库 drop path. Returns the rows actually removed (so a
    /// later `restore` undo re-inserts exactly what was lost); EMPTY when none of
    /// the ids are present anymore (benign — another entry point already took
    /// them); NIL when the persist threw (nothing was deleted; the caller surfaces
    /// a retryable failure, not silence).
    func deleteAll(_ targets: [ShoppingItem]) async -> [ShoppingItem]? {
        guard !targets.isEmpty else { return [] }
        let ids = Set(targets.map(\.id))
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        let snapshot = items
        items.removeAll { ids.contains($0.id) } // optimistic
        return await serializedPersist {
            do {
                try await self.repository.delete(self.householdID, ids: Array(ids))
            } catch {
                self.items = snapshot
                return nil
            }
            // Same soft-delete propagation as the single `delete` (see note there).
            for item in removed {
                if let patch = DomainJSON.valueMap(item) {
                    await self.syncWriter?.enqueue(
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

    /// Index of the item's normalized category in the user's `categoryOrder`
    /// (defaults to canonical); unknown/blank categories sort last.
    private func categoryRank(_ category: String) -> Int {
        ShoppingCategoryOrder.rank(category, order: categoryOrder)
    }
}
