import SwiftUI

/// Read-only recipe detail: a category-tinted hero (remote cover when present),
/// the name + meta row (category · difficulty · N 分钟), a favorite toggle, the
/// ingredient list (name + amount), numbered cooking steps, and a "做菜" CTA that
/// opens the cook-time deduction review (the only inventory-mutating affordance
/// here — built additively on top of the browse-only screen).
struct RecipeDetailView: View {
    /// The recipe as pushed — a frozen navigation value. Rendering goes through
    /// the live `recipe` below so an edit save refreshes this screen in place.
    private let initialRecipe: Recipe
    let store: RecipesStore
    /// CRUD owner for custom recipes — drives the edit form + delete. nil-safe:
    /// the edit/delete affordances only render when `isCustom` is true.
    let customStore: CustomRecipeStore?
    /// Whether this recipe is a user-authored custom one (vs a bundled corpus
    /// recipe). When true, the toolbar surfaces 编辑 + 删除.
    let isCustom: Bool

    init(
        recipe: Recipe,
        store: RecipesStore,
        customStore: CustomRecipeStore? = nil,
        isCustom: Bool = false
    ) {
        self.initialRecipe = recipe
        self.store = store
        self.customStore = customStore
        self.isCustom = isCustom
    }

    /// Live render source: the custom store's CURRENT row when one matches (the
    /// store re-publishes after an edit save, so the detail — and a re-opened
    /// edit form — always shows the saved values, never the pushed-in snapshot),
    /// else the pushed value (bundled recipes / no custom store).
    private var recipe: Recipe {
        customStore?.recipes.first { $0.id == initialRecipe.id } ?? initialRecipe
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// The household the lazily-built stores were scoped to — they are dropped
    /// and rebuilt when it changes (login/switch/leave must not write old scope;
    /// mirrors `MealPlanView`'s scope sentinel).
    @State private var storeScope: String?
    @State private var showPlanPicker = false
    @State private var toast: String?
    /// Cook Mode (full-screen step pager) presentation.
    @State private var showCookMode = false
    /// Post-cook leftover flow: set when the deduction apply lands, consumed on
    /// the cook sheet's dismiss to raise the "存为剩菜?" prompt (presenting it
    /// while that sheet is still animating away would drop the dialog).
    @State private var leftoverPromptPending = false
    @State private var showLeftoverPrompt = false
    @State private var showLeftoverSheet = false
    /// 「观看视频」外链的 in-app Safari 呈现(item 驱动:store 实时刷新清空 videoUrl 时不会留空白 sheet)。
    @State private var videoLink: VideoLink?
    /// Cook Mode 完成 follow-up: set when the pager's 完成 (vs its X close) was
    /// tapped, consumed on the cover's onDismiss to offer the cook deduction —
    /// the same deferred-prompt timing as `leftoverPromptPending`. The offer only
    /// OPENS the review (the user still confirms there), so it can never deduct
    /// on its own — no double deduction with the 做菜 CTA.
    @State private var cookDeductPromptPending = false
    @State private var showCookDeductPrompt = false

    /// The 备料倍数 presets (mirrors the Dart `_scalePresets`).
    private static let scalePresets: [Double] = [0.5, 1, 2, 3]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                hero
                header
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
                // `recipe` is the LIVE row, so a second edit seeds from the saved
                // values; onSaved refreshes the browse list (the custom store
                // already reloaded itself inside `update`).
                CustomRecipeFormView(
                    recipe: recipe,
                    store: customStore,
                    onSaved: { Task { await store.load() } }
                )
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
        .sheet(item: $cookSession, onDismiss: {
            // Raise the optional leftover prompt only AFTER the cook sheet fully
            // dismissed (set by a successful apply below; a cancelled review
            // leaves it unset, so cooking without leftovers stays undisturbed).
            if leftoverPromptPending {
                leftoverPromptPending = false
                showLeftoverPrompt = true
            }
        }) { session in
            NavigationStack {
                DeductionReviewView(proposals: session.proposals) { outcome in
                    // Apply succeeded. Flag the leftover follow-up (the prompt
                    // itself waits for this sheet's onDismiss) and re-sync the
                    // inventory-derived UI with the stock that just changed.
                    leftoverPromptPending = true
                    if outcome.affectedCount > 0 {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                            toast = "已扣减 \(outcome.affectedCount) 项库存"
                        }
                    }
                    Task { await refreshInventoryContext() }
                }
            }
        }
        .confirmationDialog(
            "把做好的菜存为剩菜？",
            isPresented: $showLeftoverPrompt,
            titleVisibility: .visible
        ) {
            Button("存为剩菜") { showLeftoverSheet = true }
            Button("不用了", role: .cancel) {}
        } message: {
            Text("按冷藏 3 天保质期预填,保存前可修改。")
        }
        .sheet(isPresented: $showLeftoverSheet) {
            LeftoverIntakeSheet(recipe: recipe) { savedName in
                withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                    toast = "已把「\(savedName)」存入库存"
                }
                // The leftover row just landed in inventory — re-sync the
                // match pills + list ranking the same way a deduction does.
                Task { await refreshInventoryContext() }
            }
        }
        .sheet(item: $videoLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanDayPickerSheet(recipeName: recipe.name) { day in
                await addToPlan(on: day)
            }
        }
        .fullScreenCover(isPresented: $showCookMode, onDismiss: {
            // Offer the cook deduction only AFTER the cover fully dismissed
            // (mirrors the leftover prompt's deferred timing above).
            if cookDeductPromptPending {
                cookDeductPromptPending = false
                showCookDeductPrompt = true
            }
        }) {
            // Pass the SCALED ingredients so the 食材速查 sheet matches the
            // active 备料倍数 (single scaling source: `scaledIngredients`).
            CookModeView(title: recipe.name, steps: recipe.steps, ingredients: scaledIngredients) {
                // 完成 (vs the X close): the dish got cooked — reflect it in the
                // step checklist and queue the deduction offer.
                checkedSteps = Set(recipe.steps.indices)
                cookDeductPromptPending = true
            }
        }
        .confirmationDialog(
            "做完了，要扣减库存吗？",
            isPresented: $showCookDeductPrompt,
            titleVisibility: .visible
        ) {
            Button("去扣减") { Task { await presentCook() } }
            Button("暂不", role: .cancel) {}
        } message: {
            Text("打开扣减审核,确认前可调整或跳过任意食材。")
        }
        .overlay(alignment: .top) { toastBanner }
        .task(id: dependencies.householdID) {
            // Snapshot the scope this task instance serves: after any await the
            // household may have switched and a successor task (re-keyed by
            // `.task(id:)`) owns the NEW scope — assigning our stale results
            // would clobber its stores/names with the prior household's data.
            let householdID = dependencies.householdID
            // Household switch while this detail stays pushed: drop the lazily-
            // built stores so 加购/加入计划 rebuild against the new scope instead
            // of writing into the prior household's lists.
            if storeScope != householdID {
                shoppingStore = nil
                mealPlanStore = nil
                storeScope = householdID
            }
            // Load inventory names (ingredient availability highlight + 加购缺料)
            // and build the shopping store once per scope.
            let inventory = (try? await dependencies.inventoryRepository.loadAllFor(householdID)) ?? []
            guard dependencies.householdID == householdID else { return }
            inventoryNames = RecipeMatching.availableInventoryNameSet(inventory)
            if shoppingStore == nil {
                let shopping = ShoppingStore(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                await shopping.load()
                guard dependencies.householdID == householdID else { return }
                shoppingStore = shopping
            }
            if mealPlanStore == nil {
                let plan = MealPlanStore(
                    repository: dependencies.mealPlanRepository,
                    householdID: householdID,
                    syncWriter: dependencies.syncWriter
                )
                await plan.load()
                guard dependencies.householdID == householdID else { return }
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
                    if !Task.isCancelled {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { self.toast = nil }
                    }
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
        // A stale leftover prompt must never leak across cook sessions: if the
        // previous sheet was swipe-dismissed mid-apply, `onApplied` can land
        // AFTER its onDismiss ran (nothing consumed the flag) — without this
        // reset the NEXT cook's dismiss would wrongly offer 存为剩菜.
        leftoverPromptPending = false
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        // Deduct the scaled amounts so 备料倍数 carries through to the cook flow.
        let scaled = scaleFactor == 1 ? recipe : recipe.copyWith(ingredients: scaledIngredients)
        cookSession = CookSession(proposals: DeductionProposalFactory.forRecipe(scaled, inventory))
    }

    /// Re-reads the live inventory after a cook deduction / leftover save so the
    /// 已有/缺少 pills, the 一键加购 set, and the browse list's match ranking all
    /// reflect the stock that was just mutated (this screen's `.task` ran once on
    /// push and the list's `.task` doesn't re-run on a sheet dismiss or pop).
    private func refreshInventoryContext() async {
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        inventoryNames = RecipeMatching.availableInventoryNameSet(inventory)
        await store.load()
    }

    /// Honors a `-initialRoute cook` launch argument (UI snapshots / tests).
    private static var opensCookOnLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return false
        }
        return args[index + 1] == "cook"
    }

    /// 当前菜谱的合法视频外链(trim 后非空且能构造 URL),否则 nil。按钮与 sheet 共用。
    private var videoURL: URL? {
        guard let raw = recipe.videoUrl?.trimmed, !raw.isEmpty else { return nil }
        return URL(string: raw)
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
        // Round only the bottom edge so the cover softens into the header instead
        // of cutting a hard full-bleed line across the screen.
        .clipShape(
            .rect(bottomLeadingRadius: FkRadius.lg, bottomTrailingRadius: FkRadius.lg)
        )
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

            HStack(spacing: FkSpacing.sm) {
                if !recipe.category.trimmed.isEmpty {
                    metaItem(systemImage: "tag", text: recipe.category)
                        .lineLimit(1)
                }
                metaItem(systemImage: "flame", text: recipe.difficultyLabel)
                metaItem(systemImage: "clock", text: "\(recipe.cookingMinutes) 分钟")
            }

            // User tags (read-only) — so a recipe the user tagged「宴客」/「快手」
            // shows that label, closing the tag loop (edit in the form → see here →
            // filter in the browse list). Hidden when the recipe carries no tags.
            if !recipe.tags.isEmpty {
                FlowLayout(spacing: FkSpacing.sm) {
                    ForEach(recipe.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkOnSurface)
                            .padding(.horizontal, FkSpacing.md)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.fkSurfaceContainer)
                                    .overlay(Capsule().strokeBorder(Color.fkHair, lineWidth: 1))
                            )
                    }
                }
                .padding(.top, FkSpacing.xs)
            }

            // Description lives INSIDE the header group (sm rhythm) so the name →
            // meta → description read as one block; previously it sat in the outer
            // VStack and was pushed away by the larger lg gap (reversed rhythm).
            if !recipe.description.trimmed.isEmpty {
                Text(recipe.description)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .padding(.top, FkSpacing.xs)
            }
            if let url = videoURL {
                Button {
                    videoLink = VideoLink(url: url)
                } label: {
                    Label("观看视频", systemImage: "play.rectangle.fill")
                        .font(.fkLabelLarge)
                }
                .buttonStyle(.borderedProminent)
                .tint(.fkPrimary)
                .padding(.top, FkSpacing.xs)
                .accessibilityLabel("观看「\(recipe.name)」的做法视频")
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
            // Bind the derived lists once — the rows, separator count, and the
            // add-missing button all share a single evaluation per render.
            let ingredients = scaledIngredients
            let missingCount = missingIngredients.count
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack {
                    // FkSectionHeader already carries a trailing Spacer, so the
                    // count + "已有 N/M" sit at the edges without a second one.
                    FkSectionHeader(title: "食材清单", count: recipe.ingredients.count)
                    if hasInventory {
                        Text("已有 \(matched)/\(recipe.ingredients.count)")
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                }
                .padding(.bottom, FkSpacing.xs)
                if hasScalableIngredient {
                    scaleSelector
                }
                FkCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                            ingredientRow(ingredient, hasInventory: hasInventory)
                            if index < ingredients.count - 1 {
                                Rectangle().fill(Color.fkHair).frame(height: 0.5)
                            }
                        }
                    }
                }
                if hasInventory, missingCount > 0 {
                    addMissingButton(missingCount: missingCount)
                        .padding(.top, FkSpacing.xs)
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
                    // The dashed icon now carries the missing cue for VoiceOver,
                    // replacing the removed "缺少" text pill.
                    .accessibilityLabel(available ? "已有" : "缺少")
            }
            // Missing state reads from the dashed icon + soft row tint alone — the
            // name stays neutral so the ingredient itself isn't drowned in red.
            Text(ingredient.name)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(1)
            Spacer(minLength: FkSpacing.sm)
            // Amount keeps layout priority so a long name truncates before it —
            // the quantity is the dense, must-read half of the row.
            if !ingredient.displayAmount.trimmed.isEmpty {
                Text(ingredient.displayAmount)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, FkSpacing.lg)
        .padding(.vertical, FkSpacing.md)
        .background(missing ? Color.fkDangerSoft.opacity(0.4) : Color.clear)
    }

    /// "加购缺少的 N 件" — adds all missing ingredients to the shopping list.
    private func addMissingButton(missingCount: Int) -> some View {
        Button {
            Task { await addMissingToShopping() }
        } label: {
            // Secondary chip (content-width soft capsule, mirrors 烹饪模式) so the
            // bottom 做菜 capsule stays the only full-width filled primary action.
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(isAddingMissing ? "加入中…" : "加购缺少的 \(missingCount) 件")
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(Color.fkPrimaryContainer)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, FkSpacing.sm)
            .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .disabled(isAddingMissing)
    }

    private func addMissingToShopping() async {
        guard !isAddingMissing, let shoppingStore else { return }
        isAddingMissing = true
        defer { isAddingMissing = false }
        var added = 0
        var failed = 0
        for ingredient in missingIngredients {
            let category = FoodKnowledge.lookup(ingredient.name)?.category
            switch await shoppingStore.addItem(name: ingredient.name, category: category) {
            case .added: added += 1
            case .duplicate: break // already on the list — the goal is met
            case .failed: failed += 1
            }
        }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            // A write failure must never read as「已在购物清单中」— nothing landed.
            if failed > 0 {
                toast = added > 0 ? "已添加 \(added) 项，部分添加失败，请重试" : "添加失败，请重试"
            } else {
                toast = added > 0 ? "已添加 \(added) 项到购物清单" : "缺少的食材已在购物清单中"
            }
        }
    }

    // MARK: 加入膳食计划

    /// Plans this dish on `day` via the meal-plan store, then toasts. Dismisses
    /// the picker on success. Mirrors the Dart `_addToPlan`.
    private func addToPlan(on day: Date) async {
        guard let mealPlanStore else { return }
        let ok = await mealPlanStore.addDish(recipe: recipe, date: day)
        showPlanPicker = false
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = ok ? "已加入 \(PlanDayPickerSheet.dayLabel(day)) 的膳食计划" : "加入计划失败,请重试"
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            let total = recipe.steps.count
            // Clamped: an edit save can shrink the live step list below the
            // already-checked count (the checklist is per-push local state).
            let done = min(checkedSteps.count, total)
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack {
                    // FkSectionHeader's own trailing Spacer pushes the count +
                    // 烹饪模式 button to the edge; grouping them in one HStack keeps
                    // a stable gap so they no longer butt against each other.
                    FkSectionHeader(title: "烹饪步骤", count: total)
                    HStack(spacing: FkSpacing.sm) {
                        Text("\(done)/\(total)")
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                        cookModeButton
                    }
                }
                .padding(.bottom, FkSpacing.xs)
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

                VStack(spacing: FkSpacing.md) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index: index, number: index + 1, text: step)
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
            .padding(.top, FkSpacing.xs)
        }
    }

    /// Entry into the full-screen Cook Mode step pager (styled to match the
    /// section header's count pill).
    private var cookModeButton: some View {
        Button {
            showCookMode = true
        } label: {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("烹饪模式")
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(Color.fkPrimaryContainer)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .accessibilityLabel("进入烹饪模式")
    }

    private func stepRow(index: Int, number: Int, text: String) -> some View {
        let checked = checkedSteps.contains(index)
        return Button {
            withAnimation(FkMotion.animation(.easeOut(duration: 0.15), reduceMotion: reduceMotion)) {
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

/// `.sheet(item:)` 需要 Identifiable;裸 URL 不符合,用 absoluteString 作 id 包装。
private struct VideoLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
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
