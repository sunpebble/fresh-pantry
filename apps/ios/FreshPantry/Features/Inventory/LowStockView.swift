import SwiftUI

/// The 库存不足 (常买补货) screen, pushed from the Dashboard: the names bought ≥3
/// times that are no longer in stock (the restock candidates), grouped by food
/// category, each prechecked. A sticky bottom CTA adds the selected items to the
/// shopping list and jumps to the 购物 tab.
///
/// Builds its own `LowStockStore` + `ShoppingStore` from the injected
/// `AppDependencies` (the reusable feature pattern). The add respects the shopping
/// list's name-unique dedup — only the items actually added are counted.
struct LowStockView: View {
    /// Switches the root tab selection to 购物 after a successful add. Injected by
    /// the Dashboard (which receives it from `RootView`).
    var onSelectShopping: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: LowStockStore?
    @State private var shoppingStore: ShoppingStore?
    @State private var isAdding = false
    /// Toast copy for the stay-put cases (everything chosen was already on the
    /// list, or some adds failed to write) — the screen doesn't jump, so the CTA
    /// must say why, and a failure must never read as「已在清单中」.
    @State private var feedback: String?

    var body: some View {
        Group {
            if let store {
                LowStockContent(
                    store: store,
                    isAdding: isAdding,
                    onAdd: addSelected
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle(String(localized: "dashboard.lowStock.title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) { feedbackBanner }
        // Rebuild the primary candidate store whenever the active household changes
        // (login "" → uuid, switch, or leave) so the list re-scopes to the new
        // household. The ShoppingStore is transient (only for the cross-action add),
        // rebuilt alongside so its add targets the same current scope.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            let lowStock = LowStockStore(
                repository: dependencies.inventoryRepository,
                householdID: householdID,
                foodLogRepository: dependencies.foodLogRepository
            )
            let shopping = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            // OFFLINE-FIRST, NO FLASH: load the new scope's local rows BEFORE
            // swapping the store in, so a household switch keeps the previous list on
            // screen until the new (local, instant) data is ready instead of flashing
            // an empty list. Guard after the loads so a newer switch landing here
            // doesn't assign this stale scope's stores over the successor's.
            await lowStock.load()
            await shopping.load()
            guard householdID == dependencies.householdID, !Task.isCancelled else { return }
            self.store = lowStock
            self.shoppingStore = shopping
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload so
        // the candidate list reflects inventory/shopping pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task {
                await store?.load()
                await shoppingStore?.load()
            }
        }
    }

    /// Adds every chosen candidate to the shopping list (respecting its name-unique
    /// dedup), counts how many actually landed, then jumps to the 购物 tab and pops
    /// this screen. When everything deduped away the screen stays and a toast says
    /// so (the tab jump IS the success feedback; a toast there would never be seen).
    /// A write FAILURE also keeps the screen (selection intact, so the CTA is the
    /// retry) and must never claim「已在清单中」— nothing was written.
    private func addSelected() async {
        guard let store, let shoppingStore, !isAdding else { return }
        let chosen = store.chosenItems
        guard !chosen.isEmpty else { return }

        isAdding = true
        var added = 0
        var failed = 0
        for item in chosen {
            let category = FoodKnowledge.lookup(item.name)?.category
            switch await shoppingStore.addItem(name: item.name, category: category) {
            case .added: added += 1
            case .duplicate: break // already on the list — the goal is met
            case .failed: failed += 1
            }
        }
        isAdding = false

        if failed > 0 {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                feedback = added > 0 ? String(localized: "inventory.lowStock.partialFailed") : String(localized: "dashboard.shopping.addFailed")
            }
            return
        }
        if added == 0 {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                feedback = String(localized: "inventory.lowStock.allDuplicate")
            }
            return
        }
        onSelectShopping()
        dismiss()
    }

    /// Top toast consuming `feedback` — the Dashboard banner pattern (2s auto-hide).
    @ViewBuilder
    private var feedbackBanner: some View {
        if let feedback {
            Text(feedback)
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
                .task(id: feedback) {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { self.feedback = nil }
                    }
                }
        }
    }
}

/// Inner content bound to a live store. Split out so `@Bindable` can drive the
/// per-row selection toggles.
private struct LowStockContent: View {
    @Bindable var store: LowStockStore
    let isAdding: Bool
    let onAdd: () async -> Void

    var body: some View {
        Group {
            if !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty {
                FkEmptyState(
                    systemImage: "checkmark.seal",
                    title: String(localized: "inventory.lowStock.emptyTitle"),
                    message: String(localized: "inventory.lowStock.emptyMessage")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                groupList
            }
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
        .safeAreaInset(edge: .bottom) {
            if !store.items.isEmpty {
                StickyAddBar(
                    count: store.chosenItems.count,
                    isAdding: isAdding,
                    onTap: { Task { await onAdd() } }
                )
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.xl) {
                ForEach(Array(store.groupedByCategory.enumerated()), id: \.element.category) { sectionIndex, group in
                    VStack(alignment: .leading, spacing: FkSpacing.sm) {
                        FkSectionHeader(title: FoodCategories.displayLabel(for: group.category), count: group.items.count)
                            .padding(.horizontal, FkSpacing.lg)

                        LazyVStack(spacing: FkSpacing.sm) {
                            ForEach(Array(group.items.enumerated()), id: \.element.name) { index, item in
                                Button {
                                    store.toggle(item.name)
                                } label: {
                                    FkCard {
                                        LowStockRow(
                                            item: item,
                                            isSelected: store.selectedNames.contains(item.name),
                                            prediction: store.prediction(for: item.name)
                                        )
                                    }
                                }
                                .buttonStyle(.fkPressable)
                                .fkEntrance(index: sectionIndex + index)
                            }
                        }
                        .padding(.horizontal, FkSpacing.lg)
                    }
                }
            }
            .padding(.top, FkSpacing.md)
            .padding(.bottom, FkSpacing.huge)
            .fkEntranceWindow()
        }
    }
}

/// One candidate row: category avatar + name (+ reorder-cadence hint) + "买过 N
/// 次" stat + a check toggle.
private struct LowStockRow: View {
    let item: FrequentItem
    let isSelected: Bool
    var prediction: ReorderPrediction? = nil

    /// "该补了 · 约每7天" when due, else "约每7天" — nil when no cadence estimate.
    private var cadenceHint: String? {
        guard let prediction else { return nil }
        let every = String(localized: "inventory.lowStock.everyDays \(Int(prediction.avgIntervalDays.rounded()))")
        return prediction.isDue ? String(localized: "inventory.lowStock.dueNow \(every)") : every
    }

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(imageUrl: "", category: item.category, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                if let cadenceHint {
                    Text(cadenceHint)
                        .font(.fkLabelSmall)
                        .foregroundStyle(prediction?.isDue == true ? Color.fkPrimary : Color.fkOnSurfaceVariant)
                }
            }

            Spacer(minLength: FkSpacing.sm)

            Text(String(localized: "inventory.lowStock.boughtCount \(item.count)"))
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)

            checkCircle
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var checkCircle: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.fkPrimary : Color.clear)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(isSelected ? Color.fkPrimary : Color.fkOutlineVariant, lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.fkOnPrimary)
            }
        }
    }
}

/// Sticky bottom CTA: "加入购物清单 (N)". Disabled when nothing is selected or a
/// add is in flight; shows a spinner while adding.
private struct StickyAddBar: View {
    let count: Int
    let isAdding: Bool
    let onTap: () -> Void

    private var enabled: Bool { count > 0 && !isAdding }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FkSpacing.sm) {
                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.fkOnPrimary)
                } else {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(String(localized: "inventory.lowStock.addToShoppingCount \(count)"))
                    .font(.fkLabelLarge)
            }
            .foregroundStyle(enabled ? Color.fkOnPrimary : Color.fkOutline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(enabled ? Color.fkPrimary : Color.fkSurfaceContainer)
            )
        }
        .buttonStyle(.fkPressable)
        .disabled(!enabled)
        .padding(.horizontal, FkSpacing.lg)
        .padding(.top, FkSpacing.sm)
        .padding(.bottom, FkSpacing.sm)
        .background(.bar)
    }
}
