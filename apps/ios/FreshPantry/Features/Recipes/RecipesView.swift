import SwiftUI

/// The 食谱 tab: browses the merged shared + custom recipe corpus, with category
/// filter chips, a name/ingredient search, a 只看收藏 toggle, and a favorite heart
/// per card. Pull-to-refresh reloads; cards push the read-only detail screen.
///
/// The view builds its `RecipesStore` from the injected `AppDependencies` — the
/// reusable feature pattern. Unlike Inventory/Shopping there is no DEBUG seed:
/// the HowToCook catalog is real read-only data from DB/cache.
struct RecipesView: View {
    /// Spotlight deep-link intent: the recipe id whose detail to push once the
    /// corpus is loaded. Consumed (set to nil) once applied. `RootView` owns it.
    @Binding var pendingRecipeID: String?
    /// Cross-tab intent: preset the browse tab (e.g. 用临期). `RootView` owns it.
    @Binding var pendingRecipesTab: RecipesStore.Tab?

    @Environment(AppDependencies.self) private var dependencies
    @Environment(RecipeImportRouter.self) private var importRouter
    @Environment(RecipeFilterRouter.self) private var recipeFilterRouter
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
            .navigationTitle(String(localized: "recipe.tabTitle"))
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
        // than keeping the prior scope's stale rows. (The shared catalog is scope-free.)
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
                    catalogCache: dependencies.recipeCatalogCache,
                    cookHistoryRepository: dependencies.cookHistoryRepository
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
            consumePendingIngredient()
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
        .task(id: recipeFilterRouter.pendingIngredient) { consumePendingIngredient() }
    }

    /// 临期→做这道菜 (#18): filter the 探索 tab to recipes using the tapped
    /// ingredient by setting the search to its name. Clears other narrowing
    /// filters first so the full set of matching dishes shows. Waits for load so a
    /// cold-start intent resolves against the real corpus.
    private func consumePendingIngredient() {
        guard let name = recipeFilterRouter.pendingIngredient, let store, store.hasLoaded else { return }
        recipeFilterRouter.consume()
        store.tab = .explore
        store.clearFilters()
        store.searchQuery = name
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
                toast = String(localized: "recipe.list.alreadyDeleted")
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
        .accessibilityLabel(String(localized: "recipe.list.dietarySettings"))
    }

    /// "+" toolbar entry — a menu offering manual authoring or 拍照导入 (OCR + AI
    /// structuring of a photographed / screenshotted recipe).
    private var createToolbarButton: some View {
        Menu {
            Button {
                showCreateForm = true
            } label: {
                Label(String(localized: "recipe.list.createManual"), systemImage: "square.and.pencil")
            }
            Button {
                showPhotoImport = true
            } label: {
                Label(String(localized: "recipe.photoImport.title"), systemImage: "text.viewfinder")
            }
        } label: {
            Image(systemName: "plus")
        }
        .disabled(customStore == nil)
        .accessibilityLabel(String(localized: "recipe.list.createNew"))
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

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The card long-press 快捷菜单 needs the same two writer stores the detail
    // screen lazily builds for 加购 / 加入计划. Built once per household scope and
    // dropped on a switch so a write never lands in the prior scope's lists
    // (mirrors `RecipeDetailView`'s `storeScope` sentinel).
    @State private var shoppingStore: ShoppingStore?
    @State private var mealPlanStore: MealPlanStore?
    @State private var storeScope: String?

    /// `.sheet(item:)` routes carrying the recipe a contextMenu action fired on
    /// (`Recipe` is `Hashable` but not `Identifiable`, hence the wrapper).
    @State private var planRoute: RecipeActionRoute?
    @State private var editRoute: RecipeActionRoute?
    @State private var deleteRoute: RecipeActionRoute?
    /// Local action feedback (加购 / 加入计划 / 删除) — own toast like the detail screen.
    @State private var actionToast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery, placeholder: String(localized: "recipe.list.searchPlaceholder"))
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

                seasonalCarousel

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
        // Build (and re-scope) the 加购 / 加入计划 writer stores for the card menu.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            if storeScope != householdID {
                shoppingStore = nil
                mealPlanStore = nil
                storeScope = householdID
            }
            if shoppingStore == nil {
                let shopping = ShoppingStore(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                await shopping.load()
                guard dependencies.householdID == householdID, !Task.isCancelled else { return }
                shoppingStore = shopping
            }
            if mealPlanStore == nil {
                let plan = MealPlanStore(
                    repository: dependencies.mealPlanRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                await plan.load()
                guard dependencies.householdID == householdID, !Task.isCancelled else { return }
                mealPlanStore = plan
            }
        }
        .sheet(item: $planRoute) { route in
            PlanDayPickerSheet(recipeName: route.recipe.name) { day in
                await addToPlan(route.recipe, on: day)
            }
        }
        .sheet(item: $editRoute) { route in
            CustomRecipeFormView(
                recipe: route.recipe,
                store: customStore,
                aiSettingsStore: dependencies.aiSettingsStore,
                onSaved: { Task { await store.load(); await customStore.load() } }
            )
        }
        .confirmationDialog(
            String(localized: "recipe.detail.deleteTitle"),
            isPresented: Binding(get: { deleteRoute != nil }, set: { if !$0 { deleteRoute = nil } }),
            titleVisibility: .visible,
            presenting: deleteRoute
        ) { route in
            Button(String(localized: "recipe.detail.delete"), role: .destructive) {
                Task { await deleteCustom(route.recipe) }
            }
            Button(String(localized: "recipe.detail.cancel"), role: .cancel) {}
        } message: { route in
            Text(String(localized: "recipe.detail.deleteConfirm \(route.recipe.name)"))
        }
        .overlay(alignment: .top) { actionToastBanner }
    }

    // MARK: Card long-press 快捷菜单

    /// Quick actions for a recipe card's long-press 上下文菜单 — mirrors the detail
    /// toolbar (收藏 / 加入膳食计划 / 加购缺料 / 自建食谱 编辑·删除) so a long-press finally
    /// gives feedback, consistent with 库存 / 购物 / 膳食计划.
    @ViewBuilder
    private func recipeContextMenu(for recipe: Recipe) -> some View {
        Button {
            store.toggleFavorite(recipe)
        } label: {
            Label(
                store.isFavorite(recipe) ? String(localized: "recipe.detail.unfavorite") : String(localized: "recipe.detail.favorite"),
                systemImage: store.isFavorite(recipe) ? "heart.slash" : "heart"
            )
        }
        Button {
            planRoute = RecipeActionRoute(recipe: recipe)
        } label: {
            Label(String(localized: "recipe.detail.addToPlan"), systemImage: "calendar.badge.plus")
        }
        .disabled(mealPlanStore == nil)
        // 加购缺料 — only when an inventory context exists AND something is missing,
        // so there's never a dead "加购缺少的 0 件" action.
        if store.hasInventoryContext {
            let missing = RecipeMatching.missingIngredients(store.inventoryNames, recipe).count
            if missing > 0 {
                Button {
                    Task { await addMissingToShopping(recipe) }
                } label: {
                    Label(String(localized: "recipe.detail.addMissingItems \(missing)"), systemImage: "cart.badge.plus")
                }
                .disabled(shoppingStore == nil)
            }
        }
        // 用户自建食谱才显示 编辑 / 删除。
        if customStore.recipes.contains(where: { $0.id == recipe.id }) {
            Divider()
            Button {
                editRoute = RecipeActionRoute(recipe: recipe)
            } label: {
                Label(String(localized: "recipe.detail.edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteRoute = RecipeActionRoute(recipe: recipe)
            } label: {
                Label(String(localized: "recipe.detail.delete"), systemImage: "trash")
            }
        }
    }

    /// Adds the recipe's missing ingredients to the shopping list (unscaled — the
    /// list has no 备料倍数 control), then toasts. Reuses the exact detail-screen
    /// add path so dedup / merge / category lookup stay one source of truth.
    private func addMissingToShopping(_ recipe: Recipe) async {
        guard let shoppingStore else { return }
        let adds = RecipeMatching.missingShoppingDetails(store.inventoryNames, recipe, scaleFactor: 1)
        guard !adds.isEmpty else { return }
        var added = 0
        var failed = 0
        for add in adds {
            let category = FoodKnowledge.lookup(add.name)?.category
            switch await shoppingStore.addItem(name: add.name, detail: add.detail, category: category) {
            case .added: added += 1
            case .duplicate: break // already on the list — the goal is met
            case .failed: failed += 1
            }
        }
        if failed > 0 {
            setActionToast(added > 0 ? String(localized: "recipe.detail.addedPartialFailed \(added)") : String(localized: "recipe.detail.addFailed"))
        } else {
            setActionToast(added > 0 ? String(localized: "recipe.detail.addedToShopping \(added)") : String(localized: "recipe.detail.missingAlreadyInShopping"))
        }
    }

    /// Plans `recipe` on `day`, dismisses the picker, and toasts (mirrors the
    /// detail screen's `addToPlan`).
    private func addToPlan(_ recipe: Recipe, on day: Date) async {
        guard let mealPlanStore else { return }
        let ok = await mealPlanStore.addDish(recipe: recipe, date: day)
        planRoute = nil
        setActionToast(ok
            ? String(localized: "recipe.detail.addedToPlan \(PlanDayPickerSheet.dayLabel(day))")
            : String(localized: "recipe.detail.addToPlanFailed"))
    }

    /// Deletes a custom recipe, then refreshes the merged browse list + toasts.
    private func deleteCustom(_ recipe: Recipe) async {
        guard await customStore.remove(recipe.id) else {
            setActionToast(String(localized: "recipe.list.deleteFailed"))
            return
        }
        await store.load()
        setActionToast(String(localized: "recipe.list.deleted \(recipe.name)"))
    }

    private func setActionToast(_ message: String) {
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            actionToast = message
        }
    }

    /// The standard top toast (mirrors `RecipesView.toastBanner`).
    @ViewBuilder
    private var actionToastBanner: some View {
        if let actionToast {
            Text(actionToast)
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
                .task(id: actionToast) {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { self.actionToast = nil }
                    }
                }
        }
    }

    // MARK: Tab picker (探索 / 现有 / 用临期 / 我的)

    /// Primary list selector — the four parity tabs. A segmented control (vs the
    /// chip rows below, which are secondary narrowing filters).
    private var tabPicker: some View {
        Picker(String(localized: "recipe.list.browseMode"), selection: $store.tab) {
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
                    FkChip(label: String(localized: "recipe.list.clearFilters"), isSelected: false) {
                        store.clearFilters()
                    }
                }

                FavoritesChip(
                    isOn: store.favoritesOnly,
                    count: store.favoriteCount
                ) { store.favoritesOnly.toggle() }

                // #7 做过次数 sort — re-tap to turn off (back to source order).
                FkChip(label: String(localized: "recipe.list.mostCooked"), isSelected: store.cookSort == .mostCooked) {
                    store.cookSort = store.cookSort == .mostCooked ? .none : .mostCooked
                }
                FkChip(label: String(localized: "recipe.list.leastRecent"), isSelected: store.cookSort == .leastRecent) {
                    store.cookSort = store.cookSort == .leastRecent ? .none : .leastRecent
                }

                FkChip(
                    label: String(localized: "recipe.list.allCategories"),
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
                    FkChip(label: String(localized: "recipe.list.allTags"), isSelected: store.selectedTag == nil) {
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
            Text(String(localized: "recipe.list.prioritizeExpiring \(store.expiringItemCount)"))
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

    /// 节气时令推荐 — a horizontal carousel of in-season dishes, only on the 探索
    /// tab with no active query (so it never competes with a filtered list).
    @ViewBuilder
    private var seasonalCarousel: some View {
        if store.tab == .explore, !store.hasActiveQuery {
            let seasonal = store.seasonalRecipes()
            if !seasonal.isEmpty {
                VStack(alignment: .leading, spacing: FkSpacing.sm) {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.fkPrimary)
                        Text(String(localized: "recipe.list.seasonalRecommendation \(store.currentSeasonName())"))
                            .font(.fkTitleSmall)
                            .foregroundStyle(Color.fkOnSurface)
                    }
                    .padding(.horizontal, FkSpacing.lg)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FkSpacing.sm) {
                            ForEach(seasonal, id: \.id) { recipe in
                                Button {
                                    selectedRoute = RecipeRoute(recipe: recipe)
                                } label: {
                                    seasonalPill(recipe)
                                }
                                .buttonStyle(.fkPressable)
                                .contextMenu { recipeContextMenu(for: recipe) }
                            }
                        }
                        .padding(.horizontal, FkSpacing.lg)
                    }
                }
            }
        }
    }

    private func seasonalPill(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(1)
            Text(recipe.category)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .padding(FkSpacing.md)
        .frame(width: 130, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous).fill(Color.fkPrimarySoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "recipe.list.seasonalPick \(recipe.name)"))
    }

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
                            expiringUse: store.expiringUseCount(recipe),
                            cookCount: store.cookCount(recipe)
                        )
                    }
                    .buttonStyle(.fkPressable)
                    // Long-press → quick-action menu (the screen used to give NO
                    // long-press feedback while every other list tab did). Same
                    // Button-in-fkPressable + .contextMenu pattern as MealPlanDishRow.
                    .contextMenu { recipeContextMenu(for: recipe) }
                    .fkEntrance(index: index)
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .fkEntranceWindow()
        }
    }

    private var emptyState: some View {
        let searching = !store.searchQuery.trimmed.isEmpty
        let title: String
        let message: String?
        var icon = "book"
        if searching {
            title = String(localized: "recipe.list.emptySearch \(store.searchQuery.trimmed)")
            message = String(localized: "recipe.list.tryAnotherKeyword")
            icon = "magnifyingglass"
        } else if store.favoritesOnly {
            title = String(localized: "recipe.list.emptyFavorites")
            message = String(localized: "recipe.list.emptyFavoritesHint")
            icon = "heart"
        } else if store.timeFilter != .all {
            title = String(localized: "recipe.list.emptyTimeFilter \(store.timeFilter.label)")
            message = String(localized: "recipe.list.emptyTimeFilterHint")
            icon = "clock"
        } else if store.effectiveCategory != nil {
            title = String(localized: "recipe.list.emptyCategory")
            message = String(localized: "recipe.list.emptyCategoryHint")
        } else {
            // Tab-specific empties (no query active) — match the Flutter copy.
            switch store.tab {
            case .available:
                title = store.hasInventoryContext ? String(localized: "recipe.list.emptyAvailable") : String(localized: "recipe.list.emptyNoInventory")
                message = store.hasInventoryContext ? String(localized: "recipe.list.emptyAvailableHint") : String(localized: "recipe.list.emptyNoInventoryHint")
                icon = "refrigerator"
            case .expiring:
                title = String(localized: "recipe.list.emptyExpiring")
                message = String(localized: "recipe.list.emptyExpiringHint")
                icon = "flame"
            case .mine:
                title = String(localized: "recipe.list.emptyMine")
                message = String(localized: "recipe.list.emptyMineHint")
                icon = "square.and.pencil"
            case .explore:
                title = String(localized: "recipe.list.emptyExplore")
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
                    Text(String(localized: "recipe.list.dietaryHint"))
                }
                .listRowBackground(Color.fkSurfaceContainerLowest)
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle(String(localized: "recipe.list.dietary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "recipe.detail.done")) { dismiss() }
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
        count > 0 ? String(localized: "recipe.list.favoritesCount \(count)") : String(localized: "recipe.detail.favorite")
    }
}

/// `Hashable` navigation route wrapping a `Recipe`. (`Recipe` is `Hashable` by id
/// already, but wrapping keeps the route type explicit and future-proof.)
private struct RecipeRoute: Hashable {
    let recipe: Recipe
}

/// `Identifiable` wrapper so a card's long-press contextMenu action can drive a
/// `.sheet(item:)` / `.confirmationDialog(presenting:)` with the specific recipe
/// it fired on (`Recipe` is `Hashable` but not `Identifiable`).
private struct RecipeActionRoute: Identifiable {
    let recipe: Recipe
    var id: String { recipe.id }
}
