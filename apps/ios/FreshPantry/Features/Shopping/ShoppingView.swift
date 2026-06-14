import SwiftUI

/// The 购物 tab: a purchase-progress card, 全部/待购买/已购 filter chips, then the
/// household's shopping items grouped by canonical food category — with check-off
/// (struck + dimmed, sorted to the bottom), a leading "加入库存" swipe (single-item
/// intake review), a trailing swipe-delete with undo, a "清空已完成" CTA, and a
/// bottom "一键入库" CTA that routes the checked rows through the shared intake
/// review (then removes only the rows that actually entered inventory).
///
/// The view builds its `ShoppingStore` from the injected `AppDependencies` —
/// the reusable pattern every feature view follows. SwiftData is never touched
/// here; all scoping / sorting / persistence lives in the store.
struct ShoppingView: View {
    /// Cross-tab intent: scroll to and briefly highlight this item. `RootView` owns it.
    @Binding var pendingItemID: String?

    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ShoppingStore?
    /// The household the current `store` was built for — lets the build `.task`
    /// tell a real scope change (rebuild) from a tab reappear (reload, keep store).
    @State private var loadedHouseholdID: String?

    init(pendingItemID: Binding<String?> = .constant(nil)) {
        _pendingItemID = pendingItemID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    ShoppingContent(store: store, pendingItemID: $pendingItemID)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("购物清单")
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
                await ShoppingSeeder.seedIfNeeded(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID
                )
            }
            #endif
            // This `.task` re-runs on every tab REAPPEAR (sidebarAdaptable
            // lifecycle), not only on a household change. Build the store ONCE per
            // household and merely RELOAD on a same-scope reappear so the filter
            // persists across tab switches (and the search→highlight cross-tab
            // intent isn't raced by a store rebuild); a real scope change rebuilds.
            if store == nil || loadedHouseholdID != householdID {
                let store = ShoppingStore(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                // OFFLINE-FIRST, NO FLASH: load the new scope's local rows BEFORE
                // swapping the store in — assigning an empty store first flashed an
                // empty list between the swap and `load()` on every household switch
                // (incl. the cold-launch "" → uuid auto-select). Loading first keeps
                // the previous list on screen until the new (local, instant) data is
                // ready. Guard so a newer switch during the load doesn't assign this
                // stale scope's store over the successor's.
                await store.load()
                guard householdID == dependencies.householdID, !Task.isCancelled else { return }
                self.store = store
                self.loadedHouseholdID = householdID
            } else {
                await store?.load()
            }
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the list reflects rows pulled from other household members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
        // Siri drain pulse: `IntentAddDrainer` writes through its OWN store
        // instance, so this list would otherwise keep its pre-drain snapshot
        // (Siri 报成功、打开却看不到) until a manual pull-to-refresh.
        .onReceive(NotificationCenter.default.publisher(for: .intentDidDrainShoppingAdd)) { _ in
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store (split out so the bindable store can drive
/// the filter chips, and the add sheet / mutations get a concrete store).
private struct ShoppingContent: View {
    @Bindable var store: ShoppingStore
    @Binding var pendingItemID: String?
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shared per-row sync-status set (injected at the tab root). Optional so a
    /// standalone preview / snapshot render — which doesn't inject it — is safe.
    @Environment(PendingSyncStatusStore.self) private var pendingSync: PendingSyncStatusStore?

    @State private var isAddingItem = false
    @State private var isEditingOrder = false
    /// Drives the intake-review push; `reviewSource` is the rows sent so the
    /// applied ones can be removed from the list on return.
    @State private var reviewRoute: ReviewRoute?
    @State private var reviewSource: [ShoppingItem] = []
    /// The just-deleted rows (single swipe-delete OR the 清空已完成 batch),
    /// surfaced in a transient undo banner.
    @State private var pendingUndo: PendingUndo?
    @State private var showClearConfirm = false
    /// Transient top toast (入库结果 / 库存读取失败), the Dashboard pattern.
    @State private var toast: String?
    /// Row whose 数量 detail is being edited (sheet route — `ShoppingItem`
    /// itself isn't Identifiable, mirroring the `ReviewRoute` pattern).
    @State private var editRoute: ShoppingDetailEditRoute?
    @State private var highlightedItemID: String?

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .background(Color.fkSurface)
        // Keep the 「待同步」 badges fresh: any items change — a reload or a check-
        // off / edit / delete, each of which reassigns `items` — re-reads the
        // pending outbox set so a just-queued row's badge appears (and a synced
        // one's clears) without waiting for a sync pulse.
        .onChange(of: store.items) {
            Task { await pendingSync?.refresh() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditingOrder = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("分类排序")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加食材")
            }
        }
        .sheet(isPresented: $isAddingItem) {
            ShoppingAddSheet(store: store)
        }
        .sheet(isPresented: $isEditingOrder) {
            ShoppingCategoryOrderView { Task { await store.load() } }
        }
        .sheet(item: $editRoute) { route in
            ShoppingDetailEditSheet(store: store, item: route.item)
        }
        .navigationDestination(item: $reviewRoute) { route in
            IntakeReviewView(proposals: route.proposals, title: "已购买项入库") { outcome in
                let applied = ShoppingIntake.appliedSourceItems(reviewSource, appliedIds: outcome.appliedIds)
                Task {
                    _ = await store.deleteAll(applied)
                    // 已入库的行不给撤销——恢复它们会和刚进库存的批次重复。
                    if !outcome.appliedIds.isEmpty {
                        toast = "已入库 \(outcome.appliedIds.count) 项"
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { intakeCTA }
        .overlay(alignment: .bottom) { undoBanner }
        .overlay(alignment: .top) { toastBanner }
        .confirmationDialog(
            "清理已购项目",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清理", role: .destructive) { Task { await clearChecked() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要移除所有已勾选的购物项吗？")
        }
        // Cross-tab intent (全局搜索 → 高亮购物行). `.task(id:)` runs for the current
        // value on appearance AND on change, so an intent set in the same transaction
        // that switches to this tab still applies — replacing the `.onChange` +
        // `.onAppear` pair that missed it intermittently (see InventoryView for why).
        .task(id: pendingItemID) { consumePendingItem() }
    }

    private func consumePendingItem() {
        guard let id = pendingItemID, store.hasLoaded else { return }
        pendingItemID = nil
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        store.filter = .all
        store.ensureExpanded(item.category)
        highlightedItemID = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if highlightedItemID == id { highlightedItemID = nil }
        }
    }

    // MARK: List

    private var itemList: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                ShoppingProgressCard(done: store.checkedCount, total: store.total, progress: store.progress)
                    // leading/trailing 0: the section's `.listSectionMargins` already
                    // insets the row to FkSpacing.lg (16pt), so the blue card's edges land
                    // exactly where the 首页 hero's do. Adding FkSpacing.lg here again
                    // double-inset it (insetGrouped's ~20pt default section margin + 16 =
                    // ~36pt), making it visibly narrower than the home hero.
                    .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: 0, bottom: FkSpacing.xs, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ShoppingFilterChips(store: store)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: FkSpacing.sm, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionMargins(.horizontal, FkSpacing.lg)

            if store.displaySections.isEmpty {
                Section {
                    Text(store.filter == .todo ? "没有待购项目" : "没有已购项目")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, FkSpacing.xl)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionMargins(.horizontal, FkSpacing.lg)
            } else {
                ForEach(store.displaySections, id: \.category) { section in
                    Section {
                        if !store.isCollapsed(section.category) {
                            ForEach(section.items, id: \.id) { item in
                                ShoppingRow(item: item, showsPendingBadge: showsPendingBadge(for: item)) {
                                    Task { await store.toggleChecked(item) }
                                }
                                .id(item.id)
                                .listRowBackground(
                                    item.id == highlightedItemID
                                        ? Color.fkPrimarySoft
                                        : Color.fkSurfaceContainerLowest
                                )
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        openIntake(for: [item])
                                    } label: {
                                        Label("加入库存", systemImage: "tray.and.arrow.down")
                                    }
                                    .tint(Color.fkPrimary)
                                }
                                .swipeActions(edge: .trailing) {
                                    // Delete stays FIRST so full-swipe keeps deleting.
                                    Button(role: .destructive) {
                                        Task { await deleteWithUndo(item) }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        editRoute = ShoppingDetailEditRoute(item: item)
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    .tint(Color.fkPrimaryDeep)
                                }
                                .contextMenu {
                                    Button {
                                        editRoute = ShoppingDetailEditRoute(item: item)
                                    } label: {
                                        Label("编辑数量", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    } header: {
                        CategoryHeader(
                            category: section.category,
                            count: section.items.count,
                            collapsed: store.isCollapsed(section.category)
                        ) {
                            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { store.toggleCollapsed(section.category) }
                        }
                    }
                    .listSectionMargins(.horizontal, FkSpacing.lg)
                }
            }

            if store.checkedCount > 0 {
                Section {
                    clearDoneButton
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionMargins(.horizontal, FkSpacing.lg)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .refreshable { await store.load() }
        .onChange(of: highlightedItemID) { _, id in
            guard let id else { return }
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
    }

    // MARK: Bottom intake CTA

    @ViewBuilder
    private var intakeCTA: some View {
        if store.checkedCount > 0 {
            Button {
                openIntake(for: store.items.filter(\.isChecked))
            } label: {
                Text("已购买的 \(store.checkedCount) 项一键入库")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.fkPrimary))
            }
            .buttonStyle(.fkPressable)
            .padding(.horizontal, FkSpacing.lg)
            .padding(.bottom, FkSpacing.sm)
        }
    }

    // MARK: Undo banner

    @ViewBuilder
    private var undoBanner: some View {
        if let undo = pendingUndo {
            HStack(spacing: FkSpacing.md) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.fkDanger)
                Text(undo.items.count == 1
                    ? "「\(undo.items[0].name)」已删除"
                    : "已清理 \(undo.items.count) 项")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: FkSpacing.sm)
                Button("撤销") {
                    Task {
                        // Count REAL failures only — `.duplicate` (the row is
                        // already back, e.g. a remote merge re-added it) means
                        // the undo's goal is met, not that it broke.
                        var failures = 0
                        for item in undo.items {
                            if await store.restoreItem(item) == .failed { failures += 1 }
                        }
                        guard failures == 0 else {
                            // Keep the banner so 撤销 can be retried (rows that
                            // did restore re-report `.duplicate`, staying benign).
                            toast = "恢复失败，请重试"
                            return
                        }
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
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
            // Sit above the bottom intake CTA when it's showing.
            .padding(.bottom, store.checkedCount > 0 ? 72 : FkSpacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled {
                    withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
                }
            }
        }
    }

    // MARK: Toast

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

    // MARK: Clear-completed

    private var clearDoneButton: some View {
        Button {
            showClearConfirm = true
        } label: {
            Text("清空已完成 (\(store.checkedCount))")
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FkSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                        .strokeBorder(Color.fkHair, style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
        }
        .buttonStyle(.fkPressable)
    }

    // MARK: Actions

    /// Loads the live inventory, builds intake proposals for `items`, and pushes
    /// the shared review. On apply only the rows whose proposal landed are removed.
    private func openIntake(for items: [ShoppingItem]) {
        guard !items.isEmpty else { return }
        Task {
            let inventory: [Ingredient]
            do {
                inventory = try await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)
            } catch {
                // 合并判定全靠库存现状——读不到时进审核会把该合并的全误判成
                // 新建批次（落库后要手动清理重复行），宁可不进并提示重试。
                toast = "读取库存失败，请重试"
                return
            }
            let proposals = ShoppingIntake.buildProposals(items, inventory: inventory)
            guard !proposals.isEmpty else { return }
            reviewSource = items
            reviewRoute = ReviewRoute(proposals: proposals)
        }
    }

    private func deleteWithUndo(_ item: ShoppingItem) async {
        guard await store.delete(item) else { return }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            pendingUndo = PendingUndo(items: [item])
        }
    }

    /// 清空已完成: one atomic batch delete, then the same 4-second undo the
    /// swipe-delete offers (the banner restores exactly the rows `deleteAll`
    /// reported removed — never rows some other entry point already took).
    /// nil = read/persist failure: the user confirmed a destructive action, so
    /// silence would read as a dead button — toast a retry instead. An EMPTY
    /// result stays silent (the rows were already gone — a benign no-op).
    private func clearChecked() async {
        guard let removed = await store.deleteAll(store.items.filter(\.isChecked)) else {
            toast = "清理失败，请重试"
            return
        }
        guard !removed.isEmpty else { return }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            pendingUndo = PendingUndo(items: removed)
        }
    }

    /// Whether `item` carries a 「待同步」 badge: only in 家庭模式 (a real household is
    /// selected — local-only writes never enqueue) AND when the row's id has a
    /// queued outbox op.
    private func showsPendingBadge(for item: ShoppingItem) -> Bool {
        guard !dependencies.householdID.isEmpty, let pendingSync else { return false }
        return pendingSync.isPending(item.id)
    }

    // MARK: Empty state

    private var emptyState: some View {
        FkEmptyState(
            systemImage: "cart",
            title: "购物清单为空",
            message: "点右上角 + 添加需要购买的食材"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One undo banner's payload: the just-deleted rows (a single swipe-delete or
/// the 清空已完成 batch). The fresh `id` per deletion re-arms the 4s dismiss
/// timer even when banners replace each other back-to-back.
private struct PendingUndo: Identifiable {
    let id = UUID()
    let items: [ShoppingItem]
}

/// Gradient purchase-progress card: 本次采购进度 + done/total + percent + bar.
private struct ShoppingProgressCard: View {
    let done: Int
    let total: Int
    let progress: Double

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        let percent = Int((clamped * 100).rounded())
        return VStack(alignment: .leading, spacing: FkSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: FkSpacing.xs) {
                    Text("本次采购进度")
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(done)")
                            // .largeTitle (34pt base) so the stat scales with Dynamic Type.
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("/ \(total) 项")
                            .font(.fkBodyMedium)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                Spacer(minLength: FkSpacing.sm)
                Text("\(percent)%")
                    .font(.fkHeadlineSmall)
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: 6)
        }
        .padding(FkSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.xl, style: .continuous)
                .fill(
                    // fkPrimaryDeep(双模式同为深蓝)而非 fkPrimaryContainer:
                    // 后者在深色下是浅 ink,会让白字失去对比。
                    LinearGradient(
                        colors: [Color.fkPrimary, Color.fkPrimaryDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

/// 全部 / 待购买 / 已购 filter chips with live counts.
/// A tappable category section header: chevron (rotates on collapse) + name +
/// item count. Toggles the section's collapsed state (ports the Flutter
/// collapsible group headers).
private struct CategoryHeader: View {
    let category: String
    let count: Int
    let collapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                Text(category)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category)，\(count) 件")
        .accessibilityHint(collapsed ? "点按展开分类" : "点按折叠分类")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ShoppingFilterChips: View {
    @Bindable var store: ShoppingStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                chip("全部", .all, store.total)
                chip("待购买", .todo, store.uncheckedCount)
                chip("已购", .done, store.checkedCount)
            }
            // No internal horizontal padding: the row sits inside the section margin
            // (FkSpacing.lg), so the first chip already starts at 16pt — flush with the
            // progress card above. Re-adding padding here would push it in to ~32pt.
        }
    }

    private func chip(_ label: String, _ value: ShoppingStore.ShoppingFilter, _ count: Int) -> some View {
        FkChip(label: label, count: count, isSelected: store.filter == value) {
            store.filter = value
        }
    }
}

/// One shopping list row: a tappable check circle, category avatar, name, and
/// optional detail (quantity text). Checked → struck-through + dimmed.
private struct ShoppingRow: View {
    let item: ShoppingItem
    /// 家庭模式下该行有未上传的本地改动时为 true — drives the trailing 「待同步」 badge.
    var showsPendingBadge: Bool = false
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(item.isChecked ? Color.fkPrimary : Color.fkOutline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "取消勾选 \(item.name)" : "勾选 \(item.name)")

            FkCategoryAvatar(
                imageUrl: item.imageUrl ?? "",
                category: item.category,
                size: 40
            )

            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text(item.name)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .strikethrough(item.isChecked, color: Color.fkOnSurfaceVariant)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: FkSpacing.sm)

            if showsPendingBadge {
                PendingSyncBadge()
            }
        }
        .padding(.vertical, FkSpacing.xs)
        .opacity(item.isChecked ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

/// Add-item sheet: name (required), detail (optional), and a category picker
/// that auto-defaults from `FoodKnowledge` as the user types the name.
private struct ShoppingAddSheet: View {
    let store: ShoppingStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var detail = ""
    @State private var category = FoodCategories.other
    @State private var categoryEdited = false
    @State private var isSaving = false
    /// Inline notice — set when a save was rejected as a dup (the Flutter
    /// "已在清单中" feedback) OR failed to write (retryable), so the add never
    /// silently closes having added nothing.
    @State private var addError: String?

    private var trimmedName: String { name.trimmed }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("食材") {
                    TextField("名称（必填）", text: $name)
                        .onChange(of: name) { _, newValue in
                            guard !categoryEdited else { return }
                            category = FoodKnowledge.categoryFor(newValue)
                            addError = nil
                        }
                    TextField("数量 / 备注（选填，如 2 盒）", text: $detail)
                }
                if let addError {
                    Section {
                        Label(addError, systemImage: "exclamationmark.circle")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkDanger)
                    }
                }
                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(FoodCategories.values, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .onChange(of: category) { _, _ in categoryEdited = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("添加食材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let outcome = await store.addItem(name: trimmedName, detail: detail, category: category)
            isSaving = false
            switch outcome {
            case .added:
                dismiss()
            case .duplicate:
                // Rejected as a duplicate — keep the sheet open and say so rather
                // than closing as if it worked. (A same-unit duplicate would have
                // merged its quantity into the existing row and reported `.added`.)
                addError = "「\(trimmedName)」已在购物清单中"
            case .failed:
                // Read/persist error — nothing was written; never claim the item
                // is already on the list. Keep the sheet open for a retry.
                addError = "添加失败，请重试"
            }
        }
    }
}

/// Identifiable sheet route for the 数量 edit (id = the row's stable id so the
/// sheet identity survives store reloads).
private struct ShoppingDetailEditRoute: Identifiable {
    var id: String { item.id }
    let item: ShoppingItem
}

/// 编辑数量 sheet: read-only name + free-text detail field. While the draft
/// parses to a leading number, an `FkInlineStepper` (step 1, floor 0) offers
/// quick − / + bumps, writing back through `QuantityText.formatQuantity` so
/// float noise never reaches the stored detail. Blank saves are allowed —
/// clearing the quantity is a legitimate edit.
private struct ShoppingDetailEditSheet: View {
    let store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss

    @State private var detail: String
    @State private var isSaving = false
    /// Inline save-failure notice — set when `updateDetail` reports false (row
    /// deleted by another member mid-edit, or persist failed), so the sheet
    /// never closes as if the edit stuck (mirrors `ShoppingAddSheet.addError`).
    @State private var saveError: String?

    init(store: ShoppingStore, item: ShoppingItem) {
        self.store = store
        self.item = item
        _detail = State(initialValue: item.detail)
    }

    /// Leading quantity + unit of the current draft; nil hides the stepper
    /// (free-text like "适量" stays free-text).
    private var parsedDetail: (magnitude: String, remainder: String)? {
        QuantityText.parseLeadingQuantity(detail.trimmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("食材") {
                    Text(item.name)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Section("数量") {
                    TextField("数量，如：2 个", text: $detail)
                        .onChange(of: detail) { _, _ in saveError = nil }
                    if let parsed = parsedDetail {
                        HStack {
                            Text("快速调整")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                            Spacer(minLength: FkSpacing.sm)
                            FkInlineStepper(
                                value: parsed.magnitude,
                                suffix: parsed.remainder.isEmpty ? nil : parsed.remainder
                            ) { next in
                                detail = parsed.remainder.isEmpty ? next : "\(next) \(parsed.remainder)"
                            }
                        }
                    }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("编辑数量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await store.updateDetail(item, detail: detail)
            isSaving = false
            if saved {
                dismiss()
            } else {
                // Keep the sheet open and say so rather than closing as if it
                // worked (the row may have been deleted by another member while
                // this sheet was open, or the persist failed).
                saveError = "保存失败，该食材可能已被移除"
            }
        }
    }
}
