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
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ShoppingStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    ShoppingContent(store: store)
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
            let store = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the list reflects rows pulled from other household members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store (split out so the bindable store can drive
/// the filter chips, and the add sheet / mutations get a concrete store).
private struct ShoppingContent: View {
    @Bindable var store: ShoppingStore
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAddingItem = false
    /// Drives the intake-review push; `reviewSource` is the rows sent so the
    /// applied ones can be removed from the list on return.
    @State private var reviewRoute: ReviewRoute?
    @State private var reviewSource: [ShoppingItem] = []
    /// The just-deleted row, surfaced in a transient undo banner.
    @State private var pendingUndo: ShoppingItem?
    @State private var showClearConfirm = false

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
        .toolbar {
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
        .navigationDestination(item: $reviewRoute) { route in
            IntakeReviewView(proposals: route.proposals, title: "已购买项入库") { outcome in
                let applied = ShoppingIntake.appliedSourceItems(reviewSource, appliedIds: outcome.appliedIds)
                Task { for item in applied { await store.delete(item) } }
            }
        }
        .safeAreaInset(edge: .bottom) { intakeCTA }
        .overlay(alignment: .bottom) { undoBanner }
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
    }

    // MARK: List

    private var itemList: some View {
        List {
            Section {
                ShoppingProgressCard(done: store.checkedCount, total: store.total, progress: store.progress)
                    .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: FkSpacing.lg, bottom: FkSpacing.xs, trailing: FkSpacing.lg))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ShoppingFilterChips(store: store)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: FkSpacing.sm, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

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
            } else {
                ForEach(store.displaySections, id: \.category) { section in
                    Section {
                        if !store.isCollapsed(section.category) {
                            ForEach(section.items, id: \.id) { item in
                                ShoppingRow(item: item) {
                                    Task { await store.toggleChecked(item) }
                                }
                                .listRowBackground(Color.fkSurfaceContainerLowest)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        openIntake(for: [item])
                                    } label: {
                                        Label("加入库存", systemImage: "tray.and.arrow.down")
                                    }
                                    .tint(Color.fkPrimary)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await deleteWithUndo(item) }
                                    } label: {
                                        Label("删除", systemImage: "trash")
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
                }
            }

            if store.checkedCount > 0 {
                Section {
                    clearDoneButton
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .refreshable { await store.load() }
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
                Text("「\(undo.name)」已删除")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: FkSpacing.sm)
                Button("撤销") {
                    Task {
                        await store.restore(undo)
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
            let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
            let proposals = ShoppingIntake.buildProposals(items, inventory: inventory)
            guard !proposals.isEmpty else { return }
            reviewSource = items
            reviewRoute = ReviewRoute(proposals: proposals)
        }
    }

    private func deleteWithUndo(_ item: ShoppingItem) async {
        guard await store.delete(item) else { return }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = item }
    }

    private func clearChecked() async {
        for item in store.items.filter(\.isChecked) {
            _ = await store.delete(item)
        }
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
            .padding(.horizontal, FkSpacing.lg)
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
    /// Inline duplicate notice — set when a save was rejected as a dup, so the add
    /// doesn't silently close having added nothing (the Flutter "已在清单中" feedback).
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
            let added = await store.add(name: trimmedName, detail: detail, category: category)
            isSaving = false
            if added {
                dismiss()
            } else {
                // Rejected as a duplicate — keep the sheet open and say so rather
                // than closing as if it worked.
                addError = "「\(trimmedName)」已在购物清单中"
            }
        }
    }
}
