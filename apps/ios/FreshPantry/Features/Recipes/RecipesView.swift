import SwiftUI

/// The 食谱 tab: browses the merged bundled + custom recipe corpus, with category
/// filter chips, a name/ingredient search, a 只看收藏 toggle, and a favorite heart
/// per card. Pull-to-refresh reloads; cards push the read-only detail screen.
///
/// The view builds its `RecipesStore` from the injected `AppDependencies` — the
/// reusable feature pattern. Unlike Inventory/Shopping there is no DEBUG seed:
/// the bundled HowToCook corpus is real read-only data present on every install.
struct RecipesView: View {
    /// Spotlight deep-link intent: the recipe id whose detail to push once the
    /// corpus is loaded. Consumed (set to nil) once applied. `RootView` owns it.
    @Binding var pendingRecipeID: String?
    /// Cross-tab intent: preset the browse tab (e.g. 用临期). `RootView` owns it.
    @Binding var pendingRecipesTab: RecipesStore.Tab?

    @Environment(AppDependencies.self) private var dependencies
    @Environment(RecipeImportRouter.self) private var importRouter
    @State private var store: RecipesStore?
    /// CRUD owner for the user's custom recipes — drives the create/edit form and
    /// distinguishes custom recipes (for the detail edit/delete affordances).
    @State private var customStore: CustomRecipeStore?
    /// The household the current stores were built for — lets the build `.task`
    /// tell a real scope change (rebuild) from a tab reappear (reload, keep stores).
    @State private var loadedHouseholdID: String?
    /// Presents the create form sheet (the toolbar "+" › 手动新建).
    @State private var showCreateForm = false
    /// Presents the 拍照导入食谱 sheet (the toolbar "+" › 拍照导入).
    @State private var showPhotoImport = false
    /// A Share-Extension recipe URL to pre-fill the create form's AI import with.
    /// nil for a normal "+" open; set when consuming a share-intent deep link.
    @State private var importPrefillURL: String?
    /// Presents the 忌口 (avoided-ingredient) editor sheet from the toolbar.
    @State private var showDietarySheet = false
    /// Programmatic stack path. Normally empty; the `-initialRoute cook` launch
    /// hook pre-seeds it (in `.task`) so a recipe detail — and its auto-presented
    /// deduction review — can be snapshotted directly without a tap.
    @State private var path: [Recipe] = []
    /// Pushed detail route. Owned here (vs `RecipesContent`) so the Spotlight
    /// deep link drives the SAME `navigationDestination(item:)` as a card tap —
    /// two parallel push mechanisms on one stack (item + bound path) interleave
    /// unpredictably when both are live.
    @State private var selectedRoute: RecipeRoute?
    /// Transient banner copy (the standard top-toast pattern) — currently only
    /// the Spotlight miss feedback, so a stale deep link never lands silently.
    @State private var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        pendingRecipeID: Binding<String?> = .constant(nil),
        pendingRecipesTab: Binding<RecipesStore.Tab?> = .constant(nil)
    ) {
        _pendingRecipeID = pendingRecipeID
        _pendingRecipesTab = pendingRecipesTab
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store, let customStore {
                    RecipesContent(
                        store: store,
                        customStore: customStore,
                        favoritesStore: dependencies.favoritesStore,
                        selectedRoute: $selectedRoute
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("食谱")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { dietaryToolbarButton }
                ToolbarItem(placement: .topBarTrailing) { createToolbarButton }
            }
            .sheet(isPresented: $showDietarySheet) {
                DietaryExclusionsSheet(store: dependencies.dietaryPreferencesStore)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                if let store, let customStore {
                    RecipeDetailView(
                        recipe: recipe,
                        store: store,
                        customStore: customStore,
                        isCustom: customStore.recipes.contains { $0.id == recipe.id }
                    )
                }
            }
            .sheet(isPresented: $showCreateForm, onDismiss: { importPrefillURL = nil }) {
                if let customStore {
                    CustomRecipeFormView(
                        store: customStore,
                        aiSettingsStore: dependencies.aiSettingsStore,
                        onSaved: { Task { await reload() } },
                        initialImportURL: importPrefillURL
                    )
                }
            }
            .sheet(isPresented: $showPhotoImport) {
                if let customStore {
                    RecipePhotoImportView(
                        store: customStore,
                        aiSettingsStore: dependencies.aiSettingsStore,
                        onSaved: { Task { await reload() } }
                    )
                }
            }
            // Share-Extension import: open the create form pre-filled with the
            // shared recipe URL (warm path) — and once stores exist on cold start.
            .onChange(of: importRouter.pendingURL) { _, _ in consumeImportIntent() }
            .overlay(alignment: .top) { toastBanner }
        }
        // Rebuild both stores whenever the active household changes (login "" → uuid,
        // switch, or leave) so custom recipes re-scope to the new household rather
        // than keeping the prior scope's stale rows. (The bundled corpus is scope-free.)
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            // This `.task` re-runs on every tab REAPPEAR (sidebarAdaptable
            // lifecycle), not only on a household change. Rebuilding the stores each
            // time reset the 浏览 tab / filters and raced cross-tab intents (用临期
            // 预设 / Spotlight 深链 → 偶尔不生效). So build the stores ONCE per
            // household and merely RELOAD on a same-scope reappear: filters persist,
            // a real scope change still rebuilds fresh. (See InventoryView for the
            // full rationale + the matching 库存 fix.)
            if store == nil || loadedHouseholdID != householdID {
                let store = RecipesStore(
                    localRepository: dependencies.localRecipeRepository,
                    customRepository: dependencies.customRecipeRepository,
                    favoritesStore: dependencies.favoritesStore,
                    householdID: householdID,
                    inventoryRepository: dependencies.inventoryRepository,
                    dietaryStore: dependencies.dietaryPreferencesStore,
                    dietPreferenceStore: dependencies.dietPreferenceStore,
                    remoteCatalog: dependencies.remoteRecipeCatalog,
                    catalogCache: dependencies.recipeCatalogCache
                )
                let customStore = CustomRecipeStore(
                    repository: dependencies.customRecipeRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                // OFFLINE-FIRST, NO FLASH: load the new scope BEFORE swapping the
                // stores in. Assigning empty stores first flashed an empty corpus
                // for the duration of `load()` — and the off-main 900KB catalog
                // decode (catalogRecipes) widened that window — so a household
                // switch showed an empty 食谱 list before the cache/bundle resolved.
                // Loading first keeps the previous corpus on screen until the new
                // (local, instant) data is ready. Guard so a newer switch during the
                // load doesn't assign this stale scope's stores over the successor's.
                await store.load()
                await customStore.load()
                guard householdID == dependencies.householdID, !Task.isCancelled else { return }
                self.store = store
                self.customStore = customStore
                self.loadedHouseholdID = householdID
            } else {
                await reload()
            }
            // Cold start: intents captured before this tab built/loaded.
            consumeImportIntent()
            consumePendingRecipe()
            consumePendingRecipesTab()
            #if DEBUG
            // Snapshot affordance: `-initialRoute cook` seeds the inventory,
            // picks a recipe that matches it, and pushes its detail (whose own
            // `-initialRoute cook` hook then presents the deduction review).
            if RecipesView.opensCookOnLaunch, let store, let recipe = await cookSnapshotRecipe(store) {
                path = [recipe]
            }
            #endif
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so custom recipes pulled from other household members show up.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await reload() }
        }
        // Cross-tab intents (Spotlight 食谱深链 / 用临期 tab 预设). `.task(id:)` — not
        // `.onChange` — so an intent set in the same transaction that switches to this
        // tab still applies (see InventoryView for the full rationale): `.onChange`
        // never fires for the value already present when the (re)created tab view
        // appears. The cold `.task` above tail-applies the not-yet-loaded case.
        .task(id: pendingRecipeID) { consumePendingRecipe() }
        .task(id: pendingRecipesTab) { consumePendingRecipesTab() }
    }

    /// Applies a pending Spotlight deep link: pushes the matching recipe's
    /// detail via `selectedRoute` — the same `navigationDestination(item:)` a
    /// card tap uses, so a deep link arriving while a detail is already open
    /// swaps it in place instead of fighting the bound `path`. Waits for the
    /// initial load (`hasLoaded`) so a cold-start intent resolves against the
    /// real corpus; consumed even when the id no longer resolves (custom recipe
    /// deleted elsewhere) so a stale intent can't re-fire on a later reload.
    /// A miss toasts instead of landing silently — the index can lag a local
    /// delete until the next rebuild, and "nothing happened" reads as a broken
    /// route rather than gone data.
    private func consumePendingRecipesTab() {
        guard let tab = pendingRecipesTab, let store, store.hasLoaded else { return }
        store.tab = tab
        pendingRecipesTab = nil
    }

    private func consumePendingRecipe() {
        guard let id = pendingRecipeID, let store, store.hasLoaded else { return }
        pendingRecipeID = nil
        guard let match = store.recipes.first(where: { $0.id == id }) else {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                toast = "该食谱已删除"
            }
            return
        }
        selectedRoute = RecipeRoute(recipe: match)
    }

    /// The standard top toast (mirrors `InventoryContent.toastBanner`).
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

    /// Consumes a pending Share-Extension recipe URL: pre-fills + opens the create
    /// form (once the custom-recipe store exists), then clears the router so it
    /// doesn't re-fire. No-op when nothing is pending.
    private func consumeImportIntent() {
        guard let url = importRouter.pendingURL, customStore != nil else { return }
        importPrefillURL = url
        showCreateForm = true
        importRouter.clear()
    }

    /// 忌口 toolbar entry — fills + tints red when any keyword is active.
    private var dietaryToolbarButton: some View {
        let active = (store?.exclusionCount ?? 0) > 0
        return Button {
            showDietarySheet = true
        } label: {
            Image(systemName: active ? "nosign.app.fill" : "nosign")
        }
        .disabled(store == nil)
        .tint(active ? .fkDanger : .fkOnSurfaceVariant)
        .accessibilityLabel("忌口设置")
    }

    /// "+" toolbar entry — a menu offering manual authoring or 拍照导入 (OCR + AI
    /// structuring of a photographed / screenshotted recipe).
    private var createToolbarButton: some View {
        Menu {
            Button {
                showCreateForm = true
            } label: {
                Label("手动新建", systemImage: "square.and.pencil")
            }
            Button {
                showPhotoImport = true
            } label: {
                Label("拍照导入食谱", systemImage: "text.viewfinder")
            }
        } label: {
            Image(systemName: "plus")
        }
        .disabled(customStore == nil)
        .accessibilityLabel("新建食谱")
    }

    /// Reloads both the merged browse list and the custom-recipe set (after an
    /// author/edit/delete, or a remote merge pulse).
    private func reload() async {
        await store?.load()
        await customStore?.load()
    }

    #if DEBUG
    /// Honors `-initialRoute cook` for UI snapshots.
    private static var opensCookOnLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return false
        }
        return args[index + 1] == "cook"
    }

    /// Seeds the sample inventory and returns the first loaded recipe whose
    /// ingredients overlap it (so the deduction review has real candidates).
    private func cookSnapshotRecipe(_ store: RecipesStore) async -> Recipe? {
        // Sample data is for the local-only personal scope only — never seed a
        // real household (its rows come from sync).
        if dependencies.householdID.isEmpty {
            await InventorySeeder.seedIfNeeded(
                repository: dependencies.inventoryRepository,
                householdID: dependencies.householdID
            )
        }
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        let names = Set(inventory.map { $0.name })
        return store.recipes.first { recipe in
            recipe.ingredients.filter { ing in
                names.contains { $0.contains(ing.name) || ing.name.contains($0) }
            }.count >= 2
        }
    }
    #endif
}

/// Inner content bound to a live store (split out so `@Bindable` drives the
/// search field / filter chips, and observing the shared `FavoritesStore` lets
/// hearts re-render the moment a favorite toggles).
private struct RecipesContent: View {
    @Bindable var store: RecipesStore
    /// Drives the detail edit/delete affordances + the custom-recipe distinction.
    var customStore: CustomRecipeStore
    /// Observed so a favorite toggle re-renders the affected hearts/cards.
    var favoritesStore: FavoritesStore

    /// Hoisted to `RecipesView` so the Spotlight deep link and a card tap share
    /// one push mechanism (see the owner's comment).
    @Binding var selectedRoute: RecipeRoute?

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery, placeholder: "搜索菜谱或食材")
                    .padding(.horizontal, FkSpacing.lg)

                tabPicker

                filterChips

                timeFilterChips

                tagChips

                // The banner is the 用临期 tab's whole premise — only surface it as a
                // prompt on the OTHER tabs.
                if store.expiringItemCount > 0, store.tab != .expiring {
                    expiringBanner
                }

                listBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await store.load()
            await customStore.load()
        }
        .navigationDestination(item: $selectedRoute) { route in
            RecipeDetailView(
                recipe: route.recipe,
                store: store,
                customStore: customStore,
                isCustom: customStore.recipes.contains { $0.id == route.recipe.id }
            )
        }
    }

    // MARK: Tab picker (探索 / 现有 / 用临期 / 我的)

    /// Primary list selector — the four parity tabs. A segmented control (vs the
    /// chip rows below, which are secondary narrowing filters).
    private var tabPicker: some View {
        Picker("浏览方式", selection: $store.tab) {
            ForEach(RecipesStore.Tab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, FkSpacing.lg)
    }

    // MARK: Time filter chips (不限 / ≤15 / ≤30 分钟)

    private var timeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                ForEach(RecipesStore.TimeFilter.allCases) { option in
                    FkChip(
                        label: option.label,
                        isSelected: store.timeFilter == option
                    ) {
                        // Re-tap a non-default chip clears back to 不限.
                        store.timeFilter = (store.timeFilter == option && option != .all) ? .all : option
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    // MARK: Filter chips (favorites toggle + 全部 + categories)

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FkSpacing.sm) {
                if store.hasActiveQuery {
                    // One-tap reset when filters are stacked — clears category / tag /
                    // time / favorites / search at once (the tab stays put). Never
                    // "selected" (it's an action, not a toggle). Plain state set, like
                    // the sibling category/time chips.
                    FkChip(label: "清除筛选", isSelected: false) {
                        store.clearFilters()
                    }
                }

                FavoritesChip(
                    isOn: store.favoritesOnly,
                    count: store.favoriteCount
                ) { store.favoritesOnly.toggle() }

                FkChip(
                    label: "全部",
                    isSelected: store.effectiveCategory == nil
                ) { store.categoryFilter = nil }

                ForEach(store.categoryOptions, id: \.self) { category in
                    FkChip(
                        label: category,
                        isSelected: store.effectiveCategory == category
                    ) {
                        // Re-tap clears back to 全部 (single-select toggle).
                        store.categoryFilter = (store.effectiveCategory == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    // MARK: 标签筛选行 (user tags)

    /// 标签筛选行 — dynamic from the corpus's in-use user tags (frequency-then-name
    /// ordered). The whole row is hidden when no recipe carries a tag, so there's no
    /// dead "全部标签" control on a tag-free corpus. Mirrors `InventoryView.tagChips`.
    @ViewBuilder
    private var tagChips: some View {
        let options = chipTags
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FkSpacing.sm) {
                    FkChip(label: "全部标签", isSelected: store.selectedTag == nil) {
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

    // MARK: 临期 banner

    /// "优先使用 N 件临期食材" prompt — surfaces the reduce-waste intent when the
    /// pantry has expiring items (mirrors the Flutter `_ExpiringBanner`).
    private var expiringBanner: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fkDanger)
            Text("优先使用 \(store.expiringItemCount) 件临期食材")
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(Color.fkWarnSoft)
        )
        .padding(.horizontal, FkSpacing.lg)
    }

    // MARK: List / empty / loading

    @ViewBuilder
    private var listBody: some View {
        let recipes = store.displayRecipes
        if store.isLoading && !store.hasLoaded {
            ProgressView()
                .padding(.top, 80)
        } else if recipes.isEmpty {
            emptyState
                .padding(.top, FkSpacing.huge)
        } else {
            LazyVStack(spacing: FkSpacing.md) {
                ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                    Button {
                        selectedRoute = RecipeRoute(recipe: recipe)
                    } label: {
                        RecipeCard(
                            recipe: recipe,
                            isFavorite: store.isFavorite(recipe),
                            onToggleFavorite: { store.toggleFavorite(recipe) },
                            matchedCount: store.hasInventoryContext ? store.matchedCount(recipe) : nil,
                            totalIngredients: store.hasInventoryContext ? recipe.ingredients.count : nil,
                            expiringUse: store.expiringUseCount(recipe)
                        )
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
        let title: String
        let message: String?
        var icon = "book"
        if searching {
            title = "没有匹配「\(store.searchQuery.trimmed)」的菜谱"
            message = "试试换个关键词"
            icon = "magnifyingglass"
        } else if store.favoritesOnly {
            title = "还没有收藏的菜谱"
            message = "点 ♥ 收藏几道喜欢的吧"
            icon = "heart"
        } else if store.timeFilter != .all {
            title = "没有「\(store.timeFilter.label)」的菜谱"
            message = "放宽时间或换个分类试试"
            icon = "clock"
        } else if store.effectiveCategory != nil {
            title = "该分类下暂无菜谱"
            message = "换个分类试试"
        } else {
            // Tab-specific empties (no query active) — match the Flutter copy.
            switch store.tab {
            case .available:
                title = store.hasInventoryContext ? "现有食材还做不了整道菜" : "先去添加些库存食材"
                message = store.hasInventoryContext ? "去采购缺少的食材,或看看「探索」" : "有了库存才能推荐能做的菜"
                icon = "refrigerator"
            case .expiring:
                title = "暂无可用临期食材的菜谱"
                message = "没有临期食材,或它们暂时配不出整道菜"
                icon = "flame"
            case .mine:
                title = "还没有自建食谱"
                message = "点右上角「+」创建,或用 AI 从链接导入"
                icon = "square.and.pencil"
            case .explore:
                title = "暂无可探索的菜谱"
                message = nil
            }
        }
        return FkEmptyState(systemImage: icon, title: title, message: message)
    }
}

/// The 忌口 editor presented as a sheet from the Recipes toolbar — reuses the
/// shared `DietaryExclusionEditor` (same one in 设置 › 忌口) so the avoided-keyword
/// set, normalization, and persistence stay one source of truth. Editing here
/// immediately re-filters every recipe tab.
private struct DietaryExclusionsSheet: View {
    let store: DietaryPreferencesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DietaryExclusionEditor(store: store)
                } footer: {
                    Text("含这些关键字的食材会在所有菜谱列表中被隐藏。")
                }
                .listRowBackground(Color.fkSurfaceContainerLowest)
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("忌口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .tint(.fkPrimary)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Leading favorites pill — a heart that filters to favorited recipes only.
private struct FavoritesChip: View {
    let isOn: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: isOn ? "heart.fill" : "heart")
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                Text(label)
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(isOn ? Color.fkOnDanger : Color.fkOnSurface)
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isOn ? Color.fkDanger : Color.fkSurfaceContainerLowest)
                    .overlay(
                        Capsule().strokeBorder(isOn ? Color.clear : Color.fkHair, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.fkPressable)
    }

    private var label: String {
        count > 0 ? "收藏 · \(count)" : "收藏"
    }
}

/// `Hashable` navigation route wrapping a `Recipe`. (`Recipe` is `Hashable` by id
/// already, but wrapping keeps the route type explicit and future-proof.)
private struct RecipeRoute: Hashable {
    let recipe: Recipe
}
