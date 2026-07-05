import PhotosUI
import SwiftData
import SwiftUI

/// The manual custom-recipe authoring form, presented as a sheet for create
/// (`recipe == nil`) or edit (`recipe` non-nil). Mirrors the Dart
/// `CustomRecipeFormScreen` sections — 封面图片 / 基础信息 / 食材 / 步骤 — using the
/// design system (FkCard / FkFormField / FkChip / FkInlineStepper / FkPickerSheet).
///
/// SCOPE: the manual form PLUS the AI URL-import banner (CREATE mode only —
/// mirrors the Dart `if !editing`). The 封面图片 section lets the user pick a cover
/// from the photo library (persisted to disk via `RecipeCoverStore` as a `file://`
/// URL) OR shows an AI-imported remote cover; a recipe with no cover falls back to
/// the category-color hero. A locally-picked cover is device-local (see
/// `RecipeCoverStore`'s sync-limitation note); a remote AI cover renders anywhere.
///
/// Validation is delegated to the pure `CustomRecipeDraft.validate()` so the
/// rules stay unit-testable; the View only renders the per-field messages and
/// anchors/scrolls to the first error. Save builds a `Recipe` (a NEW one gets a
/// lowercased UUID id so it syncs cleanly) and routes through `store.add` /
/// `store.update`.
struct CustomRecipeFormView: View {
    /// The injected parser seam — `(url) -> RecipeDraft`. Defaults to the live
    /// `AiRecipeParser` over the configured settings; tests inject a fake.
    typealias RecipeURLParser = @Sendable (String) async throws -> RecipeDraft

    /// The recipe being edited; nil for create.
    let recipe: Recipe?
    /// The CRUD owner (built/passed by the caller so sync wiring is one place).
    let store: CustomRecipeStore
    /// AI provider config — gates the import banner; nil hides it (e.g. previews).
    let aiSettingsStore: AiSettingsStore?
    /// Called after a successful save so the caller can reload its list.
    var onSaved: () -> Void = {}
    /// A recipe URL handed in by the Share Extension — pre-fills the AI-import field
    /// + expands the banner on first appear (create mode). nil for normal opens.
    private let initialImportURL: String?
    /// An already-AI-generated draft to pre-fill the editable form with (create
    /// mode only) — the 清冰箱 generator's outcome. The user reviews + edits the
    /// fields, then saves through the same `CustomRecipeStore` path as a manual or
    /// URL-imported recipe. nil for normal opens. Takes priority over
    /// `recipe`/`initialImportURL` for the initial draft seed.
    private let initialGeneratedDraft: RecipeDraft?
    /// Test seam: override the URL→RecipeDraft parser (prod builds it from
    /// `aiSettingsStore` at parse time).
    private let urlParserOverride: RecipeURLParser?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppDependencies.self) private var dependencies

    @State private var draft: CustomRecipeDraft
    @State private var initialDraft: CustomRecipeDraft
    @State private var errors: [CustomRecipeDraft.Field: String] = [:]
    @State private var showCategoryPicker = false
    @State private var showCustomCategory = false
    @State private var customCategory = ""
    @State private var unitPickerRow: CustomRecipeDraft.IngredientRow.ID?
    @State private var showDiscardConfirm = false
    @State private var saveFailed = false
    @State private var aiExpanded = false
    @State private var importURL = ""
    @State private var isParsing = false
    @State private var importError: String?
    /// The recipe URL auto-detected on the clipboard when the form opened (create
    /// mode); drives the inline "已从剪贴板检测到链接" hint. nil when none / dismissed.
    @State private var clipboardSuggestion: String?
    /// Owns the per-URL ignore cooldown so a dismissed suggestion doesn't re-offer.
    /// Injectable (like `urlParserOverride`) so previews / tests can feed a canned
    /// clipboard without touching the real pasteboard.
    @State private var clipboardDetector: ClipboardRecipeURLDetector
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverError: String?
    /// Per-session cover file id — used for EVERY pick (create AND edit) so a
    /// re-pick never overwrites the recipe's already-saved cover file in place
    /// (丢弃 must leave that file intact; it's reconciled on save instead).
    /// Stable for the form's lifetime so re-picks overwrite the same session file.
    @State private var draftCoverId = UUID().uuidString.lowercased()
    /// A successful AI parse waiting for the user to confirm overwriting a form
    /// that already has content (`isDirty`). nil otherwise — a parse onto a
    /// pristine form applies immediately.
    @State private var pendingParsedDraft: CustomRecipeDraft?
    /// Pro 门控：.needsPro 时点 解析 弹 PaywallSheet。
    @State private var showPaywall = false

    init(
        recipe: Recipe? = nil,
        store: CustomRecipeStore,
        aiSettingsStore: AiSettingsStore? = nil,
        onSaved: @escaping () -> Void = {},
        initialImportURL: String? = nil,
        initialGeneratedDraft: RecipeDraft? = nil,
        urlParserOverride: RecipeURLParser? = nil,
        clipboardDetector: ClipboardRecipeURLDetector? = nil
    ) {
        self.recipe = recipe
        self.store = store
        self.aiSettingsStore = aiSettingsStore
        self.onSaved = onSaved
        self.initialImportURL = initialImportURL
        self.initialGeneratedDraft = initialGeneratedDraft
        self.urlParserOverride = urlParserOverride
        // Seed precedence: a generated draft (清冰箱) > an edited recipe > a blank
        // create form. A generated draft only applies in create mode (`recipe == nil`).
        let seed: CustomRecipeDraft
        if let recipe {
            seed = CustomRecipeDraft(recipe: recipe)
        } else if let initialGeneratedDraft {
            seed = CustomRecipeDraft(parsed: initialGeneratedDraft)
        } else {
            seed = CustomRecipeDraft()
        }
        _draft = State(initialValue: seed)
        // A generated draft starts DIRTY (baseline = a blank form) so dismissing
        // without saving prompts the discard confirm — parity with the URL import,
        // where the parse fills `draft` while the baseline stays blank.
        _initialDraft = State(initialValue: initialGeneratedDraft != nil && recipe == nil ? CustomRecipeDraft() : seed)
        _clipboardDetector = State(initialValue: clipboardDetector ?? ClipboardRecipeURLDetector())
    }

    private var isEditing: Bool { recipe != nil }
    private var isDirty: Bool { draft != initialDraft }
    /// The AI-import banner shows ONLY in create mode and only when an AI store
    /// is wired in (the gate inside the banner handles the unconfigured case).
    private var showsAiImport: Bool { !isEditing && aiSettingsStore != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: FkSpacing.lg) {
                        if showsAiImport {
                            aiImportBanner
                        }
                        coverCard
                        basicsCard
                        ingredientsCard
                        stepsCard
                    }
                    .padding(FkSpacing.lg)
                }
                .background(Color.fkSurface)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: errors) { _, _ in scrollToFirstError(proxy) }
                .task { await offerClipboardURLIfNeeded() }
            }
            .overlay {
                if isParsing {
                    FkBusyOverlay(text: String(localized: "recipe.form.aiParsing"))
                }
            }
            .navigationTitle(isEditing ? String(localized: "recipe.form.editTitle") : String(localized: "recipe.form.newTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "recipe.form.cancel")) { requestDismiss() }
                        .disabled(isParsing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isSaving ? String(localized: "recipe.form.saving") : String(localized: "recipe.form.save")) { Task { await save() } }
                        .font(.fkLabelLarge)
                        .disabled(store.isSaving || isParsing)
                }
            }
            .sheet(isPresented: $showCategoryPicker) { categoryPicker }
            .sheet(item: unitPickerBinding) { wrapper in unitPicker(forRowID: wrapper.id) }
            .sheet(isPresented: $showPaywall) { PaywallSheet(proStore: dependencies.proStore) }
            .alert(String(localized: "recipe.form.customCategory"), isPresented: $showCustomCategory) {
                TextField(String(localized: "recipe.form.customCategoryPlaceholder"), text: $customCategory)
                Button(String(localized: "recipe.form.cancel"), role: .cancel) {}
                Button(String(localized: "recipe.form.confirm")) {
                    let value = customCategory.trimmed
                    if !value.isEmpty { setCategory(value) }
                }
            }
            .alert(String(localized: "recipe.form.discardChanges"), isPresented: $showDiscardConfirm) {
                Button(String(localized: "recipe.form.continueEditing"), role: .cancel) {}
                Button(String(localized: "recipe.form.discard"), role: .destructive) { discardDraft() }
            } message: {
                Text(isEditing
                    ? String(localized: "recipe.form.discardEditConfirm \(recipe?.name ?? "")")
                    : String(localized: "recipe.form.discardNewConfirm"))
            }
            .alert(String(localized: "recipe.form.saveFailed"), isPresented: $saveFailed) {
                Button(String(localized: "recipe.form.retry")) { Task { await save() } }
                Button(String(localized: "recipe.form.cancel"), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? String(localized: "recipe.form.saveFailedRetry"))
            }
            .alert(String(localized: "recipe.form.overwriteContent"), isPresented: Binding(
                get: { pendingParsedDraft != nil },
                set: { if !$0 { pendingParsedDraft = nil } }
            )) {
                Button(String(localized: "recipe.form.cancel"), role: .cancel) { pendingParsedDraft = nil }
                Button(String(localized: "recipe.form.overwrite"), role: .destructive) {
                    if let parsed = pendingParsedDraft { applyParsed(parsed) }
                    pendingParsedDraft = nil
                }
            } message: {
                Text(String(localized: "recipe.form.parseSuccessOverwrite"))
            }
            .onChange(of: coverPickerItem) { _, item in
                guard let item else { return }
                Task { await handlePickedCover(item) }
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: AI 导入

    /// Collapsible "AI 导入" banner (create mode only). Expanded, it shows the URL
    /// field + 解析 button when the 三态 allows it (BYOK / Pro 内置 / needsPro——点
    /// 解析 弹 paywall), or the "去设置配置 AI" hint (Pro + 本地模式) otherwise.
    private var aiImportBanner: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                Button {
                    withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                        aiExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: FkSpacing.sm) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Color.fkPrimary)
                        Text(String(localized: "recipe.form.aiImport"))
                            .font(.fkTitleSmall)
                            .foregroundStyle(Color.fkOnSurface)
                        Spacer(minLength: 0)
                        Image(systemName: aiExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.fkOutline)
                    }
                }
                .buttonStyle(.fkPressable)

                if aiExpanded {
                    if aiImportAvailable {
                        aiImportEditor
                    } else {
                        aiImportNotConfigured
                    }
                }
            }
        }
    }

    private var aiImportEditor: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Text(String(localized: "recipe.form.aiImportHint"))
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)

            if clipboardSuggestion != nil {
                clipboardHint
            }

            HStack(spacing: FkSpacing.sm) {
                FkTextFieldPill(text: $importURL, placeholder: "https://…", keyboard: .URL) {
                    Task { await parseURL() }
                }
                .onChange(of: importURL) { _, newValue in
                    importError = nil
                    // Once the user edits away from the auto-detected link, drop the
                    // hint (they're driving now); don't cooldown — they may be tweaking.
                    if let suggestion = clipboardSuggestion, newValue != suggestion {
                        clipboardSuggestion = nil
                    }
                }
                .disabled(isParsing)

                Button(String(localized: "recipe.form.parse")) { Task { await parseURL() } }
                    .font(.fkLabelLarge)
                    .foregroundStyle(canParse ? Color.fkPrimary : Color.fkOutline)
                    .disabled(!canParse)
            }

            if let importError {
                Text(importError)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Inline notice shown when the URL field was auto-filled from a clipboard link,
    /// so the pre-filled value doesn't look like it appeared from nowhere. 忽略 clears
    /// it and starts the cooldown so the same link isn't re-offered for 30 minutes.
    private var clipboardHint: some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fkPrimary)
            Text(String(localized: "recipe.form.clipboardDetected"))
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Spacer(minLength: 0)
            Button(String(localized: "recipe.form.dismiss")) { dismissClipboardSuggestion() }
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOutline)
        }
        .padding(.horizontal, FkSpacing.sm)
        .padding(.vertical, FkSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                .fill(Color.fkPrimarySoft)
        )
    }

    private var aiImportNotConfigured: some View {
        Text(String(localized: "recipe.form.aiNotConfigured"))
            .font(.fkBodySmall)
            .foregroundStyle(Color.fkOnSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canParse: Bool {
        !importURL.trimmed.isEmpty && !isParsing && aiImportAvailable
    }

    /// BYOK / 内置(Pro) / paywall 三态；nil ⇔ 无 aiSettingsStore（previews）。
    private var aiAvailability: AiAvailability? {
        aiSettingsStore.map { AiChatAccess.resolve(byok: $0.settings, isPro: dependencies.proStore.isPro) }
    }

    /// 三态下 URL 编辑器是否展示/可点：BYOK、Pro 内置可用，或 needsPro（点 解析
    /// 弹 PaywallSheet）。仅 Pro + 本地模式（内置通道缺失）退回「去设置配置 AI」提示。
    private var aiImportAvailable: Bool {
        switch aiAvailability {
        case .byok, .needsPro: return true
        case .builtIn: return dependencies.builtInAiChatFn() != nil
        case nil: return false
        }
    }

    // MARK: 封面图片

    /// Cover-image section: shows the current cover (local `file://` pick OR a
    /// remote AI-imported URL) via `AsyncImage` with 更换/移除 affordances, or an
    /// "添加封面" `PhotosPicker` placeholder when there is no cover.
    private var coverCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: String(localized: "recipe.form.coverImage"))

                if let urlString = draft.imageUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                    coverPreview(url: url)
                    coverActions
                } else {
                    coverPlaceholder
                }

                if let coverError {
                    Text(coverError)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func coverPreview(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .empty:
                ZStack { Color.fkSurfaceContainer; ProgressView() }
            default:
                ZStack {
                    Color.fkSurfaceContainer
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.fkOutline)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous))
    }

    private var coverActions: some View {
        HStack(spacing: FkSpacing.md) {
            PhotosPicker(selection: $coverPickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(localized: "recipe.form.coverReplace"))
                        .font(.fkLabelMedium)
                }
                .foregroundStyle(Color.fkPrimary)
            }
            .buttonStyle(.fkPressable)

            Button {
                removeCover()
            } label: {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(localized: "recipe.form.coverRemove"))
                        .font(.fkLabelMedium)
                }
                .foregroundStyle(Color.fkDanger)
            }
            .buttonStyle(.fkPressable)
            .accessibilityLabel(String(localized: "recipe.form.coverRemoveLabel"))

            Spacer(minLength: 0)
        }
    }

    private var coverPlaceholder: some View {
        PhotosPicker(selection: $coverPickerItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: FkSpacing.sm) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
                Text(String(localized: "recipe.form.coverAdd"))
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .strokeBorder(Color.fkPrimary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .fill(Color.fkPrimarySoft)
                    )
            )
        }
        .buttonStyle(.fkPressable)
    }

    // MARK: 基础信息

    private var basicsCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                FkSectionHeader(title: String(localized: "recipe.form.basics"))

                FkFormField(label: String(localized: "recipe.form.nameLabel")) {
                    FkTextFieldPill(text: $draft.name, placeholder: String(localized: "recipe.form.namePlaceholder")) {}
                        .onChange(of: draft.name) { _, _ in clearError(.name) }
                    fieldError(.name)
                }

                FkFormField(label: String(localized: "recipe.form.categoryLabel")) {
                    FkValuePill(value: draft.category.trimmed.isEmpty ? String(localized: "recipe.form.categoryPlaceholder") : draft.category) {
                        showCategoryPicker = true
                    }
                    fieldError(.category)
                }

                FkFormField(label: String(localized: "recipe.form.cookingTimeLabel")) {
                    cookingMinutesRow
                    fieldError(.cookingMinutes)
                }

                FkFormField(label: String(localized: "recipe.form.difficultyLabel")) {
                    DifficultyStars(value: draft.difficulty) { value in
                        draft.difficulty = value
                        clearError(.difficulty)
                    }
                    fieldError(.difficulty)
                }

                FkFormField(label: String(localized: "recipe.form.descriptionLabel")) {
                    multilineField(text: $draft.description, placeholder: String(localized: "recipe.form.descriptionPlaceholder"))
                }

                FkFormField(label: String(localized: "recipe.form.tipsLabel")) {
                    multilineField(text: $draft.notes, placeholder: String(localized: "recipe.form.tipsPlaceholder"))
                }

                FkFormField(label: String(localized: "recipe.form.tagsLabel")) {
                    IngredientTagsEditor(tags: $draft.tags)
                }
            }
        }
        .id(CustomRecipeDraft.Field.name)
    }

    /// Preset cooking-time chips + a custom numeric field. The last preset (120)
    /// renders as "120+" but still writes 120.
    private var cookingMinutesRow: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FkSpacing.sm) {
                    ForEach(RecipePresets.cookingMinutes, id: \.self) { minutes in
                        FkChip(
                            label: minutes == 120 ? "120+" : "\(minutes)",
                            isSelected: Int(draft.cookingMinutes.trimmed) == minutes
                        ) {
                            draft.cookingMinutes = String(minutes)
                            clearError(.cookingMinutes)
                        }
                    }
                }
            }
            HStack(spacing: FkSpacing.sm) {
                Text(String(localized: "recipe.form.customMinutes"))
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                TextField(String(localized: "recipe.form.minutesUnit"), text: $draft.cookingMinutes)
                    .font(.fkTitleMedium)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 80)
                    .padding(.horizontal, FkSpacing.sm)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                            .fill(Color.fkSurfaceContainer)
                    )
                    .onChange(of: draft.cookingMinutes) { _, _ in clearError(.cookingMinutes) }
                Text(String(localized: "recipe.form.minutesUnit"))
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }

    // MARK: 食材

    private var ingredientsCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: String(localized: "recipe.form.ingredients"), count: draft.ingredients.count)
                fieldError(.ingredients)

                ForEach($draft.ingredients) { $row in
                    ingredientRow($row)
                    if row.id != draft.ingredients.last?.id {
                        Rectangle().fill(Color.fkHair).frame(height: 0.5)
                    }
                }

                addRowButton(title: String(localized: "recipe.form.addIngredient")) {
                    draft.ingredients.append(.init())
                    clearError(.ingredients)
                }
            }
        }
        .id(CustomRecipeDraft.Field.ingredients)
    }

    private func ingredientRow(_ row: Binding<CustomRecipeDraft.IngredientRow>) -> some View {
        HStack(spacing: FkSpacing.sm) {
            TextField(String(localized: "recipe.form.ingredientNamePlaceholder"), text: row.name)
                .font(.fkBodyMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: row.wrappedValue.name) { _, _ in clearError(.ingredients) }

            TextField(String(localized: "recipe.form.amountPlaceholder"), text: row.quantity)
                .font(.fkBodyMedium)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .onChange(of: row.wrappedValue.quantity) { _, _ in clearError(.ingredients) }

            Button {
                unitPickerRow = row.wrappedValue.id
            } label: {
                HStack(spacing: 2) {
                    Text(row.wrappedValue.unit.isEmpty ? String(localized: "recipe.form.unitPlaceholder") : UnitLabels.displayLabel(for: row.wrappedValue.unit))
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkOnSurface)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.fkOutline)
                }
                .padding(.horizontal, FkSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                        .fill(Color.fkSurfaceContainer)
                )
            }
            .buttonStyle(.fkPressable)

            if draft.ingredients.count > 1 {
                let index = draft.ingredients.firstIndex { $0.id == row.wrappedValue.id }
                reorderButtons(
                    canMoveUp: (index ?? 0) > 0,
                    canMoveDown: index.map { $0 < draft.ingredients.count - 1 } ?? false,
                    upLabel: String(localized: "recipe.form.moveIngredientUp"),
                    downLabel: String(localized: "recipe.form.moveIngredientDown")
                ) { offset in
                    if let index { draft.moveIngredient(from: index, by: offset); clearError(.ingredients) }
                }
                Button {
                    draft.ingredients.removeAll { $0.id == row.wrappedValue.id }
                    clearError(.ingredients)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkDanger)
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel(String(localized: "recipe.form.removeIngredient"))
            }
        }
        .padding(.vertical, FkSpacing.xs)
    }

    /// A compact up/down nudge pair for reordering a row (Recipes #10). Disabled at
    /// the list edges; the `move` closure receives -1 (up) or +1 (down).
    private func reorderButtons(
        canMoveUp: Bool,
        canMoveDown: Bool,
        upLabel: String,
        downLabel: String,
        move: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                    .foregroundStyle(canMoveUp ? Color.fkOnSurfaceVariant : Color.fkOutline)
            }
            .buttonStyle(.fkPressable)
            .disabled(!canMoveUp)
            .accessibilityLabel(upLabel)

            Button { move(1) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                    .foregroundStyle(canMoveDown ? Color.fkOnSurfaceVariant : Color.fkOutline)
            }
            .buttonStyle(.fkPressable)
            .disabled(!canMoveDown)
            .accessibilityLabel(downLabel)
        }
    }

    // MARK: 步骤

    private var stepsCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: String(localized: "recipe.form.steps"), count: draft.steps.count)
                fieldError(.steps)

                ForEach(Array($draft.steps.enumerated()), id: \.element.id) { index, $step in
                    stepRow(number: index + 1, step: $step)
                }

                addRowButton(title: String(localized: "recipe.form.addStep")) {
                    draft.steps.append(.init())
                    clearError(.steps)
                }
            }
        }
        .id(CustomRecipeDraft.Field.steps)
    }

    private func stepRow(number: Int, step: Binding<CustomRecipeDraft.StepRow>) -> some View {
        HStack(alignment: .top, spacing: FkSpacing.md) {
            Text("\(number)")
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.fkPrimary))

            multilineField(text: step.text, placeholder: String(localized: "recipe.form.stepPlaceholder"))
                .onChange(of: step.wrappedValue.text) { _, _ in clearError(.steps) }

            if draft.steps.count > 1 {
                let index = draft.steps.firstIndex { $0.id == step.wrappedValue.id }
                reorderButtons(
                    canMoveUp: (index ?? 0) > 0,
                    canMoveDown: index.map { $0 < draft.steps.count - 1 } ?? false,
                    upLabel: String(localized: "recipe.form.moveStepUp"),
                    downLabel: String(localized: "recipe.form.moveStepDown")
                ) { offset in
                    if let index { draft.moveStep(from: index, by: offset); clearError(.steps) }
                }
                Button {
                    draft.steps.removeAll { $0.id == step.wrappedValue.id }
                    clearError(.steps)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkDanger)
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel(String(localized: "recipe.form.removeStep"))
            }
        }
        .padding(.vertical, FkSpacing.xs)
    }

    // MARK: Shared bits

    private func multilineField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.fkBodyMedium)
            .lineLimit(2...6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
            )
    }

    private func addRowButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(Color.fkPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .strokeBorder(Color.fkPrimary.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.fkPressable)
    }

    @ViewBuilder
    private func fieldError(_ field: CustomRecipeDraft.Field) -> some View {
        if let message = errors[field] {
            Text(message)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pickers

    private var categoryPicker: some View {
        var options = RecipePresets.categories
        if !draft.category.trimmed.isEmpty && !options.contains(draft.category) {
            options.insert(draft.category, at: 0)
        }
        return FkPickerSheet(
            title: String(localized: "recipe.form.selectCategory"),
            options: options.map { FkPickerOption(value: $0, label: RecipePresets.categoryDisplayLabel(for: $0)) }
                + [FkPickerOption(value: customSentinel, label: String(localized: "recipe.form.otherCategory"))],
            selected: draft.category
        ) { value in
            if value == customSentinel {
                customCategory = ""
                showCustomCategory = true
            } else {
                setCategory(value)
            }
        }
    }

    @ViewBuilder
    private func unitPicker(forRowID rowID: CustomRecipeDraft.IngredientRow.ID) -> some View {
        if let row = draft.ingredients.first(where: { $0.id == rowID }) {
            let options = RecipePresets.units.contains(row.unit) || row.unit.isEmpty
                ? RecipePresets.units
                : RecipePresets.units + [row.unit]
            FkPickerSheet(
                title: String(localized: "recipe.form.selectUnit"),
                options: options.map { FkPickerOption(value: $0, label: UnitLabels.displayLabel(for: $0)) },
                selected: row.unit
            ) { value in
                if let index = draft.ingredients.firstIndex(where: { $0.id == rowID }) {
                    draft.ingredients[index].unit = value
                    clearError(.ingredients)
                }
            }
        }
    }

    private var unitPickerBinding: Binding<IdentifiedRowID?> {
        Binding(
            get: { unitPickerRow.map(IdentifiedRowID.init) },
            set: { unitPickerRow = $0?.id }
        )
    }

    private let customSentinel = "__custom_category__"

    private func setCategory(_ value: String) {
        draft.category = value
        clearError(.category)
    }

    // MARK: Save / dismiss

    private func save() async {
        let validation = draft.validate()
        guard validation.isEmpty else {
            errors = validation
            return
        }
        errors = [:]

        let built = draft.buildRecipe(existing: recipe)
        let ok = isEditing ? await store.update(built) : await store.add(built)
        if ok {
            // The save replaced/removed the recipe's previously-saved cover —
            // its file is unreferenced now (delete ignores remote URLs).
            if let previous = recipe?.imageUrl, previous != built.imageUrl {
                RecipeCoverStore.delete(previous)
            }
            onSaved()
            dismiss()
        } else {
            saveFailed = true
        }
    }

    private func requestDismiss() {
        if isDirty {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    /// Discards the form. A cover picked THIS session already hit the disk but
    /// nothing will ever reference it once the draft is gone — delete it. The
    /// recipe's previously-saved cover is untouched (the edit was discarded).
    private func discardDraft() {
        if let cover = draft.imageUrl, isSessionCover(cover) {
            RecipeCoverStore.delete(cover)
        }
        dismiss()
    }

    // MARK: Clipboard auto-detect

    /// On first appear in create mode (with AI configured and the field empty),
    /// peeks the clipboard for a懒饭/下厨房 link and, if found, expands the banner +
    /// pre-fills the URL so the user can parse it with one tap. Mirrors the Dart
    /// `_maybeOfferClipboardUrl`. No-op when editing, already filled, or AI is unset.
    private func offerClipboardURLIfNeeded() async {
        // A Share-Extension URL takes priority: pre-fill + expand the banner even if
        // AI isn't configured yet (the banner then shows the 去设置配置 AI hint).
        if let shared = initialImportURL?.trimmed, !shared.isEmpty, !isEditing, importURL.trimmed.isEmpty {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                aiExpanded = true
            }
            importURL = shared
            return
        }

        // 剪贴板自动建议只在解析真正能跑（BYOK / Pro 内置）时出现——不为 paywall
        // 做被动引流，needsPro 用户不被动弹窗。
        guard showsAiImport, importURL.trimmed.isEmpty, clipboardSuggestion == nil,
              aiImportAvailable, aiAvailability != .needsPro,
              let url = await clipboardDetector.peek()
        else { return }

        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            aiExpanded = true
        }
        importURL = url
        clipboardSuggestion = url
    }

    /// Dismisses the clipboard suggestion: clears the pre-filled URL and starts the
    /// per-URL cooldown so the same link isn't re-offered on the next open.
    private func dismissClipboardSuggestion() {
        if let url = clipboardSuggestion {
            clipboardDetector.markIgnored(url)
            if importURL == url { importURL = "" }
        }
        clipboardSuggestion = nil
    }

    // MARK: AI import action

    /// Runs the URL → `RecipeDraft` parse and fills the form on success. Errors
    /// (unsupported host, network, malformed JSON, missing fields) surface their
    /// Chinese `AiError.message` inline; the manual fields are untouched on error.
    private func parseURL() async {
        guard !isParsing else { return }
        let raw = importURL.trimmed
        guard !raw.isEmpty else { return }

        // 测试 override 优先；否则按 BYOK / 内置(Pro) / paywall 三态解析出 parser。
        let parser: RecipeURLParser
        if let urlParserOverride {
            parser = urlParserOverride
        } else {
            switch aiAvailability {
            case .byok(let settings):
                parser = { url in
                    try await AiRecipeParser.fromUrl(url) { messages in
                        try await AiClient.chat(
                            settings: settings,
                            messages: messages,
                            responseFormat: ["type": .string("json_object")]
                        )
                    }
                }
            case .builtIn:
                guard let chatFn = dependencies.builtInAiChatFn(responseFormat: ["type": .string("json_object")]) else {
                    importError = AiError.notConfigured.message
                    return
                }
                parser = { url in try await AiRecipeParser.fromUrl(url, chatFn: chatFn) }
            case .needsPro:
                showPaywall = true
                return
            case nil:
                importError = AiError.notConfigured.message
                return
            }
        }

        // Acting on the link resolves the suggestion; hide the hint.
        clipboardSuggestion = nil
        isParsing = true
        importError = nil
        defer { isParsing = false }

        do {
            let parsed = CustomRecipeDraft(parsed: try await parser(raw))
            if isDirty {
                // Something is already filled in (typed fields / a picked cover) —
                // ask before replacing it. A pristine form applies straight away.
                pendingParsedDraft = parsed
            } else {
                applyParsed(parsed)
            }
        } catch let error as AiError {
            importError = error.message
        } catch {
            importError = String(localized: "recipe.form.parseFailed \(error.localizedDescription)")
        }
    }

    /// Replaces the form with the parse result via `CustomRecipeDraft.mergingParsed`
    /// (a parse with no cover keeps the picked one), deleting the local cover file
    /// the merge displaced so it can't be orphaned on disk.
    private func applyParsed(_ parsed: CustomRecipeDraft) {
        let merge = CustomRecipeDraft.mergingParsed(parsed, over: draft)
        if let replaced = merge.replacedCover {
            RecipeCoverStore.delete(replaced)
        }
        draft = merge.merged
        errors = [:]
    }

    // MARK: Cover actions

    /// Loads the picked photo, downscales + persists it to disk via
    /// `RecipeCoverStore`, and sets the draft's `imageUrl` to the returned
    /// `file://` path. Every pick writes the SESSION file (`draftCoverId` stem) —
    /// re-picks overwrite it in place, and the recipe's previously-saved cover
    /// file is left alone until 保存 lands (so 丢弃 can't corrupt or orphan it).
    private func handlePickedCover(_ item: PhotosPickerItem) async {
        coverError = nil
        defer { coverPickerItem = nil }

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            coverError = String(localized: "recipe.form.photoReadFailed \(error.localizedDescription)")
            return
        }
        guard let data, !data.isEmpty else {
            coverError = String(localized: "recipe.form.photoReadFailedRetry")
            return
        }

        do {
            draft.imageUrl = try await RecipeCoverStore.save(data, recipeId: draftCoverId)
        } catch {
            coverError = String(localized: "recipe.form.photoProcessFailed")
        }
    }

    /// Clears the cover. Only a file THIS session wrote is deleted right away;
    /// the recipe's saved cover survives until 保存 confirms the removal (丢弃
    /// must leave the saved recipe rendering its old cover). Remote AI URLs have
    /// no local file either way.
    private func removeCover() {
        coverError = nil
        if let urlString = draft.imageUrl, isSessionCover(urlString) {
            RecipeCoverStore.delete(urlString)
        }
        draft.imageUrl = nil
    }

    /// True when `urlString` is the cover file THIS form session wrote (the
    /// `draftCoverId` stem) — the only file safe to delete before a save lands.
    private func isSessionCover(_ urlString: String) -> Bool {
        urlString.hasSuffix("/\(draftCoverId).jpg")
    }

    /// Scrolls to the first field with an error (anchors the basics card top,
    /// the ingredients card, or the steps card — the three `.id`-tagged sections).
    private func scrollToFirstError(_ proxy: ScrollViewProxy) {
        let order: [CustomRecipeDraft.Field] = [.name, .category, .cookingMinutes, .difficulty, .ingredients, .steps]
        guard let first = order.first(where: { errors[$0] != nil }) else { return }
        let anchor: CustomRecipeDraft.Field
        switch first {
        case .name, .category, .cookingMinutes, .difficulty:
            anchor = .name
        case .ingredients:
            anchor = .ingredients
        case .steps:
            anchor = .steps
        }
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func clearError(_ field: CustomRecipeDraft.Field) {
        if errors[field] != nil { errors[field] = nil }
    }
}

/// `Identifiable` wrapper so an ingredient-row id can drive `.sheet(item:)` for
/// the unit picker (a bare `UUID` is `Identifiable` already, but wrapping keeps
/// the binding explicit and avoids ambiguity).
private struct IdentifiedRowID: Identifiable {
    let id: CustomRecipeDraft.IngredientRow.ID
}

/// 5-star difficulty selector with labels, ported from the Dart `DifficultyStars`.
private struct DifficultyStars: View {
    let value: Int
    let onChanged: (Int) -> Void

    private let labelKeys = [
        "recipe.form.difficulty.easy",
        "recipe.form.difficulty.easier",
        "recipe.form.difficulty.normal",
        "recipe.form.difficulty.advanced",
        "recipe.form.difficulty.expert",
    ]

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            HStack(spacing: FkSpacing.xs) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        onChanged(star)
                    } label: {
                        Image(systemName: star <= value ? "star.fill" : "star")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(star <= value ? Color.fkWarn : Color.fkOutlineVariant)
                    }
                    .buttonStyle(.fkPressable)
                    .accessibilityLabel(String(localized: "recipe.form.difficultyStars \(star)"))
                }
            }
            if value >= 1 && value <= 5 {
                Text(String(localized: String.LocalizationValue(labelKeys[value - 1])))
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}

/// Create mode with a懒饭/下厨房 link already on the clipboard (injected) and AI
/// configured — exercises the clipboard auto-detect: the banner expands, the URL
/// pre-fills, and the "已从剪贴板检测到食谱链接" hint shows.
#Preview("剪贴板检测") { // i18n:ignore Xcode canvas preview title, not shipped UI text
    clipboardDetectPreview()
}

@MainActor private func clipboardDetectPreview() -> some View {
    let container = try! ModelContainerFactory.makeInMemory()
    let aiSettings = AiSettingsStore(secrets: InMemorySecretStore())
    aiSettings.save(AiSettings(baseUrl: "https://api.example.com/v1", apiKey: "preview-key", model: "gpt-x"))
    let store = CustomRecipeStore(
        repository: CustomRecipeRepository(modelContainer: container),
        householdID: "preview"
    )
    let detector = ClipboardRecipeURLDetector(
        reader: { "https://www.xiachufang.com/recipe/100271164/" }
    )
    return CustomRecipeFormView(
        store: store,
        aiSettingsStore: aiSettings,
        clipboardDetector: detector
    )
    // 三态门控读 proStore / builtInAiChatFn，预览也要有 AppDependencies。
    .environment(AppDependencies(modelContainer: container))
}
