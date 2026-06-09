import SwiftUI

/// The 临期 screen, pushed from the Dashboard: the household's non-fresh
/// inventory (state ∈ {expiringSoon, urgent, expired}), urgency-sorted and
/// sectioned by tier (已过期 → 快过期 → 即将过期).
///
/// Each row taps through to the read-only detail and carries two quick actions
/// (用了 → log a consumed departure + remove; 加购 → add to the shopping list),
/// mirroring the Flutter expiring screen's per-item affordances. It builds an
/// `ExpiringStore` (display) plus an `InventoryStore` (the 用了 removal + the
/// detail push) and a `ShoppingStore` (加购) from the injected `AppDependencies`.
struct ExpiringView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ExpiringStore?
    @State private var inventoryStore: InventoryStore?
    @State private var shoppingStore: ShoppingStore?
    /// Live OS notification-permission state, for the reminder-status card.
    @State private var remindersGranted = false

    var body: some View {
        Group {
            if let store, let inventoryStore {
                ExpiringContent(
                    store: store,
                    inventoryStore: inventoryStore,
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
        .navigationTitle("临期提醒")
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
            self.store = expiring
            self.inventoryStore = inventory
            self.shoppingStore = shopping
            await expiring.load()
            await inventory.load()
            await shopping.load()
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
    /// expiring list so it drops off.
    private func consume(_ item: Ingredient) async {
        guard let inventoryStore, let store else { return }
        _ = await inventoryStore.remove(item, outcome: .consumed)
        await store.load()
    }

    /// "加购": adds the item to the shopping list (name-unique dedup). Returns a
    /// short confirmation for the toast.
    private func addToShopping(_ item: Ingredient) async -> String {
        guard let shoppingStore else { return "" }
        let added = await shoppingStore.add(name: item.name, category: item.category)
        return added ? "已将「\(item.name)」加入购物清单" : "「\(item.name)」已在购物清单中"
    }
}

/// Inner content bound to live stores. Rows tap through to the detail; the
/// trailing 用了 / 加购 buttons are independent tap targets (not a nested Button).
private struct ExpiringContent: View {
    let store: ExpiringStore
    let inventoryStore: InventoryStore
    let reminderSettings: ReminderSettings
    let remindersGranted: Bool
    let onConsume: (Ingredient) async -> Void
    let onAddToShopping: (Ingredient) async -> String

    @State private var selectedIngredient: Ingredient?
    @State private var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        title: "暂无临期食材",
                        message: "冰箱状态健康，继续保持！"
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
        .navigationDestination(item: $selectedIngredient) { ingredient in
            IngredientDetailView(ingredient: ingredient, store: inventoryStore)
        }
    }

    private var tierList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.xl) {
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
        }
    }

    /// Per-item quick actions: 用了 (consumed removal) + 加购 (shopping add).
    private func actionRow(_ item: Ingredient) -> some View {
        HStack(spacing: FkSpacing.sm) {
            actionButton("用了", systemImage: "fork.knife", tint: Color.fkPrimary) {
                Task { await onConsume(item) }
            }
            actionButton("加购", systemImage: "cart.badge.plus", tint: Color.fkOnSurfaceVariant) {
                Task {
                    let message = await onAddToShopping(item)
                    if !message.isEmpty {
                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { toast = message }
                    }
                }
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

    private func tierHeader(_ tier: ExpiringStore.Tier) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Circle()
                .fill(tier.state.statusStyle.foreground)
                .frame(width: 8, height: 8)
            Text(tier.state.expiringSectionTitle)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
            Text("\(tier.items.count) 件")
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }
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
                    Text(granted ? "提醒已开启" : "通知未开启")
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
        guard granted else { return "去「设置 › 临期提醒」开启系统通知后送达" }
        var parts: [String] = []
        let offsets = settings.enabledOffsetDays
        if !offsets.isEmpty {
            parts.append("提前 " + offsets.map(String.init).joined(separator: "·") + " 天")
        }
        if settings.remindDaily { parts.append("每日 9:00 汇总") }
        return parts.isEmpty ? "未设置提醒时机" : parts.joined(separator: " · ")
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
