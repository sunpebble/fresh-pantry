import Foundation
import SwiftData
import Testing
@testable import FreshPantry

@MainActor
struct WidgetDataReaderTests {
    private let hh = "hh-test"
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } // 固定 now

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    @Test func expiringTiersSortedAndCounted() async throws {
        let container = try makeContainer()
        let inv = InventoryRepository(modelContainer: container)
        let cal = Calendar.current
        // expired(-1天), urgent(+1天), soon(freshness 低 + 无近到期), fresh(高 freshness)
        func ing(_ name: String, days: Int?, fresh: Double) -> Ingredient {
            Ingredient(
                id: UUID().uuidString, name: name, quantity: "1", unit: "份",
                imageUrl: "", freshnessPercent: fresh, state: .fresh,
                expiryDate: days.map { cal.date(byAdding: .day, value: $0, to: now())! }
            )
        }
        try await inv.saveItems(hh, [
            ing("过期菜", days: -1, fresh: 0.1),
            ing("紧急奶", days: 1, fresh: 0.4),
            ing("将过期", days: nil, fresh: 0.3),
            ing("新鲜肉", days: 10, fresh: 0.9),
        ])

        let reader = WidgetDataReader(container: container)
        let snap = await reader.expiringSnapshot(householdID: hh, now: now())

        // 存储形态:候选集含带日期的新鲜项(为跨午夜晋升保留),计数为发布时刻投影。
        #expect(snap.items.count == 4)
        #expect(snap.expiredCount == 1)
        #expect(snap.urgentCount == 1)
        #expect(snap.soonCount == 1)
        #expect(snap.needsAttentionCount == 3)       // 新鲜肉不计

        // 渲染形态:投影滤掉 fresh、按严重度→最快到期排序(无到期日最后)。
        let projected = snap.projected(now: now())
        #expect(projected.needsAttentionCount == 3)
        #expect(projected.items.map(\.name) == ["过期菜", "紧急奶", "将过期"])
        #expect(projected.items.first?.daysRemaining == -1)
    }

    @Test func mealPlanShowsOnlyToday() async throws {
        let container = try makeContainer()
        let repo = MealPlanRepository(modelContainer: container)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        func entry(_ name: String, date: Date, done: Bool = false) -> MealPlanEntry {
            MealPlanEntry(id: UUID().uuidString, date: date, recipeId: "r", recipeName: name,
                          servings: 1, done: done, remoteVersion: 0)
        }
        try await repo.saveEntries(hh, [
            entry("番茄炒蛋", date: today),
            entry("红烧肉", date: today, done: true),
            entry("明天的菜", date: tomorrow),
        ])

        let reader = WidgetDataReader(container: container)
        let snap = await reader.mealPlanSnapshot(householdID: hh, now: now())

        #expect(snap.items.count == 2)
        #expect(snap.items.contains { $0.title == "番茄炒蛋" && !$0.done })
        #expect(snap.items.contains { $0.title == "红烧肉" && $0.done })
        #expect(!snap.items.contains { $0.title == "明天的菜" })
    }

    @Test func shoppingUncheckedFirstAndCounted() async throws {
        let container = try makeContainer()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.upsert(hh, ShoppingItem(id: "a", name: "牛奶", detail: "", category: FoodCategories.other, isChecked: true))
        try await repo.upsert(hh, ShoppingItem(id: "b", name: "鸡蛋", detail: "", category: FoodCategories.other, isChecked: false))

        let reader = WidgetDataReader(container: container)
        let snap = await reader.shoppingSnapshot(householdID: hh, limit: 8)

        #expect(snap.uncheckedCount == 1)
        #expect(snap.items.first?.name == "鸡蛋")     // 未勾选优先
        #expect(snap.items.first?.isChecked == false)
    }

    @Test func wasteUsesDomainStats() async throws {
        let container = try makeContainer()
        let repo = FoodLogRepository(modelContainer: container)
        func log(_ outcome: FoodLogOutcome, expiring: Bool = false) -> FoodLogEntry {
            FoodLogEntry(id: UUID().uuidString, name: "x", category: FoodCategories.other,
                         outcome: outcome, loggedAt: now(), wasExpiring: expiring, remoteVersion: 0)
        }
        try await repo.append(hh, log(.consumed, expiring: true))
        try await repo.append(hh, log(.consumed))
        try await repo.append(hh, log(.wasted))

        let reader = WidgetDataReader(container: container)
        let snap = await reader.wasteSnapshot(householdID: hh, now: now())

        #expect(snap.wastedCount == 1)
        #expect(snap.rescuedCount == 1)
        #expect(snap.useUpPercent == 67)
        #expect(!snap.isEmpty)
    }

    @Test func expiringStoresAllCandidatesAndCountsAll() async throws {
        let container = try makeContainer()
        let inv = InventoryRepository(modelContainer: container)
        let cal = Calendar.current
        // 5 个全过期项:候选集不截断(展示截断由 widget 视图 prefix 负责),计数计全部。
        let items = (0..<5).map { i in
            Ingredient(id: "x\(i)", name: "过期\(i)", quantity: "1", unit: "份",
                       imageUrl: "", freshnessPercent: 0.1, state: .fresh,
                       expiryDate: cal.date(byAdding: .day, value: -1, to: now())!)
        }
        try await inv.saveItems(hh, items)

        let reader = WidgetDataReader(container: container)
        let snap = await reader.expiringSnapshot(householdID: hh, now: now())

        #expect(snap.expiredCount == 5)
        #expect(snap.items.count == 5)
    }

    // MARK: 渲染时刻投影(widget 进程侧的纯日期数学)

    // 核心回归:发布后多日不开 app,投影须让天数推进、urgent→expired 与
    // fresh→urgent 的晋升如期发生(修复 widget 天数冻结在发布时刻的 bug)。
    @Test func projectionAdvancesTiersAcrossMidnights() {
        let cal = Calendar.current
        func item(_ name: String, days: Int, low: Bool) -> WidgetExpiringSnapshot.Item {
            .init(name: name, daysRemaining: days,
                  expiryDate: cal.date(byAdding: .day, value: days, to: now())!,
                  lowFreshness: low)
        }
        let stored = WidgetExpiringSnapshot(
            expiredCount: 0, urgentCount: 1, soonCount: 0,
            items: [item("紧急奶", days: 2, low: false), item("新鲜肉", days: 5, low: false)]
        )
        let threeDaysLater = cal.date(byAdding: .day, value: 3, to: now())!
        let p = stored.projected(now: threeDaysLater)
        #expect(p.expiredCount == 1)                        // 紧急奶:2-3 = -1 天
        #expect(p.urgentCount == 1)                         // 新鲜肉:5-3 = 2 天,fresh→urgent
        #expect(p.items.map(\.name) == ["紧急奶", "新鲜肉"])
        #expect(p.items.first?.daysRemaining == -1)         // 天数按渲染时刻重算
    }

    // 无日期候选项只因低新鲜度入选,状态冻结为 soon,不随时间推进。
    @Test func projectionKeepsUndatedItemsFrozen() {
        let stored = WidgetExpiringSnapshot(
            expiredCount: 0, urgentCount: 0, soonCount: 1,
            items: [.init(name: "散装米", daysRemaining: nil, expiryDate: nil, lowFreshness: true)]
        )
        let p = stored.projected(now: Calendar.current.date(byAdding: .day, value: 30, to: now())!)
        #expect(p.soonCount == 1)
        #expect(p.items.first?.daysRemaining == nil)
    }

    // 旧版快照(项上无 v2 字段)没有重算依据 → 原样返回,待 app 下次发布覆盖。
    @Test func projectionPassesThroughLegacySnapshot() {
        let legacy = WidgetExpiringSnapshot(
            expiredCount: 2, urgentCount: 1, soonCount: 0,
            items: [.init(name: "牛奶", daysRemaining: -1)]
        )
        #expect(legacy.projected(now: now()) == legacy)
    }

    // 跨天口径 parity:发布一次、多日后渲染,投影分桶必须与「app 若在渲染日打开」
    // 的 Domain 口径一致(refreshFreshness 会按当天重算 freshness = days/shelfLife,
    // fresh→soon 的晋升 widget 靠存下的 shelfLifeDays 同式重算)。
    @Test func projectionParityWithDomainAcrossRenderDays() {
        let cal = Calendar.current
        for shelfLife in [4, 10] {
            for daysAtPublish in 1...shelfLife {
                let expiry = cal.date(byAdding: .day, value: daysAtPublish, to: now())!
                let freshnessAtPublish = ExpiryCalculator.expiryFreshness(
                    expiryDate: expiry, totalShelfLifeDays: shelfLife, now: now()
                )
                let item = WidgetExpiringSnapshot.Item(
                    name: "x", daysRemaining: daysAtPublish, expiryDate: expiry,
                    lowFreshness: !(freshnessAtPublish > 0.5), shelfLifeDays: shelfLife
                )
                for offset in 0...(daysAtPublish + 2) {
                    let render = cal.date(byAdding: .day, value: offset, to: now())!
                    let freshness = ExpiryCalculator.expiryFreshness(
                        expiryDate: expiry, totalShelfLifeDays: shelfLife, now: render
                    )
                    let expected = ExpiryCalculator.freshnessStateForExpiry(
                        freshness: freshness, expiryDate: expiry, now: render
                    )
                    let p = WidgetExpiringSnapshot(
                        expiredCount: 0, urgentCount: 0, soonCount: 0, items: [item]
                    ).projected(now: render)
                    let actual: FreshnessState = p.expiredCount == 1 ? .expired
                        : p.urgentCount == 1 ? .urgent
                        : p.soonCount == 1 ? .expiringSoon : .fresh
                    #expect(actual == expected,
                            "shelfLife=\(shelfLife) publish=\(daysAtPublish) offset=\(offset)")
                }
            }
        }
    }

    // 同时刻口径 parity:投影分桶必须与 Domain 的 ExpiryCalculator 完全一致
    // (WidgetSnapshots 编进 widget target 不能依赖 Domain,是复刻,靠本测试钉住)。
    @Test func projectionTierParityWithExpiryCalculator() {
        let cal = Calendar.current
        for days in -3...5 {
            for freshness in [0.2, 0.9] {
                let expiry = cal.date(byAdding: .day, value: days, to: now())!
                let expected = ExpiryCalculator.freshnessStateForExpiry(
                    freshness: freshness, expiryDate: expiry, now: now()
                )
                let p = WidgetExpiringSnapshot(
                    expiredCount: 0, urgentCount: 0, soonCount: 0,
                    items: [.init(name: "x", daysRemaining: nil, expiryDate: expiry,
                                  lowFreshness: !(freshness > 0.5))]
                ).projected(now: now())
                let actual: FreshnessState = p.expiredCount == 1 ? .expired
                    : p.urgentCount == 1 ? .urgent
                    : p.soonCount == 1 ? .expiringSoon : .fresh
                #expect(actual == expected, "days=\(days) freshness=\(freshness)")
            }
        }
    }

    @Test func emptyContainerYieldsEmptySnapshots() async throws {
        let container = try makeContainer()
        let reader = WidgetDataReader(container: container)
        let bundle = await reader.snapshotBundle(householdID: "nobody", now: now())
        #expect(bundle.expiring == .empty)
        #expect(bundle.mealPlan == .empty)
        #expect(bundle.shopping == .empty)
        #expect(bundle.waste == .empty)
    }
}
