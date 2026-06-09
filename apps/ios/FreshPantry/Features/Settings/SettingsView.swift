import SwiftUI

/// The 设置 tab ("我的"): a grouped form over the cream surface with the locally
/// persisted setting groups — 临期提醒 toggles, 忌口 keyword editor, an AI 助手
/// sub-screen, and an 关于 footer with the bundle version.
///
/// Follows the established feature pattern: reads the shared stores off the
/// injected `AppDependencies` (so settings stay consistent app-wide) and binds
/// the form rows directly to them. The 更多 section links to the 数据备份
/// export/import sub-screen.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        NavigationStack {
            SettingsContent(
                reminderStore: dependencies.reminderSettingsStore,
                dietaryStore: dependencies.dietaryPreferencesStore,
                dietPreferenceStore: dependencies.dietPreferenceStore,
                aiStore: dependencies.aiSettingsStore,
                appearanceStore: dependencies.appearanceStore,
                auth: dependencies.authService,
                notifications: dependencies.notificationCoordinator,
                householdID: dependencies.householdID
            )
            .navigationTitle("设置")
        }
    }
}

/// Inner content bound to the live stores (split out so `@Bindable`-free direct
/// observation of the `@Observable` stores drives row state).
private struct SettingsContent: View {
    let reminderStore: ReminderSettingsStore
    let dietaryStore: DietaryPreferencesStore
    let dietPreferenceStore: DietPreferenceStore
    let aiStore: AiSettingsStore
    let appearanceStore: AppearanceStore
    @Bindable var auth: AuthService
    let notifications: NotificationCoordinator
    let householdID: String

    @Environment(AppDependencies.self) private var dependencies
    /// Live OS notification-permission state, refreshed on appear and after a
    /// grant request. Drives the 提醒 permission affordance row.
    @State private var permissionGranted = false
    /// At-a-glance counts for the stats row (食材 / 采购 / 收藏菜谱).
    @State private var inventoryCount = 0
    @State private var shoppingCount = 0
    /// Built when signed-in to drive the 家庭共享 row's dynamic subtitle (name · N
    /// 名成员) and the pending-invite red dot. nil in local-only / signed-out.
    @State private var householdStore: HouseholdSessionStore?

    var body: some View {
        Form {
            statsSection
            accountSection
            reminderSection
            dietarySection
            dietPreferenceSection
            assistantSection
            appearanceSection
            comingSoonSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .tint(.fkPrimary)
        .task {
            permissionGranted = await notifications.refreshPermission()
            await loadStats()
            await loadHousehold()
        }
    }

    /// Builds the household store (when a backend is configured + signed in) and
    /// refreshes it, so the 家庭共享 row can show the live household name + member
    /// count and the pending-invite red dot. No-op in local-only / signed-out.
    private func loadHousehold() async {
        guard dependencies.remotePantryRepository != nil, auth.signedInEmail != nil else {
            householdStore = nil
            return
        }
        let store = householdStore ?? HouseholdSessionStore(
            remote: dependencies.remotePantryRepository,
            session: dependencies.syncSession,
            auth: auth,
            inventory: dependencies.inventoryRepository,
            shopping: dependencies.shoppingRepository,
            customRecipe: dependencies.customRecipeRepository,
            mealPlan: dependencies.mealPlanRepository
        )
        householdStore = store
        await store.refreshHouseholds()
    }

    /// Count of invites addressed to the user — drives the 家庭共享 red dot.
    private var pendingInviteCount: Int { householdStore?.pendingInvitePreviews.count ?? 0 }

    // MARK: 统计概览

    private var statsSection: some View {
        Section {
            HStack(spacing: FkSpacing.sm) {
                StatTile(value: inventoryCount, label: "件食材", systemImage: "refrigerator")
                StatTile(value: shoppingCount, label: "项采购", systemImage: "cart")
                StatTile(value: dependencies.favoritesStore.favoriteIDs.count, label: "个收藏", systemImage: "heart")
            }
            .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: FkSpacing.md, bottom: FkSpacing.sm, trailing: FkSpacing.md))
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    private func loadStats() async {
        inventoryCount = ((try? await dependencies.inventoryRepository.loadAllFor(householdID)) ?? []).count
        shoppingCount = ((try? await dependencies.shoppingRepository.loadAllFor(householdID)) ?? []).count
    }

    // MARK: 账号

    private var accountSection: some View {
        Section {
            NavigationLink {
                LoginView(auth: auth)
            } label: {
                SettingsLinkLabel(
                    systemImage: accountIcon,
                    title: "账号",
                    subtitle: accountSubtitle
                )
            }
            NavigationLink {
                HouseholdView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "house.and.flag",
                    title: "家庭共享",
                    subtitle: householdSubtitle,
                    showBadge: pendingInviteCount > 0
                )
            }
        } header: {
            Text("账号 · 家庭")
        } footer: {
            Text("登录后可创建或加入家庭,在成员间同步库存、采购与食谱。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    /// The 家庭共享 row subtitle, reflecting whether sharing is usable yet. When
    /// signed in and in a household, shows the live "name · N 名成员"; a pending
    /// invite adds a "· N 条邀请" hint alongside the red dot.
    private var householdSubtitle: String {
        switch auth.state {
        case .signedIn:
            if let household = householdStore?.selectedHousehold {
                let base = "\(household.name) · \(householdStore?.members.count ?? 0) 名成员"
                return pendingInviteCount > 0 ? "\(base) · \(pendingInviteCount) 条邀请" : base
            }
            return pendingInviteCount > 0 ? "\(pendingInviteCount) 条待处理邀请" : "管理家庭成员与邀请"
        case .localOnly: return "未配置后端 · 不可用"
        default: return "登录后创建或加入家庭"
        }
    }

    private var accountIcon: String {
        switch auth.state {
        case .signedIn: "person.crop.circle.fill"
        case .localOnly: "person.crop.circle.badge.xmark"
        default: "person.crop.circle"
        }
    }

    private var accountSubtitle: String {
        switch auth.state {
        case let .signedIn(email): email
        case .localOnly: "未配置后端 · 本地模式"
        default: "登录以同步家庭数据"
        }
    }

    // MARK: 提醒

    private var reminderSection: some View {
        Section {
            NotificationPermissionRow(
                granted: permissionGranted,
                onRequest: {
                    permissionGranted = await notifications.requestPermission(householdID: householdID)
                }
            )
            ReminderToggleRow(
                store: reminderStore,
                flag: .d1,
                title: "提前 1 天提醒",
                subtitle: "高优先级 · 推送 + 角标",
                onChange: rescheduleReminders
            )
            ReminderToggleRow(
                store: reminderStore,
                flag: .d3,
                title: "提前 3 天提醒",
                subtitle: "标准 · 仅推送",
                onChange: rescheduleReminders
            )
            ReminderToggleRow(
                store: reminderStore,
                flag: .d7,
                title: "提前 7 天提醒",
                subtitle: "轻量 · 仅角标",
                onChange: rescheduleReminders
            )
            ReminderToggleRow(
                store: reminderStore,
                flag: .daily,
                title: "每日 9:00 汇总",
                subtitle: "包含临期 + 库存不足",
                onChange: rescheduleReminders
            )
        } header: {
            Text("临期提醒")
        } footer: {
            Text("提醒在开启系统通知权限后送达。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    /// Recompute the scheduled notification set after a reminder toggle changes.
    private func rescheduleReminders() {
        Task { await notifications.reschedule(householdID: householdID) }
    }

    // MARK: 忌口

    private var dietarySection: some View {
        Section {
            DietaryExclusionEditor(store: dietaryStore)
        } header: {
            Text("忌口")
        } footer: {
            Text("含这些关键字的食材会在菜谱推荐中被过滤。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: 饮食偏好

    private var dietPreferenceSection: some View {
        Section {
            FlowLayout(spacing: FkSpacing.sm) {
                ForEach(DietPreferenceStore.allLabels, id: \.self) { label in
                    FkChip(label: label, isSelected: dietPreferenceStore.isSelected(label)) {
                        dietPreferenceStore.toggle(label)
                    }
                }
            }
            .padding(.vertical, FkSpacing.xs)
        } header: {
            Text("饮食偏好")
        } footer: {
            Text("根据偏好为「现有」与「今日推荐」加权排序菜谱。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: AI 助手

    private var assistantSection: some View {
        Section {
            NavigationLink {
                AiSettingsView(store: aiStore)
            } label: {
                SettingsLinkLabel(
                    systemImage: "sparkles",
                    title: "AI 助手",
                    subtitle: aiStore.isConfigured ? "已配置 · \(aiStore.settings.model)" : "配置模型与连接"
                )
            }
        } header: {
            Text("AI 助手")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: 外观

    /// 跟随系统/浅色/深色 segmented picker. Binding is built inside the
    /// `@MainActor` `body` (the `ReminderToggleRow` pattern) so the store
    /// mutation never crosses an isolation boundary.
    private var appearanceSection: some View {
        let binding = Binding(
            get: { appearanceStore.mode },
            set: { appearanceStore.set($0) }
        )
        return Section {
            Picker("外观", selection: binding) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: FkSpacing.md, bottom: FkSpacing.sm, trailing: FkSpacing.md))
        } header: {
            Text("外观")
        } footer: {
            Text("「跟随系统」随 iOS 外观自动切换浅色与深色。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: 更多

    private var comingSoonSection: some View {
        Section {
            NavigationLink {
                WasteInsightsView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "leaf.fill",
                    title: "减废成效",
                    subtitle: "本月用掉与浪费 · 越用越省"
                )
            }
            NavigationLink {
                BackupView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "tray.and.arrow.up",
                    title: "数据备份",
                    subtitle: "导出或恢复本机数据"
                )
            }
        } header: {
            Text("更多")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer()
                Text(AppVersion.displayString)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            HStack {
                Text("开源致谢")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer()
                Text("HowToCook · Unlicense")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        } header: {
            Text("关于 \(AppVersion.appName)")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }
}

// MARK: - Rows

/// One at-a-glance stat tile (big count + icon + label) for the settings overview.
private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: FkSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.fkPrimary)
            Text("\(value)")
                .font(.fkTitleLarge)
                .foregroundStyle(Color.fkOnSurface)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FkSpacing.sm)
    }
}

/// A reminder toggle row: title + caption + a `Switch` bound through the store's
/// `ReminderFlag` accessor. Binding is built inside the `@MainActor` `body` so the
/// store mutation never crosses an isolation boundary.
private struct ReminderToggleRow: View {
    let store: ReminderSettingsStore
    let flag: ReminderSettingsStore.Flag
    let title: String
    let subtitle: String
    /// Invoked after the flag persists, so reminders are rescheduled.
    let onChange: () -> Void

    var body: some View {
        let binding = Binding(
            get: { store.value(for: flag) },
            set: {
                store.setValue($0, for: flag)
                onChange()
            }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(subtitle)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}

/// The 提醒 permission affordance: a CTA to grant OS notification permission
/// when ungranted, collapsing to an "已开启" status row once granted. The async
/// request runs on tap; the parent refreshes `granted` from its result.
private struct NotificationPermissionRow: View {
    let granted: Bool
    let onRequest: () async -> Void

    @State private var requesting = false

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            Image(systemName: granted ? "bell.badge.fill" : "bell.slash")
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(granted ? Color.fkPrimary : Color.fkOnSurfaceVariant)
                .frame(width: FkSize.settingsIconBox)
            VStack(alignment: .leading, spacing: 2) {
                Text("通知权限")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(granted ? "已开启 · 提醒可送达" : "开启后临期提醒才会送达")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.fkPrimary)
            } else {
                Button("开启") {
                    requesting = true
                    Task {
                        await onRequest()
                        requesting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.fkPrimary)
                .disabled(requesting)
            }
        }
    }
}

/// A leading-icon nav-link label matching the Flutter `_LinkRow` shape.
private struct SettingsLinkLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    /// Renders a red notification dot on the icon (e.g. a pending family invite).
    var showBadge: Bool = false

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                    .fill(Color.fkPrimarySoft)
                    .frame(width: FkSize.settingsIconBox, height: FkSize.settingsIconBox)
                Image(systemName: systemImage)
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
            }
            .overlay(alignment: .topTrailing) {
                if showBadge {
                    Circle()
                        .fill(Color.fkDanger)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.fkSurfaceContainerLowest, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(subtitle)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}
