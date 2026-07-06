import SwiftUI

/// The 库存 tab: lists the household's ingredients, urgency-sorted, with a
/// category/state filter row (全部 / 不新鲜 / 5 大类), storage-area filter chips, and
/// a name search. Each row taps through to detail; non-fresh rows carry a quick
/// 加购 (buy-again → shopping list) button. The toolbar adds an item ("+") and can
/// clear the whole pantry (顶栏「清空全部」, confirmed).
///
/// The view builds its `InventoryStore` (+ a `ShoppingStore` for 加购) from the
/// injected `AppDependencies` — the reusable pattern every feature view follows.
/// SwiftData is never touched here; all scoping / sorting / filtering lives in the
/// store.
struct InventoryView: View {
    /// Cross-tab drill-down intent from the 首页 食材分类 grid: a canonical category
    /// to preset on appear. Consumed (set to nil) once applied. `RootView` owns it.
    @Binding var pendingCategory: String?
    /// Spotlight deep-link intent: the ingredient id whose detail to push once
    /// rows are loaded. Consumed (set to nil) once applied. `RootView` owns it.
    @Binding var pendingIngredientID: String?

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: InventoryStore?
    @State private var shoppingStore: ShoppingStore?
    /// The household the current `store` was built for. Lets the build `.task`
    /// distinguish a real scope change (rebuild + fresh filters) from a mere tab
    /// reappear (reload data, KEEP the store + its filters) — see that `.task`.
    @State private var loadedHouseholdID: String?
    /// Detail push target — owned here (vs `InventoryContent`) so the Spotlight
    /// deep link drives the same `navigationDestination` as a row tap.
    @State private var selectedIngredient: Ingredient?
    /// Transient banner copy — owned here (vs `InventoryContent`) so the
    /// Spotlight miss feedback shares the content's toast surface.
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Group {
                if let store, let shoppingStore {
                    InventoryContent(
                        store: store,
                        shoppingStore: shoppingStore,
                        selectedIngredient: $selectedIngredient,
                        toast: $toast
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle(String(localized: "inventory.title"))
        }
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the visible list re-scopes to the new household
        // rather than keeping the prior scope's stale rows.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's rows come from sync, never the seeder.
            if householdID.isEmpty {
                await InventorySeeder.seedIfNeeded(
                    repository: dependencies.inventoryRepository,
                    householdID: householdID
                )
            }
            #endif
            // This `.task` re-runs on every tab REAPPEAR (sidebarAdaptable
            // lifecycle), not only on a household change. Rebuilding the store each
            // time reset the category filter to 全部 and RACED the 首页 分类下钻
            // intent (the filter landed on a store that was about to be replaced →
            // 「点分类偶尔不选中」). So build the store ONCE per household and merely
            // RELOAD its data on a same-scope reappear: the filter persists, and
            // changes made via other tabs (e.g. 购物入库, which doesn't bump
            // dataRevision) still surface. A real scope change rebuilds fresh.
            if store == nil || loadedHouseholdID != householdID {
                let store = InventoryStore(
                    repository: dependencies.inventoryRepository,
                    foodLogRepository: dependencies.foodLogRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                let shopping = ShoppingStore(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                // OFFLINE-FIRST, NO FLASH: load the new scope's local rows BEFORE
                // swapping the stores in. Assigning an empty store first rendered an
                // empty list for the duration of `load()` — a household switch (incl.
                // every cold-launch "" → uuid auto-select) flashed empty before the
                // local data appeared. Loading first keeps the previous household's
                // list on screen until the new (local, instant) data is ready, then
                // swaps atomically. Guard so a newer switch landing during the load
                // doesn't assign this stale scope's stores over the successor's.
                await store.load()
                await shopping.load()
                guard householdID == dependencies.householdID, !Task.isCancelled else { return }
                self.store = store
                self.shoppingStore = shopping
                self.loadedHouseholdID = householdID
            } else {
                await store?.load()
                await shoppingStore?.load()
            }
            // Cold path: intents that arrived before this tab built/loaded.
            consumePendingCategory()
            consumePendingIngredient()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload the
        // store so the visible list reflects rows pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task {
                await store?.load()
                await shoppingStore?.load()
            }
        }
        // Cross-tab intents (首页 分类网格下钻 / Spotlight 深链). `.task(id:)` — not
        // `.onChange` — so an intent set in the SAME state transaction that switches
        // to this tab is still applied: the sidebar-adaptable TabView (re)creates the
        // tab's view on selection, and `.onChange` never fires for the value already
        // present when the view appears — only for LATER changes — so the warm path
        // missed intermittently. `.task(id:)` runs for the current value on appearance
        // AND on every change. No-op until the store exists; the `.task(id: householdID)`
        // above tail-applies the cold-start case once the first load finishes.
        .task(id: pendingCategory) { consumePendingCategory() }
        .task(id: pendingIngredientID) { consumePendingIngredient() }
    }

    /// Applies a pending 首页 category drill-down to the live store (preset the
    /// category filter, reset the storage filter), then clears the intent so a
    /// later household reload doesn't re-apply it. No-op until the store exists.
    private func consumePendingCategory() {
        guard let category = pendingCategory, let store else { return }
        store.categoryFilter = .category(category)
        store.storageFilter = .all
        pendingCategory = nil
    }

    /// Applies a pending Spotlight deep link: pushes the matching row's detail.
    /// Waits for the initial load (`hasLoaded`) so a cold-start intent resolves
    /// against real rows; the intent is consumed even when the row no longer
    /// exists (deleted on another device) so a stale id can't re-fire later.
    /// A miss toasts instead of landing silently — the index can lag a local
    /// delete until the next rebuild, and "nothing happened" reads as a broken
    /// route rather than gone data.
    private func consumePendingIngredient() {
        guard let id = pendingIngredientID, let store, store.hasLoaded else { return }
        pendingIngredientID = nil
        guard let match = store.items.first(where: { $0.id == id }) else {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                toast = String(localized: "inventory.spotlight.notFound")
            }
            return
        }
        selectedIngredient = match
    }

    /// Honors a `-initialRoute add` launch argument (UI snapshots / tests).
    static var opensAddOnLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return false
        }
        return args[index + 1] == "add"
    }
}

/// Inner content bound to a live store (split out so `@Bindable` can drive the
/// search field / filter chips once the store exists).
private struct InventoryContent: View {
    @Bindable var store: InventoryStore
    let shoppingStore: ShoppingStore
    /// Owned by `InventoryView` so the Spotlight deep link can push the same
    /// detail destination a row tap does.
    @Binding var selectedIngredient: Ingredient?
    /// Owned by `InventoryView` so the Spotlight miss feedback shares this
    /// content's toast surface (the only banner host on the tab).
    @Binding var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppDependencies.self) private var dependencies
    /// Shared per-row sync-status set (injected at the tab root). Optional so a
    /// standalone preview / snapshot render — which doesn't inject it — is safe
    /// (nil → no badges, never a trap).
    @Environment(PendingSyncStatusStore.self) private var pendingSync: PendingSyncStatusStore?

    @State private var showClearConfirm = false
    /// Multi-select mode (long-press to enter): the selected rows' identity keys.
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var showBatchDeleteConfirm = false
    /// Pending batch-delete undo handle — drives the bottom "已删除 · 撤销" banner.
    @State private var batchUndo: InventoryStore.BatchRemovalUndo?
    @State private var isBatchWorking = false
    /// Long-press 预览菜单 targets: the row to edit (drives the edit sheet, wrapped
    /// so `.sheet(item:)` has an Identifiable without making the domain `Ingredient`
    /// one — its id is blank for local rows) and the row to delete (drives the
    /// single-item 去向追问 dialog). Both nil = no menu action pending.
    @State private var editTarget: EditTarget?
    @State private var deletingItem: Ingredient?

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery)
                    .padding(.horizontal, FkSpacing.lg)

                categoryChips
                storageChips
                tagChips

                listBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.load() }
        // Keep the 「待同步」 badges fresh: any items change — a reload or an
        // in-place mutation (delete / edit / merge), each of which reassigns
        // `items` — re-reads the pending outbox set so a just-queued row's badge
        // appears (and a synced one's clears) without waiting for a sync pulse.
        .onChange(of: store.items) {
            Task { await pendingSync?.refresh() }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $isAddingPresented) {
            AddIngredientView { Task { await store.load() } }
        }
        // Long-press 预览菜单「编辑」: the same edit form the detail screen presents.
        // `EditIngredientView` updates the store in place; reload tail-syncs anyway.
        .sheet(item: $editTarget) { target in
            EditIngredientView(original: target.ingredient, store: store) {
                Task { await store.load() }
            }
        }
        .navigationTitle(isSelecting ? String(localized: "inventory.selection.count \(selectedKeys.count)") : String(localized: "inventory.title"))
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
        .navigationDestination(item: $selectedIngredient) { ingredient in
            IngredientDetailView(ingredient: ingredient, store: store)
        }
        .safeAreaInset(edge: .bottom) { batchActionBar }
        // Snapshot affordance: `-initialRoute add` opens the add sheet so the form
        // can be screenshotted directly (mirrors `-initialTab`).
        .task {
            if InventoryView.opensAddOnLaunch { isAddingPresented = true }
        }
        .overlay(alignment: .top) { toastBanner }
        .overlay(alignment: .bottom) { undoBanner }
        .confirmationDialog(
            String(localized: "inventory.clearAll.title"),
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "inventory.clearAll.confirm \(store.items.count)"), role: .destructive) {
                Task {
                    let ok = await store.clearAll()
                    if !ok {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                            toast = String(localized: "inventory.clearAll.failed")
                        }
                    }
                }
            }
            Button(String(localized: "inventory.action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "inventory.clearAll.message \(store.items.count)"))
        }
        // 去向追问 (aligned with the single-delete sheet): one choice applied to
        // every selected row, so the batch path feeds the waste stats too.
        .confirmationDialog(
            String(localized: "inventory.batchDelete.title \(selectedKeys.count)"),
            isPresented: $showBatchDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "inventory.batchRemoveOutcome.consumed")) { Task { await batchDelete(outcome: .consumed) } }
            Button(String(localized: "inventory.batchRemoveOutcome.donated")) { Task { await batchDelete(outcome: .donated) } }
            Button(String(localized: "inventory.batchRemoveOutcome.composted")) { Task { await batchDelete(outcome: .composted) } }
            Button(String(localized: "inventory.batchRemoveOutcome.wasted")) { Task { await batchDelete(outcome: .wasted) } }
            Button(String(localized: "inventory.removeOutcome.removeOnly")) { Task { await batchDelete(outcome: nil) } }
            Button(String(localized: "inventory.action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "inventory.batchRemoveOutcome.message"))
        }
        // 去向追问 for the long-press 预览菜单「删除」: a single-row mirror of the
        // detail-screen delete, routed through `deleteMany` so it reuses the shared
        // 撤销 banner and feeds the waste stats.
        .confirmationDialog(
            deletingItem.map { String(localized: "inventory.removeOutcome.title \($0.name)") } ?? String(localized: "inventory.removeOutcome.genericTitle"),
            isPresented: Binding(
                get: { deletingItem != nil },
                set: { if !$0 { deletingItem = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingItem
        ) { item in
            Button(String(localized: "inventory.removeOutcome.consumed")) { Task { await deleteSingle(item, outcome: .consumed) } }
            Button(String(localized: "inventory.removeOutcome.donated")) { Task { await deleteSingle(item, outcome: .donated) } }
            Button(String(localized: "inventory.removeOutcome.composted")) { Task { await deleteSingle(item, outcome: .composted) } }
            Button(String(localized: "inventory.removeOutcome.wasted")) { Task { await deleteSingle(item, outcome: .wasted) } }
            Button(String(localized: "inventory.removeOutcome.removeOnly")) { Task { await deleteSingle(item, outcome: nil) } }
            Button(String(localized: "inventory.action.cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(localized: "inventory.batchRemoveOutcome.message"))
        }
    }

    /// The toolbar "+" presentation lives here (not the outer view) so it shares
    /// the same store instance the content already renders.
    @State private var isAddingPresented = false

    // MARK: Toolbar (normal vs multi-select)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "inventory.action.cancel")) { exitSelection() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? String(localized: "inventory.intakeReview.deselectAll") : String(localized: "inventory.intakeReview.selectAll")) { toggleSelectAll() }
                    .disabled(store.displayItems.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "inventory.addIngredient.title"))
            }
            ToolbarItem(placement: .topBarLeading) {
                if !store.items.isEmpty {
                    Menu {
                        Button(String(localized: "inventory.action.multiSelect")) { isSelecting = true }
                        Button(String(localized: "inventory.clearAll.menuTitle"), role: .destructive) {
                            showClearConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "inventory.action.more"))
                }
            }
        }
    }

    // MARK: Multi-select action bar + undo

    /// The selected rows resolved from their identity keys (live store order).
    private var selectedItems: [Ingredient] {
        store.items.filter { selectedKeys.contains($0.identityKey) }
    }

    private var allSelected: Bool {
        let visible = store.displayItems
        return !visible.isEmpty && visible.allSatisfy { selectedKeys.contains($0.identityKey) }
    }

    /// Bottom action bar shown in multi-select: 合并 (when the selection is one
    /// mergeable batch) · 加购 · 删除. Empty when not selecting.
    @ViewBuilder
    private var batchActionBar: some View {
        if isSelecting {
            HStack(spacing: FkSpacing.sm) {
                if InventoryStore.canMerge(selectedItems) {
                    batchButton(title: String(localized: "inventory.action.merge"), systemImage: "arrow.triangle.merge", tint: .fkPrimary) {
                        Task { await mergeSelected() }
                    }
                }
                batchButton(title: String(localized: "inventory.action.addToShoppingShort"), systemImage: "cart.badge.plus", tint: .fkPrimary) {
                    Task { await batchAddToShopping() }
                }
                batchButton(title: String(localized: "inventory.action.delete"), systemImage: "trash", tint: .fkDanger) {
                    showBatchDeleteConfirm = true
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, FkSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .disabled(selectedKeys.isEmpty || isBatchWorking)
            .opacity(selectedKeys.isEmpty ? 0.5 : 1)
        }
    }

    private func batchButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.fkLabelSmall)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.fkPressable)
    }

    /// Bottom "已删除 N 项 · 撤销" banner after a batch delete (5s auto-dismiss).
    /// "已记录" when a去向 was chosen (departures were logged), so the feedback
    /// confirms the waste-stats write — mirrors the single-delete banner copy.
    @ViewBuilder
    private var undoBanner: some View {
        if let undo = batchUndo {
            let logged = undo.removed.contains { !$0.loggedEntryId.isEmpty }
            // Single-row delete (long-press「删除」or a 1-item selection) reads better
            // as the named subject the detail screen uses ("已记录「番茄」"); only fall
            // back to the "N 项" count for a true multi-row batch.
            let count = undo.removed.count
            let bannerTitle: String = {
                if count == 1, let name = undo.removed.first?.ingredient.displayName {
                    return logged
                        ? String(localized: "inventory.removeOutcome.recorded \(name)")
                        : String(localized: "inventory.batchDelete.deletedOne \(name)")
                }
                return logged
                    ? String(localized: "inventory.batchDelete.recordedAndDeleted \(count)")
                    : String(localized: "inventory.batchDelete.deleted \(count)")
            }()
            HStack(spacing: FkSpacing.md) {
                Text(bannerTitle)
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: 0)
                Button(String(localized: "dashboard.expiring.undo")) {
                    Task {
                        if await store.undoBatchRemoval(undo) {
                            batchUndo = nil
                        } else {
                            // The restore didn't persist (rows NOT back, the
                            // departures NOT reversed): keep the handle so 撤销
                            // stays retryable, and say so instead of silently
                            // dropping the banner.
                            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = String(localized: "inventory.undo.failed") }
                        }
                    }
                }
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkPrimary)
            }
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, FkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerLowest)
            )
            .fkCardShadow()
            .padding(.horizontal, FkSpacing.lg)
            .padding(.bottom, FkSpacing.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { batchUndo = nil }
                }
            }
        }
    }

    // MARK: Selection actions

    private func exitSelection() {
        isSelecting = false
        selectedKeys = []
    }

    private func toggleSelection(_ item: Ingredient) {
        let key = item.identityKey
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedKeys = []
        } else {
            selectedKeys = Set(store.displayItems.map(\.identityKey))
        }
    }

    /// Batch delete with the chosen去向: an outcome logs one departure per row
    /// (the waste-stats input); nil is the plain 仅移除 (no log). The undo banner
    /// reverses both sides either way. A nil handle for a non-empty selection
    /// means the persist threw (rows untouched, nothing logged) — keep the
    /// multi-select state for a one-tap retry and surface the failure, because
    /// a silent exit reads as a successful delete.
    private func batchDelete(outcome: FoodLogOutcome?) async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        let targets = selectedItems
        let undo = await store.deleteMany(targets, outcome: outcome)
        if let undo {
            exitSelection()
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { batchUndo = undo }
        } else if targets.isEmpty {
            // Stale selection resolved to no live rows — nothing to delete.
            exitSelection()
        } else {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = String(localized: "inventory.delete.failed") }
        }
    }

    /// Single-row delete from the long-press 预览菜单, routed through the batch
    /// `deleteMany` path so it reuses the shared 撤销 banner and logs the chosen
    /// 去向 for the waste stats — exactly like the detail-screen delete, minus the
    /// navigation pop (we never left the list).
    private func deleteSingle(_ item: Ingredient, outcome: FoodLogOutcome?) async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        if let undo = await store.deleteMany([item], outcome: outcome) {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { batchUndo = undo }
        } else if store.items.contains(where: { $0.identityKey == item.identityKey }) {
            // The row is still here yet `deleteMany` returned nil → the persist
            // threw. A nil for an already-gone row (removed via sync / another
            // action) is NOT a failure, so only that case toasts (mirrors
            // `batchDelete`'s stale-vs-failed split).
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = String(localized: "inventory.delete.failed") }
        }
    }

    private func batchAddToShopping() async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        var added = 0
        for item in selectedItems {
            if await shoppingStore.add(name: item.name, category: item.category) { added += 1 }
        }
        let count = selectedKeys.count
        exitSelection()
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = added > 0
                ? String(localized: "inventory.batchShopping.added \(added) \(count)")
                : String(localized: "inventory.batchShopping.allDuplicate")
        }
    }

    private func mergeSelected() async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        let count = selectedKeys.count
        let ok = await store.mergeBatch(selectedItems)
        exitSelection()
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = ok ? String(localized: "inventory.merge.success \(count)") : String(localized: "inventory.merge.failed")
        }
    }

    // MARK: Category / state filter chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                FkChip(label: String(localized: "inventory.filter.all"), count: store.count(for: InventoryStore.CategoryFilter.all), isSelected: store.categoryFilter == .all) {
                    store.categoryFilter = .all
                }
                FkChip(label: String(localized: "inventory.filter.notFresh"), count: store.count(for: .notFresh), isSelected: store.categoryFilter == .notFresh) {
                    store.categoryFilter = .notFresh
                }
                ForEach(FoodCategories.values, id: \.self) { category in
                    FkChip(
                        label: FoodCategories.displayLabel(for: category),
                        count: store.count(for: .category(category)),
                        isSelected: store.categoryFilter == .category(category)
                    ) {
                        store.categoryFilter = .category(category)
                    }
                    .accessibilityIdentifier("inventory.categoryChip.\(category)")
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    // MARK: Storage filter chips

    private var storageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                FkChip(
                    label: String(localized: "inventory.filter.allLocations"),
                    count: store.count(for: InventoryStore.StorageFilter.all),
                    isSelected: store.storageFilter == .all
                ) { store.storageFilter = .all }

                ForEach(IconType.allCases, id: \.self) { area in
                    FkChip(
                        label: area.storageAreaLabel,
                        count: store.count(for: .area(area)),
                        isSelected: store.storageFilter == .area(area)
                    ) { store.storageFilter = .area(area) }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    // MARK: Tag filter chips

    /// 标签筛选行 — dynamic from the inventory's in-use tags (frequency-then-name
    /// ordered). The whole row is hidden when no row carries a tag, so there's no
    /// dead "全部标签" control on a tag-free pantry.
    @ViewBuilder
    private var tagChips: some View {
        // Keep the active selection visible even if it dropped out of the in-use
        // set (e.g. its last row was deleted), so the user can always clear it.
        let options = chipTags
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FkSpacing.sm) {
                    FkChip(label: String(localized: "inventory.filter.allTags"), isSelected: store.selectedTag == nil) {
                        store.selectedTag = nil
                    }
                    ForEach(options, id: \.self) { tag in
                        FkChip(label: tag, isSelected: store.selectedTag == tag) {
                            // Tap the active tag again to clear it (back to 全部标签).
                            store.selectedTag = store.selectedTag == tag ? nil : tag
                        }
                    }
                }
                .padding(.horizontal, FkSpacing.lg)
            }
        }
    }

    /// In-use tags, with the active selection appended when it's no longer in the
    /// derived set (so a stale filter still has a clearable chip).
    private var chipTags: [String] {
        var options = store.tagOptions
        if let selected = store.selectedTag, !options.contains(selected) {
            options.append(selected)
        }
        return options
    }

    // MARK: List / empty / loading

    @ViewBuilder
    private var listBody: some View {
        let items = store.displayItems
        if store.isLoading && !store.hasLoaded {
            ProgressView()
                .padding(.top, 80)
        } else if items.isEmpty {
            emptyState
                .padding(.top, FkSpacing.huge)
        } else {
            LazyVStack(spacing: FkSpacing.sm) {
                ForEach(Array(items.enumerated()), id: \.element.identityKey) { index, item in
                    row(for: item)
                        .fkEntrance(index: index)
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .fkEntranceWindow()
        }
    }

    /// One inventory row. In normal mode it taps through to detail and shows the
    /// 加购 affordance; in multi-select mode a leading checkmark toggles selection
    /// and the whole card toggles (no navigation). A long-press peeks a preview card
    /// with a quick-action menu (查看详情 / 编辑 / 加购 / 删除) — multi-select is
    /// reached from the 顶栏 ⋯「多选」 instead. The preview is suppressed while
    /// selecting (a long-press there would offer single-row actions mid-batch).
    @ViewBuilder
    private func row(for item: Ingredient) -> some View {
        let selected = selectedKeys.contains(item.identityKey)
        let card = FkCard {
            VStack(spacing: FkSpacing.sm) {
                HStack(spacing: FkSpacing.sm) {
                    if isSelecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selected ? Color.fkPrimary : Color.fkOutline)
                    }
                    IngredientRow(ingredient: item)
                    if showsPendingBadge(for: item) {
                        PendingSyncBadge()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(item)
                    } else {
                        selectedIngredient = item
                    }
                }
                // 非新鲜食材就地补货 — hidden in selection mode to avoid mis-taps.
                if !isSelecting, item.state != .fresh {
                    buyAgainButton(item)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .strokeBorder(selected ? Color.fkPrimary : Color.clear, lineWidth: 2)
        )

        if isSelecting {
            card
        } else {
            card.contextMenu {
                Button { selectedIngredient = item } label: {
                    Label(String(localized: "inventory.action.viewDetail"), systemImage: "info.circle")
                }
                Button { editTarget = EditTarget(ingredient: item) } label: {
                    Label(String(localized: "inventory.action.edit"), systemImage: "pencil")
                }
                Button { Task { await addToShopping(item) } } label: {
                    Label(String(localized: "dashboard.expiring.addToShopping"), systemImage: "cart.badge.plus")
                }
                Button(role: .destructive) { deletingItem = item } label: {
                    Label(String(localized: "inventory.action.delete"), systemImage: "trash")
                }
            } preview: {
                IngredientPreviewCard(ingredient: item)
            }
        }
    }

    /// Whether `item` carries a 「待同步」 badge: only in 家庭模式 (a real household
    /// is selected — local-only writes never enqueue, so a badge there would be
    /// noise) AND when the row's id has a queued outbox op. A freshly-created
    /// local row (blank id) never matches.
    private func showsPendingBadge(for item: Ingredient) -> Bool {
        guard !dependencies.householdID.isEmpty, let pendingSync else { return false }
        return pendingSync.isPending(item.id)
    }

    private func buyAgainButton(_ item: Ingredient) -> some View {
        Button {
            Task { await addToShopping(item) }
        } label: {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "inventory.action.addToShoppingShort"))
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(Color.fkPrimaryContainer)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkPrimarySoft)
            )
        }
        .buttonStyle(.fkPressable)
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkOnSurface)
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, FkSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                        .fill(Color.fkSurfaceContainerLowest)
                )
                .fkCardShadow()
                .padding(.top, FkSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { self.toast = nil }
                    }
                }
        }
    }

    private func addToShopping(_ item: Ingredient) async {
        let added = await shoppingStore.add(name: item.name, category: item.category)
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = added
                ? String(localized: "dashboard.shopping.added \(item.displayName)")
                : String(localized: "dashboard.shopping.duplicate \(item.displayName)")
        }
    }

    private var emptyState: some View {
        let searching = !store.searchQuery.trimmed.isEmpty
        return FkEmptyState(
            systemImage: store.hasActiveQuery ? "magnifyingglass" : "tray",
            title: searching ? String(localized: "inventory.empty.notFound \(store.searchQuery.trimmed)")
                : (store.hasActiveQuery ? String(localized: "inventory.empty.noMatchForFilter") : String(localized: "inventory.empty.title")),
            message: store.hasActiveQuery ? String(localized: "inventory.empty.tryDifferentFilter") : String(localized: "inventory.empty.addSome")
        )
    }
}

/// Identifiable wrapper so the long-press「编辑」can drive `.sheet(item:)` without
/// making the domain `Ingredient` Identifiable (its `id` is blank for local rows,
/// which would make an Identifiable conformance collide across unsaved rows). The
/// id is the row's stable `identityKey` (mirrors `ShoppingDetailEditRoute`), so the
/// sheet identity survives a store reload mid-edit rather than churning on a UUID.
private struct EditTarget: Identifiable {
    var id: String { ingredient.identityKey }
    let ingredient: Ingredient
}

/// The peek shown above the long-press 上下文菜单 (contextMenu `preview:`): a compact
/// card of the row's essentials — avatar, name, 数量·位置, 新鲜度 + 到期. Read-only
/// and built from the `Ingredient` already in hand, so it adds no fetch.
private struct IngredientPreviewCard: View {
    let ingredient: Ingredient

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(
                imageUrl: ingredient.imageUrl,
                category: ingredient.category,
                size: 56,
                cornerRadius: FkRadius.lg,
                iconScale: 0.5
            )
            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text(ingredient.displayName)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Text("\(ingredient.quantity)\(UnitLabels.displayLabel(for: ingredient.unit)) · \(ingredient.storage.storageAreaLabel)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                HStack(spacing: FkSpacing.sm) {
                    UrgencyBadge(state: ingredient.state)
                    if let label = ingredient.expiryLabel {
                        Text(label)
                            .font(.fkLabelSmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.lg)
        // maxWidth (not a hard width) so the peek shrinks to fit narrow devices
        // rather than clipping; rounded fill so the card's corners match the
        // system preview platter instead of showing square edges.
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(Color.fkSurfaceContainerLowest)
        )
    }
}

extension Ingredient {
    /// Stable list identity: id when persisted, else a name+storage composite for
    /// local-only rows (keeps `ForEach` keys distinct without reorder churn).
    fileprivate var identityKey: String {
        id.isEmpty ? "\(name)\u{0}\(storage.rawValue)\u{0}\(quantity)\u{0}\(unit)" : id
    }
}
