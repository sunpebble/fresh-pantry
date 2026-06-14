import Charts
import SwiftUI

/// The 减废统计 screen: a use-up-rate headline over consumed/wasted/rescued metric
/// tiles and a per-category consumed-vs-wasted breakdown, with a switchable time
/// window. Pushed from the Dashboard (首页) — lives inside the host
/// `NavigationStack`, so it owns no stack of its own.
///
/// Builds its `WasteInsightsStore` from the injected `AppDependencies` (the
/// reusable feature pattern). In DEBUG it runs `FoodLogSeeder` (seed-then-load,
/// the same idempotent one-shot the other tabs use) before loading, so the
/// screen has data even on a fresh install. SwiftData is never touched here.
struct WasteInsightsView: View {
    var onSelectCategory: (String) -> Void = { _ in }
    var onSelectExpiringRecipes: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var store: WasteInsightsStore?

    var body: some View {
        Group {
            if let store {
                WasteInsightsContent(
                    store: store,
                    onSelectCategory: onSelectCategory,
                    onSelectExpiringRecipes: onSelectExpiringRecipes,
                    onNavigateAway: { dismiss() }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle("减废统计")
        .navigationBarTitleDisplayMode(.inline)
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the stats re-scope to the new household rather than
        // keeping the prior scope's stale food-log records.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's records come from sync, never the seeder.
            if householdID.isEmpty {
                await FoodLogSeeder.seedIfNeeded(
                    repository: dependencies.foodLogRepository,
                    householdID: householdID
                )
            }
            #endif
            let store = WasteInsightsStore(
                repository: dependencies.foodLogRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            // OFFLINE-FIRST, NO FLASH: load the new scope's local records BEFORE
            // swapping the store in, so a household switch keeps the previous stats on
            // screen until the new (local, instant) data is ready instead of flashing
            // an empty state. Guard after the load so a newer switch landing here
            // doesn't assign this stale scope's store.
            await store.load()
            guard householdID == dependencies.householdID, !Task.isCancelled else { return }
            self.store = store
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the stats reflect food-log records pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store. Split out so `@Bindable` drives the
/// window selection.
private struct WasteInsightsContent: View {
    @Bindable var store: WasteInsightsStore
    var onSelectCategory: (String) -> Void
    var onSelectExpiringRecipes: () -> Void
    var onNavigateAway: () -> Void

    var body: some View {
        let summary = store.summary()
        return ScrollView {
            VStack(spacing: FkSpacing.lg) {
                WindowSelector(selected: $store.window)
                    .padding(.horizontal, FkSpacing.lg)

                categoryFilterChips

                achievementsSection

                body(
                    stats: summary.stats,
                    breakdown: summary.breakdown,
                    mostWasted: summary.mostWasted
                )
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
    }

    /// 分类下钻筛选行 — drills the whole window (stats / breakdown / 最常浪费 /
    /// history) into one category. Derived from the in-window buckets; the row hides
    /// on an empty log (no dead control). Mirrors the inventory/recipe filter rows,
    /// including keeping a stale selection clearable.
    @ViewBuilder
    private var categoryFilterChips: some View {
        let options = categoryChips
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FkSpacing.sm) {
                    FkChip(label: "全部分类", isSelected: store.categoryFilter == nil) {
                        store.categoryFilter = nil
                    }
                    ForEach(options, id: \.self) { category in
                        FkChip(label: category, isSelected: store.categoryFilter == category) {
                            // Re-tap the active category to clear it (back to 全部分类).
                            store.categoryFilter = (store.categoryFilter == category) ? nil : category
                        }
                    }
                }
                .padding(.horizontal, FkSpacing.lg)
            }
        }
    }

    /// 减废成就 / 零浪费连胜 — process rewards over the full loaded log. Hidden
    /// until there's at least one log so an empty screen stays clean.
    @ViewBuilder
    private var achievementsSection: some View {
        let badges = store.achievements()
        if !store.entries.isEmpty {
            FkCard {
                VStack(alignment: .leading, spacing: FkSpacing.md) {
                    Text("减废成就")
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnSurface)
                    FlowLayout(spacing: FkSpacing.sm) {
                        ForEach(badges) { badge in
                            badgePill(badge)
                        }
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    private func badgePill(_ badge: WasteAchievement) -> some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: badge.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(badge.title)
                .font(.fkLabelMedium)
        }
        .foregroundStyle(badge.unlocked ? Color.fkPrimary : Color.fkOnSurfaceVariant)
        .padding(.horizontal, FkSpacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(badge.unlocked ? Color.fkPrimarySoft : Color.fkSurfaceContainer))
        .opacity(badge.unlocked ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title),\(badge.unlocked ? "已解锁" : "未解锁"),\(badge.detail)")
    }

    /// In-window category buckets, with the active selection appended when it's no
    /// longer present (e.g. after switching to a window where it has no departures),
    /// so a stale filter always keeps a clearable chip.
    private var categoryChips: [String] {
        var options = store.categoryOptions()
        if let selected = store.categoryFilter, !options.contains(selected) {
            options.append(selected)
        }
        return options
    }

    @ViewBuilder
    private func body(stats: FoodLogStats, breakdown: [WasteCategoryBreakdown], mostWasted: [WasteCategoryCount]) -> some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView().padding(.top, 80)
        } else if stats.isEmpty {
            FkEmptyState(
                systemImage: "leaf",
                title: "还没有食材去向记录",
                message: "做菜用掉、或清理食材时选「吃完 / 扔了」,这里就会统计你的减废成效"
            )
            .padding(.top, FkSpacing.md)
        } else {
            VStack(spacing: FkSpacing.lg) {
                HeadlineCard(window: store.window, stats: stats)
                    .padding(.horizontal, FkSpacing.lg)

                MetricRow(stats: stats)
                    .padding(.horizontal, FkSpacing.lg)

                if stats.rescued > 0 || stats.wasted > 0 {
                    actionCard(stats: stats)
                        .padding(.horizontal, FkSpacing.lg)
                }

                if !breakdown.isEmpty {
                    CategoryBreakdownSection(breakdown: breakdown)
                        .padding(.horizontal, FkSpacing.lg)
                }

                if !mostWasted.isEmpty {
                    MostWastedSection(rows: mostWasted, onSelectCategory: { category in
                        onNavigateAway()
                        onSelectCategory(category)
                    })
                    .padding(.horizontal, FkSpacing.lg)
                }

                NavigationLink {
                    FoodLogHistoryView(store: store)
                } label: {
                    HStack(spacing: FkSpacing.sm) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(Color.fkPrimary)
                        Text("查看详细记录")
                            .font(.fkBodyMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }
                    .padding(.horizontal, FkSpacing.lg)
                    .padding(.vertical, FkSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .fill(Color.fkSurfaceContainer)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, FkSpacing.lg)
            }
        }
    }

    /// Actionable next steps — bridges waste stats into inventory/recipe flows.
    private func actionCard(stats: FoodLogStats) -> some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "下一步")
                if stats.rescued > 0 {
                    Button {
                        onNavigateAway()
                        onSelectExpiringRecipes()
                    } label: {
                        HStack(spacing: FkSpacing.sm) {
                            Image(systemName: "leaf.arrow.circlepath")
                                .foregroundStyle(Color.fkPrimary)
                            Text("用临期食材做菜")
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                    }
                    .buttonStyle(.fkPressable)
                }
                if stats.wasted > 0 {
                    Text("点「最常浪费」分类可查看库存中同类食材，优先安排使用。")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
    }
}

// MARK: - Window selector

/// Chip row over `WasteStatsWindow.allCases` (本月 / 近 30 天 / 近 90 天). Always
/// shown, even on an empty log, so the user can switch before any data exists.
private struct WindowSelector: View {
    @Binding var selected: WasteStatsWindow

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            ForEach(WasteStatsWindow.allCases, id: \.self) { window in
                FkChip(
                    label: window.label,
                    isSelected: window == selected,
                    action: { selected = window }
                )
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Headline (use-up rate)

/// A soft-tinted card with the big use-up-rate percent and a "共处理 N 样" subline.
private struct HeadlineCard: View {
    let window: WasteStatsWindow
    let stats: FoodLogStats

    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                Text("\(window.label)用掉率")
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)

                HStack(alignment: .firstTextBaseline, spacing: FkSpacing.xs) {
                    Text("\(stats.useUpPercent)")
                        .font(.fkHeroStat)
                        .foregroundStyle(Color.fkPrimary)
                    Text("%")
                        .font(.fkHeroSubStat)
                        .foregroundStyle(Color.fkPrimary)
                }

                Text("\(window.label)共处理 \(stats.total) 样食材")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Metric tiles (用掉 / 浪费 / 抢救临期)

private struct MetricRow: View {
    let stats: FoodLogStats

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            MetricTile(label: "用掉", value: stats.consumed, tint: .fkPrimary, fill: .fkPrimarySoft)
            MetricTile(label: "浪费", value: stats.wasted, tint: .fkDanger, fill: .fkDangerSoft)
            MetricTile(label: "抢救临期", value: stats.rescued, tint: .fkWarnInk, fill: .fkWarnSoft)
        }
    }
}

/// One soft-bg metric tile: a big tinted COUNT over a muted label.
private struct MetricTile: View {
    let label: String
    let value: Int
    let tint: Color
    let fill: Color

    var body: some View {
        VStack(spacing: FkSpacing.xs) {
            Text("\(value)")
                .font(.fkHeroSubStat)
                .foregroundStyle(tint)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(fill)
        )
    }
}

// MARK: - Category breakdown

/// Per-category consumed-vs-wasted bars (Swift Charts grouped bar). Each category
/// shows a 用掉 bar (primary) and a 浪费 bar (danger), so the user sees where waste
/// concentrates. Counts only — quantities are free-text and never summed.
/// "最常浪费" — categories ranked by wasted count desc, with explicit 件数 (the
/// ranking insight the category bar chart doesn't convey at a glance).
private struct MostWastedSection: View {
    let rows: [WasteCategoryCount]
    let onSelectCategory: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "最常浪费")
            FkCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelectCategory(row.category)
                        } label: {
                            HStack(spacing: FkSpacing.sm) {
                                Text(row.category)
                                    .font(.fkBodyMedium)
                                    .foregroundStyle(Color.fkOnSurface)
                                Spacer(minLength: 0)
                                Text("\(row.count) 样")
                                    .font(.fkBodyMedium.weight(.semibold))
                                    .foregroundStyle(Color.fkDanger)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.fkOnSurfaceVariant)
                            }
                            .padding(.horizontal, FkSpacing.lg)
                            .padding(.vertical, FkSpacing.md)
                        }
                        .buttonStyle(.fkPressable)
                        if index < rows.count - 1 {
                            Rectangle().fill(Color.fkHair).frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryBreakdownSection: View {
    let breakdown: [WasteCategoryBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "分类去向")

            FkCard {
                Chart {
                    ForEach(breakdown) { row in
                        BarMark(
                            x: .value("数量", row.consumed),
                            y: .value("分类", row.category)
                        )
                        .foregroundStyle(by: .value("去向", "用掉"))
                        .position(by: .value("去向", "用掉"))

                        BarMark(
                            x: .value("数量", row.wasted),
                            y: .value("分类", row.category)
                        )
                        .foregroundStyle(by: .value("去向", "浪费"))
                        .position(by: .value("去向", "浪费"))
                    }
                }
                .chartForegroundStyleScale(["用掉": Color.fkPrimary, "浪费": Color.fkDanger])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, spacing: FkSpacing.sm)
                .frame(height: chartHeight)
            }
        }
    }

    /// Roughly 44pt per category plus padding for the legend, so few-category
    /// charts stay compact and many-category charts stay readable.
    private var chartHeight: CGFloat {
        CGFloat(breakdown.count) * 48 + 48
    }
}

// MARK: - Detailed history + outcome correction

/// Browsable per-departure log for the active stats window, with one-tap
/// outcome correction when a row was logged as the wrong choice.
private struct FoodLogHistoryView: View {
    @Bindable var store: WasteInsightsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toast: String?

    var body: some View {
        let rows = store.historyEntries()
        return Group {
            if rows.isEmpty {
                FkEmptyState(
                    systemImage: "list.bullet",
                    title: "这个时段还没有记录",
                    message: "切换上方时间范围，或先去用掉 / 清理一些食材"
                )
                .padding(.top, FkSpacing.md)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            FoodLogHistoryRow(entry: entry) { outcome in
                                Task {
                                    let ok = await store.correctOutcome(entryId: entry.id, to: outcome)
                                    if !ok {
                                        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) {
                                            toast = "修改失败，请重试"
                                        }
                                    }
                                }
                            }
                            if index < rows.count - 1 {
                                Rectangle().fill(Color.fkHair).frame(height: 0.5)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .fill(Color.fkSurfaceContainer)
                    )
                    .padding(.horizontal, FkSpacing.lg)
                    .padding(.vertical, FkSpacing.sm)
                }
            }
        }
        .background(Color.fkSurface)
        .overlay(alignment: .top) { toastBanner }
        .navigationTitle("详细记录")
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct FoodLogHistoryRow: View {
    let entry: FoodLogEntry
    let onCorrect: (FoodLogOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            HStack(alignment: .top, spacing: FkSpacing.sm) {
                VStack(alignment: .leading, spacing: FkSpacing.xs) {
                    Text(entry.name)
                        .font(.fkBodyMedium.weight(.semibold))
                        .foregroundStyle(Color.fkOnSurface)
                    Text(FoodCategories.dropdownValue(entry.category))
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: FkSpacing.xs) {
                    Text(outcomeLabel)
                        .font(.fkLabelSmall.weight(.semibold))
                        .foregroundStyle(outcomeColor)
                    Text(Self.dateLabel(entry.loggedAt))
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
            if entry.wasExpiring && entry.isConsumed {
                Text("抢救临期")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkWarnInk)
            }
            HStack(spacing: FkSpacing.sm) {
                Text("记错了？改成")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                Button(entry.isConsumed ? "浪费" : "用掉") {
                    onCorrect(entry.isConsumed ? .wasted : .consumed)
                }
                .font(.fkBodySmall.weight(.semibold))
                .foregroundStyle(Color.fkPrimary)
            }
        }
        .padding(.horizontal, FkSpacing.lg)
        .padding(.vertical, FkSpacing.md)
    }

    private var outcomeLabel: String { entry.isConsumed ? "用掉" : "浪费" }
    private var outcomeColor: Color { entry.isConsumed ? .fkPrimary : .fkDanger }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
