import Foundation

/// Feature store for the Dashboard (首页) slice — same `@Observable @MainActor`
/// template the Inventory / Shopping stores established.
///
/// Reads the inventory + shopping household scopes and derives a single
/// `DashboardSummary` view-model (urgency-tier counts, the soonest-expiring
/// preview, and the shopping-unchecked count). The source lists are kept in
/// repo/insertion order — never mutated by display concerns; all classification
/// and ordering happens in pure derivations here.
@Observable
@MainActor
final class DashboardStore {
    /// Items at or sooner than this many calendar days surface as "non-fresh"
    /// for the 临期 preview / counts (state ∈ {expiringSoon, urgent, expired}).
    /// The blueprint's `expiringItemsProvider` semantic, single-sourced here.
    static let previewLimit = 4

    private let inventoryRepository: InventoryRepository
    private let shoppingRepository: ShoppingRepository
    private let householdID: String

    /// Repo/insertion-ordered scopes (the source of truth — never reordered).
    private(set) var inventory: [Ingredient] = []
    private(set) var shopping: [ShoppingItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init(
        inventoryRepository: InventoryRepository,
        shoppingRepository: ShoppingRepository,
        householdID: String
    ) {
        self.inventoryRepository = inventoryRepository
        self.shoppingRepository = shoppingRepository
        self.householdID = householdID
    }

    // MARK: Loading

    /// Loads both scopes off their repo actors and assigns on the main actor.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        async let inventoryLoad = (try? await inventoryRepository.loadAllFor(householdID)) ?? []
        async let shoppingLoad = (try? await shoppingRepository.loadAllFor(householdID)) ?? []
        inventory = await inventoryLoad
        shopping = await shoppingLoad
    }

    // MARK: Derived view data

    /// The fully-derived summary the view renders. Recomputed on access; the
    /// underlying scopes stay in source order.
    var summary: DashboardSummary {
        DashboardSummary(
            totalItems: inventory.count,
            expiredCount: count(of: .expired),
            urgentCount: count(of: .urgent),
            soonCount: count(of: .expiringSoon),
            uncheckedShoppingCount: shopping.lazy.filter { !$0.isChecked }.count,
            expiringPreview: Array(sortedNonFresh.prefix(Self.previewLimit))
        )
    }

    /// Inventory grouped by canonical food category (件数 per 全部/5 大类), in the
    /// stable `FoodCategories.values` order, dropping empty buckets. Drives the
    /// 首页 食材分类 grid; tapping a tile drills into the 库存 tab pre-filtered.
    /// Counts by `FoodCategories.dropdownValue` so it matches the Inventory chips.
    var categoryCounts: [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in inventory {
            counts[FoodCategories.dropdownValue(item.category), default: 0] += 1
        }
        return FoodCategories.values.compactMap { category in
            guard let count = counts[category], count > 0 else { return nil }
            return (category, count)
        }
    }

    /// The household's non-fresh items, urgency-sorted (expired → urgent → soon,
    /// soonest expiry first). The ExpiringView renders the full list; the
    /// Dashboard preview is its prefix.
    var sortedNonFresh: [Ingredient] {
        sortByUrgency(inventory.filter { Self.isNonFresh($0.state) })
    }

    // MARK: Classification / sorting internals

    /// Non-fresh tiers feeding the 临期 surfaces — mirrors `isNotFreshIngredient`
    /// (`state ∈ {expiringSoon, urgent, expired}`).
    static func isNonFresh(_ state: FreshnessState) -> Bool {
        switch state {
        case .expiringSoon, .urgent, .expired: return true
        case .fresh: return false
        }
    }

    private func count(of state: FreshnessState) -> Int {
        inventory.lazy.filter { $0.state == state }.count
    }

    /// Sort: most-severe state first (expired→urgent→expiringSoon), then soonest
    /// expiry first (nil expiry last), stable by original index. Mirrors the
    /// Inventory store's urgency sort so the two stay consistent.
    private func sortByUrgency(_ list: [Ingredient]) -> [Ingredient] {
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ state: FreshnessState) -> Int { order.firstIndex(of: state) ?? order.count }

        return list.enumerated().sorted { lhs, rhs in
            let lRank = rank(lhs.element.state)
            let rRank = rank(rhs.element.state)
            if lRank != rRank { return lRank < rRank }

            switch (lhs.element.expiryDate, rhs.element.expiryDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.offset < rhs.offset // stable by source order
            }
        }.map(\.element)
    }
}

/// Immutable projection the Dashboard hero + sections render. Pure value type so
/// it's trivially testable and view-agnostic.
struct DashboardSummary: Equatable, Sendable {
    let totalItems: Int
    let expiredCount: Int
    let urgentCount: Int
    let soonCount: Int
    let uncheckedShoppingCount: Int
    let expiringPreview: [Ingredient]

    /// 临期 headline: everything not fresh (soon + urgent + expired).
    var needsAttentionCount: Int { soonCount + urgentCount + expiredCount }

    /// 库存充足 items (fresh tier) — the complement of `needsAttentionCount`.
    var freshCount: Int { totalItems - needsAttentionCount }

    /// True when nothing in the pantry needs attention (drives the empty 临期
    /// section state).
    var hasNoExpiring: Bool { expiringPreview.isEmpty }
}
