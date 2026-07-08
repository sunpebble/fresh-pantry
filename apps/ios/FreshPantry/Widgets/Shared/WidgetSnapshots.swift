import Foundation

/// 临期投影。存储形态是**候选集**:全部带到期日的库存项(含发布时仍新鲜的——
/// 长期不开 app 时它们会跨入 urgent/expired)+ 无到期日的低新鲜项;计数字段为
/// 发布时刻的投影值。widget 渲染前必须经 `projected(now:)` 按渲染时刻重算天数、
/// 分桶与计数,得到展示形态(仅非新鲜、按严重度排序)——否则天数会冻结在发布
/// 时刻(app 多日不开时永远显示「还剩 2 天」)。
public struct WidgetExpiringSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let name: String
        public let daysRemaining: Int?   // 发布时刻的剩余天数;nil = 无到期日。带日期项渲染时重算
        public let expiryDate: Date?     // 渲染时刻重算的依据;nil = 无到期日
        public let lowFreshness: Bool?   // 发布时刻 freshness ≤ 0.5;仅无 shelfLife 时用作冻结兜底。nil = 旧版快照
        public let shelfLifeDays: Int?   // 发布时已解析的保质期(saved > 知识库 > addedAt 推导);days > 2 时按渲染时刻重算 soon/fresh
        public init(
            name: String, daysRemaining: Int?, expiryDate: Date? = nil,
            lowFreshness: Bool? = nil, shelfLifeDays: Int? = nil
        ) {
            self.name = name
            self.daysRemaining = daysRemaining
            self.expiryDate = expiryDate
            self.lowFreshness = lowFreshness
            self.shelfLifeDays = shelfLifeDays
        }
    }
    public let expiredCount: Int
    public let urgentCount: Int
    public let soonCount: Int
    public let items: [Item]

    public init(expiredCount: Int, urgentCount: Int, soonCount: Int, items: [Item]) {
        self.expiredCount = expiredCount
        self.urgentCount = urgentCount
        self.soonCount = soonCount
        self.items = items
    }

    public var needsAttentionCount: Int { expiredCount + urgentCount + soonCount }
    public static let empty = WidgetExpiringSnapshot(expiredCount: 0, urgentCount: 0, soonCount: 0, items: [])

    /// 按渲染时刻 `now` 重投影:重算带日期项的剩余天数,重分桶(days < 0 → expired,
    /// ≤ 2 → urgent,否则按 lowFreshness 分 soon/fresh),重计数;展示项滤掉 fresh,
    /// 按严重度→最快到期排序(无到期日最后,稳定)。纯日期数学,无 SwiftData,
    /// widget 进程(30MB 内存预算)可安全调用。
    ///
    /// 分级口径对齐 Domain 的 `ExpiryCalculator`(本文件编进 widget target,不能
    /// 依赖 Domain,故就地复刻;一致性由 WidgetDataReaderTests 的 parity 测试钉住)。
    public func projected(now: Date) -> WidgetExpiringSnapshot {
        // 旧版快照(项上无 v2 字段)没有重算依据,原样返回,待 app 下次发布覆盖。
        guard items.contains(where: { $0.expiryDate != nil || $0.lowFreshness != nil }) else { return self }

        let tagged: [(item: Item, tier: Tier)] = items.map { item in
            guard let expiry = item.expiryDate else {
                // 无日期候选项只因低新鲜度入选;状态不随时间推进,冻结为 soon。
                return (item, .soon)
            }
            let days = Self.calendarDaysBetween(now, expiry)
            // days > 2 的 soon/fresh 分界:app 侧 freshness = days/shelfLife 随时间下降
            //(IngredientNormalizer.refreshFreshness),这里同式重算才能让 fresh→soon
            // 跨午夜如期晋升;无 shelfLife 时 app 侧 freshness 也不随时间变,用冻结值。
            let low = item.shelfLifeDays.map { $0 <= 0 || Double(days) / Double($0) <= 0.5 }
                ?? (item.lowFreshness == true)
            let tier: Tier = days < 0 ? .expired
                : days <= Self.urgentWithinDays ? .urgent
                : low ? .soon : .fresh
            let updated = Item(
                name: item.name, daysRemaining: days, expiryDate: expiry,
                lowFreshness: item.lowFreshness, shelfLifeDays: item.shelfLifeDays
            )
            return (updated, tier)
        }
        let nonFresh = tagged.filter { $0.tier != .fresh }
        let sorted = nonFresh.enumerated().sorted { lhs, rhs in
            if lhs.element.tier != rhs.element.tier {
                return lhs.element.tier.rawValue < rhs.element.tier.rawValue
            }
            switch (lhs.element.item.daysRemaining, rhs.element.item.daysRemaining) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element.item)

        func count(_ tier: Tier) -> Int { nonFresh.lazy.filter { $0.tier == tier }.count }
        return WidgetExpiringSnapshot(
            expiredCount: count(.expired),
            urgentCount: count(.urgent),
            soonCount: count(.soon),
            items: sorted
        )
    }

    private enum Tier: Int { case expired = 0, urgent, soon, fresh }

    /// 同 `ExpiryCalculator.urgentWithinDays`。
    private static let urgentWithinDays = 2

    /// 同 `ExpiryCalculator.calendarDaysBetween`:本地日历、date-only 的整日差。
    private static func calendarDaysBetween(_ start: Date, _ end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func dateOnly(_ date: Date) -> Date {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return calendar.date(from: c) ?? date
        }
        return calendar.dateComponents([.day], from: dateOnly(start), to: dateOnly(end)).day ?? 0
    }
}

/// 今日膳食投影(只含今天的条目)。
public struct WidgetMealPlanSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let title: String
        public let done: Bool
        public init(title: String, done: Bool) {
            self.title = title
            self.done = done
        }
    }
    public let items: [Item]
    public init(items: [Item]) { self.items = items }
    public static let empty = WidgetMealPlanSnapshot(items: [])
}

/// 购物投影。`items` 已「未勾选优先」并截断;每行带 id 供交互按钮回写。
public struct WidgetShoppingSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let isChecked: Bool
        public init(id: String, name: String, isChecked: Bool) {
            self.id = id
            self.name = name
            self.isChecked = isChecked
        }
    }
    public let uncheckedCount: Int
    public let items: [Item]
    public init(uncheckedCount: Int, items: [Item]) {
        self.uncheckedCount = uncheckedCount
        self.items = items
    }
    public static let empty = WidgetShoppingSnapshot(uncheckedCount: 0, items: [])
}

/// 减废投影(复用 Domain 的 FoodLogStatistics 口径)。
public struct WidgetWasteSnapshot: Codable, Equatable, Sendable {
    public let useUpPercent: Int
    public let rescuedCount: Int
    public let wastedCount: Int
    public let isEmpty: Bool
    public init(useUpPercent: Int, rescuedCount: Int, wastedCount: Int, isEmpty: Bool) {
        self.useUpPercent = useUpPercent
        self.rescuedCount = rescuedCount
        self.wastedCount = wastedCount
        self.isEmpty = isEmpty
    }
    public static let empty = WidgetWasteSnapshot(useUpPercent: 0, rescuedCount: 0, wastedCount: 0, isEmpty: true)
}

/// 四类内容的合集快照,一次读取填满(Provider 只读一次容器)。
public struct WidgetSnapshotBundle: Codable, Equatable, Sendable {
    public var expiring: WidgetExpiringSnapshot = .empty
    public var mealPlan: WidgetMealPlanSnapshot = .empty
    public var shopping: WidgetShoppingSnapshot = .empty
    public var waste: WidgetWasteSnapshot = .empty
    public init(
        expiring: WidgetExpiringSnapshot = .empty,
        mealPlan: WidgetMealPlanSnapshot = .empty,
        shopping: WidgetShoppingSnapshot = .empty,
        waste: WidgetWasteSnapshot = .empty
    ) {
        self.expiring = expiring
        self.mealPlan = mealPlan
        self.shopping = shopping
        self.waste = waste
    }
    public static let empty = WidgetSnapshotBundle()
}
