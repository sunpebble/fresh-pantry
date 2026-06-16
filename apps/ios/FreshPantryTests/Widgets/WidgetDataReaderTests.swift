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
        let snap = await reader.expiringSnapshot(householdID: hh, now: now(), limit: 8)

        #expect(snap.expiredCount == 1)
        #expect(snap.urgentCount == 1)
        #expect(snap.soonCount == 1)
        #expect(snap.needsAttentionCount == 3)       // 新鲜肉不计
        #expect(snap.items.first?.name == "过期菜")    // expired 排最前
        #expect(snap.items.first?.daysRemaining == -1)
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

        #expect(snap.consumedCount == 2)
        #expect(snap.wastedCount == 1)
        #expect(snap.rescuedCount == 1)
        #expect(snap.useUpPercent == 67)
        #expect(!snap.isEmpty)
    }

    @Test func expiringTruncatesToLimitButCountsAll() async throws {
        let container = try makeContainer()
        let inv = InventoryRepository(modelContainer: container)
        let cal = Calendar.current
        // 5 个全过期项,limit=3:items 截断到 3,但 expiredCount 计全部 5。
        let items = (0..<5).map { i in
            Ingredient(id: "x\(i)", name: "过期\(i)", quantity: "1", unit: "份",
                       imageUrl: "", freshnessPercent: 0.1, state: .fresh,
                       expiryDate: cal.date(byAdding: .day, value: -1, to: now())!)
        }
        try await inv.saveItems(hh, items)

        let reader = WidgetDataReader(container: container)
        let snap = await reader.expiringSnapshot(householdID: hh, now: now(), limit: 3)

        #expect(snap.expiredCount == 5)   // 计数跨全部非新鲜
        #expect(snap.items.count == 3)    // 展示项按 limit 截断
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
