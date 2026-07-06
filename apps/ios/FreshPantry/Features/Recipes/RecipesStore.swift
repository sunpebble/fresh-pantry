import Foundation

/// Feature store for the Recipes browse slice — the same `@Observable @MainActor`
/// template the Inventory / Shopping stores established.
///
/// Merges the shared DB/cache recipe catalog with
/// the user's custom recipes (`CustomRecipeRepository`), de-duping by `id` with
/// **custom winning** (a user edit of a shared recipe overrides the shared
/// copy — mirrors `recommendedRecipesProvider`'s id-dedup merge). Holds the
/// category / search / favorites-only filter state and exposes the derived
/// `displayRecipes`. Favorite state is delegated to the shared `FavoritesStore`.
/// Views never decode catalog JSON or touch SwiftData directly.
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
            case .explore: String(localized: "recipe.tab.explore")
            case .available: String(localized: "recipe.tab.available")
            case .expiring: String(localized: "recipe.tab.expiring")
            case .mine: String(localized: "recipe.tab.mine")
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
            case .all: String(localized: "recipe.timeFilter.all")
            case .fast15: String(localized: "recipe.timeFilter.within15")
            case .fast30: String(localized: "recipe.timeFilter.within30")
            }
        }
    }

    /// Active browse tab. `explore` is the default (the full corpus).
    var tab: Tab = .explore
    /// Category filter. `nil` = 全部 (all categories).
    var categoryFilter: String?
    /// User-tag filter. `nil` = 全部标签 (no tag restriction). Matched case-
    /// insensitively against each recipe's tags so a stale differently-cased
    /// selection still resolves (mirrors the inventory tag filter).
    var selectedTag: String?
    var searchQuery: String = ""
    var favoritesOnly: Bool = false
    var timeFilter: TimeFilter = .all

    private let localRepository: LocalRecipeRepository
    private let customRepository: CustomRecipeRepository
    private let favoritesStore: FavoritesStore
    private let householdID: String
    /// DB-backed catalog source (nil = cache/local only, e.g. tests).
    /// `load()` shows the cache immediately, fetches DB on first install, then
    /// refreshes in the background when cached data was used.
    private let remoteCatalog: (any RecipeCatalogFetching)?
    /// On-disk cache for the DB catalog (the offline copy). nil disables caching.
    private let catalogCache: RecipeCatalogCache?
    /// In-memory recipe i18n overlay. nil means use the Chinese source corpus.
    private let recipeOverlay: [String: RecipeOverlayEntry]?
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
    /// Optional device-local cook tally (#7) — powers cookCount + the 最常做/好久
    /// 没做 sort. nil disables it (tests pass nil).
    private let cookHistoryRepository: CookHistoryRepository?

    /// 做过次数 sort over the 探索 list (#7). `none` keeps source order.
    enum CookSort: Equatable { case none, mostCooked, leastRecent }
    var cookSort: CookSort = .none
    /// Cook tallies keyed by recipe id, refreshed alongside `recipes`.
    private(set) var cookHistoryByRecipeId: [String: CookHistory] = [:]

    /// Merged, id-deduped recipes (shared catalog order first, custom appended; custom
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
    /// edit/delete affordances). Includes custom overrides of shared catalog ids.
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
        catalogCache: RecipeCatalogCache? = nil,
        cookHistoryRepository: CookHistoryRepository? = nil,
        recipeOverlay: [String: RecipeOverlayEntry]? = nil
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
        self.recipeOverlay = recipeOverlay
        self.cookHistoryRepository = cookHistoryRepository
    }

    /// Times the user has cooked `recipe` (0 when never / no source).
    func cookCount(_ recipe: Recipe) -> Int { cookHistoryByRecipeId[recipe.id]?.cookCount ?? 0 }

    private func catalogRecipes() async -> [Recipe] {
        await RecipeCatalogLoader.load(
            local: localRepository,
            remote: remoteCatalog,
            cache: catalogCache
        )
    }

    private func overlay() async -> [String: RecipeOverlayEntry]? {
        await RecipeCatalogLoader.overlay(injected: recipeOverlay, remote: remoteCatalog)
    }

    // MARK: Loading

    /// Loads the catalog (DB/cache) + custom recipes and merges
    /// them (custom wins on id), plus the inventory match corpus when an inventory
    /// source is wired. When a remote catalog is configured, kicks off a background
    /// DB refresh that updates the cache and re-merges when cached data was used.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        async let catalogLoad = catalogRecipes()
        async let overlayLoad = overlay()
        let custom = (try? await customRepository.loadAllFor(householdID)) ?? []
        recipes = Self.merge(bundled: RecipeLocalizer.apply(await overlayLoad, to: await catalogLoad), custom: custom)
        customIDs = Set(custom.map(\.id))
        cookHistoryByRecipeId = (try? await cookHistoryRepository?.loadAll()) ?? [:]
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
    /// is a no-op — the already-shown cache/local copy stays. Overlapping refreshes
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
        recipes = Self.merge(bundled: RecipeLocalizer.apply(await overlay(), to: fresh), custom: custom)
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

    /// Shared catalog first, then custom; a custom recipe with the same id REPLACES the
    /// shared one in its original slot (custom wins), and a brand-new custom
    /// recipe is appended. Keeps catalog ordering otherwise.
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
        let filtered = tabBaseList
            .filter { Self.matchesCategory($0, activeCategory) }
            .filter(matchesTag)
            .filter { Self.matchesSearch($0, query: searchQuery) }
            .filter(matchesTime)
            .filter(matchesFavorites)
            .filter { !RecipeMatching.hasExcludedIngredient($0, exclusions) }
        return applyCookSort(filtered)
    }

    /// #7 做过次数 sort: 最常做 (cookCount desc) or 好久没做 (cooked oldest-first,
    /// never-cooked last). Stable by source order on ties. `none` = no reorder.
    private func applyCookSort(_ list: [Recipe]) -> [Recipe] {
        switch cookSort {
        case .none:
            return list
        case .mostCooked:
            return list.enumerated().sorted { lhs, rhs in
                let a = cookCount(lhs.element), b = cookCount(rhs.element)
                if a != b { return a > b }
                return lhs.offset < rhs.offset
            }.map(\.element)
        case .leastRecent:
            return list.enumerated().sorted { lhs, rhs in
                let la = cookHistoryByRecipeId[lhs.element.id]?.lastCookedAt
                let lb = cookHistoryByRecipeId[rhs.element.id]?.lastCookedAt
                switch (la, lb) {
                case let (x?, y?): return x != y ? x < y : lhs.offset < rhs.offset
                case (_?, nil): return true   // cooked before never-cooked
                case (nil, _?): return false
                case (nil, nil): return lhs.offset < rhs.offset
                }
            }.map(\.element)
        }
    }

    /// 当前节气名 (e.g. "芒种") — labels the 时令推荐 carousel.
    func currentSolarTermName(now: Date = Date()) -> String {
        SeasonalRules.currentTerm(now).name
    }

    /// In-season recipes for today (ranked by distinct in-season ingredients),
    /// honoring 忌口 exclusions. Empty when nothing matches. Shown only on the
    /// 探索 tab with no active query so it never fights the filtered list.
    func seasonalRecipes(now: Date = Date(), limit: Int = 6) -> [Recipe] {
        let exclusions = dietaryStore?.keywords ?? []
        let eligible = recipes.filter { !RecipeMatching.hasExcludedIngredient($0, exclusions) }
        return SeasonalRules.rankRecipes(eligible, date: now, limit: limit)
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

    /// The tag chips to surface, derived from the CURRENT corpus: every user tag in
    /// use, ordered by frequency (most-used first), ties broken by scalar name so
    /// the row is stable across reloads. Empty when no recipe carries a tag (the
    /// view hides the whole row, leaving no dead control). Mirrors the inventory
    /// `tagOptions` exactly.
    var tagOptions: [String] {
        var counts: [String: Int] = [:]        // lowercased key -> count
        var display: [String: String] = [:]    // lowercased key -> first-seen casing
        for recipe in recipes {
            for tag in recipe.tags {
                let key = tag.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = tag }
            }
        }
        return counts.keys
            .sorted { lhs, rhs in
                if counts[lhs]! != counts[rhs]! { return counts[lhs]! > counts[rhs]! }
                return display[lhs]! < display[rhs]!
            }
            .map { display[$0]! }
    }

    /// True when any filter/search is narrowing the list (drives empty-state copy).
    var hasActiveQuery: Bool {
        !searchQuery.trimmed.isEmpty || effectiveCategory != nil || favoritesOnly
            || timeFilter != .all || selectedTag != nil || cookSort != .none
    }

    var favoriteCount: Int {
        recipes.filter { favoritesStore.isFavorite($0.id) }.count
    }

    /// One-tap reset of every NARROWING filter (category / tag / search / time /
    /// favorites) back to 全部 — the tab stays put (it's the primary list selector,
    /// not a filter). Drives the "清除筛选" chip shown while `hasActiveQuery`.
    func clearFilters() {
        categoryFilter = nil
        selectedTag = nil
        searchQuery = ""
        favoritesOnly = false
        timeFilter = .all
        cookSort = .none
    }

    // MARK: Filtering internals

    private static func matchesCategory(_ recipe: Recipe, _ category: String?) -> Bool {
        guard let category else { return true }
        return recipe.category.trimmed == category.trimmed
    }

    /// Pinyin-aware contains on the recipe name OR any ingredient name — matches
    /// 中文子串, 全拼 (`fanqie`), and 首字母 (`fq`) via `PinyinMatcher`.
    private static func matchesSearch(_ recipe: Recipe, query: String) -> Bool {
        let needle = query.trimmed.lowercased()
        if needle.isEmpty { return true }
        if PinyinMatcher.matches(recipe.name, query: needle) { return true }
        return recipe.ingredients.contains { PinyinMatcher.matches($0.name, query: needle) }
    }

    private func matchesFavorites(_ recipe: Recipe) -> Bool {
        guard favoritesOnly else { return true }
        return favoritesStore.isFavorite(recipe.id)
    }

    /// Keeps recipes carrying the selected user tag (case-insensitive). No
    /// selection keeps all.
    private func matchesTag(_ recipe: Recipe) -> Bool {
        guard let selectedTag else { return true }
        let target = selectedTag.lowercased()
        return recipe.tags.contains { $0.lowercased() == target }
    }

    /// Keeps recipes whose cooking time is within the selected bound (不限 keeps
    /// all). Ports the Dart `cookingMinutes <= 15/30` predicate.
    private func matchesTime(_ recipe: Recipe) -> Bool {
        guard let max = timeFilter.maxMinutes else { return true }
        return recipe.cookingMinutes <= max
    }
}
