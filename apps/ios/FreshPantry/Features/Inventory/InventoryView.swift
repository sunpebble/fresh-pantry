import SwiftUI

/// The 库存 tab: lists the household's ingredients, urgency-sorted, with storage
/// filter chips and a name search. Pull-to-refresh reloads from the store; rows
/// push the read-only detail screen.
///
/// The view builds its `InventoryStore` from the injected `AppDependencies` —
/// the reusable pattern every feature view follows. SwiftData is never touched
/// here; all scoping / sorting / filtering lives in the store.
struct InventoryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: InventoryStore?
    /// Drives the add-ingredient sheet (toolbar "+"). The `-initialRoute add`
    /// launch hook pre-opens it for snapshots/tests.
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    InventoryContent(store: store)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("库存")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加食材")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddIngredientView { Task { await store?.load() } }
            }
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
            self.store = store
            await store.load()
            // Snapshot affordance: `-initialRoute add` opens the add sheet so
            // the form can be screenshotted directly (mirrors `-initialTab`).
            if InventoryView.opensAddOnLaunch { showAddSheet = true }
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // the store so the visible list reflects rows pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }

    /// Honors a `-initialRoute add` launch argument (UI snapshots / tests).
    private static var opensAddOnLaunch: Bool {
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

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery)
                    .padding(.horizontal, FkSpacing.lg)

                storageChips

                listBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.load() }
        .navigationDestination(item: $selectedIngredient) { ingredient in
            IngredientDetailView(ingredient: ingredient, store: store)
        }
    }

    @State private var selectedIngredient: Ingredient?

    // MARK: Storage filter chips

    private var storageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                FkChip(
                    label: "全部",
                    count: store.count(for: .all),
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
                    Button {
                        selectedIngredient = item
                    } label: {
                        FkCard {
                            IngredientRow(ingredient: item)
                        }
                    }
                    .buttonStyle(.fkPressable)
                    .fkEntrance(index: index)
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    private var emptyState: some View {
        let searching = !store.searchQuery.trimmed.isEmpty
        return FkEmptyState(
            systemImage: store.hasActiveQuery ? "magnifyingglass" : "tray",
            title: searching ? "没有找到「\(store.searchQuery.trimmed)」"
                : (store.hasActiveQuery ? "该位置下暂无食材" : "冰箱空空如也"),
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
