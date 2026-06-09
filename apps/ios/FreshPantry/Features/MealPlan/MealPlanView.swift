import SwiftUI

/// The 膳食计划 screen: a weekly calendar (Mon → Sun strip) over the selected
/// day's planned dishes. Pushed from the Dashboard (首页) — lives inside the
/// host `NavigationStack`, so it owns no stack of its own.
///
/// Builds its `MealPlanStore` from the injected `AppDependencies` (the reusable
/// feature pattern). In DEBUG it runs `MealPlanSeeder` (seed-then-load, same
/// idempotent one-shot the other tabs use) before loading, so the screen has
/// data even when opened first. SwiftData is never touched here.
struct MealPlanView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: MealPlanStore?

    var body: some View {
        Group {
            if let store {
                MealPlanContent(store: store, dependencies: dependencies)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle("膳食计划")
        .navigationBarTitleDisplayMode(.inline)
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the calendar re-scopes to the new household rather
        // than keeping the prior scope's stale entries.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's entries come from sync, never the seeder.
            if householdID.isEmpty {
                await MealPlanSeeder.seedIfNeeded(
                    repository: dependencies.mealPlanRepository,
                    recipeRepository: dependencies.localRecipeRepository,
                    householdID: householdID
                )
            }
            #endif
            let store = MealPlanStore(
                repository: dependencies.mealPlanRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so meal-plan entries pulled from other household members show up.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store.
private struct MealPlanContent: View {
    let store: MealPlanStore
    let dependencies: AppDependencies

    @State private var showingPicker = false
    /// Recipe corpus (id → recipe) + inventory names, for the 缺料 shortfall card.
    @State private var recipesById: [String: Recipe] = [:]
    @State private var inventoryNames: Set<String> = []
    @State private var shoppingStore: ShoppingStore?
    @State private var isAddingMissing = false
    @State private var toast: String?

    private var missingNames: [String] {
        MealPlanMissing.missingIngredientNames(
            entries: store.entries,
            recipesById: recipesById,
            inventoryNames: inventoryNames
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.lg) {
                if !missingNames.isEmpty {
                    missingIngredientsCard
                        .padding(.horizontal, FkSpacing.lg)
                }

                WeekStrip(store: store)
                    .padding(.horizontal, FkSpacing.lg)

                dayHeader
                    .padding(.horizontal, FkSpacing.lg)

                dayBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .refreshable {
            await store.load()
            await reloadMatchContext()
        }
        .overlay(alignment: .top) { toastBanner }
        .task { await reloadMatchContext() }
        .sheet(isPresented: $showingPicker) {
            RecipePickerSheet(
                dependencies: dependencies,
                onPick: { recipe in
                    Task {
                        await store.addDish(recipe: recipe, date: store.selectedDay)
                        await reloadMatchContext()
                    }
                }
            )
        }
    }

    /// "本周还缺 N 样食材 · 一键加入购物清单" — adds every shortfall ingredient to
    /// the shopping list (name-unique dedup). Mirrors the Flutter `mp-missing` card.
    private var missingIngredientsCard: some View {
        Button {
            Task { await addMissingToShopping() }
        } label: {
            HStack(spacing: FkSpacing.md) {
                ZStack {
                    Circle().fill(Color.fkPrimarySoft).frame(width: 44, height: 44)
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.fkPrimaryContainer)
                }
                VStack(alignment: .leading, spacing: FkSpacing.xs) {
                    Text("本周还缺 \(missingNames.count) 样食材")
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnSurface)
                    Text(isAddingMissing ? "加入中…" : "一键加入购物清单")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Spacer(minLength: FkSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .padding(FkSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerLowest)
            )
            .fkCardShadow()
        }
        .buttonStyle(.fkPressable)
        .disabled(isAddingMissing)
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

    /// Loads the recipe corpus (bundled + custom), the inventory match names, and
    /// the shopping store so the 缺料 card can compute + act.
    private func reloadMatchContext() async {
        let bundled = await dependencies.localRecipeRepository.loadAll()
        let custom = (try? await dependencies.customRecipeRepository.loadAllFor(dependencies.householdID)) ?? []
        var byId: [String: Recipe] = [:]
        for recipe in bundled { byId[recipe.id] = recipe }
        for recipe in custom { byId[recipe.id] = recipe } // custom wins
        recipesById = byId
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        inventoryNames = RecipeMatching.inventoryNameSet(inventory)
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

    private func addMissingToShopping() async {
        guard !isAddingMissing, let shoppingStore else { return }
        isAddingMissing = true
        defer { isAddingMissing = false }
        var added = 0
        for name in missingNames {
            let category = FoodKnowledge.lookup(name)?.category
            if await shoppingStore.add(name: name, category: category) { added += 1 }
        }
        withAnimation {
            toast = added > 0 ? "已加入 \(added) 样食材到购物清单" : "缺的食材都已在购物清单中"
        }
    }

    // MARK: Day header (selected date + 添加菜品)

    private var dayHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: FkSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MealPlanFormat.dayTitle(store.selectedDay))
                    .font(.fkTitleLarge)
                    .foregroundStyle(Color.fkOnSurface)
                Text(MealPlanFormat.dishSummary(store.dishCount(forDay: store.selectedDay)))
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer(minLength: FkSpacing.sm)
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("添加菜品")
                        .font(.fkLabelMedium)
                }
                .foregroundStyle(Color.fkOnPrimary)
                .padding(.horizontal, FkSpacing.md)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.fkPrimary))
            }
            .buttonStyle(.fkPressable)
        }
    }

    // MARK: Day body (planned dishes or empty state)

    @ViewBuilder
    private var dayBody: some View {
        let dishes = store.selectedDayEntries
        if store.isLoading && !store.hasLoaded {
            ProgressView()
                .padding(.top, 80)
        } else if dishes.isEmpty {
            FkEmptyState(
                systemImage: "fork.knife",
                title: "这天还没有计划",
                message: "点「添加菜品」安排今天吃什么"
            )
            .padding(.top, FkSpacing.md)
        } else {
            LazyVStack(spacing: FkSpacing.sm) {
                ForEach(Array(dishes.enumerated()), id: \.element.id) { index, entry in
                    MealPlanDishRow(
                        entry: entry,
                        onToggleDone: { Task { await store.toggleDone(entry) } }
                    )
                    .fkEntrance(index: index)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await store.remove(entry) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }
}

// MARK: - Week strip

/// Horizontal 7-day strip (Mon → Sun). Each cell shows the weekday + day number,
/// highlights today and the selected day, and dots the days that have dishes.
private struct WeekStrip: View {
    let store: MealPlanStore

    var body: some View {
        VStack(spacing: FkSpacing.md) {
            header
            HStack(spacing: FkSpacing.xs) {
                ForEach(store.weekDays, id: \.self) { day in
                    DayCell(
                        day: day,
                        isSelected: MealPlanFormat.sameDay(day, store.selectedDay),
                        isToday: MealPlanFormat.isToday(day),
                        dishCount: store.dishCount(forDay: day),
                        onTap: { store.select(day) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: FkSpacing.sm) {
            navButton(systemImage: "chevron.left", accessibility: "上一周") {
                store.goToPreviousWeek()
            }
            Spacer(minLength: 0)
            Text(MealPlanFormat.weekRange(store.weekDays))
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
            navButton(systemImage: "chevron.right", accessibility: "下一周") {
                store.goToNextWeek()
            }
        }
    }

    private func navButton(systemImage: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fkPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .accessibilityLabel(accessibility)
    }
}

/// One day cell in the week strip.
private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let dishCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: FkSpacing.xs) {
                Text(MealPlanFormat.weekdayShort(day))
                    .font(.fkLabelSmall)
                    .foregroundStyle(weekdayColor)
                Text(MealPlanFormat.dayNumber(day))
                    .font(.fkTitleMedium)
                    .foregroundStyle(numberColor)
                Circle()
                    .fill(dishCount > 0 ? dotColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FkSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(isSelected ? Color.fkPrimary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                            .strokeBorder(
                                (isToday && !isSelected) ? Color.fkPrimary : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.fkPressable)
        .accessibilityLabel(MealPlanFormat.cellAccessibility(day, dishCount: dishCount, isToday: isToday))
    }

    private var weekdayColor: Color {
        isSelected ? Color.fkOnPrimary.opacity(0.85) : Color.fkOnSurfaceVariant
    }

    private var numberColor: Color {
        if isSelected { return Color.fkOnPrimary }
        return isToday ? Color.fkPrimary : Color.fkOnSurface
    }

    private var dotColor: Color {
        isSelected ? Color.fkOnPrimary : Color.fkPrimary
    }
}

// MARK: - Dish row

/// One planned dish: cover (recipe image or category glyph), name, "N 份"
/// servings, and a done-toggle checkmark. Tapping the checkmark flips done.
private struct MealPlanDishRow: View {
    let entry: MealPlanEntry
    let onToggleDone: () -> Void

    var body: some View {
        FkCard(padding: FkSpacing.md) {
            HStack(spacing: FkSpacing.md) {
                cover
                VStack(alignment: .leading, spacing: FkSpacing.xs) {
                    Text(entry.recipeName)
                        .font(.fkTitleMedium)
                        .foregroundStyle(entry.done ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                        .strikethrough(entry.done, color: Color.fkOnSurfaceVariant)
                        .lineLimit(2)
                    Text("\(entry.servings) 份")
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Spacer(minLength: FkSpacing.sm)
                doneToggle
            }
        }
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
            .fill(Color.fkPrimarySoft)
            .frame(width: 52, height: 52)
            .overlay { coverImage }
            .clipShape(RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous))
    }

    private var coverImage: some View {
        RecipeImage(source: entry.recipeImageUrl) { glyph }
    }

    private var glyph: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.fkPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneToggle: some View {
        Button(action: onToggleDone) {
            Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(entry.done ? Color.fkSuccess : Color.fkOutline)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.done ? "标记为未完成" : "标记为已完成")
    }
}

// MARK: - Recipe picker sheet

/// Searchable list of bundled + custom recipes. Tapping one plans it on the
/// selected day (servings default 1) and dismisses. Reuses `RecipesStore` so the
/// merged corpus + search predicate are not duplicated.
private struct RecipePickerSheet: View {
    let dependencies: AppDependencies
    let onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store: RecipesStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    PickerList(store: store, onPick: { recipe in
                        onPick(recipe)
                        dismiss()
                    })
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("选择菜品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task {
            if store == nil {
                let store = RecipesStore(
                    localRepository: dependencies.localRecipeRepository,
                    customRepository: dependencies.customRecipeRepository,
                    favoritesStore: dependencies.favoritesStore,
                    householdID: dependencies.householdID
                )
                self.store = store
                await store.load()
            }
        }
    }
}

/// The bound picker list (split out so `@Bindable` drives the search field).
private struct PickerList: View {
    @Bindable var store: RecipesStore
    let onPick: (Recipe) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.md) {
                FkSearchField(text: $store.searchQuery, placeholder: "搜索菜谱或食材")
                    .padding(.horizontal, FkSpacing.lg)

                listBody
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var listBody: some View {
        let recipes = store.displayRecipes
        if store.isLoading && !store.hasLoaded {
            ProgressView().padding(.top, 80)
        } else if recipes.isEmpty {
            FkEmptyState(
                systemImage: "magnifyingglass",
                title: store.searchQuery.trimmed.isEmpty ? "暂无可选的菜谱" : "没有匹配的菜谱",
                message: store.searchQuery.trimmed.isEmpty ? nil : "试试换个关键词"
            )
            .padding(.top, FkSpacing.huge)
        } else {
            LazyVStack(spacing: FkSpacing.md) {
                ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                    Button {
                        onPick(recipe)
                    } label: {
                        RecipeCard(
                            recipe: recipe,
                            isFavorite: store.isFavorite(recipe),
                            onToggleFavorite: { store.toggleFavorite(recipe) }
                        )
                    }
                    .buttonStyle(.fkPressable)
                    .fkEntrance(index: index)
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }
}

// MARK: - Formatting helpers

/// Pure date/string formatters for the calendar UI, kept off the view so they
/// can be exercised in isolation. All local-time, locale-aware where it reads
/// naturally (weekday names) and fixed where parity matters (day numbers).
enum MealPlanFormat {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static func sameDay(_ a: Date, _ b: Date) -> Bool {
        MealPlanEntry.dateKey(a) == MealPlanEntry.dateKey(b)
    }

    static func isToday(_ day: Date) -> Bool {
        sameDay(day, Date())
    }

    /// Short weekday label (周一 … 周日).
    static func weekdayShort(_ day: Date) -> String {
        let weekday = calendar.component(.weekday, from: day) // 1=Sun … 7=Sat
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[(weekday - 1) % 7]
    }

    static func dayNumber(_ day: Date) -> String {
        "\(calendar.component(.day, from: day))"
    }

    /// "M月 d日 周X" for the selected-day header, with a 今天 prefix on today.
    static func dayTitle(_ day: Date) -> String {
        let month = calendar.component(.month, from: day)
        let date = calendar.component(.day, from: day)
        let core = "\(month)月\(date)日 \(weekdayShort(day))"
        return isToday(day) ? "今天 · \(core)" : core
    }

    /// "M月d日 - M月d日" range across the visible week's first/last day.
    static func weekRange(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let fm = calendar.component(.month, from: first)
        let fd = calendar.component(.day, from: first)
        let lm = calendar.component(.month, from: last)
        let ld = calendar.component(.day, from: last)
        return "\(fm)月\(fd)日 - \(lm)月\(ld)日"
    }

    static func dishSummary(_ count: Int) -> String {
        count > 0 ? "已计划 \(count) 道菜" : "暂无计划"
    }

    static func cellAccessibility(_ day: Date, dishCount: Int, isToday: Bool) -> String {
        let base = "\(weekdayShort(day)) \(dayNumber(day))日"
        let todayTag = isToday ? "，今天" : ""
        let dishes = dishCount > 0 ? "，\(dishCount) 道菜" : ""
        return base + todayTag + dishes
    }
}
