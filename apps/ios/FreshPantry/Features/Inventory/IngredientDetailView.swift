import SwiftUI

/// Read-only ingredient detail with a category-tinted hero, a quantity /
/// freshness split card, a storage / category / shelf-life info list, and a
/// destructive delete (confirmed) that calls the store and pops.
struct IngredientDetailView: View {
    let ingredient: Ingredient
    let store: InventoryStore

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showOutcomePrompt = false
    @State private var isDeleting = false
    /// Drives the edit sheet; `didSaveEdit` defers the detail pop to the sheet's
    /// dismissal so the list (which reflects the in-place store update) shows on return.
    @State private var showEdit = false
    @State private var didSaveEdit = false
    /// Cache-first OFF food-details lookup driving the nutrition card. Built lazily
    /// from `dependencies` on first appearance (mirrors the Flutter auto-fetch).
    @State private var detailsStore: FoodDetailsStore?
    /// Holds the just-removed row so the undo banner can reverse BOTH the
    /// inventory removal and the food-log append before the screen pops.
    @State private var pendingUndo: InventoryStore.RemovalUndo?
    /// Lazily-built shopping store backing the "加入购物清单" action (loaded once on
    /// first add so the dedup runs against the live list).
    @State private var shoppingStore: ShoppingStore?
    @State private var isAddingToShopping = false
    /// Drives the "用了一部分" amount-entry sheet + guards re-entrancy while a
    /// partial consume is in flight.
    @State private var showConsumeSheet = false
    @State private var isConsuming = false
    /// Transient confirmation copy shown after an add-to-shopping tap.
    @State private var toast: String?

    private var palette: FkCategoryColors { FkCategoryIcon.palette(for: ingredient.category) }

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.lg) {
                hero
                quantityAndFreshnessCard
                foodDetailsSection
                infoList
                consumePartialButton
                addToShoppingButton
            }
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .navigationTitle(ingredient.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if detailsStore == nil {
                let store = FoodDetailsStore(
                    ingredient: ingredient,
                    repository: dependencies.foodDetailsRepository
                )
                detailsStore = store
                await store.load()
            }
        }
        .overlay(alignment: .bottom) { undoBanner }
        .overlay(alignment: .top) { toastBanner }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(String(localized: "inventory.action.edit"))
                .disabled(isDeleting)

                Button(role: .destructive) {
                    showOutcomePrompt = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "inventory.action.delete"))
                .tint(.fkDanger)
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: {
            // After a successful edit, pop back to the list (which already reflects
            // the in-place store update). Mirrors the Flutter post-edit pop.
            if didSaveEdit { dismiss() }
        }) {
            EditIngredientView(original: ingredient, store: store) {
                didSaveEdit = true
            }
        }
        .sheet(isPresented: $showConsumeSheet) {
            PartialConsumeSheet(
                itemName: ingredient.name,
                available: availableQuantity ?? 0,
                unit: ingredient.unit
            ) { amount in
                Task { await performConsume(amount: amount) }
            }
        }
        .confirmationDialog(
            String(localized: "inventory.removeOutcome.title \(ingredient.name)"),
            isPresented: $showOutcomePrompt,
            titleVisibility: .visible
        ) {
            Button(String(localized: "inventory.removeOutcome.consumed")) { Task { await performRemove(outcome: .consumed) } }
            Button(String(localized: "inventory.removeOutcome.donated")) { Task { await performRemove(outcome: .donated) } }
            Button(String(localized: "inventory.removeOutcome.composted")) { Task { await performRemove(outcome: .composted) } }
            Button(String(localized: "inventory.removeOutcome.wasted")) { Task { await performRemove(outcome: .wasted) } }
            Button(String(localized: "inventory.removeOutcome.removeOnly")) { Task { await performDelete() } }
            Button(String(localized: "inventory.action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "inventory.removeOutcome.message"))
        }
    }

    // MARK: Undo banner

    /// A transient banner shown after a removal-with-outcome. Tapping 撤销 reverses
    /// the inventory removal AND point-deletes the logged departure; otherwise it
    /// auto-dismisses the screen after a short grace period.
    @ViewBuilder
    private var undoBanner: some View {
        if let undo = pendingUndo {
            HStack(spacing: FkSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.fkSuccess)
                Text(String(localized: "inventory.removeOutcome.recorded \(undo.ingredient.name)"))
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
                // Grace period for undo, then pop. Cancelled if the row is undone
                // (pendingUndo clears → this task is torn down before the sleep ends).
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { dismiss() }
            }
        }
    }

    // MARK: 用了一部分 (partial consume)

    /// The on-hand numeric magnitude of the quantity (the unit lives in the separate
    /// `unit` field), or nil when the quantity isn't a positive number — the
    /// "用了一部分" action only makes sense for a measurable quantity.
    private var availableQuantity: Double? {
        guard let parsed = QuantityText.parseLeadingQuantity(ingredient.quantity.trimmed),
              let value = Double(parsed.magnitude), value > 0 else { return nil }
        return value
    }

    /// "用了一部分" pill — opens the amount-entry sheet. Hidden for a non-numeric
    /// quantity (where a subtract-from is meaningless), so there's no dead control.
    @ViewBuilder
    private var consumePartialButton: some View {
        if availableQuantity != nil {
            Button {
                showConsumeSheet = true
            } label: {
                HStack(spacing: FkSpacing.sm) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                    Text(String(localized: "inventory.consume.partial"))
                        .font(.fkLabelLarge)
                }
                .foregroundStyle(Color.fkOnSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FkSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                        .fill(Color.fkSurfaceContainer)
                )
            }
            .buttonStyle(.fkPressable)
            .disabled(isConsuming || isDeleting)
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    // MARK: Add-to-shopping action

    /// "加入购物清单" pill (mirrors the Flutter detail `_ActionRow`). Builds +
    /// loads a shopping store on first use so the add dedups against the live list.
    private var addToShoppingButton: some View {
        Button {
            Task { await addToShopping() }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                Text(String(localized: "dashboard.expiring.addToShopping"))
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
        .disabled(isAddingToShopping)
        .padding(.horizontal, FkSpacing.lg)
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

    private func addToShopping() async {
        guard !isAddingToShopping else { return }
        isAddingToShopping = true
        defer { isAddingToShopping = false }

        if shoppingStore == nil {
            let store = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: dependencies.householdID,
                syncWriter: dependencies.syncWriter
            )
            await store.load()
            shoppingStore = store
        }
        guard let shoppingStore else { return }
        let added = await shoppingStore.add(name: ingredient.name, category: ingredient.category)
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
            toast = added
                ? String(localized: "dashboard.shopping.added \(ingredient.name)")
                : String(localized: "dashboard.shopping.duplicate \(ingredient.name)")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(
                imageUrl: ingredient.imageUrl,
                category: ingredient.category,
                size: 92,
                cornerRadius: FkRadius.xxl,
                iconScale: 0.55
            )

            VStack(spacing: FkSpacing.xs) {
                HStack(spacing: FkSpacing.sm) {
                    Text(ingredient.name)
                        .font(.fkHeadlineSmall)
                        .foregroundStyle(Color.fkOnSurface)
                    if ingredient.state != .fresh {
                        UrgencyBadge(state: ingredient.state)
                    }
                }
                Text("\(FoodCategories.displayLabel(for: FoodCategories.dropdownValue(ingredient.category))) · \(ingredient.storage.storageAreaLabel)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(palette.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FkSpacing.huge)
        .background(palette.tint)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: FkRadius.hero,
                bottomTrailingRadius: FkRadius.hero,
                style: .continuous
            )
        )
    }

    // MARK: Quantity + freshness

    private var quantityAndFreshnessCard: some View {
        let freshnessColor = ingredient.state == .expired ? Color.fkDanger : ingredient.state.statusStyle.foreground
        return FkCard {
            HStack(alignment: .top, spacing: 0) {
                statColumn(
                    label: String(localized: "inventory.detail.currentQuantity"),
                    value: ingredient.quantity,
                    unit: ingredient.unit,
                    valueColor: .fkOnSurface
                )
                Rectangle()
                    .fill(Color.fkHair)
                    .frame(width: 0.5)
                statColumn(
                    label: String(localized: "inventory.detail.freshness"),
                    value: "\(Int((min(max(ingredient.freshnessPercent, 0), 1) * 100).rounded()))",
                    unit: "%",
                    hint: ingredient.expiryLabel,
                    valueColor: freshnessColor
                )
            }
        }
        .padding(.horizontal, FkSpacing.lg)
    }

    private func statColumn(
        label: String,
        value: String,
        unit: String,
        hint: String? = nil,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: FkSpacing.xs) {
                Text(value)
                    .font(.fkHeroSubStat)
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.md)
    }

    // MARK: Food details (OFF) — image / description / nutrition

    /// The OFF-enriched section: a product image + description card and a per-100g
    /// nutrition card, each rendered only when the loaded details supply them.
    /// Renders nothing in idle / loading / not-found / error (the screen already
    /// shows the local quantity + info, so a failed lookup is silent).
    @ViewBuilder
    private var foodDetailsSection: some View {
        if case let .loaded(details) = detailsStore?.state {
            if hasProductCard(details) {
                productCard(details)
                    .padding(.horizontal, FkSpacing.lg)
            }
            if let nutrition = details.nutrition, nutrition.hasAny {
                NutritionCard(nutrition: nutrition)
                    .padding(.horizontal, FkSpacing.lg)
            }
        }
    }

    /// The product card is worth showing only when OFF added something beyond the
    /// local data — a real image and/or a non-placeholder description.
    private func hasProductCard(_ details: FoodDetails) -> Bool {
        let hasImage = !(details.imageUrl ?? "").trimmed.isEmpty
        let hasDescription = !details.description.trimmed.isEmpty
            && !isPlaceholderFoodDescription(details.description)
        return hasImage || hasDescription
    }

    private func productCard(_ details: FoodDetails) -> some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                if let imageUrl = details.imageUrl, !imageUrl.trimmed.isEmpty {
                    FkCategoryAvatar(
                        imageUrl: imageUrl,
                        category: details.category,
                        size: 72,
                        cornerRadius: FkRadius.lg,
                        iconScale: 0.5
                    )
                }
                if !details.description.trimmed.isEmpty,
                   !isPlaceholderFoodDescription(details.description) {
                    Text(details.description)
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(String(localized: "inventory.detail.dataSource"))
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }

    // MARK: Info list

    private var infoList: some View {
        FkCard(padding: 0) {
            VStack(spacing: 0) {
                infoRow(String(localized: "inventory.field.category"), FoodCategories.displayLabel(for: FoodCategories.dropdownValue(ingredient.category)))
                divider
                infoRow(String(localized: "inventory.field.storage"), ingredient.storage.storageAreaLabel)
                if let shelfLife = ingredient.shelfLifeDays, shelfLife > 0 {
                    divider
                    infoRow(String(localized: "inventory.detail.shelfLifeSuggestion"), String(localized: "inventory.shelfLife.days \(shelfLife)"))
                }
                if let expiry = ingredient.expiryDate {
                    divider
                    infoRow(String(localized: "inventory.detail.expiryDate"), Self.dateFormatter.string(from: expiry))
                }
            }
        }
        .padding(.horizontal, FkSpacing.lg)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Spacer()
            Text(value)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
        }
        .padding(FkSpacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.fkHair).frame(height: 0.5)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: Delete / remove-with-outcome

    /// Removes the row and logs the chosen outcome (consumed/wasted), then shows
    /// the undo banner (which pops after its grace period). The undo handle is the
    /// only path that can reverse the food-log append.
    private func performRemove(outcome: FoodLogOutcome) async {
        isDeleting = true
        let undo = await store.remove(ingredient, outcome: outcome)
        isDeleting = false
        if let undo {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = undo }
        } else {
            dismiss() // nothing matched (already gone) — just leave the screen
        }
    }

    /// Plain remove with NO departure logged (the "仅移除" choice).
    private func performDelete() async {
        isDeleting = true
        let removed = await store.delete(ingredient)
        isDeleting = false
        if removed {
            dismiss()
        } else {
            toast = String(localized: "inventory.remove.failed \(ingredient.name)")
        }
    }

    /// Reverses a removal-with-outcome (re-add row + point-delete the logged
    /// entry) and clears the banner, keeping the user on the detail screen.
    private func performUndo(_ undo: InventoryStore.RemovalUndo) async {
        _ = await store.undoRemove(undo)
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
    }

    /// Applies a partial consume. A decrement pops back to the list (which shows the
    /// reduced quantity — this screen's `ingredient` is an immutable snapshot, like
    /// the post-edit pop); a full depletion reuses the undo banner (row removed + a
    /// `.consumed` departure logged); a failure surfaces a retry toast.
    private func performConsume(amount: Double) async {
        isConsuming = true
        let result = await store.consumePartial(ingredient, amount: amount)
        isConsuming = false
        switch result {
        case .decremented:
            dismiss()
        case let .depleted(undo):
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = undo }
        case .invalid, .failed:
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                toast = String(localized: "dashboard.expiring.actionFailed")
            }
        }
    }
}

/// Amount-entry sheet for "用了一部分": shows what's on hand and takes the amount
/// used (decimal). "全部用完" is a shortcut that confirms the full remaining amount
/// (which the store treats as a full consume + departure log).
private struct PartialConsumeSheet: View {
    let itemName: String
    let available: Double
    let unit: String
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @FocusState private var fieldFocused: Bool

    private var amount: Double? {
        guard let value = Double(amountText.trimmed), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                Text(String(localized: "inventory.consume.remaining \(QuantityText.formatQuantity(available)) \(unit)"))
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)

                HStack(spacing: FkSpacing.sm) {
                    TextField(String(localized: "inventory.consume.amountPlaceholder"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.fkTitleMedium)
                        .focused($fieldFocused)
                        .padding(FkSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                                .fill(Color.fkSurfaceContainer)
                        )
                    Text(unit)
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }

                Button(String(localized: "inventory.consume.all")) {
                    onConfirm(available)
                    dismiss()
                }
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkPrimary)
                .accessibilityLabel(String(localized: "inventory.consume.allAccessibility \(itemName)"))

                Spacer(minLength: 0)
            }
            .padding(FkSpacing.lg)
            .navigationTitle(String(localized: "inventory.consume.partial"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "inventory.action.confirm")) {
                        guard let amount else { return }
                        onConfirm(amount)
                        dismiss()
                    }
                    .disabled(amount == nil)
                }
            }
            .task { fieldFocused = true }
        }
        .presentationDetents([.medium])
    }
}
