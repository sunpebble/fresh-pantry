import Foundation

/// Feature store for the Recipes browse slice — the same `@Observable @MainActor`
/// template the Inventory / Shopping stores established.
///
/// Merges the read-only bundled HowToCook corpus (`LocalRecipeRepository`) with
/// the user's custom recipes (`CustomRecipeRepository`), de-duping by `id` with
/// **custom winning** (a user edit of a bundled recipe overrides the bundled
/// copy — mirrors `recommendedRecipesProvider`'s id-dedup merge). Holds the
/// category / search / favorites-only filter state and exposes the derived
/// `displayRecipes`. Favorite state is delegated to the shared `FavoritesStore`.
/// Views never decode the bundle or touch SwiftData directly.
@Observable
@MainActor
final class RecipesStore {
    /// Which slice the list shows (探索/现有/用临期/我的) — ports `_RecipeTab`.
    enum Tab: String, CaseIterable, Identifiable {
        case explore   // 探索 — the full corpus
        case available // 现有 — recipes you can (partly) make now, match-ranked
        case expiring  // 用临期 — recipes that use the most expiring items
        case mine      // 我的 — the user's custom recipes

        var id: String { rawValue }
        var label: String {
            switch self {
            case .explore: "探索"
            case .available: "现有"
            case .expiring: "用临期"
            case .mine: "我的"
            }
        }
    }

    /// Cooking-time filter (不限/≤15/≤30 分钟) — ports `_TimeFilter`.
    enum TimeFilter: String, CaseIterable, Identifiable {
        case all, fast15, fast30

        var id: String { rawValue }
        /// Inclusive upper bound in minutes; nil = 不限.
        var maxMinutes: Int? {
            switch self {
            case .all: nil
            case .fast15: 15
            case .fast30: 30
            }
        }
        var label: String {
            switch self {
            case .all: "不限时间"
            case .fast15: "15 分钟内"
            case .fast30: "30 分钟内"
            }
        }
    }

    /// Active browse tab. `explore` is the default (the full corpus).
    var tab: Tab = .explore
    /// Category filter. `nil` = 全部 (all categories).
    var categoryFilter: String?
    var searchQuery: String = ""
    var favoritesOnly: Bool = false
    var timeFilter: TimeFilter = .all

    private let localRepository: LocalRecipeRepository
    private let customRepository: CustomRecipeRepository
    private let favoritesStore: FavoritesStore
    private let householdID: String
    /// DB-backed catalog source (nil = bundle-only, e.g. tests / local-only mode).
    /// When present, `load()` shows the cache-or-bundle immediately, then refreshes
    /// from the database in the background — offline-first with a fresh-when-online
    /// upgrade.
    private let remoteCatalog: (any RecipeCatalogFetching)?
    /// On-disk cache for the DB catalog (the offline copy). nil disables caching.
    private let catalogCache: RecipeCatalogCache?
    /// Guards against overlapping background refreshes from rapid `load()` calls.
    private var isRefreshingCatalog = false
    /// Optional inventory source for the ingredient-match progress + 临期 banner.
    /// nil keeps the store browse-only (tests / meal-plan picker pass nil).
    private let inventoryRepository: InventoryRepository?
    /// Optional 忌口 source — recipes containing an avoided keyword are hidden from
    /// every tab. nil disables the filter (tests / meal-plan picker pass nil).
    private let dietaryStore: DietaryPreferencesStore?
    /// Optional 饮食偏好 source — boosts matching recipes in the 现有 ranking.
    /// nil disables the boost (tests / meal-plan picker pass nil).
    private let dietPreferenceStore: DietPreferenceStore?

    /// Merged, id-deduped recipes (bundled order first, custom appended; custom
    /// overrides a shared id in place). The parity-critical source order is never
    /// mutated by display concerns.
    private(set) var recipes: [Recipe] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    /// Lower-cased inventory names (the match corpus) + the expiring/expired
    /// subset, refreshed alongside `recipes`. Empty when no inventory source.
    private(set) var inventoryNames: Set<String> = []
    private(set) var expiringNames: Set<String> = []
    /// Ids of the user's custom recipes (drives the 我的 tab + the detail
    /// edit/delete affordances). Includes custom overrides of bundled ids.
    private(set) var customIDs: Set<String> = []

    init(
        localRepository: LocalRecipeRepository,
        customRepository: CustomRecipeRepository,
        favoritesStore: FavoritesStore,
        householdID: String,
        inventoryRepository: InventoryRepository? = nil,
        dietaryStore: DietaryPreferencesStore? = nil,
        dietPreferenceStore: DietPreferenceStore? = nil,
        remoteCatalog: (any RecipeCatalogFetching)? = nil,
        catalogCache: RecipeCatalogCache? = nil
    ) {
        self.localRepository = localRepository
        self.customRepository = customRepository
        self.favoritesStore = favoritesStore
        self.householdID = householdID
        self.inventoryRepository = inventoryRepository
        self.dietaryStore = dietaryStore
        self.dietPreferenceStore = dietPreferenceStore
        self.remoteCatalog = remoteCatalog
        self.catalogCache = catalogCache
    }

    /// The catalog source for an immediate (offline-safe) load: the on-disk DB
    /// cache when present, else the bundled corpus. The background refresh
    /// (`refreshCatalogFromRemote`) updates the cache so subsequent loads are
    /// DB-sourced.
    private func catalogRecipes() async -> [Recipe] {
        if let catalogCache {
            // Decode the ~900KB on-disk catalog OFF the main actor — a synchronous
            // JSON decode of that size on the main thread stalls the Recipes-tab open
            // / pull-to-refresh (a main-thread hang contributor).
            let cached = await Task.detached(priority: .userInitiated) {
                catalogCache.read()
            }.value
            if let cached, !cached.isEmpty { return cached }
        }
        return await localRepository.loadAll()
    }

    // MARK: Loading

    /// Loads the catalog (DB cache or bundled seed) + custom recipes and merges
    /// them (custom wins on id), plus the inventory match corpus when an inventory
    /// source is wired. When a remote catalog is configured, kicks off a background
    /// DB refresh that updates the cache and re-merges — the initial load stays
    /// instant and offline-safe.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let catalog = await catalogRecipes()
        let custom = (try? await customRepository.loadAllFor(householdID)) ?? []
        recipes = Self.merge(bundled: catalog, custom: custom)
        customIDs = Set(custom.map(\.id))
        if let inventoryRepository {
            let inventory = (try? await inventoryRepository.loadAllFor(householdID)) ?? []
            inventoryNames = RecipeMatching.availableInventoryNameSet(inventory)
            expiringNames = RecipeMatching.inventoryNameSet(inventory.filter { $0.state != .fresh })
        }
        if remoteCatalog?.isAvailable == true {
            Task { await refreshCatalogFromRemote() }
        }
    }

    /// Background DB refresh: fetch the catalog from Supabase, and on a non-empty
    /// result persist it to the cache and re-merge with custom recipes so the list
    /// upgrades to the DB copy. An empty fetch (offline / not yet seeded / error)
    /// is a no-op — the already-shown cache-or-bundle stays. Overlapping refreshes
    /// are coalesced.
    func refreshCatalogFromRemote() async {
        guard let remoteCatalog, let catalogCache, !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        let fresh = await remoteCatalog.fetchAll()
        guard !fresh.isEmpty else { return }
        // Encode the ~900KB catalog to disk OFF the main actor (best-effort).
        await Task.detached(priority: .utility) {
            catalogCache.write(fresh)
        }.value
        let custom = (try? await customRepository.loadAllFor(householdID)) ?? []
        recipes = Self.merge(bundled: fresh, custom: custom)
        customIDs = Set(custom.map(\.id))
    }

    // MARK: Inventory match (ingredient availability + 临期)

    /// In-stock ingredient count for a recipe (0 when no inventory source).
    func matchedCount(_ recipe: Recipe) -> Int {
        RecipeMatching.matchedCount(inventoryNames, recipe)
    }

    /// Distinct expiring/expired inventory items the recipe would use up.
    func expiringUseCount(_ recipe: Recipe) -> Int {
        RecipeMatching.expiringCount(expiringNames, recipe)
    }

    /// Whether the match progress should render (an inventory source is present).
    var hasInventoryContext: Bool { !inventoryNames.isEmpty }

    /// Count of distinct expiring/expired inventory names — drives the "优先使用 N
    /// 件临期食材" banner.
    var expiringItemCount: Int { expiringNames.count }

    /// Bundled first, then custom; a custom recipe with the same id REPLACES the
    /// bundled one in its original slot (custom wins), and a brand-new custom
    /// recipe is appended. Keeps bundled ordering otherwise.
    static func merge(bundled: [Recipe], custom: [Recipe]) -> [Recipe] {
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var result: [Recipe] = []
        var seen = Set<String>()
        for recipe in bundled {
            seen.insert(recipe.id)
            result.append(customByID[recipe.id] ?? recipe)
        }
        for recipe in custom where !seen.contains(recipe.id) {
            seen.insert(recipe.id)
            result.append(recipe)
        }
        return result
    }

    // MARK: Favorites (delegated to the shared store)

    func isFavorite(_ recipe: Recipe) -> Bool {
        favoritesStore.isFavorite(recipe.id)
    }

    @discardableResult
    func toggleFavorite(_ recipe: Recipe) -> Bool {
        favoritesStore.toggle(recipe.id)
    }

    // MARK: Derived view data

    /// The list the view renders: the active tab's (possibly ranked) base list,
    /// then category → name/ingredient search → cooking-time → favorites-only →
    /// 忌口 filters. Filters only NARROW, so a ranked tab (现有/用临期) keeps its
    /// order. A stale category filter (not present in the corpus) is treated as
    /// 全部 so it never silently empties the list (blueprint invariant 7).
    var displayRecipes: [Recipe] {
        let activeCategory = effectiveCategory
        let exclusions = dietaryStore?.keywords ?? []
        return tabBaseList
            .filter { Self.matchesCategory($0, activeCategory) }
            .filter { Self.matchesSearch($0, query: searchQuery) }
            .filter(matchesTime)
            .filter(matchesFavorites)
            .filter { !RecipeMatching.hasExcludedIngredient($0, exclusions) }
    }

    /// The per-tab source list BEFORE the shared filters. `explore`/`mine` keep
    /// source order; `available`/`expiring` are inventory-ranked (empty without
    /// an inventory context, which the view renders as a contextual empty state).
    private var tabBaseList: [Recipe] {
        switch tab {
        case .explore:
            return recipes
        case .available:
            return RecipeMatching.rankedByAvailability(
                recipes, inventoryNames: inventoryNames, expiringNames: expiringNames,
                prefs: dietPreferenceStore?.selected ?? []
            )
        case .expiring:
            return RecipeMatching.rankedByExpiringUse(recipes, expiringNames)
        case .mine:
            return recipes.filter { customIDs.contains($0.id) }
        }
    }

    /// 忌口 keyword count — drives the toolbar entry's badge/active state.
    var exclusionCount: Int { dietaryStore?.keywords.count ?? 0 }

    /// Distinct non-blank categories ordered by count desc, ties by first
    /// appearance (ports `recipeCategoryOptions`). Drives the filter chips.
    var categoryOptions: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for recipe in recipes {
            let category = recipe.category.trimmed
            guard !category.isEmpty else { continue }
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        return order.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    /// The category filter actually applied: the selected one if it's still a
    /// present option, else `nil` (全部).
    var effectiveCategory: String? {
        guard let categoryFilter, categoryOptions.contains(categoryFilter) else { return nil }
        return categoryFilter
    }

    /// True when any filter/search is narrowing the list (drives empty-state copy).
    var hasActiveQuery: Bool {
        !searchQuery.trimmed.isEmpty || effectiveCategory != nil || favoritesOnly
            || timeFilter != .all
    }

    var favoriteCount: Int {
        recipes.filter { favoritesStore.isFavorite($0.id) }.count
    }

    // MARK: Filtering internals

    private static func matchesCategory(_ recipe: Recipe, _ category: String?) -> Bool {
        guard let category else { return true }
        return recipe.category.trimmed == category.trimmed
    }

    /// Case-insensitive contains on the recipe name OR any ingredient name
    /// (ports the RecipesScreen search predicate).
    private static func matchesSearch(_ recipe: Recipe, query: String) -> Bool {
        let needle = query.trimmed.lowercased()
        if needle.isEmpty { return true }
        if recipe.name.lowercased().contains(needle) { return true }
        return recipe.ingredients.contains { $0.name.lowercased().contains(needle) }
    }

    private func matchesFavorites(_ recipe: Recipe) -> Bool {
        guard favoritesOnly else { return true }
        return favoritesStore.isFavorite(recipe.id)
    }

    /// Keeps recipes whose cooking time is within the selected bound (不限 keeps
    /// all). Ports the Dart `cookingMinutes <= 15/30` predicate.
    private func matchesTime(_ recipe: Recipe) -> Bool {
        guard let max = timeFilter.maxMinutes else { return true }
        return recipe.cookingMinutes <= max
    }
}
