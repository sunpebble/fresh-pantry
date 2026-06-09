import SwiftUI

/// Read-only recipe detail: a category-tinted hero (remote cover when present),
/// the name + meta row (category · difficulty · N 分钟), a favorite toggle, the
/// ingredient list (name + amount), numbered cooking steps, and a "做菜" CTA that
/// opens the cook-time deduction review (the only inventory-mutating affordance
/// here — built additively on top of the browse-only screen).
struct RecipeDetailView: View {
    let recipe: Recipe
    let store: RecipesStore
    /// CRUD owner for custom recipes — drives the edit form + delete. nil-safe:
    /// the edit/delete affordances only render when `isCustom` is true.
    var customStore: CustomRecipeStore?
    /// Whether this recipe is a user-authored custom one (vs a bundled corpus
    /// recipe). When true, the toolbar surfaces 编辑 + 删除.
    var isCustom: Bool = false

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    /// Built when "做菜" is tapped (inventory loaded → proposals via the factory),
    /// then presented as a review sheet. nil while idle. Wrapped because a bare
    /// array isn't `Identifiable` for `.sheet(item:)`.
    @State private var cookSession: CookSession?
    @State private var isPreparingCook = false
    @State private var showEditForm = false
    @State private var showDeleteConfirm = false
    /// Lower-cased inventory names for the ingredient availability highlight +
    /// the missing-ingredient shopping add. Loaded on appear.
    @State private var inventoryNames: Set<String> = []
    /// Lazily-built shopping store for "加购缺料".
    @State private var shoppingStore: ShoppingStore?
    @State private var isAddingMissing = false
    /// Step indices the user has checked off (local cooking progress).
    @State private var checkedSteps: Set<Int> = []
    /// Ingredient-amount scaling for 备料 (½×/1×/2×/3×). Display + cook proposals
    /// scale; 1× is a no-op that preserves explicit non-numeric amounts.
    @State private var scaleFactor: Double = 1
    /// Lazily-built meal-plan store for "加入膳食计划".
    @State private var mealPlanStore: MealPlanStore?
    @State private var showPlanPicker = false
    @State private var toast: String?

    /// The 备料倍数 presets (mirrors the Dart `_scalePresets`).
    private static let scalePresets: [Double] = [0.5, 1, 2, 3]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                hero
                header
                if !recipe.description.trimmed.isEmpty {
                    Text(recipe.description)
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .padding(.horizontal, FkSpacing.lg)
                }
                ingredientsSection
                stepsSection
            }
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .safeAreaInset(edge: .bottom) { cookBar }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(recipe)
                } label: {
                    Image(systemName: store.isFavorite(recipe) ? "heart.fill" : "heart")
                }
                .tint(store.isFavorite(recipe) ? .fkDanger : .fkOnSurfaceVariant)
                .accessibilityLabel(store.isFavorite(recipe) ? "取消收藏" : "收藏")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPlanPicker = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .tint(.fkOnSurfaceVariant)
                .disabled(mealPlanStore == nil)
                .accessibilityLabel("加入膳食计划")
            }
            if isCustom, customStore != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditForm = true
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("食谱操作")
                }
            }
        }
        .sheet(isPresented: $showEditForm) {
            if let customStore {
                CustomRecipeFormView(recipe: recipe, store: customStore)
            }
        }
        .confirmationDialog(
            "删除食谱",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    if let customStore, await customStore.remove(recipe.id) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除「\(recipe.name)」吗？此操作无法撤销。")
        }
        .sheet(item: $cookSession) { session in
            NavigationStack {
                DeductionReviewView(proposals: session.proposals) {
                    // Apply succeeded; the inventory/dashboard reload on their own
                    // `.task`/refresh, so nothing to do here beyond dismissing.
                }
            }
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanDayPickerSheet(recipeName: recipe.name) { day in
                await addToPlan(on: day)
            }
        }
        .overlay(alignment: .top) { toastBanner }
        .task {
            // Load inventory names (ingredient availability highlight + 加购缺料)
            // and build the shopping store once.
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
            if mealPlanStore == nil {
                let plan = MealPlanStore(
                    repository: dependencies.mealPlanRepository,
                    householdID: dependencies.householdID,
                    syncWriter: dependencies.syncWriter
                )
                await plan.load()
                mealPlanStore = plan
            }
            // Snapshot affordance: `-initialRoute cook` opens the deduction review
            // directly (built from this recipe vs the live inventory) so the screen
            // can be screenshotted without a tap. Mirrors `-initialRoute add`.
            if RecipeDetailView.opensCookOnLaunch, cookSession == nil {
                await presentCook()
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

    // MARK: 做菜 CTA + cook flow

    /// Bottom CTA that loads the live inventory, builds `[DeductionProposal]` via
    /// `DeductionProposalFactory.forRecipe`, and presents the deduction review.
    private var cookBar: some View {
        Button {
            Task { await presentCook() }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                if isPreparingCook {
                    ProgressView().tint(Color.fkOnPrimary)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isPreparingCook ? "准备中…" : "做菜")
                    .font(.fkLabelLarge)
            }
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.fkPrimary))
        }
        .buttonStyle(.fkPressable)
        .disabled(isPreparingCook || recipe.ingredients.isEmpty)
        .padding(.horizontal, FkSpacing.lg)
        .padding(.bottom, FkSpacing.sm)
        .accessibilityLabel("做菜并扣减库存")
    }

    /// Loads inventory, builds deduction proposals against it, and triggers the
    /// review sheet. A no-op if already preparing.
    private func presentCook() async {
        guard !isPreparingCook else { return }
        isPreparingCook = true
        defer { isPreparingCook = false }
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        // Deduct the scaled amounts so 备料倍数 carries through to the cook flow.
        let scaled = scaleFactor == 1 ? recipe : recipe.copyWith(ingredients: scaledIngredients)
        cookSession = CookSession(proposals: DeductionProposalFactory.forRecipe(scaled, inventory))
    }

    /// Honors a `-initialRoute cook` launch argument (UI snapshots / tests).
    private static var opensCookOnLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return false
        }
        return args[index + 1] == "cook"
    }

    private var palette: FkCategoryColors { FkCategoryIcon.palette(for: recipe.category) }

    // MARK: Hero

    private var hero: some View {
        ZStack {
            palette.tint
            RecipeImage(source: recipe.imageUrl) { heroGlyph }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroGlyph: some View {
        Image(systemName: FkCategoryIcon.symbol(for: recipe.category))
            .font(.system(size: 72, weight: .semibold))
            .foregroundStyle(palette.ink)
    }

    // MARK: Header (name + meta)

    private var header: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Text(recipe.name)
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkOnSurface)

            HStack(spacing: FkSpacing.md) {
                if !recipe.category.trimmed.isEmpty {
                    metaItem(systemImage: "tag", text: recipe.category)
                }
                metaItem(systemImage: "flame", text: recipe.difficultyLabel)
                metaItem(systemImage: "clock", text: "\(recipe.cookingMinutes) 分钟")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.lg)
    }

    private func metaItem(systemImage: String, text: String) -> some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.fkLabelMedium)
        }
        .foregroundStyle(Color.fkOnSurfaceVariant)
    }

    // MARK: Ingredients

    /// The recipe's ingredients with the active 备料倍数 applied (a non-numeric
    /// quantity is preserved unchanged by `scaledBy`). Names are untouched, so
    /// inventory matching is unaffected by scaling.
    private var scaledIngredients: [RecipeIngredient] {
        recipe.ingredients.map { $0.scaledBy(scaleFactor) }
    }

    /// Whether any ingredient carries a numeric quantity worth scaling (drives the
    /// 备料倍数 selector's visibility — no point showing it for "适量"-only recipes).
    private var hasScalableIngredient: Bool {
        recipe.ingredients.contains(where: \.isScalable)
    }

    /// Missing recipe ingredients (not in stock). Empty when inventory hasn't
    /// loaded or everything is on hand.
    private var missingIngredients: [RecipeIngredient] {
        guard !inventoryNames.isEmpty else { return [] }
        return RecipeMatching.missingIngredients(inventoryNames, recipe)
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if !recipe.ingredients.isEmpty {
            let hasInventory = !inventoryNames.isEmpty
            let matched = RecipeMatching.matchedCount(inventoryNames, recipe)
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack {
                    FkSectionHeader(title: "食材清单", count: recipe.ingredients.count)
                    Spacer(minLength: FkSpacing.sm)
                    if hasInventory {
                        Text("已有 \(matched)/\(recipe.ingredients.count)")
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                }
                if hasScalableIngredient {
                    scaleSelector
                }
                FkCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(scaledIngredients.enumerated()), id: \.offset) { index, ingredient in
                            ingredientRow(ingredient, hasInventory: hasInventory)
                            if index < scaledIngredients.count - 1 {
                                Rectangle().fill(Color.fkHair).frame(height: 0.5)
                            }
                        }
                    }
                }
                if hasInventory, !missingIngredients.isEmpty {
                    addMissingButton
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    /// 备料倍数 chips (½×/1×/2×/3×) — scales the displayed amounts and the cook
    /// deduction. Mirrors the Dart `_ScaleSelector`.
    private var scaleSelector: some View {
        HStack(spacing: FkSpacing.sm) {
            Text("备料")
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            ForEach(Self.scalePresets, id: \.self) { preset in
                FkChip(
                    label: Self.scaleLabel(preset),
                    isSelected: scaleFactor == preset
                ) {
                    scaleFactor = preset
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "½×" for 0.5, else "N×" with any trailing ".0" dropped.
    private static func scaleLabel(_ factor: Double) -> String {
        if factor == 0.5 { return "½×" }
        return "\(QuantityText.formatQuantity(factor))×"
    }

    private func ingredientRow(_ ingredient: RecipeIngredient, hasInventory: Bool) -> some View {
        let available = hasInventory && RecipeMatching.ingredientMatchesInventory(ingredient, inventoryNames)
        let missing = hasInventory && !available
        return HStack(spacing: FkSpacing.sm) {
            if hasInventory {
                Image(systemName: available ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(available ? Color.fkSuccess : Color.fkDanger)
            }
            Text(ingredient.name)
                .font(.fkBodyMedium)
                .foregroundStyle(missing ? Color.fkDanger : Color.fkOnSurface)
            if missing {
                Text("缺少")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkDanger)
                    .padding(.horizontal, FkSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.fkDangerSoft))
            }
            Spacer(minLength: FkSpacing.md)
            if !ingredient.amount.trimmed.isEmpty {
                Text(ingredient.amount)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .padding(FkSpacing.lg)
        .background(missing ? Color.fkDangerSoft.opacity(0.4) : Color.clear)
    }

    /// "加购缺少的 N 件" — adds all missing ingredients to the shopping list.
    private var addMissingButton: some View {
        Button {
            Task { await addMissingToShopping() }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(isAddingMissing ? "加入中…" : "一键加购缺少的 \(missingIngredients.count) 件")
                    .font(.fkLabelLarge)
            }
            .foregroundStyle(Color.fkPrimaryContainer)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkPrimarySoft)
            )
        }
        .buttonStyle(.fkPressable)
        .disabled(isAddingMissing)
    }

    private func addMissingToShopping() async {
        guard !isAddingMissing, let shoppingStore else { return }
        isAddingMissing = true
        defer { isAddingMissing = false }
        var added = 0
        for ingredient in missingIngredients {
            let category = FoodKnowledge.lookup(ingredient.name)?.category
            if await shoppingStore.add(name: ingredient.name, category: category) { added += 1 }
        }
        withAnimation {
            toast = added > 0 ? "已添加 \(added) 项到购物清单" : "缺少的食材已在购物清单中"
        }
    }

    // MARK: 加入膳食计划

    /// Plans this dish on `day` via the meal-plan store, then toasts. Dismisses
    /// the picker on success. Mirrors the Dart `_addToPlan`.
    private func addToPlan(on day: Date) async {
        guard let mealPlanStore else { return }
        let ok = await mealPlanStore.addDish(recipe: recipe, date: day)
        showPlanPicker = false
        withAnimation {
            toast = ok ? "已加入 \(PlanDayPickerSheet.dayLabel(day)) 的膳食计划" : "加入计划失败,请重试"
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            let total = recipe.steps.count
            let done = checkedSteps.count
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack {
                    FkSectionHeader(title: "烹饪步骤", count: total)
                    Spacer(minLength: FkSpacing.sm)
                    Text("\(done)/\(total)")
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                // Progress bar over the tapped-off steps.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fkSurfaceContainer)
                        Capsule().fill(Color.fkPrimary)
                            .frame(width: geo.size.width * (total == 0 ? 0 : Double(done) / Double(total)))
                    }
                }
                .frame(height: 5)
                .padding(.bottom, FkSpacing.xs)

                VStack(spacing: FkSpacing.sm) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index: index, number: index + 1, text: step)
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    private func stepRow(index: Int, number: Int, text: String) -> some View {
        let checked = checkedSteps.contains(index)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if checked { checkedSteps.remove(index) } else { checkedSteps.insert(index) }
            }
        } label: {
            FkCard {
                HStack(alignment: .top, spacing: FkSpacing.md) {
                    ZStack {
                        Circle().fill(checked ? Color.fkPrimary : Color.fkPrimarySoft)
                            .frame(width: 26, height: 26)
                        if checked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.fkOnPrimary)
                        } else {
                            Text("\(number)")
                                .font(.fkLabelMedium)
                                .foregroundStyle(Color.fkPrimary)
                        }
                    }
                    Text(text)
                        .font(.fkBodyMedium)
                        .foregroundStyle(checked ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                        .strikethrough(checked, color: Color.fkOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }
}

/// `Identifiable` wrapper around the built deduction proposals so the cook review
/// can drive `.sheet(item:)` (a bare `[DeductionProposal]` isn't `Identifiable`).
private struct CookSession: Identifiable {
    let id = UUID()
    let proposals: [DeductionProposal]
}

/// 7-day picker for "加入膳食计划" — lists today + the next 6 local days with a
/// weekday + date label, calling `onPick` (an async add) on tap. Mirrors the Dart
/// `_PlanDayPickerSheet`.
private struct PlanDayPickerSheet: View {
    let recipeName: String
    /// Async add action; the parent toasts + dismisses on completion.
    let onPick: (Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var addingDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.sm) {
                    ForEach(Self.upcomingDays, id: \.self) { day in
                        dayRow(day)
                    }
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .navigationTitle("加入计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .tint(.fkPrimary)
        }
        .presentationDetents([.medium, .large])
    }

    private func dayRow(_ day: Date) -> some View {
        let isAdding = addingDay == day
        return Button {
            addingDay = day
            Task { await onPick(day) }
        } label: {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    Image(systemName: "calendar")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkPrimary)
                        .frame(width: FkSize.settingsIconBox)
                    Text(Self.dayLabel(day))
                        .font(.fkTitleSmall)
                        .foregroundStyle(Color.fkOnSurface)
                    Spacer(minLength: 0)
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.fkPrimary)
                    }
                }
            }
        }
        .buttonStyle(.fkPressable)
        .disabled(addingDay != nil)
    }

    /// Today + the next 6 days, at LOCAL midnight (matches `MealPlanEntry.dateOnly`).
    private static var upcomingDays: [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = MealPlanEntry.dateOnly(Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// "今天 · 6月9日" / "明天 · …" / "周三 · …" — friendly relative weekday + date.
    static func dayLabel(_ day: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = MealPlanEntry.dateOnly(Date())
        let offset = calendar.dateComponents([.day], from: today, to: MealPlanEntry.dateOnly(day)).day ?? 0

        let dateFmt = DateFormatter()
        dateFmt.calendar = calendar
        dateFmt.locale = Locale(identifier: "zh_CN")
        dateFmt.dateFormat = "M月d日"
        let datePart = dateFmt.string(from: day)

        let prefix: String
        switch offset {
        case 0: prefix = "今天"
        case 1: prefix = "明天"
        case 2: prefix = "后天"
        default:
            let weekdayFmt = DateFormatter()
            weekdayFmt.calendar = calendar
            weekdayFmt.locale = Locale(identifier: "zh_CN")
            weekdayFmt.dateFormat = "EEEE"
            prefix = weekdayFmt.string(from: day)
        }
        return "\(prefix) · \(datePart)"
    }
}
