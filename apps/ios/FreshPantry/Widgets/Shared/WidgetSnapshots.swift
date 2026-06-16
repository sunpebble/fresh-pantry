import Foundation

/// 临期投影。`daysRemaining` 按 widget 渲染时刻重算(每天跨午夜刷新后变化)。
struct WidgetExpiringSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let name: String
        let daysRemaining: Int?  // nil = 无到期日
        let state: FreshnessState
    }
    let expiredCount: Int
    let urgentCount: Int
    let soonCount: Int
    let items: [Item]

    var needsAttentionCount: Int { expiredCount + urgentCount + soonCount }
    static let empty = WidgetExpiringSnapshot(expiredCount: 0, urgentCount: 0, soonCount: 0, items: [])
}

/// 今日膳食投影(只含今天的条目)。
struct WidgetMealPlanSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let title: String
        let done: Bool
        let mealType: String?
    }
    let items: [Item]
    static let empty = WidgetMealPlanSnapshot(items: [])
}

/// 购物投影。`items` 已「未勾选优先」并截断;每行带 id 供交互按钮回写。
struct WidgetShoppingSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let isChecked: Bool
    }
    let uncheckedCount: Int
    let items: [Item]
    static let empty = WidgetShoppingSnapshot(uncheckedCount: 0, items: [])
}

/// 减废投影(复用 Domain 的 FoodLogStatistics 口径)。
struct WidgetWasteSnapshot: Codable, Equatable, Sendable {
    let useUpPercent: Int
    let rescuedCount: Int
    let consumedCount: Int
    let wastedCount: Int
    let isEmpty: Bool
    static let empty = WidgetWasteSnapshot(useUpPercent: 0, rescuedCount: 0, consumedCount: 0, wastedCount: 0, isEmpty: true)
}

/// 四类内容的合集快照,一次读取填满(Provider 只读一次容器)。
struct WidgetSnapshotBundle: Codable, Equatable, Sendable {
    var expiring: WidgetExpiringSnapshot = .empty
    var mealPlan: WidgetMealPlanSnapshot = .empty
    var shopping: WidgetShoppingSnapshot = .empty
    var waste: WidgetWasteSnapshot = .empty
    static let empty = WidgetSnapshotBundle()
}
