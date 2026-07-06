import SwiftUI

/// The 临期 screen, pushed from the Dashboard: the household's non-fresh
/// inventory (state ∈ {expiringSoon, urgent, expired}), urgency-sorted and
/// sectioned by tier (已过期 → 快过期 → 即将过期).
///
/// Each row taps through to the read-only detail and carries two quick actions
/// (用了 → log a consumed departure + remove, reversible via a transient 撤销
/// banner; 加购 → add to the shopping list),
/// mirroring the Flutter expiring screen's per-item affordances. It builds an
/// `ExpiringStore` (display) plus an `InventoryStore` (the 用了 removal + the
/// detail push) and a `ShoppingStore` (加购) from the injected `AppDependencies`.
struct ExpiringView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ExpiringStore?
    @State private var inventoryStore: InventoryStore?
    @State private var shoppingStore: ShoppingStore?
    /// CRUD owner for custom recipes — the 清冰箱 generation saves through it (same
    /// outbox path as the manual / URL-import authoring) and the form reloads it.
    @State private var customStore: CustomRecipeStore?
    /// Live OS notification-permission state, for the reminder-status card.
    @State private var remindersGranted = false

    var body: some View {
        Group {
            if let store, let inventoryStore, let customStore {
                ExpiringContent(
                    store: store,
                    inventoryStore: inventoryStore,
                    customStore: customStore,
                    aiSettingsStore: dependencies.aiSettingsStore,
                    reminderSettings: dependencies.reminderSettingsStore.settings,
                    remindersGranted: remindersGranted,
                    onConsume: consume,
                    onAddToShopping: addToShopping
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle(String(localized: "dashboard.expiring.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Rebuild the stores whenever the active household changes (login "" → uuid,
        // switch, or leave) so the lists re-scope to the new household.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            let expiring = ExpiringStore(
                repository: dependencies.inventoryRepository,
                householdID: householdID
            )
            let inventory = InventoryStore(
                repository: dependencies.inventoryRepository,
                foodLogRepository: dependencies.foodLogRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            let shopping = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            let custom = CustomRecipeStore(
                repository: dependencies.customRecipeRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            // OFFLINE-FIRST, NO FLASH: load the new scope's local rows BEFORE
            // swapping the stores in, so a household switch keeps the previous list
            // on screen until the new (local, instant) data is ready instead of
            // flashing an empty list. Guard after the loads so a newer switch landing
            // here doesn't assign this stale scope's stores over the successor's.
            await expiring.load()
            await inventory.load()
            await shopping.load()
            await custom.load()
            guard householdID == dependencies.householdID, !Task.isCancelled else { return }
            self.store = expiring
            self.inventoryStore = inventory
            self.shoppingStore = shopping
            self.customStore = custom
            remindersGranted = await dependencies.notificationCoordinator.refreshPermission()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the expiring list reflects inventory pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task {
                await store?.load()
                await inventoryStore?.load()
                await shoppingStore?.load()
            }
        }
    }

    /// "用了": logs a consumed departure + removes the row, then reloads the
    /// expiring list so it drops off. Returns the removal result so the content
    /// view can offer the 撤销 banner on success (the only path that can reverse
    /// the food-log append) and surface a persist failure — `.notFound` stays
    /// silent because the reload self-heals an already-gone row.
    private func consume(_ item: Ingredient) async -> InventoryStore.RemoveResult {
        guard let inventoryStore, let store else { return .notFound }
        let result = await inventoryStore.removeWithResult(item, outcome: .consumed)
        // Optimistic instant drop on success; the `onChange(of: inventoryStore.items)`
        // drift handler (and an undo's re-add) reconciles the snapshot afterward.
        if case .removed = result { store.remove(id: item.id) }
        return result
    }

    /// "加购": adds the item to the shopping list (name-unique dedup). Returns a
    /// short confirmation for the toast.
    private func addToShopping(_ item: Ingredient) async -> String {
        guard let shoppingStore else { return "" }
        let added = await shoppingStore.add(name: item.name, category: item.category)
        return added
            ? String(localized: "dashboard.shopping.added \(item.displayName)")
            : String(localized: "dashboard.shopping.duplicate \(item.displayName)")
    }
}

/// Inner content bound to live stores. Rows tap through to the detail; the
/// trailing 用了 / 加购 buttons are independent tap targets (not a nested Button).
private struct ExpiringContent: View {
    let store: ExpiringStore
    let inventoryStore: InventoryStore
    /// CRUD owner the generated recipe saves through (outbox-synced).
    let customStore: CustomRecipeStore
    /// AI provider config — gates the 清冰箱 button + supplies the chat settings.
    let aiSettingsStore: AiSettingsStore
    let reminderSettings: ReminderSettings
    let remindersGranted: Bool
    let onConsume: (Ingredient) async -> InventoryStore.RemoveResult
    let onAddToShopping: (Ingredient) async -> String

    @State private var selectedIngredient: Ingredient?
    @State private var toast: String?
    /// Holds the just-用了 row's undo handle so the 撤销 banner can reverse BOTH
    /// the inventory removal and the food-log append (same both-sides contract
    /// as IngredientDetailView's banner).
    @State private var pendingUndo: InventoryStore.RemovalUndo?
    /// True while the 清冰箱 AI generation is running (blocks re-tap + shows spinner).
    @State private var isGenerating = false
    /// Free-text 约束 (口味/时间/餐次/忌口) folded into the generation prompt (#5).
    @State private var generateConstraint = ""
    /// Inline 清冰箱 failure message (network / parse / not-configured), surfaced
    /// under the button. Cleared on a fresh attempt. nil ⇒ no error.
    @State private var generateError: String?
    /// The freshly generated draft awaiting user review in the form sheet. Setting
    /// it presents the sheet; cleared on dismiss. Wrapped in an `Identifiable`
    /// route since `RecipeDraft` is a transient model with no id (same pattern as
    /// Recipes' `RecipeRoute`).
    @State private var generatedDraft: GeneratedDraftRoute?
    /// Pro 门控：.needsPro 时弹 PaywallSheet。
    @State private var showPaywall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(RecipeFilterRouter.self) private var recipeFilterRouter
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        VStack(spacing: FkSpacing.md) {
            RemindStatusCard(granted: remindersGranted, settings: reminderSettings)
                .padding(.horizontal, FkSpacing.lg)
                .padding(.top, FkSpacing.sm)
            Group {
                if store.isLoading && !store.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.tiers.isEmpty {
                    FkEmptyState(
                        systemImage: "checkmark.circle",
                        title: String(localized: "dashboard.expiring.emptyTitle"),
                        message: String(localized: "dashboard.expiring.emptyMessage")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    tierList
                }
            }
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
        .overlay(alignment: .top) { toastBanner }
        .overlay(alignment: .bottom) { undoBanner }
        // Detail-pop staleness: the pushed detail mutates ONLY InventoryStore.items
        // (delete / remove-with-outcome / edit) while the tiers render ExpiringStore's
        // independent snapshot, and local-mode writes emit no dataRevision pulse —
        // so re-read the snapshot whenever the inventory items change (same handler
        // shape as InventoryView's onChange(of: store.items)).
        .onChange(of: inventoryStore.items) {
            Task { await store.load() }
        }
        .navigationDestination(item: $selectedIngredient) { ingredient in
            IngredientDetailView(ingredient: ingredient, store: inventoryStore)
        }
        .sheet(item: $generatedDraft) { route in
            CustomRecipeFormView(
                store: customStore,
                aiSettingsStore: aiSettingsStore,
                onSaved: { Task { await customStore.load() } },
                initialGeneratedDraft: route.draft
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: dependencies.proStore)
        }
    }

    private var tierList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.xl) {
                clearFridgeCard
                    .padding(.horizontal, FkSpacing.lg)

                ForEach(Array(store.tiers.enumerated()), id: \.element.id) { sectionIndex, tier in
                    VStack(alignment: .leading, spacing: FkSpacing.sm) {
                        tierHeader(tier)
                            .padding(.horizontal, FkSpacing.lg)

                        LazyVStack(spacing: FkSpacing.sm) {
                            ForEach(Array(tier.items.enumerated()), id: \.element.fkListIdentityKey) { index, item in
                                FkCard {
                                    VStack(spacing: FkSpacing.sm) {
                                        IngredientRow(ingredient: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedIngredient = item }
                                        actionRow(item)
                                    }
                                }
                                .fkEntrance(index: sectionIndex + index)
                            }
                        }
                        .padding(.horizontal, FkSpacing.lg)
                    }
                }
            }
            .padding(.top, FkSpacing.md)
            .padding(.bottom, FkSpacing.huge)
            .fkEntranceWindow()
        }
    }

    // MARK: 清冰箱 AI generation

    /// The "AI 生成清冰箱食谱" card — surfaced atop the tier list (so it only shows
    /// when there ARE expiring items). Generates a recipe from the临期 names via the
    /// BYOK / 内置(Pro) / paywall 三态 (`AiChatAccess.resolve`) — non-Pro users
    /// without BYOK get the PaywallSheet instead of an error; the button always
    /// stays tappable so the value prompt stays visible.
    private var clearFridgeCard: some View {
        FkCard(background: .fkPrimarySoft) {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                HStack(spacing: FkSpacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkPrimary)
                    Text(String(localized: "dashboard.clearFridge.title"))
                        .font(.fkTitleSmall)
                        .foregroundStyle(Color.fkOnSurface)
                    Spacer(minLength: 0)
                }
                Text(String(localized: "dashboard.clearFridge.subtitle"))
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)

                TextField(String(localized: "dashboard.clearFridge.constraintPlaceholder"), text: $generateConstraint)
                    .font(.fkBodyMedium)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, FkSpacing.sm)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                            .fill(Color.fkSurface)
                    )

                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isGenerating ? String(localized: "dashboard.clearFridge.generating") : String(localized: "dashboard.clearFridge.generate"))
                            .font(.fkLabelLarge)
                    }
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                            .fill(Color.fkPrimary)
                    )
                }
                .buttonStyle(.fkPressable)
                .disabled(isGenerating)

                if let generateError {
                    Text(generateError)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The临期 ingredient names fed to the generator (the non-fresh rows currently
    /// shown), de-duplicated downstream by the generator's `sanitize`.
    private var expiringNames: [String] {
        store.sortedItems.map(\.name)
    }

    /// Runs the 清冰箱 generation: builds the chat call from the AI settings, asks
    /// `AiRecipeGenerator` for a draft, and on success presents the form sheet
    /// pre-filled for review. Failures (not-configured / network / parse) surface
    /// their Chinese `AiError.message` inline under the button — never silent.
    private func generate() async {
        guard !isGenerating else { return }
        generateError = nil

        let chatFn: AiChatFn
        switch AiChatAccess.resolve(byok: aiSettingsStore.settings, isPro: dependencies.proStore.isPro) {
        case .byok(let settings):
            chatFn = { messages in
                try await AiClient.chat(
                    settings: settings,
                    messages: messages,
                    responseFormat: ["type": .string("json_object")]
                )
            }
        case .builtIn:
            guard let builtIn = dependencies.builtInAiChatFn(responseFormat: ["type": .string("json_object")]) else {
                generateError = AiError.notConfigured.message
                return
            }
            chatFn = builtIn
        case .needsPro:
            showPaywall = true
            return
        }

        let names = expiringNames
        guard !names.isEmpty else {
            generateError = String(localized: "dashboard.clearFridge.emptyError")
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let draft = try await AiRecipeGenerator.fromIngredients(
                names,
                constraint: generateConstraint,
                chatFn: chatFn
            )
            generatedDraft = GeneratedDraftRoute(draft: draft)
        } catch let error as AiError {
            generateError = error.message
        } catch {
            generateError = String(localized: "dashboard.clearFridge.generateFailed \(error.localizedDescription)")
        }
    }

    /// Per-item quick actions: 用了 (consumed removal) + 加购 (shopping add).
    private func actionRow(_ item: Ingredient) -> some View {
        HStack(spacing: FkSpacing.sm) {
            actionButton(String(localized: "dashboard.expiring.consumed"), systemImage: "fork.knife", tint: Color.fkPrimary) {
                Task {
                    switch await onConsume(item) {
                    case let .removed(undo):
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = undo }
                    case .notFound:
                        // The row was already gone — the consume reload
                        // self-heals the list; nothing to offer an undo for.
                        break
                    case .failed:
                        // The persist threw: the row is still here and no
                        // departure was logged — silence would read as a dead
                        // tap, so say so (mirrors MealPlan's toggle failure).
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = String(localized: "dashboard.expiring.actionFailed") }
                    }
                }
            }
            actionButton(String(localized: "dashboard.expiring.addToShopping"), systemImage: "cart.badge.plus", tint: Color.fkOnSurfaceVariant) {
                Task {
                    let message = await onAddToShopping(item)
                    if !message.isEmpty {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = message }
                    }
                }
            }
            // #18: jump to 食谱 tab filtered to dishes using this expiring item.
            actionButton(String(localized: "dashboard.expiring.cookThis"), systemImage: "frying.pan", tint: Color.fkPrimary) {
                recipeFilterRouter.capture(ingredient: item.name)
            }
        }
    }

    private func actionButton(
        _ label: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.fkLabelMedium)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
            )
        }
        .buttonStyle(.fkPressable)
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

    /// Transient post-用了 banner (ports IngredientDetailView's undoBanner): tapping
    /// 撤销 re-adds the row AND point-deletes the logged departure; otherwise it
    /// auto-clears after a short grace period (no screen to pop here, unlike the detail).
    @ViewBuilder
    private var undoBanner: some View {
        if let undo = pendingUndo {
            HStack(spacing: FkSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.fkSuccess)
                Text(String(localized: "dashboard.expiring.consumedUndo \(undo.ingredient.displayName)"))
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: FkSpacing.sm)
                Button(String(localized: "dashboard.expiring.undo")) { Task { await performUndo(undo) } }
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkPrimary)
            }
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, FkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerLowest)
            )
            .fkCardShadow()
            .padding(.horizontal, FkSpacing.lg)
            .padding(.bottom, FkSpacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.loggedEntryId) {
                // Grace period for undo; a fresh 用了 retargets the id and restarts
                // it, and an undo clears pendingUndo (tearing this down) first.
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled {
                    withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
                }
            }
        }
    }

    /// Reverses a 用了 removal — re-insert the row + point-delete the logged
    /// departure (both sides, via InventoryStore.undoRemove) — then reloads the
    /// expiring snapshot so the row reappears in its tier.
    private func performUndo(_ undo: InventoryStore.RemovalUndo) async {
        _ = await inventoryStore.undoRemove(undo)
        await store.load()
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
    }

    private func tierHeader(_ tier: ExpiringStore.Tier) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Circle()
                .fill(tier.state.statusStyle.foreground)
                .frame(width: 8, height: 8)
            Text(tier.state.expiringSectionTitle)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
            Text(String(localized: "dashboard.expiring.itemCount \(tier.items.count)"))
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }
}

/// `Identifiable` route wrapping a generated `RecipeDraft` so it can drive
/// `.sheet(item:)` (the transient `RecipeDraft` has no id of its own). Each
/// generation gets a fresh id so re-generating re-presents the sheet.
private struct GeneratedDraftRoute: Identifiable {
    let id = UUID()
    let draft: RecipeDraft
}

/// At-a-glance reminder-status card atop the 临期 screen (ports the Flutter
/// `_RemindShortcut`). Unlike Flutter's decorative hardcoded copy, this reads the
/// REAL OS permission + the live `ReminderSettings`. No deep-link to Settings:
/// 设置 is a separate tab in iOS, so jumping there would yank the user out of the
/// 临期 stack — the value here is the status, not the navigation.
private struct RemindStatusCard: View {
    let granted: Bool
    let settings: ReminderSettings

    var body: some View {
        FkCard(padding: FkSpacing.md, background: .fkPrimarySoft) {
            HStack(spacing: FkSpacing.md) {
                ZStack {
                    Circle().fill(Color.fkSurfaceContainerLowest).frame(width: 36, height: 36)
                    Image(systemName: granted ? "bell.badge.fill" : "bell.slash")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkPrimaryContainer)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(granted ? String(localized: "dashboard.reminder.granted") : String(localized: "dashboard.reminder.ungranted"))
                        .font(.fkLabelLarge)
                        .foregroundStyle(Color.fkPrimaryContainer)
                    Text(subtitle)
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkPrimaryContainer.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Honest reminder summary from the live settings (parity improvement over
    /// Flutter's static literal).
    private var subtitle: String {
        guard granted else { return String(localized: "dashboard.reminder.enableInSettings") }
        var parts: [String] = []
        let offsets = settings.enabledOffsetDays
        if !offsets.isEmpty {
            let days = offsets.map(String.init).joined(separator: "·")
            parts.append(String(localized: "dashboard.reminder.offsetDays \(days)"))
        }
        // Gate on `dailySummaryEnabled` (the scheduler's truth source: summaryOnly
        // forces it on even with remindDaily off) and use the configured time —
        // never the old hardcoded 9:00 — so the card never claims "未设置提醒时机"
        // while a summary actually fires.
        if settings.dailySummaryEnabled {
            parts.append(String(localized: "dashboard.reminder.dailySummary \(settings.reminderTimeLabel)"))
        }
        return parts.isEmpty ? String(localized: "dashboard.reminder.notSet") : parts.joined(separator: " · ")
    }
}

extension Ingredient {
    /// Stable list identity for `ForEach` shared by the Dashboard preview and the
    /// Expiring tiers (id when persisted, else a name+storage composite for
    /// local-only rows). Named distinctly from the Inventory view's fileprivate
    /// `identityKey` to avoid a same-type redeclaration.
    var fkListIdentityKey: String {
        id.isEmpty ? "\(name)\u{0}\(storage.rawValue)\u{0}\(quantity)\u{0}\(unit)" : id
    }
}
