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
            if !dependencies.proStore.isPro {
                ProLockedView(featureName: String(localized: "mealPlan.weeklyPlan"), proStore: dependencies.proStore)
            } else if let store {
                MealPlanContent(store: store, dependencies: dependencies)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle(String(localized: "mealPlan.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dependencies.proStore.isPro, let store {
                ToolbarItem(placement: .topBarTrailing) {
                    MealPlanTemplateMenu(store: store)
                }
            }
        }
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the calendar re-scopes to the new household rather
        // than keeping the prior scope's stale entries.
        .task(id: dependencies.householdID) {
            await loadStore()
        }
        .onChange(of: dependencies.proStore.isPro) {
            Task { await loadStore() }
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so meal-plan entries pulled from other household members show up.
        .onChange(of: dependencies.syncSession.dataRevision) {
            if dependencies.proStore.isPro {
                Task { await store?.load() }
            }
        }
    }

    private func loadStore() async {
        guard dependencies.proStore.isPro else {
            store = nil
            return
        }

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
        // The seeder await above is a suspension point: a household switch
        // landing there (login "" → uuid auto-select) starts a NEW run, and
        // this stale run must not assign an old-scope store over its work.
        guard householdID == dependencies.householdID, !Task.isCancelled else { return }
        let store = MealPlanStore(
            repository: dependencies.mealPlanRepository,
            householdID: householdID,
            syncWriter: dependencies.syncWriter,
            cookHistoryRepository: dependencies.cookHistoryRepository
        )
        // OFFLINE-FIRST, NO FLASH: load the new scope's local entries BEFORE
        // swapping the store in, so a household switch keeps the previous
        // calendar on screen until the new (local, instant) data is ready
        // instead of flashing an empty week. Re-guard after the load so a newer
        // switch landing here doesn't assign this stale scope's store.
        await store.load()
        guard householdID == dependencies.householdID, !Task.isCancelled else { return }
        self.store = store
    }
}

/// Inner content bound to a live store.
private struct MealPlanContent: View {
    let store: MealPlanStore
    let dependencies: AppDependencies

    @State private var showingPicker = false
    @State private var showNoteInput = false
    @State private var noteText = ""
    /// Recipe corpus (id → recipe) + inventory names, for the 缺料 shortfall card.
    @State private var recipesById: [String: Recipe] = [:]
    @State private var inventoryNames: Set<String> = []
    @State private var shoppingStore: ShoppingStore?
    /// Browse store backing the pushed `RecipeDetailView` (favorite state etc.).
    @State private var recipesStore: RecipesStore?
    /// Row-tap target — pushes the resolved recipe's detail.
    @State private var selectedRecipe: Recipe?
    /// Set when a dish is marked done and its recipe still resolves — drives the
    /// skippable 「顺便扣减库存?」 prompt, then the review sheet.
    @State private var deductCandidate: PlanDeductionCandidate?
    @State private var showDeductPrompt = false
    @State private var cookSession: PlanCookSession?
    /// The household the lazily-built stores were scoped to — they are dropped
    /// and rebuilt when it changes (login/switch/leave must not write old scope).
    @State private var matchContextScope: String?
    @State private var isAddingMissing = false
    @State private var toast: String?
    /// The dish being rescheduled — drives the move-to-another-day sheet.
    @State private var reschedulingEntry: ReschedulingEntry?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 缺料 over the VISIBLE week only — the card sits above the week strip, so
    /// its count must match what the strip shows (a stale past week's pending
    /// dishes must not inflate it).
    private var missingNames: [String] {
        MealPlanMissing.missingIngredientNames(
            entries: store.entriesInVisibleWeek,
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
        // The match context is household-scoped: on a household switch the
        // lazily-built stores must be dropped, or 一键加购 keeps writing into the
        // prior scope's shopping list. (Re-appear also lands here, which doubles
        // as the refresh after cooking/deducting in a pushed detail.)
        .task(id: dependencies.householdID) {
            if matchContextScope != dependencies.householdID {
                shoppingStore = nil
                recipesStore = nil
                matchContextScope = dependencies.householdID
            }
            await reloadMatchContext()
        }
        // Remote merge pulse: recipes/inventory may have changed under us —
        // recompute the match context so the 缺料 card tracks merged data.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await reloadMatchContext() }
        }
        .navigationDestination(item: $selectedRecipe) { recipe in
            if let recipesStore {
                RecipeDetailView(recipe: recipe, store: recipesStore)
            }
        }
        .sheet(isPresented: $showingPicker) {
            RecipePickerSheet(
                dependencies: dependencies,
                onPick: { recipe in
                    Task {
                        if await store.addDish(recipe: recipe, date: store.selectedDay) {
                            await reloadMatchContext()
                        } else {
                            showToast(String(localized: "mealPlan.addDishFailed"))
                        }
                    }
                }
            )
        }
        .alert(String(localized: "mealPlan.addNote"), isPresented: $showNoteInput) {
            TextField(String(localized: "mealPlan.notePlaceholder"), text: $noteText)
            Button(String(localized: "mealPlan.cancel"), role: .cancel) {}
            Button(String(localized: "mealPlan.add")) {
                Task {
                    if !(await store.addNote(title: noteText, date: store.selectedDay)) {
                        showToast(String(localized: "mealPlan.noteEmpty"))
                    }
                }
            }
        } message: {
            Text(String(localized: "mealPlan.noteHint"))
        }
        // Completing a dish whose recipe still resolves offers a skippable
        // cook-time deduction — the same factory + review the detail 「做菜」 CTA
        // uses — so cooking off the plan also lands in inventory + FoodLog.
        .confirmationDialog(
            String(localized: "mealPlan.deductPrompt"),
            isPresented: $showDeductPrompt,
            titleVisibility: .visible,
            presenting: deductCandidate
        ) { candidate in
            Button(String(localized: "mealPlan.deductStock")) { Task { await presentDeduction(candidate) } }
            Button(String(localized: "mealPlan.skip"), role: .cancel) {}
        } message: { candidate in
            Text(String(localized: "mealPlan.deductHint \(candidate.recipe.name)"))
        }
        .sheet(item: $cookSession) { session in
            NavigationStack {
                DeductionReviewView(proposals: session.proposals) { outcome in
                    // Apply landed → inventory changed; recompute the 缺料 card.
                    if outcome.affectedCount > 0 {
                        showToast(String(localized: "mealPlan.deductedItems \(outcome.affectedCount)"))
                    }
                    Task { await reloadMatchContext() }
                }
            }
        }
        .sheet(item: $reschedulingEntry) { wrapper in
            MovePlanEntrySheet(entry: wrapper.entry) { newDate in
                Task {
                    if !(await store.moveDish(wrapper.entry, to: newDate)) {
                        showToast(String(localized: "mealPlan.moveFailed"))
                    }
                }
            }
        }
    }

    /// "还缺 N 样食材 · 一键加入购物清单" (visible-week scope) — adds every shortfall
    /// ingredient to the shopping list (name-unique dedup). Mirrors the Flutter
    /// `mp-missing` card.
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
                    Text(MealPlanMissing.cardTitle(count: missingNames.count, isCurrentWeek: store.isShowingWeek()))
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnSurface)
                    Text(isAddingMissing ? String(localized: "mealPlan.adding") : shoppingStore == nil ? String(localized: "mealPlan.loading") : String(localized: "mealPlan.addAllToShopping"))
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
        .disabled(isAddingMissing || shoppingStore == nil)
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

    /// Loads the recipe corpus (bundled + custom), the inventory match names, and
    /// the lazily-built shopping/browse stores the 缺料 card + pushed detail need.
    /// Safe to re-run: existing stores are reloaded rather than rebuilt.
    ///
    /// SCOPE GUARD: every await below is a suspension point where a household
    /// switch can land (login "" → uuid auto-select, switch, leave). A stale
    /// run resuming afterwards must NOT assign state built for the old scope —
    /// the new run's `== nil` lazy-build has already run, so a stale store
    /// would stick (the `matchContextScope` sentinel matches and never fires
    /// again) and 一键加购 would write into the prior household's list. The
    /// stores swallow `CancellationError` into empty results, so cancellation
    /// alone does not stop a stale run — re-check after EVERY await, before
    /// EVERY assignment.
    private func reloadMatchContext() async {
        let scope = dependencies.householdID
        let bundled = RecipeLocalizer.apply(
            RecipeLocalizer.load(),
            to: await dependencies.localRecipeRepository.loadAll()
        )
        let custom = (try? await dependencies.customRecipeRepository.loadAllFor(scope)) ?? []
        guard scope == dependencies.householdID, !Task.isCancelled else { return }
        var byId: [String: Recipe] = [:]
        for recipe in bundled { byId[recipe.id] = recipe }
        for recipe in custom { byId[recipe.id] = recipe } // custom wins
        recipesById = byId
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(scope)) ?? []
        guard scope == dependencies.householdID, !Task.isCancelled else { return }
        inventoryNames = RecipeMatching.availableInventoryNameSet(inventory)
        if let shoppingStore {
            await shoppingStore.load()
        } else {
            let shopping = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: scope,
                syncWriter: dependencies.syncWriter
            )
            await shopping.load()
            guard scope == dependencies.householdID, !Task.isCancelled else { return }
            shoppingStore = shopping
        }
        if let recipesStore {
            await recipesStore.load()
        } else {
            let recipes = RecipesStore(
                localRepository: dependencies.localRecipeRepository,
                customRepository: dependencies.customRecipeRepository,
                favoritesStore: dependencies.favoritesStore,
                householdID: scope,
                remoteCatalog: dependencies.remoteRecipeCatalog,
                catalogCache: dependencies.recipeCatalogCache
            )
            await recipes.load()
            guard scope == dependencies.householdID, !Task.isCancelled else { return }
            recipesStore = recipes
        }
    }

    private func addMissingToShopping() async {
        guard !isAddingMissing, let shoppingStore else { return }
        isAddingMissing = true
        defer { isAddingMissing = false }
        var added = 0
        var failed = 0
        for name in missingNames {
            let category = FoodKnowledge.lookup(name)?.category
            switch await shoppingStore.addItem(name: name, category: category) {
            case .added: added += 1
            case .duplicate: break // already on the list — goal satisfied
            case .failed: failed += 1
            }
        }
        // A persist failure must never read as the affirmative「已在购物清单中」.
        if failed > 0 {
            showToast(added > 0
                ? String(localized: "mealPlan.addedPartialFailed \(added) \(failed)")
                : String(localized: "mealPlan.addFailed"))
        } else {
            showToast(added > 0
                ? String(localized: "mealPlan.addedToShopping \(added)")
                : String(localized: "mealPlan.missingAlreadyInShopping"))
        }
    }

    /// Flips `done` (surfacing a persist failure — the screen otherwise gives no
    /// hint the tap didn't land), then offers the cook-time deduction when the
    /// dish was just completed and its recipe still resolves.
    private func toggleDone(_ entry: MealPlanEntry) async {
        let completing = !entry.done
        guard await store.toggleDone(entry) else {
            showToast(String(localized: "mealPlan.updateFailed"))
            return
        }
        if completing, let recipe = MealPlanStore.deductionCandidate(for: entry, recipesById: recipesById) {
            deductCandidate = PlanDeductionCandidate(recipe: recipe, servings: entry.servings)
            showDeductPrompt = true
        }
    }

    /// Builds deduction proposals against the live inventory and raises the
    /// review sheet (mirrors `RecipeDetailView.presentCook`, including 份数 scaling).
    private func presentDeduction(_ candidate: PlanDeductionCandidate) async {
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        let scaled: Recipe
        if candidate.servings == 1 {
            scaled = candidate.recipe
        } else {
            let factor = Double(candidate.servings)
            scaled = candidate.recipe.copyWith(
                ingredients: candidate.recipe.ingredients.map { $0.scaledBy(factor) }
            )
        }
        cookSession = PlanCookSession(proposals: DeductionProposalFactory.forRecipe(scaled, inventory))
    }

    private func showToast(_ message: String) {
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = message
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
            Menu {
                Button {
                    showingPicker = true
                } label: {
                    Label(String(localized: "mealPlan.addRecipe"), systemImage: "fork.knife")
                }
                Button {
                    noteText = ""
                    showNoteInput = true
                } label: {
                    Label(String(localized: "mealPlan.addNote"), systemImage: "note.text")
                }
            } label: {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(String(localized: "mealPlan.add"))
                        .font(.fkLabelMedium)
                }
                .foregroundStyle(Color.fkOnPrimary)
                .padding(.horizontal, FkSpacing.md)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.fkPrimary))
            }
            .buttonStyle(.fkPressable)
            .accessibilityLabel(String(localized: "mealPlan.addRecipeOrNote"))
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
                title: String(localized: "mealPlan.emptyDayTitle"),
                message: String(localized: "mealPlan.emptyDayMessage")
            )
            .padding(.top, FkSpacing.md)
        } else {
            LazyVStack(spacing: FkSpacing.sm) {
                ForEach(Array(dishes.enumerated()), id: \.element.id) { index, entry in
                    // Row → detail only when the recipeId still resolves (same
                    // lookup the 缺料 derivation uses); otherwise untappable.
                    let recipe = recipesById[entry.recipeId]
                    let canOpen = recipe != nil && recipesStore != nil
                    MealPlanDishRow(
                        entry: entry,
                        onToggleDone: { Task { await toggleDone(entry) } },
                        onOpen: canOpen ? { selectedRecipe = recipe } : nil
                    )
                    .fkEntrance(index: index)
                    // Long-press → 删除. NOT swipeActions: that modifier only
                    // works on List rows and is a silent no-op inside this
                    // ScrollView/LazyVStack — this is the screen's ONLY delete
                    // path, so it must be a control that actually renders.
                    .contextMenu {
                        Button {
                            reschedulingEntry = ReschedulingEntry(entry: entry)
                        } label: {
                            Label(String(localized: "mealPlan.moveToOtherDate"), systemImage: "calendar")
                        }
                        Button(role: .destructive) {
                            Task {
                                if !(await store.remove(entry)) {
                                    showToast(String(localized: "mealPlan.deleteFailed"))
                                }
                            }
                        } label: {
                            Label(String(localized: "mealPlan.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .fkEntranceWindow()
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
            navButton(systemImage: "chevron.left", accessibility: String(localized: "mealPlan.previousWeek")) {
                store.goToPreviousWeek()
            }
            Spacer(minLength: 0)
            Text(MealPlanFormat.weekRange(store.weekDays))
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
            if !store.isShowingWeek() {
                todayButton
            }
            navButton(systemImage: "chevron.right", accessibility: String(localized: "mealPlan.nextWeek")) {
                store.goToNextWeek()
            }
        }
    }

    /// 「今天」 jump-back pill — rendered only while today's week is off-screen
    /// (inside the current week the strip's outlined today cell is the anchor).
    private var todayButton: some View {
        Button {
            store.goToToday()
        } label: {
            Text(String(localized: "mealPlan.today"))
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkPrimary)
                .padding(.horizontal, FkSpacing.md)
                .frame(height: 36)
                .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .accessibilityLabel(String(localized: "mealPlan.backToToday"))
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
/// servings, and a done-toggle checkmark. Tapping the checkmark flips done;
/// tapping the rest of the row opens the recipe detail when it still resolves.
private struct MealPlanDishRow: View {
    let entry: MealPlanEntry
    let onToggleDone: () -> Void
    /// nil when the entry's recipeId no longer matches the corpus — the row then
    /// renders untappable rather than pushing a dead detail.
    var onOpen: (() -> Void)?

    var body: some View {
        if let onOpen {
            // The nested done-toggle Button keeps its own tap (the RecipeCard-in-
            // Button pattern the picker list already relies on).
            Button(action: onOpen) { card }
                .buttonStyle(.fkPressable)
        } else {
            card
        }
    }

    private var card: some View {
        FkCard(padding: FkSpacing.md) {
            HStack(spacing: FkSpacing.md) {
                cover
                VStack(alignment: .leading, spacing: FkSpacing.xs) {
                    Text(entry.displayTitle)
                        .font(.fkTitleMedium)
                        .foregroundStyle(entry.done ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                        .strikethrough(entry.done, color: Color.fkOnSurfaceVariant)
                        .lineLimit(2)
                    HStack(spacing: FkSpacing.xs) {
                        if let mealType = entry.mealType, !mealType.isEmpty {
                            tag(mealType, color: .fkPrimary)
                        }
                        if entry.isLeftover { tag(String(localized: "mealPlan.leftover"), color: .fkWarn) }
                        if entry.isNote {
                            tag(String(localized: "mealPlan.note"), color: .fkOnSurfaceVariant)
                        } else {
                            Text(String(localized: "mealPlan.servings \(entry.servings)"))
                                .font(.fkLabelSmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                    }
                }
                Spacer(minLength: FkSpacing.sm)
                doneToggle
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.fkLabelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, FkSpacing.xs)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
            .fill(Color.fkPrimarySoft)
            .frame(width: 52, height: 52)
            .overlay { coverImage }
            .clipShape(RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous))
    }

    private var coverImage: some View {
        // 52pt cover glyph — decode small, not at the 900px hero default.
        RecipeImage(source: entry.recipeImageUrl, maxPixel: 208) { glyph }
    }

    private var glyph: some View {
        Image(systemName: entry.isNote ? "note.text" : "fork.knife")
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
        .accessibilityLabel(entry.done ? String(localized: "mealPlan.markUndone") : String(localized: "mealPlan.markDone"))
    }
}

/// Recipe + planned servings captured when a dish is marked done — the deduction
/// prompt must scale proposals by the entry's 份数, not always 1×.
private struct PlanDeductionCandidate: Identifiable {
    let recipe: Recipe
    let servings: Int
    var id: String { recipe.id }
}

/// Identifiable wrapper so the move-to-another-day sheet can be driven by
/// `.sheet(item:)` (MealPlanEntry itself isn't Identifiable).
private struct ReschedulingEntry: Identifiable {
    let entry: MealPlanEntry
    var id: String { entry.id }
}

/// Date-picker sheet for rescheduling a planned dish to another day. Seeds the
/// picker from the entry's current day; "移动" forwards the chosen date to
/// `MealPlanStore.moveDish` (a same-day pick is a harmless no-op there).
private struct MovePlanEntrySheet: View {
    let entry: MealPlanEntry
    let onMove: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(entry: MealPlanEntry, onMove: @escaping (Date) -> Void) {
        self.entry = entry
        self.onMove = onMove
        _selectedDate = State(initialValue: entry.date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: FkSpacing.lg) {
                DatePicker(String(localized: "mealPlan.moveTo"), selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, FkSpacing.lg)
                Spacer(minLength: 0)
            }
            .padding(.top, FkSpacing.md)
            .navigationTitle(String(localized: "mealPlan.moveDish \(entry.recipeName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "mealPlan.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "mealPlan.move")) {
                        onMove(selectedDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// `Identifiable` wrapper around the built deduction proposals so the review can
/// drive `.sheet(item:)` — the meal-plan twin of recipe detail's `CookSession`.
private struct PlanCookSession: Identifiable {
    let id = UUID()
    let proposals: [DeductionProposal]
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
            .navigationTitle(String(localized: "mealPlan.selectDish"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "mealPlan.cancel")) { dismiss() }
                }
            }
        }
        .task {
            if store == nil {
                let store = RecipesStore(
                    localRepository: dependencies.localRecipeRepository,
                    customRepository: dependencies.customRecipeRepository,
                    favoritesStore: dependencies.favoritesStore,
                    householdID: dependencies.householdID,
                    inventoryRepository: dependencies.inventoryRepository,
                    dietaryStore: dependencies.dietaryPreferencesStore,
                    dietPreferenceStore: dependencies.dietPreferenceStore,
                    remoteCatalog: dependencies.remoteRecipeCatalog,
                    catalogCache: dependencies.recipeCatalogCache
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
                FkSearchField(text: $store.searchQuery, placeholder: String(localized: "recipe.list.searchPlaceholder"))
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
                title: store.searchQuery.trimmed.isEmpty ? String(localized: "mealPlan.noRecipesAvailable") : String(localized: "mealPlan.noMatchingRecipes"),
                message: store.searchQuery.trimmed.isEmpty ? nil : String(localized: "recipe.list.tryAnotherKeyword")
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
                            onToggleFavorite: { store.toggleFavorite(recipe) },
                            matchedCount: store.hasInventoryContext ? store.matchedCount(recipe) : nil,
                            totalIngredients: recipe.ingredients.count,
                            expiringUse: store.expiringUseCount(recipe)
                        )
                    }
                    .buttonStyle(.fkPressable)
                    .fkEntrance(index: index)
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .fkEntranceWindow()
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

    /// Short weekday label (周一 … 周日), locale-aware via `Date.FormatStyle`.
    static func weekdayShort(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(timeZone: .current).weekday(.abbreviated))
    }

    static func dayNumber(_ day: Date) -> String {
        "\(calendar.component(.day, from: day))"
    }

    private static func monthDay(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(timeZone: .current).month().day())
    }

    /// "M月 d日 周X" for the selected-day header, with a 今天 prefix on today.
    static func dayTitle(_ day: Date) -> String {
        let core = "\(monthDay(day)) \(weekdayShort(day))"
        return isToday(day) ? String(localized: "mealPlan.today.dated \(core)") : core
    }

    /// "M月d日 - M月d日" range across the visible week's first/last day.
    static func weekRange(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(monthDay(first)) - \(monthDay(last))"
    }

    static func dishSummary(_ count: Int) -> String {
        count > 0 ? String(localized: "mealPlan.dishesPlanned \(count)") : String(localized: "mealPlan.noPlan")
    }

    static func cellAccessibility(_ day: Date, dishCount: Int, isToday: Bool) -> String {
        let base = day.formatted(Date.FormatStyle(timeZone: .current).weekday(.abbreviated).day())
        let todayTag = isToday ? String(localized: "mealPlan.todayTag") : ""
        let dishes = dishCount > 0 ? String(localized: "mealPlan.dishesTag \(dishCount)") : ""
        return base + todayTag + dishes
    }
}
