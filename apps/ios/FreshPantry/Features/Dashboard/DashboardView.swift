import SwiftUI

/// The 首页 tab: a data-backed home hub summarizing the household's pantry —
/// a tinted hero with headline + sub-stats, a 临期提醒 preview that pushes the
/// full `ExpiringView`, and a 购物清单 summary that switches to the 购物 tab.
///
/// Builds its `DashboardStore` from the injected `AppDependencies` (the reusable
/// feature pattern). In DEBUG it runs the inventory + shopping seeders (the same
/// idempotent one-shots the other tabs use) before loading, so 首页 has data even
/// when opened first. SwiftData is never touched here.
struct DashboardView: View {
    /// Switches the root tab selection — used by the 购物清单 summary row to jump
    /// to the 购物 tab. Injected by `RootView`.
    var onSelectShopping: () -> Void = {}
    /// Drills into the 库存 tab pre-filtered to a tapped 食材分类 (canonical name).
    /// Injected by `RootView` (mirrors `onSelectShopping`).
    var onSelectCategory: (String) -> Void = { _ in }
    /// Opens the global search overlay (owned/presented by `RootView`).
    var onSearch: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @State private var store: DashboardStore?
    /// Programmatic stack path. Normally empty; the `-initialRoute` launch hook
    /// pre-seeds it (in `.task`) so a pushed screen (e.g. 膳食计划) can be
    /// snapshotted directly without a tap.
    @State private var path: [DashboardRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store {
                    DashboardContent(store: store, onSelectShopping: onSelectShopping, onSelectCategory: onSelectCategory)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("首页")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索")
                }
            }
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .expiring: ExpiringView()
                case .mealPlan: MealPlanView()
                case .wasteInsights: WasteInsightsView()
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
            let store = DashboardStore(
                inventoryRepository: dependencies.inventoryRepository,
                shoppingRepository: dependencies.shoppingRepository,
                householdID: householdID
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the dashboard reflects inventory/shopping pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
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

/// Inner content bound to a live store.
private struct DashboardContent: View {
    let store: DashboardStore
    var onSelectShopping: () -> Void
    var onSelectCategory: (String) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    /// View-local secondary stats for the entry-card subtitles (kept out of the
    /// DashboardStore to avoid widening its init): waste use-up + meal-plan summary.
    @State private var wasteStats: FoodLogStats?
    @State private var mealPlan: MealPlanGlance?
    /// Lazily-built shopping store for the 临期 preview "加购" action.
    @State private var shoppingStore: ShoppingStore?
    /// Recipe browse store (favorites + the pushed detail) for the home recipe
    /// cards. Built once with the inventory/忌口 context, like the Recipes tab.
    @State private var recipesStore: RecipesStore?
    /// 今日推荐 (top match-ranked recipe) + its matched-ingredient count.
    @State private var recommendation: Recipe?
    @State private var recommendationMatched = 0
    /// 用临期 fallback: the dish covering the most expiring items + covered names.
    @State private var fallback: FallbackSuggestion?
    /// Low-stock restock candidates (count≥3 & not in stock) for the inline card.
    @State private var lowStockItems: [FrequentItem] = []
    @State private var isAddingLowStock = false
    @State private var showLowStockConfirm = false
    /// Set once the secondary load runs, so the recipe cards can show a skeleton
    /// only on the FIRST load (not on every pull-to-refresh).
    @State private var didLoadRecipes = false
    /// Recipe selected from a home card → pushes the detail in this stack.
    @State private var selectedRecipe: Recipe?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.xl) {
                HeroSummary(summary: store.summary, categoryCount: store.categoryCounts.count)
                    .padding(.horizontal, FkSpacing.lg)

                recommendationSection
                    .padding(.horizontal, FkSpacing.lg)

                let categoryCounts = store.categoryCounts
                if !categoryCounts.isEmpty {
                    CategorySection(counts: categoryCounts, onSelect: onSelectCategory)
                        .padding(.horizontal, FkSpacing.lg)
                }

                ExpiringPreviewSection(summary: store.summary, onAddToShopping: addToShopping)
                    .padding(.horizontal, FkSpacing.lg)

                if let fallback {
                    ExpiringFallbackCard(suggestion: fallback) { selectedRecipe = fallback.recipe }
                        .padding(.horizontal, FkSpacing.lg)
                }

                MealPlanEntryRow(glance: mealPlan)
                    .padding(.horizontal, FkSpacing.lg)

                WasteInsightsEntryRow(stats: wasteStats)
                    .padding(.horizontal, FkSpacing.lg)

                if !lowStockItems.isEmpty {
                    LowStockInlineCard(
                        items: lowStockItems,
                        isAdding: isAddingLowStock,
                        onAddAll: { showLowStockConfirm = true }
                    )
                    .padding(.horizontal, FkSpacing.lg)
                }

                ShoppingSummaryRow(
                    uncheckedCount: store.summary.uncheckedShoppingCount,
                    onTap: onSelectShopping
                )
                .padding(.horizontal, FkSpacing.lg)
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .overlay(alignment: .top) { toastBanner }
        .navigationDestination(item: $selectedRecipe) { recipe in
            if let recipesStore {
                RecipeDetailView(recipe: recipe, store: recipesStore)
            }
        }
        .confirmationDialog(
            "全部加入购物清单",
            isPresented: $showLowStockConfirm,
            titleVisibility: .visible
        ) {
            Button("加入 \(lowStockItems.count) 项") { Task { await addAllLowStock() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("把 \(lowStockItems.count) 项常买缺货食材加入购物清单？")
        }
        .refreshable {
            await store.load()
            await loadSecondaryStats()
        }
        .task { await loadSecondaryStats() }
    }

    // MARK: 今日推荐

    /// The top match-ranked recipe as a tappable `RecipeCard`, with a skeleton on
    /// first load. Hidden once loaded if there's no inventory match (the Recipes
    /// tab's 现有 list covers the empty case).
    @ViewBuilder
    private var recommendationSection: some View {
        if let recommendation, let recipesStore {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "今日推荐")
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
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "今日推荐")
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
                    if !Task.isCancelled { withAnimation { self.toast = nil } }
                }
        }
    }

    /// Loads the waste use-up stats, the meal-plan glance (upcoming/today/缺料),
    /// the home recipe suggestions (今日推荐 + 用临期 fallback), the low-stock
    /// restock candidates, and the shopping store for 临期 加购.
    private func loadSecondaryStats() async {
        let wasteStore = WasteInsightsStore(repository: dependencies.foodLogRepository, householdID: dependencies.householdID)
        await wasteStore.load()
        wasteStats = wasteStore.stats()

        // Build the recipe browse store once — it owns the merged corpus + the
        // inventory/expiring match context the home cards and detail view need.
        let recipes: RecipesStore
        if let recipesStore {
            await recipesStore.load()
            recipes = recipesStore
        } else {
            recipes = RecipesStore(
                localRepository: dependencies.localRecipeRepository,
                customRepository: dependencies.customRecipeRepository,
                favoritesStore: dependencies.favoritesStore,
                householdID: dependencies.householdID,
                inventoryRepository: dependencies.inventoryRepository,
                dietaryStore: dependencies.dietaryPreferencesStore,
                dietPreferenceStore: dependencies.dietPreferenceStore
            )
            await recipes.load()
            recipesStore = recipes
        }

        // 今日推荐 = the top match-ranked recipe; 用临期 = the best expiring-cover dish.
        let available = RecipeMatching.rankedByAvailability(
            recipes.recipes, inventoryNames: recipes.inventoryNames, expiringNames: recipes.expiringNames,
            prefs: dependencies.dietPreferenceStore.selected
        )
        recommendation = available.first
        recommendationMatched = recommendation.map { recipes.matchedCount($0) } ?? 0
        fallback = RecipeMatching.expiringFallback(recipes.recipes, recipes.expiringNames)
            .map { FallbackSuggestion(recipe: $0.recipe, covered: coveredDisplayNames($0.recipe, $0.covered)) }
        didLoadRecipes = true

        // Meal-plan glance reuses the merged corpus (no second recipe decode).
        let byId = Dictionary(recipes.recipes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let entries = (try? await dependencies.mealPlanRepository.loadAllFor(dependencies.householdID)) ?? []
        let missing = MealPlanMissing.missingIngredientNames(
            entries: entries, recipesById: byId, inventoryNames: recipes.inventoryNames
        )
        mealPlan = MealPlanGlance.from(entries: entries, missingCount: missing.count)

        // Low-stock restock candidates for the inline 库存不足 card.
        let lowStock = LowStockStore(repository: dependencies.inventoryRepository, householdID: dependencies.householdID)
        await lowStock.load()
        lowStockItems = lowStock.items

        if shoppingStore == nil {
            let shopping = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: dependencies.householdID,
                syncWriter: dependencies.syncWriter
            )
            await shopping.load()
            shoppingStore = shopping
        }
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

    /// Adds ALL low-stock candidates to the shopping list (the inline "全部加入"
    /// action; per-item selection lives on the pushed `LowStockView`). Dedupe is
    /// the shopping store's job, so the toast reports the真正 added count.
    private func addAllLowStock() async {
        guard let shoppingStore, !isAddingLowStock else { return }
        isAddingLowStock = true
        defer { isAddingLowStock = false }
        var added = 0
        for item in lowStockItems {
            let category = FoodKnowledge.lookup(item.name)?.category
            if await shoppingStore.add(name: item.name, category: category) { added += 1 }
        }
        withAnimation {
            toast = added > 0 ? "已添加 \(added) 项到购物清单" : "常买缺货项已在购物清单中"
        }
    }

    private func addToShopping(_ item: Ingredient) async {
        guard let shoppingStore else { return }
        let added = await shoppingStore.add(name: item.name, category: item.category)
        withAnimation {
            toast = added ? "已将「\(item.name)」加入购物清单" : "「\(item.name)」已在购物清单中"
        }
    }
}

/// Lightweight meal-plan summary for the Dashboard entry card: dishes planned in
/// the next 7 days, how many are today, and the shortfall count. Ports
/// `mealPlanWeekSummaryProvider`.
struct MealPlanGlance: Equatable {
    let upcoming: Int
    let today: Int
    let missing: Int

    static func from(entries: [MealPlanEntry], missingCount: Int, now: Date = Date()) -> MealPlanGlance {
        let today = MealPlanEntry.dateOnly(now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        var upcoming = 0
        var todayCount = 0
        for entry in entries {
            let day = MealPlanEntry.dateOnly(entry.date)
            if day < today || day >= windowEnd { continue }
            upcoming += 1
            if day == today { todayCount += 1 }
        }
        return MealPlanGlance(upcoming: upcoming, today: todayCount, missing: missingCount)
    }
}

/// The 用临期 fallback suggestion for the Dashboard: the dish that clears the most
/// expiring items, plus the (original-cased) covered ingredient names for chips.
struct FallbackSuggestion: Equatable {
    let recipe: Recipe
    let covered: [String]
}

// MARK: - Hero

/// Tinted hero block: a headline "需要关注" count over sub-stats for 临期 and
/// 库存充足. Uses the primary brand fill with on-primary text (the blueprint's
/// hero treatment, status-bar gradient omitted as optional).
private struct HeroSummary: View {
    let summary: DashboardSummary
    /// Distinct non-empty inventory categories (covers "· N 类" next to 件食材).
    var categoryCount: Int = 0

    /// Time-of-day greeting (早安/午安/下午好/晚上好/夜深了),主厨。— ports the Flutter
    /// dashboard greeting. Computed from the local hour at render time.
    static func greeting(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let hour = calendar.component(.hour, from: now)
        let part: String
        switch hour {
        case 5..<11: part = "早安"
        case 11..<13: part = "午安"
        case 13..<18: part = "下午好"
        case 18..<23: part = "晚上好"
        default: part = "夜深了"
        }
        return "\(part)，主厨。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.lg) {
            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text(Self.greeting())
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnPrimary.opacity(0.8))

                HStack(alignment: .firstTextBaseline, spacing: FkSpacing.sm) {
                    Text("\(summary.totalItems)")
                        .font(.fkHeroStat)
                        .foregroundStyle(Color.fkOnPrimary)
                    Text("件食材")
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnPrimary.opacity(0.85))
                    if categoryCount > 0 {
                        Text("· \(categoryCount) 类")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnPrimary.opacity(0.85))
                    }
                }
            }

            HStack(spacing: FkSpacing.sm) {
                MiniStat(
                    label: "需要处理",
                    value: summary.needsAttentionCount,
                    accent: .fkWarn
                )
                .fkEntrance(index: 0)

                MiniStat(
                    label: "已过期",
                    value: summary.expiredCount,
                    accent: .fkDanger
                )
                .fkEntrance(index: 1)

                MiniStat(
                    label: "库存充足",
                    value: summary.freshCount,
                    accent: .fkOnPrimary
                )
                .fkEntrance(index: 2)
            }
        }
        .padding(FkSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.hero, style: .continuous)
                .fill(Color.fkPrimary)
        )
        .fkCardShadow()
    }
}

/// One hero sub-stat: a big accent number over a muted label, in a translucent
/// tile (mirrors the blueprint's `_MiniStat`).
private struct MiniStat: View {
    let label: String
    let value: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text("\(value)")
                .font(.fkHeroSubStat)
                .foregroundStyle(accent)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnPrimary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                .fill(Color.fkOnPrimary.opacity(0.15))
        )
    }
}

// MARK: - 食材分类 grid

/// 4-column grid of inventory categories (icon + canonical name + 件数). Tapping a
/// tile drills into the 库存 tab pre-filtered to that category. Ports the Flutter
/// `_CategorySection`/`_CategoryGrid`.
private struct CategorySection: View {
    let counts: [(category: String, count: Int)]
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FkSpacing.sm), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "食材分类")
            LazyVGrid(columns: columns, spacing: FkSpacing.sm) {
                ForEach(Array(counts.enumerated()), id: \.element.category) { index, entry in
                    Button {
                        onSelect(entry.category)
                    } label: {
                        tile(category: entry.category, count: entry.count)
                    }
                    .buttonStyle(.fkPressable)
                    .fkEntrance(index: index)
                }
            }
        }
    }

    private func tile(category: String, count: Int) -> some View {
        let palette = FkCategoryIcon.palette(for: category)
        return VStack(spacing: FkSpacing.xs) {
            ZStack {
                Circle().fill(palette.tint).frame(width: 40, height: 40)
                Image(systemName: FkCategoryIcon.symbol(for: category))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            Text(category)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(1)
            Text("\(count)")
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FkSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(Color.fkSurfaceContainerLowest)
        )
    }
}

// MARK: - 临期提醒 section

private struct ExpiringPreviewSection: View {
    let summary: DashboardSummary
    /// "该用了" quick add-to-shopping for a previewed expiring item.
    var onAddToShopping: (Ingredient) async -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "临期提醒", count: summary.needsAttentionCount)

            if summary.hasNoExpiring {
                FkCard {
                    HStack(spacing: FkSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.fkSuccess)
                        VStack(alignment: .leading, spacing: FkSpacing.xs) {
                            Text("暂无临期食材")
                                .font(.fkTitleMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text("冰箱状态健康，继续保持！")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                LazyVStack(spacing: FkSpacing.sm) {
                    ForEach(Array(summary.expiringPreview.enumerated()), id: \.element.fkListIdentityKey) { index, item in
                        FkCard {
                            HStack(spacing: FkSpacing.sm) {
                                IngredientRow(ingredient: item)
                                Button {
                                    Task { await onAddToShopping(item) }
                                } label: {
                                    Image(systemName: "cart.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.fkPrimaryContainer)
                                        .padding(8)
                                        .background(Circle().fill(Color.fkPrimarySoft))
                                }
                                .buttonStyle(.fkPressable)
                                .accessibilityLabel("加入购物清单")
                            }
                        }
                        .fkEntrance(index: index)
                    }
                }

                NavigationLink(value: DashboardRoute.expiring) {
                    HStack {
                        Text("查看全部")
                            .font(.fkLabelLarge)
                            .foregroundStyle(Color.fkPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.fkPrimary)
                    }
                    .padding(.vertical, FkSpacing.md)
                    .padding(.horizontal, FkSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .fill(Color.fkPrimarySoft)
                    )
                }
                .buttonStyle(.fkPressable)
            }
        }
    }
}

// MARK: - 膳食计划 entry

/// Tappable card that pushes `MealPlanView` (the weekly meal-plan calendar) via
/// the Dashboard's `DashboardRoute`. The only meal-plan touchpoint on 首页.
private struct MealPlanEntryRow: View {
    /// nil → static copy until the glance loads; non-nil drives the dynamic
    /// "本周已排 N 顿 · 今天 M 顿" subtitle + a "还缺 K 样" badge.
    var glance: MealPlanGlance?

    var body: some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("膳食计划")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text(subtitle)
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    if let glance, glance.missing > 0 {
                        Text("还缺 \(glance.missing) 样")
                            .font(.fkLabelSmall)
                            .foregroundStyle(Color.fkDanger)
                            .padding(.horizontal, FkSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.fkWarnSoft))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var subtitle: String {
        guard let glance, glance.upcoming > 0 else { return "规划这一周吃什么" }
        if glance.today > 0 {
            return "本周已排 \(glance.upcoming) 顿 · 今天 \(glance.today) 顿"
        }
        return "本周已排 \(glance.upcoming) 顿"
    }
}

// MARK: - 减废统计 entry

/// Tappable card that pushes `WasteInsightsView` (the waste-reduction stats
/// screen) via the Dashboard's `DashboardRoute`. Mirrors `MealPlanEntryRow`.
private struct WasteInsightsEntryRow: View {
    /// nil → static copy until stats load; non-nil drives the "用掉率 X%" subtitle
    /// + a "抢救 N" badge.
    var stats: FoodLogStats?

    var body: some View {
        NavigationLink(value: DashboardRoute.wasteInsights) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("减废统计")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text(subtitle)
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    if let stats, stats.rescued > 0 {
                        Text("抢救 \(stats.rescued)")
                            .font(.fkLabelSmall)
                            .foregroundStyle(Color.fkSuccess)
                            .padding(.horizontal, FkSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.fkSuccess.opacity(0.15)))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var subtitle: String {
        guard let stats, !stats.isEmpty else { return "看看你的食材用掉率" }
        return "本月用掉率 \(stats.useUpPercent)%"
    }
}

// MARK: - 库存不足 (inline preview + 全部加购)

/// The 库存不足 card with an INLINE preview of the top restock candidates and a
/// "全部加入购物清单 (N)" bulk action — ports the Flutter `low_stock_card` so the
/// user can restock from 首页 without first drilling into `LowStockView`. The
/// header still navigates to `LowStockView` for per-item selection.
private struct LowStockInlineCard: View {
    let items: [FrequentItem]
    let isAdding: Bool
    /// Opens the confirm dialog for the bulk add (the parent owns the dialog).
    let onAddAll: () -> Void

    /// At most 4 inline rows; the rest collapse into a "+还有 N 项" line.
    private var previewItems: [FrequentItem] { Array(items.prefix(4)) }
    private var overflow: Int { max(0, items.count - previewItems.count) }

    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                NavigationLink(value: DashboardRoute.lowStock) {
                    HStack(spacing: FkSpacing.md) {
                        ZStack {
                            Circle().fill(Color.fkPrimarySoft).frame(width: 44, height: 44)
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.fkPrimaryContainer)
                        }
                        VStack(alignment: .leading, spacing: FkSpacing.xs) {
                            Text("库存不足")
                                .font(.fkTitleMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text("\(items.count) 项常买缺货")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                        Spacer(minLength: FkSpacing.sm)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                }
                .buttonStyle(.fkPressable)

                VStack(spacing: FkSpacing.xs) {
                    ForEach(previewItems, id: \.name) { item in
                        HStack(spacing: FkSpacing.sm) {
                            FkCategoryAvatar(imageUrl: "", category: item.category, size: 28)
                            Text(item.name)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Spacer(minLength: 0)
                            Text("买过 \(item.count) 次")
                                .font(.fkLabelSmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                    }
                    if overflow > 0 {
                        HStack {
                            Text("+还有 \(overflow) 项")
                                .font(.fkLabelSmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                            Spacer(minLength: 0)
                        }
                    }
                }

                Button(action: onAddAll) {
                    HStack(spacing: FkSpacing.sm) {
                        if isAdding {
                            ProgressView().controlSize(.small).tint(Color.fkOnPrimary)
                        } else {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isAdding ? "加入中…" : "全部加入购物清单 (\(items.count))")
                            .font(.fkLabelLarge)
                    }
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FkSpacing.md)
                    .background(Capsule().fill(Color.fkPrimary))
                }
                .buttonStyle(.fkPressable)
                .disabled(isAdding)
            }
        }
    }
}

// MARK: - 用临期 fallback recipe card

/// "用这些临期食材今天就能做" — a tappable card surfacing the single dish that
/// clears the most expiring items, with covered-ingredient chips. Ports the
/// Flutter `ExpiringFallbackCard`; taps push the recipe detail.
private struct ExpiringFallbackCard: View {
    let suggestion: FallbackSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FkCard {
                VStack(alignment: .leading, spacing: FkSpacing.sm) {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.fkDanger)
                        Text("用临期食材 · 今天就能做")
                            .font(.fkLabelLarge)
                            .foregroundStyle(Color.fkDanger)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                    Text(suggestion.recipe.name)
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnSurface)
                    Text("可用 \(suggestion.covered.count) 件临期食材")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    if !suggestion.covered.isEmpty {
                        HStack(spacing: FkSpacing.xs) {
                            ForEach(suggestion.covered.prefix(3), id: \.self) { name in
                                Text(name)
                                    .font(.fkLabelSmall)
                                    .foregroundStyle(Color.fkOnSurface)
                                    .padding(.horizontal, FkSpacing.sm)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.fkWarnSoft))
                            }
                            Spacer(minLength: 0)
                        }
                    }
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
        .accessibilityLabel("加载推荐中")
    }
}

// MARK: - 购物清单 summary

/// Summary row that switches to the 购物 tab. Shows the unchecked count.
private struct ShoppingSummaryRow: View {
    let uncheckedCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("购物清单")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text(subtitle)
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var subtitle: String {
        uncheckedCount > 0 ? "还有 \(uncheckedCount) 项待购买" : "清单已全部完成"
    }
}
