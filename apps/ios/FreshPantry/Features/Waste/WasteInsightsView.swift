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
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: WasteInsightsStore?

    var body: some View {
        Group {
            if let store {
                WasteInsightsContent(store: store)
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
                householdID: householdID
            )
            self.store = store
            await store.load()
        }
    }
}

/// Inner content bound to a live store. Split out so `@Bindable` drives the
/// window selection.
private struct WasteInsightsContent: View {
    @Bindable var store: WasteInsightsStore

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.lg) {
                WindowSelector(selected: $store.window)
                    .padding(.horizontal, FkSpacing.lg)

                body(stats: store.stats(), breakdown: store.categoryBreakdown(), mostWasted: store.mostWasted())
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
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

                if !breakdown.isEmpty {
                    CategoryBreakdownSection(breakdown: breakdown)
                        .padding(.horizontal, FkSpacing.lg)
                }

                if !mostWasted.isEmpty {
                    MostWastedSection(rows: mostWasted)
                        .padding(.horizontal, FkSpacing.lg)
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

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "最常浪费")
            FkCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: FkSpacing.sm) {
                            Text(row.category)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Spacer(minLength: 0)
                            Text("\(row.count) 样")
                                .font(.fkBodyMedium.weight(.semibold))
                                .foregroundStyle(Color.fkDanger)
                        }
                        .padding(.horizontal, FkSpacing.lg)
                        .padding(.vertical, FkSpacing.md)
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
