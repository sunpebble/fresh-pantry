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
    var onSelectCategory: (String) -> Void = { _ in }
    var onSelectExpiringRecipes: () -> Void = {}
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
                householdID: dependencies.householdID,
                onSelectCategory: onSelectCategory,
                onSelectExpiringRecipes: onSelectExpiringRecipes
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
    var onSelectCategory: (String) -> Void = { _ in }
    var onSelectExpiringRecipes: () -> Void = {}

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
            profileCardSection
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
            await dependencies.profileStore.load(signedIn: auth.signedInEmail != nil)
        }
        .onChange(of: dependencies.syncSession.inviteRefreshRevision) {
            Task { await householdStore?.refreshPendingInvites() }
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

    // MARK: 个人资料卡片

    /// The top 「我」 card: pushes the read-only `ProfileDetailView`. The family /
    /// sync / account lines are computed here — the detail view stays
    /// presentation-only and never reaches into household / auth itself.
    private var profileCardSection: some View {
        Section {
            NavigationLink {
                ProfileDetailView(
                    store: dependencies.profileStore,
                    familyLine: profileFamilyLine,
                    syncLine: profileSyncLine,
                    accountLine: accountSubtitle
                )
            } label: {
                ProfileCardRow(
                    avatarURL: dependencies.profileStore.avatarURL,
                    model: ProfileCardModel(
                        displayName: dependencies.profileStore.displayName,
                        nickname: dependencies.profileStore.nickname,
                        accountFallback: accountSubtitle
                    )
                )
            }
            .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: FkSpacing.md, bottom: FkSpacing.sm, trailing: FkSpacing.md))
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    /// 家庭行 ("小白家 · 管理员"); nil when signed out / no household selected, so
    /// the detail page hides the row instead of showing an empty value.
    private var profileFamilyLine: String? {
        guard let store = householdStore, let household = store.selectedHousehold else { return nil }
        return "\(household.name) · \(store.isOwnerOfSelected ? "管理员" : "成员")"
    }

    /// 同步状态行 — surfaces `ProfileStore.hasPendingUpload` so a failed profile
    /// save stays visible ("失败可见"); nil when local-only / signed out (nothing syncs).
    private var profileSyncLine: String? {
        guard case .signedIn = auth.state else { return nil }
        return dependencies.profileStore.hasPendingUpload ? "待同步…" : "已同步"
    }

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
            // Per-item + daily toggles are hidden under 仅每日汇总: in that mode
            // `enabledOffsetDays` is [] and the daily summary is forced on, so
            // leaving these tappable would let the user flip switches that have
            // no effect (and a daily row reading OFF while a summary still fires).
            if !reminderStore.settings.summaryOnly {
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
                    title: "每日 \(reminderTimeLabel) 汇总",
                    subtitle: "包含临期 + 库存不足",
                    onChange: rescheduleReminders
                )
            }
            ReminderTimeRow(store: reminderStore, onChange: rescheduleReminders)
            SummaryOnlyRow(store: reminderStore, onChange: rescheduleReminders)
            QuietHoursToggleRow(store: reminderStore, onChange: rescheduleReminders)
            if reminderStore.settings.quietHoursEnabled {
                QuietHoursTimeRow(store: reminderStore, onChange: rescheduleReminders)
            }
        } header: {
            Text("临期提醒")
        } footer: {
            Text("提醒在开启系统通知权限后送达。开启「仅每日汇总」可关闭逐条临期推送、只保留一条汇总;免打扰时段内逐条提醒不再打扰。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    /// "9:00"-style label of the user-chosen reminder time. Delegates to the
    /// model's single-source label (shared with the Dashboard reminder card).
    private var reminderTimeLabel: String { reminderStore.settings.reminderTimeLabel }

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
                WasteInsightsView(
                    onSelectCategory: onSelectCategory,
                    onSelectExpiringRecipes: onSelectExpiringRecipes
                )
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

/// The 提醒时间 row: a compact hour-and-minute `DatePicker` bound through the
/// store's `setReminderTime`. Only time-of-day components round-trip — the date
/// part of the binding is a throwaway anchor on "today". Mirrors
/// `ReminderToggleRow`: the binding is built inside the `@MainActor` `body`,
/// and `onChange` reschedules after the time persists.
private struct ReminderTimeRow: View {
    let store: ReminderSettingsStore
    /// Invoked after the time persists, so reminders are rescheduled.
    let onChange: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let binding = Binding(
            get: {
                calendar.date(
                    bySettingHour: store.settings.reminderHour,
                    minute: store.settings.reminderMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let comps = calendar.dateComponents([.hour, .minute], from: newDate)
                store.setReminderTime(
                    hour: comps.hour ?? ReminderSettings.defaultReminderHour,
                    minute: comps.minute ?? ReminderSettings.defaultReminderMinute
                )
                onChange()
            }
        )
        return DatePicker(selection: binding, displayedComponents: .hourAndMinute) {
            VStack(alignment: .leading, spacing: 2) {
                Text("提醒时间")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("临期提醒与每日汇总的送达时间")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .datePickerStyle(.compact)
    }
}

/// The 仅每日汇总 row: a `Switch` that, when on, suppresses every per-item
/// reminder and keeps only the daily summary. Mirrors `ReminderToggleRow`'s
/// binding-in-`body` pattern; `onChange` reschedules after the flag persists.
private struct SummaryOnlyRow: View {
    let store: ReminderSettingsStore
    /// Invoked after the flag persists, so reminders are rescheduled.
    let onChange: () -> Void

    var body: some View {
        let binding = Binding(
            get: { store.settings.summaryOnly },
            set: {
                store.setSummaryOnly($0)
                onChange()
            }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("仅每日汇总")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("关闭逐条临期推送 · 每天只发一条汇总")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}

/// The 免打扰时段 enable row: a `Switch` that turns the do-not-disturb window on
/// or off. When on, the `QuietHoursTimeRow` appears beneath it.
private struct QuietHoursToggleRow: View {
    let store: ReminderSettingsStore
    /// Invoked after the flag persists, so reminders are rescheduled.
    let onChange: () -> Void

    var body: some View {
        let binding = Binding(
            get: { store.settings.quietHoursEnabled },
            set: {
                store.setQuietHoursEnabled($0)
                onChange()
            }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("免打扰时段")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("此时段内逐条临期提醒不再打扰")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}

/// The 免打扰起止 row: two compact hour `DatePicker`s (start / end) bound through
/// the store's `setQuietHours`. Only the hour component round-trips — minute is
/// pinned to 0 (the suppression check is hour-granular). Both bindings are built
/// inside the `@MainActor` `body`; `onChange` reschedules after each edit.
private struct QuietHoursTimeRow: View {
    let store: ReminderSettingsStore
    /// Invoked after the time persists, so reminders are rescheduled.
    let onChange: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let startBinding = Binding(
            get: { hourDate(store.settings.quietStartHour, calendar) },
            set: { newDate in
                store.setQuietHours(
                    startHour: calendar.component(.hour, from: newDate),
                    endHour: store.settings.quietEndHour
                )
                onChange()
            }
        )
        let endBinding = Binding(
            get: { hourDate(store.settings.quietEndHour, calendar) },
            set: { newDate in
                store.setQuietHours(
                    startHour: store.settings.quietStartHour,
                    endHour: calendar.component(.hour, from: newDate)
                )
                onChange()
            }
        )
        return VStack(spacing: FkSpacing.xs) {
            DatePicker(selection: startBinding, displayedComponents: .hourAndMinute) {
                Text("开始")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
            }
            .datePickerStyle(.compact)
            DatePicker(selection: endBinding, displayedComponents: .hourAndMinute) {
                Text("结束")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
            }
            .datePickerStyle(.compact)
        }
    }

    /// A throwaway "today at `hour`:00" anchor — only the hour round-trips.
    private func hourDate(_ hour: Int, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
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

/// The top 「我」 card row: a 52pt avatar + name + nickname/account subtitle,
/// mirroring Apple Settings' Apple-ID card so the profile page is discoverable
/// at a glance. The enclosing `NavigationLink` draws the chevron.
private struct ProfileCardRow: View {
    let avatarURL: URL?
    let model: ProfileCardModel

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            MemberAvatar(displayName: model.title, avatarURL: avatarURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(model.subtitle)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, FkSpacing.xs)
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

/// Pure title/subtitle selection for the settings 「我」 card — extracted so the
/// branchy fallback logic is unit-testable without a SwiftUI host.
/// title: displayName when non-blank, else a "set me up" prompt.
/// subtitle: nickname when non-blank, else the account-state line.
struct ProfileCardModel {
    let displayName: String
    let nickname: String
    /// Account-state line (signed-in email / local-only / signed-out hint),
    /// computed by the view from the existing `accountSubtitle`.
    let accountFallback: String

    var title: String {
        displayName.trimmed.isEmpty ? "设置头像与名称" : displayName.trimmed
    }

    var subtitle: String {
        nickname.trimmed.isEmpty ? accountFallback : nickname.trimmed
    }
}
