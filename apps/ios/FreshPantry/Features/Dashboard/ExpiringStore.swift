import Foundation

/// Feature store for the Expiring (临期) screen — same `@Observable @MainActor`
/// template. Reuses `InventoryRepository`, loads the household scope, and exposes
/// the non-fresh items grouped by urgency tier (expired → urgent → soon).
///
/// Kept separate from `DashboardStore` so the pushed screen reloads / refreshes
/// independently (its own `.task` + pull-to-refresh) rather than holding a
/// reference to the home tab's store.
@Observable
@MainActor
final class ExpiringStore {
    /// One urgency tier section: a `FreshnessState` plus its sorted rows.
    struct Tier: Identifiable {
        let state: FreshnessState
        let items: [Ingredient]
        var id: FreshnessState { state }
    }

    private let repository: InventoryRepository
    private let householdID: String

    private(set) var items: [Ingredient] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init(repository: InventoryRepository, householdID: String) {
        self.repository = repository
        self.householdID = householdID
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        items = (try? await repository.loadAllFor(householdID)) ?? []
    }

    // MARK: Optimistic snapshot edit

    /// Drops the row with `id` from the in-memory snapshot so the tier list
    /// re-derives the instant a 用了/扔了 lands — the actual delete + food-log is
    /// the `InventoryStore`'s job. This store keeps its OWN snapshot, so without
    /// this the row lingers until the `onChange(of: inventoryStore.items)` drift
    /// handler reloads. That handler (and an undo, which re-adds to InventoryStore)
    /// still reconciles afterward; this just makes the drop instant. No-op when
    /// the id isn't present.
    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    // MARK: Derived view data

    /// Non-fresh items, urgency-sorted within each tier. Empty when the pantry
    /// is healthy.
    var sortedItems: [Ingredient] {
        FreshnessSort.byUrgency(items.filter { DashboardStore.isNonFresh($0.state) })
    }

    /// Sectioned by tier in severity order: expired → urgent → expiringSoon.
    /// Empty tiers are dropped.
    var tiers: [Tier] {
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon]
        let sorted = sortedItems
        return order.compactMap { state in
            let rows = sorted.filter { $0.state == state }
            return rows.isEmpty ? nil : Tier(state: state, items: rows)
        }
    }

}

extension FreshnessState {
    /// Section header copy for the Expiring screen's urgency groups.
    var expiringSectionTitle: String {
        switch self {
        case .expired: return String(localized: "component.status.expired")
        case .urgent: return String(localized: "component.status.urgent")
        case .expiringSoon: return String(localized: "component.status.soon")
        case .fresh: return String(localized: "component.status.fresh")
        }
    }
}
