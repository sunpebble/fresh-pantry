import Foundation
import SwiftData

/// 从共享 SwiftData 容器派生小组件展示数据。复用既有 `@ModelActor` repo 加载,
/// 派生口径对齐 app(`ExpiryCalculator` 临期分级,`FoodLogStatistics` 减废)。
/// 仅依赖 Domain 层 + 共享 repo,不触碰 Features/UI/网络层(本类型会编进 widget)。
/// 所有方法纯读不写。
struct WidgetDataReader {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// 一次读满四类内容。**app 侧** `WidgetSnapshotPublisher` 在主进程(内存充足)
    /// 调用,算好写进 App Group;widget 时间线只读那份快照,从不在 widget 进程调用
    /// 本类型(其内存预算约 30MB,开 13 模型容器 + 取数会被 jetsam 杀)。
    func snapshotBundle(householdID: String, now: Date) async -> WidgetSnapshotBundle {
        async let expiring = expiringSnapshot(householdID: householdID, now: now)
        async let mealPlan = mealPlanSnapshot(householdID: householdID, now: now)
        async let shopping = shoppingSnapshot(householdID: householdID, limit: 8)
        async let waste = wasteSnapshot(householdID: householdID, now: now)
        return await WidgetSnapshotBundle(
            expiring: expiring, mealPlan: mealPlan, shopping: shopping, waste: waste
        )
    }

    // MARK: 临期

    /// 存储形态是候选集(见 `WidgetExpiringSnapshot` 文档):全部带到期日的项 +
    /// 无到期日的低新鲜项,不截断不排序——widget 渲染时经 `projected(now:)` 按
    /// 渲染时刻重算天数/分桶/计数,app 多日不开也能让 urgent→expired、
    /// fresh→urgent 如期推进(候选含 fresh 的带日期项正为此)。计数字段存发布
    /// 时刻的投影值。展示截断由 widget 视图 prefix 负责。
    /// ponytail: 候选集不设上限(每项仅名字 + 日期,千级库存也只有几十 KB JSON);
    /// 若真出现病态库存再加排序截断。
    func expiringSnapshot(householdID: String, now: Date) async -> WidgetExpiringSnapshot {
        let repo = InventoryRepository(modelContainer: container)
        guard let inventory = try? await repo.loadAllFor(householdID) else { return .empty }

        // lowFreshness 与 ExpiryCalculator.freshnessStateForExpiry 的 fresh/soon 分界同口径。
        let candidates = inventory.compactMap { ing -> WidgetExpiringSnapshot.Item? in
            let lowFreshness = !(ing.freshnessPercent > 0.5)
            // 无到期日且高新鲜:任何时刻都不会非鲜,不入候选。
            guard ing.expiryDate != nil || lowFreshness else { return nil }
            return WidgetExpiringSnapshot.Item(
                name: ing.name,
                daysRemaining: ing.expiryDate.map { ExpiryCalculator.daysUntilExpiry($0, now: now) },
                expiryDate: ing.expiryDate,
                lowFreshness: lowFreshness,
                // 在 app 侧解析好(知识库 FoodKnowledge 不编进 widget),widget 投影
                // 用它按渲染时刻重算 soon/fresh 分界。
                shelfLifeDays: IngredientNormalizer.shelfLifeDays(ing)
            )
        }
        let projected = WidgetExpiringSnapshot(
            expiredCount: 0, urgentCount: 0, soonCount: 0, items: candidates
        ).projected(now: now)
        return WidgetExpiringSnapshot(
            expiredCount: projected.expiredCount,
            urgentCount: projected.urgentCount,
            soonCount: projected.soonCount,
            items: candidates
        )
    }

    // MARK: 今日膳食

    func mealPlanSnapshot(householdID: String, now: Date) async -> WidgetMealPlanSnapshot {
        let repo = MealPlanRepository(modelContainer: container)
        guard let entries = try? await repo.loadAllFor(householdID) else { return .empty }
        let cal = Calendar.current
        let todays = entries.filter { cal.isDate($0.date, inSameDayAs: now) }
        let items = todays.map { entry in
            // 复用模型的 displayTitle(与 MealPlanView 同一真源),避免 widget 与 app 显示不一致。
            WidgetMealPlanSnapshot.Item(title: entry.displayTitle, done: entry.done)
        }
        return WidgetMealPlanSnapshot(items: items)
    }

    // MARK: 购物

    func shoppingSnapshot(householdID: String, limit: Int) async -> WidgetShoppingSnapshot {
        let repo = ShoppingRepository(modelContainer: container)
        guard let all = try? await repo.loadAllFor(householdID) else { return .empty }
        let unchecked = all.lazy.filter { !$0.isChecked }.count
        // 未勾选优先,稳定保持源序。
        let sorted = all.enumerated().sorted { lhs, rhs in
            if lhs.element.isChecked != rhs.element.isChecked { return !lhs.element.isChecked }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let items = sorted.prefix(limit).map {
            WidgetShoppingSnapshot.Item(id: $0.id, name: $0.name, isChecked: $0.isChecked)
        }
        return WidgetShoppingSnapshot(uncheckedCount: unchecked, items: Array(items))
    }

    // MARK: 减废

    func wasteSnapshot(householdID: String, now: Date) async -> WidgetWasteSnapshot {
        let repo = FoodLogRepository(modelContainer: container)
        // 窗口 cutoff 用 Domain 的日历感知 helper(WasteInsightsStore 与本 reader
        // 共用,DST 安全;WasteInsightsStore 在 Features/ 未共享进 widget)。
        let sinceMs = FoodLogStatistics.recentWindowStartMillis(now: now)
        guard let entries = try? await repo.loadRecentFor(householdID, sinceMs: sinceMs) else { return .empty }
        let stats = FoodLogStatistics.computeStats(entries)
        return WidgetWasteSnapshot(
            useUpPercent: stats.useUpPercent,
            rescuedCount: stats.rescued,
            wastedCount: stats.wasted,
            isEmpty: stats.isEmpty
        )
    }
}
