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
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: InventoryStore?
    @State private var shoppingStore: ShoppingStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store, let shoppingStore {
                    InventoryContent(store: store, shoppingStore: shoppingStore)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("库存")
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
            self.store = store
            self.shoppingStore = shopping
            await store.load()
            await shopping.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload the
        // store so the visible list reflects rows pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task {
                await store?.load()
                await shoppingStore?.load()
            }
        }
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

    @State private var selectedIngredient: Ingredient?
    @State private var showClearConfirm = false
    @State private var toast: String?
    /// Multi-select mode (long-press to enter): the selected rows' identity keys.
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var showBatchDeleteConfirm = false
    /// Pending batch-delete undo handle — drives the bottom "已删除 · 撤销" banner.
    @State private var batchUndo: InventoryStore.BatchRemovalUndo?
    @State private var isBatchWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery)
                    .padding(.horizontal, FkSpacing.lg)

                categoryChips
                storageChips

                listBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.load() }
        .toolbar { toolbarContent }
        .sheet(isPresented: $isAddingPresented) {
            AddIngredientView { Task { await store.load() } }
        }
        .navigationTitle(isSelecting ? "已选 \(selectedKeys.count) 项" : "库存")
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
            "清空全部食材",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空 \(store.items.count) 件", role: .destructive) {
                Task { await store.clearAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除全部 \(store.items.count) 件食材，此操作无法撤销。")
        }
        .confirmationDialog(
            "删除所选食材",
            isPresented: $showBatchDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除 \(selectedKeys.count) 件", role: .destructive) {
                Task { await batchDelete() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所选 \(selectedKeys.count) 件食材，可在删除后撤销。")
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
                Button("取消") { exitSelection() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "取消全选" : "全选") { toggleSelectAll() }
                    .disabled(store.displayItems.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加食材")
            }
            ToolbarItem(placement: .topBarLeading) {
                if !store.items.isEmpty {
                    Menu {
                        Button("多选") { isSelecting = true }
                        Button("清空全部食材", role: .destructive) {
                            showClearConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多")
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
                    batchButton(title: "合并", systemImage: "arrow.triangle.merge", tint: .fkPrimary) {
                        Task { await mergeSelected() }
                    }
                }
                batchButton(title: "加购", systemImage: "cart.badge.plus", tint: .fkPrimary) {
                    Task { await batchAddToShopping() }
                }
                batchButton(title: "删除", systemImage: "trash", tint: .fkDanger) {
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
    @ViewBuilder
    private var undoBanner: some View {
        if let undo = batchUndo {
            HStack(spacing: FkSpacing.md) {
                Text("已删除 \(undo.removed.count) 项")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: 0)
                Button("撤销") {
                    Task {
                        await store.undoBatchRemoval(undo)
                        batchUndo = nil
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
            .task(id: undo.removed.count) {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { withAnimation { batchUndo = nil } }
            }
        }
    }

    // MARK: Selection actions

    private func enterSelection(with item: Ingredient) {
        isSelecting = true
        selectedKeys = [item.identityKey]
    }

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

    private func batchDelete() async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        let undo = await store.deleteMany(selectedItems)
        exitSelection()
        if let undo {
            withAnimation { batchUndo = undo }
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
        withAnimation {
            toast = added > 0 ? "已添加 \(added)/\(count) 项到购物清单" : "所选食材已在购物清单中"
        }
    }

    private func mergeSelected() async {
        guard !isBatchWorking else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }
        let count = selectedKeys.count
        let ok = await store.mergeBatch(selectedItems)
        exitSelection()
        withAnimation {
            toast = ok ? "已合并 \(count) 个批次" : "合并失败"
        }
    }

    // MARK: Category / state filter chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                FkChip(label: "全部", count: store.count(for: InventoryStore.CategoryFilter.all), isSelected: store.categoryFilter == .all) {
                    store.categoryFilter = .all
                }
                FkChip(label: "不新鲜", count: store.count(for: .notFresh), isSelected: store.categoryFilter == .notFresh) {
                    store.categoryFilter = .notFresh
                }
                ForEach(FoodCategories.values, id: \.self) { category in
                    FkChip(
                        label: category,
                        count: store.count(for: .category(category)),
                        isSelected: store.categoryFilter == .category(category)
                    ) {
                        store.categoryFilter = .category(category)
                    }
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
                    label: "全部位置",
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
        }
    }

    /// One inventory row. In normal mode it taps through to detail and shows the
    /// 加购 affordance; in multi-select mode a leading checkmark toggles selection
    /// and the whole card toggles (no navigation). A long-press enters selection.
    @ViewBuilder
    private func row(for item: Ingredient) -> some View {
        let selected = selectedKeys.contains(item.identityKey)
        FkCard {
            VStack(spacing: FkSpacing.sm) {
                HStack(spacing: FkSpacing.sm) {
                    if isSelecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selected ? Color.fkPrimary : Color.fkOutline)
                    }
                    IngredientRow(ingredient: item)
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
        .onLongPressGesture {
            if !isSelecting {
                enterSelection(with: item)
            }
        }
    }

    private func buyAgainButton(_ item: Ingredient) -> some View {
        Button {
            Task { await addToShopping(item) }
        } label: {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("加购")
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
                    if !Task.isCancelled { withAnimation { self.toast = nil } }
                }
        }
    }

    private func addToShopping(_ item: Ingredient) async {
        let added = await shoppingStore.add(name: item.name, category: item.category)
        withAnimation {
            toast = added ? "已将「\(item.name)」加入购物清单" : "「\(item.name)」已在购物清单中"
        }
    }

    private var emptyState: some View {
        let searching = !store.searchQuery.trimmed.isEmpty
        return FkEmptyState(
            systemImage: store.hasActiveQuery ? "magnifyingglass" : "tray",
            title: searching ? "没有找到「\(store.searchQuery.trimmed)」"
                : (store.hasActiveQuery ? "该筛选下暂无食材" : "冰箱空空如也"),
            message: store.hasActiveQuery ? "试试换个关键词或筛选条件" : "去添加一些食材吧"
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
