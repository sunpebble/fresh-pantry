import SwiftUI

/// The 首页 tab: a focused home hub around the three things users actually come
/// for — 推荐做什么 (今日推荐 + 用临期), 有哪些食材 (stat bar + 临期/分类 tiles) —
/// with the secondary features (膳食/减废/库存不足) demoted to one slim link row.
/// (购物 has its own tab, so it gets no home entry at all.)
///
/// Builds its `DashboardStore` from the injected `AppDependencies` (the reusable
/// feature pattern). In DEBUG it runs the inventory + shopping seeders (the same
/// idempotent one-shots the other tabs use) before loading, so 首页 has data even
/// when opened first. SwiftData is never touched here.
struct DashboardView: View {
    /// Switches the root tab selection — used by `LowStockView`'s bulk-add CTA to
    /// jump to the 购物 tab. Injected by `RootView`.
    var onSelectShopping: () -> Void = {}
    /// Drills into the 库存 tab pre-filtered to a tapped 食材分类 (canonical name).
    /// Injected by `RootView` (mirrors `onSelectShopping`).
    var onSelectCategory: (String) -> Void = { _ in }
    /// Opens the global search overlay (owned/presented by `RootView`).
    var onSearch: () -> Void = {}
    /// Switches to the 食谱 tab on the 用临期 slice (减废统计 CTA).
    var onSelectExpiringRecipes: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(NotificationTapRouter.self) private var tapRouter
    @Environment(WidgetDeepLinkRouter.self) private var widgetDeepLinkRouter
    @State private var store: DashboardStore?
    /// Programmatic stack path. Normally empty; the `-initialRoute` launch hook
    /// pre-seeds it (in `.task`) so a pushed screen (e.g. 膳食计划) can be
    /// snapshotted directly without a tap.
    @State private var path: [DashboardRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store {
                    DashboardContent(
                        store: store,
                        onSelectCategory: onSelectCategory
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle(String(localized: "dashboard.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(String(localized: "dashboard.search"))
                }
            }
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .expiring: ExpiringView()
                case .mealPlan: MealPlanView()
                case .wasteInsights:
                    WasteInsightsView(
                        onSelectCategory: onSelectCategory,
                        onSelectExpiringRecipes: onSelectExpiringRecipes
                    )
                case .lowStock: LowStockView(onSelectShopping: onSelectShopping)
                }
            }
        }
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the home hub re-scopes to the new household rather
        // than summarizing the prior scope's stale rows.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            // Apply the `-initialRoute` snapshot hook once, before first load.
            let initial = DashboardView.initialPath()
            if !initial.isEmpty { path = initial }
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's rows come from sync, never the seeder.
            if householdID.isEmpty {
                await InventorySeeder.seedIfNeeded(
                    repository: dependencies.inventoryRepository,
                    householdID: householdID
                )
                await ShoppingSeeder.seedIfNeeded(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID
                )
            }
            #endif
            // The seeder awaits above are suspension points: a household switch
            // landing there (login "" → uuid auto-select) starts a NEW run, and
            // this stale run must not assign an old-scope store over its work.
            guard householdID == dependencies.householdID, !Task.isCancelled else { return }
            let store = DashboardStore(
                inventoryRepository: dependencies.inventoryRepository,
                shoppingRepository: dependencies.shoppingRepository,
                householdID: householdID
            )
            // OFFLINE-FIRST, NO FLASH: load the new scope's local summary BEFORE
            // swapping the store in. Assigning an empty store first rendered an empty
            // home hub between the swap and `load()` on every household switch (incl.
            // the cold-launch "" → uuid auto-select) — the first screen the user
            // sees. Loading first keeps the previous summary on screen until the new
            // (local, instant) data is ready, then swaps atomically. Re-guard so a
            // newer switch during the load doesn't assign this stale scope's store.
            await store.load()
            guard householdID == dependencies.householdID, !Task.isCancelled else { return }
            self.store = store
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the dashboard reflects inventory/shopping pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
        // Widget toggle drain pulse: a 小组件 check-off lands in the shared store on
        // foreground via `WidgetPendingToggleDrainer`; reload so the 购物 tile's
        // 待购买 count reflects the just-checked item (it would otherwise stay stale
        // until a household switch / remote-sync apply).
        .onReceive(NotificationCenter.default.publisher(for: .widgetDidDrainShoppingToggle)) { _ in
            Task { await store?.load() }
        }
        // NOTIFICATION TAP → push 临期. `.task(id:)` rather than `.onChange` so
        // BOTH cold-start orders work: a tap captured BEFORE this view exists
        // fires on appear, and a tap arriving while visible fires on the id
        // change. Attached to the NavigationStack (not the store-gated content)
        // so it runs even while the `store == nil` loading branch is showing.
        .task(id: tapRouter.pendingTap) {
            guard tapRouter.pendingTap != nil else { return }
            tapRouter.consume()
            if path.last != .expiring { path.append(.expiring) }
        }
        // 小组件深链(临期/今日膳食/减废)→ push 对应 DashboardRoute。购物由
        // RootView 切 tab 处理(此处返回 nil 不消费)。
        .task(id: widgetDeepLinkRouter.pending) {
            guard let dest = widgetDeepLinkRouter.pending else { return }
            let route: DashboardRoute?
            switch dest {
            case .expiring: route = .expiring
            case .mealPlan: route = .mealPlan
            case .waste: route = .wasteInsights
            case .shopping: route = nil
            }
            guard let route else { return }
            widgetDeepLinkRouter.consume()
            if path.last != route { path.append(route) }
        }
    }
}

/// Navigation routes pushed from the Dashboard.
enum DashboardRoute: Hashable {
    case expiring
    case mealPlan
    case wasteInsights
    case lowStock
}

extension DashboardView {
    /// Honors a `-initialRoute <name>` launch argument by pre-seeding the
    /// navigation path, so a Dashboard-pushed screen can be snapshotted directly
    /// without a tap (a UI-snapshot affordance like `-initialTab`). Supports
    /// `mealplan` and `waste`; anything else starts at the home root.
    static func initialPath() -> [DashboardRoute] {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return []
        }
        switch args[index + 1] {
        case "mealplan": return [.mealPlan]
        case "waste": return [.wasteInsights]
        default: return []
        }
    }
}

/// Inner content bound to a live store. Lays out the focused home column.
private struct DashboardContent: View {
    let store: DashboardStore
    var onSelectCategory: (String) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lazily-built shopping store for the 临期 tile "加购" action.
    @State private var shoppingStore: ShoppingStore?
    /// Recipe browse store (favorites + the pushed detail) for the home recipe
    /// cards. Built once with the inventory/忌口 context, like the Recipes tab.
    @State private var recipesStore: RecipesStore?
    /// The household the lazily-built stores were scoped to — they are dropped
    /// and rebuilt when it changes (login/switch/leave must not write old scope).
    @State private var secondaryScope: String?
    /// 今日推荐 (top match-ranked recipe) + its matched-ingredient count.
    @State private var recommendation: Recipe?
    @State private var recommendationMatched = 0
    /// 用临期 fallback: the dish covering the most expiring items + covered names.
    @State private var fallback: FallbackSuggestion?
    /// Set once the secondary load runs, so the recipe cards can show a skeleton
    /// only on the FIRST load (not on every pull-to-refresh).
    @State private var didLoadRecipes = false
    /// Recipe selected from a home card → pushes the detail in this stack.
    @State private var selectedRecipe: Recipe?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                StatBar(summary: store.summary)
                    .fkEntrance(index: 0)
                    .padding(.horizontal, FkSpacing.lg)

                recommendationSection
                    .fkEntrance(index: 1)
                    .padding(.horizontal, FkSpacing.lg)

                if let fallback {
                    ExpiringFallbackStrip(suggestion: fallback) { selectedRecipe = fallback.recipe }
                        .padding(.horizontal, FkSpacing.lg)
                }

                expiringAndCategoryRow
                    .fkEntrance(index: 2)
                    .padding(.horizontal, FkSpacing.lg)

                SecondaryLinksRow()
                    .fkEntrance(index: 3)
                    .padding(.horizontal, FkSpacing.lg)
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
            .fkEntranceWindow()
        }
        .background(Color.fkSurface)
        .overlay(alignment: .top) { toastBanner }
        .navigationDestination(item: $selectedRecipe) { recipe in
            if let recipesStore {
                RecipeDetailView(recipe: recipe, store: recipesStore)
            }
        }
        .refreshable {
            await store.load()
            await loadSecondaryStats()
        }
        // Re-runs on every appear — so popping back from a pushed screen (临期
        // 「用了」, 购物 etc.) refreshes the stat bar/preview/计数 alongside the
        // secondary cards — and on a household switch, where the lazily-built
        // stores must be dropped first: they capture their scope at init, so a
        // kept instance would write into the prior household (the MealPlanView
        // match-context fix, applied here).
        .task(id: dependencies.householdID) {
            if secondaryScope != dependencies.householdID {
                shoppingStore = nil
                recipesStore = nil
                secondaryScope = dependencies.householdID
            }
            await store.load()
            await loadSecondaryStats()
        }
        // Remote merge pulse: the host view reloads the main store; the recipe
        // suggestions (今日推荐/用临期) consume it here so both halves of the
        // screen track merged data together.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await loadSecondaryStats() }
        }
    }

    /// Rich tile row: 临期提醒 alongside 食材分类. The category tile only renders when
    /// the pantry has any non-empty categories — an empty pantry shows 临期 full-width.
    @ViewBuilder
    private var expiringAndCategoryRow: some View {
        let categories = store.categoryCounts
        if categories.isEmpty {
            ExpiringTile(summary: store.summary, onAddToShopping: addToShopping)
        } else {
            HStack(alignment: .top, spacing: FkSpacing.sm) {
                ExpiringTile(summary: store.summary, onAddToShopping: addToShopping)
                CategoryTile(counts: categories, onSelect: onSelectCategory)
            }
        }
    }

    // MARK: 今日推荐

    /// The top match-ranked recipe as a tappable `RecipeCard`, with a skeleton on
    /// first load. Hidden once loaded if there's no inventory match (the Recipes
    /// tab's 现有 list covers the empty case).
    @ViewBuilder
    private var recommendationSection: some View {
        if let recommendation, let recipesStore {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                FkSectionHeader(title: String(localized: "dashboard.recommendation.title"))
                Button {
                    selectedRecipe = recommendation
                } label: {
                    RecipeCard(
                        recipe: recommendation,
                        isFavorite: recipesStore.isFavorite(recommendation),
                        onToggleFavorite: { recipesStore.toggleFavorite(recommendation) },
                        matchedCount: recommendationMatched,
                        totalIngredients: recommendation.ingredients.count,
                        expiringUse: recipesStore.expiringUseCount(recommendation)
                    )
                }
                .buttonStyle(.fkPressable)
            }
        } else if !didLoadRecipes {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                FkSectionHeader(title: String(localized: "dashboard.recommendation.title"))
                RecipeSkeletonCard()
            }
        }
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

    /// Loads the home recipe suggestions (今日推荐 + 用临期 fallback) and the
    /// shopping store for 临期 加购.
    ///
    /// SCOPE GUARD: every await below is a suspension point where a household
    /// switch can land (login "" → uuid auto-select, switch, leave). A stale
    /// run resuming afterwards must NOT assign stores built for the old scope —
    /// the new run's `== nil` lazy-build has already run, so a stale store
    /// would stick (the `secondaryScope` sentinel matches and never fires
    /// again) and 加购 would write into the prior household's list. The stores
    /// swallow `CancellationError` into empty results, so cancellation alone
    /// does not stop a stale run — re-check after EVERY await, before EVERY
    /// assignment.
    private func loadSecondaryStats() async {
        let scope = dependencies.householdID

        // Build the shopping store FIRST — the 临期 tile's 加购 button is
        // visible as soon as the main store loads, and everything below
        // (notably the recipe-corpus decode) would leave it a no-op for the
        // whole cold-start window otherwise.
        if shoppingStore == nil {
            let shopping = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: scope,
                syncWriter: dependencies.syncWriter
            )
            await shopping.load()
            guard scope == dependencies.householdID, !Task.isCancelled else { return }
            shoppingStore = shopping
        }

        // Build the recipe browse store once — it owns the merged corpus + the
        // inventory/expiring match context the home cards and detail view need.
        let recipes: RecipesStore
        if let recipesStore {
            await recipesStore.load()
            guard scope == dependencies.householdID, !Task.isCancelled else { return }
            recipes = recipesStore
        } else {
            let built = RecipesStore(
                localRepository: dependencies.localRecipeRepository,
                customRepository: dependencies.customRecipeRepository,
                favoritesStore: dependencies.favoritesStore,
                householdID: scope,
                inventoryRepository: dependencies.inventoryRepository,
                dietaryStore: dependencies.dietaryPreferencesStore,
                dietPreferenceStore: dependencies.dietPreferenceStore,
                remoteCatalog: dependencies.remoteRecipeCatalog,
                catalogCache: dependencies.recipeCatalogCache
            )
            await built.load()
            guard scope == dependencies.householdID, !Task.isCancelled else { return }
            recipesStore = built
            recipes = built
        }

        // 今日推荐 = the top match-ranked recipe; 用临期 = the best expiring-cover dish.
        let available = RecipeMatching.rankedByAvailability(
            recipes.recipes, inventoryNames: recipes.inventoryNames, expiringNames: recipes.expiringNames,
            prefs: dependencies.dietPreferenceStore.selected
        )
        recommendation = available.first
        recommendationMatched = recommendation.map { recipes.matchedCount($0) } ?? 0
        let exclusions = dependencies.dietaryPreferencesStore.keywords
        let eligibleForFallback = recipes.recipes.filter {
            !RecipeMatching.hasExcludedIngredient($0, exclusions)
        }
        fallback = RecipeMatching.expiringFallback(eligibleForFallback, recipes.expiringNames)
            .map { FallbackSuggestion(recipe: $0.recipe, covered: coveredDisplayNames($0.recipe, $0.covered)) }
        didLoadRecipes = true
    }

    /// The recipe's own ingredient display names (original case, deduped) that
    /// match the covered expiring set — nicer chips than the lowercased name set.
    private func coveredDisplayNames(_ recipe: Recipe, _ covered: Set<String>) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for ingredient in recipe.ingredients where covered.contains(ingredient.name.trimmed.lowercased()) {
            if seen.insert(ingredient.name.trimmed.lowercased()).inserted {
                names.append(ingredient.name.trimmed)
            }
        }
        return names
    }

    private func addToShopping(_ item: Ingredient) async {
        // The store builds at the top of loadSecondaryStats, so this window is
        // near-zero — but a tap inside it must not silently no-op.
        guard let shoppingStore else {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                toast = String(localized: "dashboard.shopping.loading")
            }
            return
        }
        let outcome = await shoppingStore.addItem(name: item.name, category: item.category)
        // Optimistically bump the summary count instead of a full two-scope reload.
        if outcome == .added { store.noteShoppingAdded(name: item.name, category: item.category) }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            switch outcome {
            case .added: toast = String(localized: "dashboard.shopping.added \(item.displayName)")
            case .duplicate: toast = String(localized: "dashboard.shopping.duplicate \(item.displayName)")
            // A read/persist failure is NOT a duplicate — claiming「已在清单中」
            // would assert a row the store never verified.
            case .failed: toast = String(localized: "dashboard.shopping.addFailed")
            }
        }
    }
}

/// The 用临期 fallback suggestion for the Dashboard: the dish that clears the most
/// expiring items, plus the (original-cased) covered ingredient names for chips.
struct FallbackSuggestion: Equatable {
    let recipe: Recipe
    let covered: [String]
}

// MARK: - Stat bar

/// Compact stat bar that replaces the tall tinted hero: a small time-of-day
/// greeting over a single horizontal row of triage counts (件食材 / 需处理 /
/// 过期 / 充足 — the former 类 segment duplicated the category tile below).
/// Reads the already-derived `DashboardSummary`; no new logic.
private struct StatBar: View {
    let summary: DashboardSummary

    /// Time-of-day greeting (早安/午安/下午好/晚上好/夜深了),主厨。— ports the Flutter
    /// dashboard greeting. Computed from the local hour at render time.
    static func greeting(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let hour = calendar.component(.hour, from: now)
        let part: String
        switch hour {
        case 5..<11: part = String(localized: "dashboard.greeting.morning")
        case 11..<13: part = String(localized: "dashboard.greeting.noon")
        case 13..<18: part = String(localized: "dashboard.greeting.afternoon")
        case 18..<23: part = String(localized: "dashboard.greeting.evening")
        default: part = String(localized: "dashboard.greeting.lateNight")
        }
        return String(localized: "dashboard.greeting.chef \(part)")
    }

    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                Text(Self.greeting())
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)

                HStack(alignment: .top, spacing: FkSpacing.xs) {
                    segment(value: summary.totalItems, label: String(localized: "dashboard.stat.items"), tint: .fkOnSurface)
                    segment(value: summary.needsAttentionCount, label: String(localized: "dashboard.stat.needsAttention"), tint: .fkWarnInk)
                    segment(value: summary.expiredCount, label: String(localized: "dashboard.stat.expired"), tint: .fkDanger)
                    segment(value: summary.freshCount, label: String(localized: "dashboard.stat.sufficient"), tint: .fkSuccess)
                }
            }
        }
    }

    private func segment(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.fkTitleLarge)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Tile surface

/// Soft surface tile that fills its column width and stretches to the row's
/// height, so two tiles paired in an `HStack(alignment: .top)` stay equal height
/// (the shorter one's background grows to match the taller). The `maxHeight`
/// must sit BEFORE the background so the fill is drawn at the stretched size.
private struct DashboardTileSurface<Content: View>: View {
    var background: Color = .fkSurfaceContainerLowest
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(FkSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.xl, style: .continuous)
                    .fill(background)
            )
            .fkCardShadow()
    }
}

/// Small trailing chevron for tappable tiles.
private struct TileChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.fkOnSurfaceVariant)
    }
}

// MARK: - 临期提醒 tile

/// Rich tile: 临期提醒 header + the soonest two expiring items (each with a quick
/// 加购 button) + a 「查看全部」footer that pushes the full `ExpiringView`. Empty
/// state shows a compact「暂无临期」success row.
private struct ExpiringTile: View {
    let summary: DashboardSummary
    /// "该用了" quick add-to-shopping for a previewed expiring item.
    var onAddToShopping: (Ingredient) async -> Void = { _ in }

    /// At most two inline rows keep the tile compact; the footer drills to the rest.
    private var preview: [Ingredient] { Array(summary.expiringPreview.prefix(2)) }

    var body: some View {
        DashboardTileSurface {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                header

                if summary.hasNoExpiring {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.fkSuccess)
                        Text(String(localized: "dashboard.expiring.none"))
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                } else {
                    ForEach(preview, id: \.fkListIdentityKey) { item in
                        row(item)
                    }
                    NavigationLink(value: DashboardRoute.expiring) {
                        HStack(spacing: FkSpacing.xs) {
                            Text(String(localized: "dashboard.expiring.viewAll"))
                                .font(.fkLabelMedium)
                                .foregroundStyle(Color.fkPrimary)
                            TileChevron()
                        }
                    }
                    .buttonStyle(.fkPressable)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fkWarnInk)
            Text(String(localized: "dashboard.expiring.title"))
                .font(.fkTitleSmall)
                .foregroundStyle(Color.fkOnSurface)
            if summary.needsAttentionCount > 0 {
                Text("\(summary.needsAttentionCount)")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkPrimaryContainer)
                    .padding(.horizontal, FkSpacing.xs)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.fkPrimarySoft))
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ item: Ingredient) -> some View {
        HStack(spacing: FkSpacing.sm) {
            FkCategoryAvatar(imageUrl: item.imageUrl, category: item.category, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.fkBodyMedium)
                    .foregroundStyle(item.state == .expired ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                    .lineLimit(1)
                if let label = item.expiryLabel, !label.isEmpty {
                    Text(label)
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await onAddToShopping(item) }
            } label: {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fkPrimaryContainer)
                    .padding(6)
                    .background(Circle().fill(Color.fkPrimarySoft))
            }
            .buttonStyle(.fkPressable)
            .accessibilityLabel(String(localized: "dashboard.expiring.addToShopping"))
        }
    }
}

// MARK: - 食材分类 tile

/// Rich tile: a 2-column mini grid of the canonical food categories (icon + name +
/// 件数). Tapping a cell drills into the 库存 tab pre-filtered to that category —
/// keeping the `home.category.<name>` accessibility identifier the UI tests assert.
private struct CategoryTile: View {
    let counts: [(category: String, count: Int)]
    let onSelect: (String) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: FkSpacing.xs),
        count: 2
    )

    var body: some View {
        DashboardTileSurface {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkPrimaryContainer)
                    Text(String(localized: "dashboard.category.title"))
                        .font(.fkTitleSmall)
                        .foregroundStyle(Color.fkOnSurface)
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: columns, spacing: FkSpacing.xs) {
                    ForEach(counts, id: \.category) { entry in
                        Button {
                            onSelect(entry.category)
                        } label: {
                            cell(category: entry.category, count: entry.count)
                        }
                        .buttonStyle(.fkPressable)
                        .accessibilityIdentifier("home.category.\(entry.category)")
                        .accessibilityLabel(String(localized: "dashboard.category.itemCount \(FoodCategories.displayLabel(for: entry.category)) \(entry.count)"))
                    }
                }
            }
        }
    }

    private func cell(category: String, count: Int) -> some View {
        let palette = FkCategoryIcon.palette(for: category)
        return HStack(spacing: 3) {
            Image(systemName: FkCategoryIcon.symbol(for: category))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(FoodCategories.displayLabel(for: category))
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Text("\(count)")
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, FkSpacing.xs)
        .padding(.vertical, FkSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkSurfaceContainer)
        )
    }
}

// MARK: - Secondary links row (膳食 / 减废 / 库存不足)

/// One slim row of pill links to the secondary features — replaces the former
/// 2×2 tile grid so the home stays focused on 推荐/食材/菜谱. 购物 has no entry
/// here at all: it owns a bottom tab. Reuses the tiles' `DashboardRoute`
/// destinations, so widget deep links keep working unchanged.
private struct SecondaryLinksRow: View {
    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            link(.mealPlan, systemImage: "calendar", title: String(localized: "dashboard.mealPlan.title"))
            link(.wasteInsights, systemImage: "leaf.fill", title: String(localized: "dashboard.waste.title"))
            link(.lowStock, systemImage: "cart.badge.plus", title: String(localized: "dashboard.lowStock.title"))
        }
    }

    private func link(_ route: DashboardRoute, systemImage: String, title: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fkPrimaryContainer)
                Text(title)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, FkSpacing.sm)
            .padding(.vertical, FkSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.fkSurfaceContainerLowest))
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - 用临期 fallback strip

/// "用临期食材 · 今天就能做" — a slim full-width accent strip surfacing the single
/// dish that clears the most expiring items. Ports the Flutter `ExpiringFallbackCard`
/// to one dense line; taps push the recipe detail.
private struct ExpiringFallbackStrip: View {
    let suggestion: FallbackSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FkCard(padding: FkSpacing.md) {
                HStack(spacing: FkSpacing.sm) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.fkDanger)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "dashboard.fallback.title"))
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkDanger)
                        Text(suggestion.recipe.name)
                            .font(.fkTitleSmall)
                            .foregroundStyle(Color.fkOnSurface)
                            .lineLimit(1)
                    }
                    Spacer(minLength: FkSpacing.sm)
                    Text(String(localized: "dashboard.fallback.available \(suggestion.covered.count)"))
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    TileChevron()
                }
            }
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - Recipe skeleton (今日推荐 first-load placeholder)

/// A shimmer-free skeleton placeholder for the 今日推荐 card while recipes load.
private struct RecipeSkeletonCard: View {
    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
                    .frame(height: 96)
                RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
                    .frame(width: 140, height: 16)
                RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
                    .frame(width: 90, height: 12)
            }
        }
        .accessibilityLabel(String(localized: "dashboard.recommendation.loading"))
    }
}
