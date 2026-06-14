import Foundation

/// Feature store for the 库存不足 (low-stock / 常买补货) screen — the third of the
/// Inventory trio (库存 / 临期 / 库存不足). Same `@Observable @MainActor` template.
///
/// Ports `lowStockItemsProvider`: from the add-history frequency memory, keeps the
/// names bought ≥3 times that are NOT currently in stock (the restock candidates),
/// sorted by `count` descending. The right-column stat is the real "买过 N 次"
/// (count) — the blueprint's threshold/remaining model has no source here, so we
/// surface the genuine purchase frequency rather than a fabricated restock amount.
///
/// Owns the candidate list + the selection set (default ALL). The actual add lives
/// in the view (it needs a `ShoppingStore`); the store stays focused on derivation.
@Observable
@MainActor
final class LowStockStore {
    private let repository: InventoryRepository
    private let householdID: String
    /// Optional food-log source for consumption-cadence reorder prediction (#8).
    /// nil keeps the store frequency-only (existing tests / NotificationCoordinator).
    private let foodLogRepository: FoodLogRepository?

    /// The low-stock candidates (count≥3 & not in inventory), count-desc.
    private(set) var items: [FrequentItem] = []
    /// Reorder cadence predictions keyed by lowercased item name (empty when no
    /// food-log source). Drives the "约每 N 天 · 该补了" row hint.
    private(set) var predictionsByName: [String: ReorderPrediction] = [:]
    /// Selected candidate names. Defaults to ALL on first load; kept in sync with
    /// the candidate list (intersected with the live names) thereafter.
    var selectedNames: Set<String> = []
    private(set) var hasLoaded = false

    /// Tracks whether `selectedNames` has been seeded with the default-all set, so
    /// a reload intersects the prior selection with the new names instead of
    /// re-defaulting to all (preserving user de-selections across refreshes).
    private var hasInitializedSelection = false

    init(
        repository: InventoryRepository,
        householdID: String,
        foodLogRepository: FoodLogRepository? = nil
    ) {
        self.repository = repository
        self.householdID = householdID
        self.foodLogRepository = foodLogRepository
    }

    // MARK: Loading

    func load(now: Date = Date()) async {
        defer { hasLoaded = true }
        let frequent = (try? await repository.loadFrequentItems()) ?? []
        let inventory = (try? await repository.loadAllFor(householdID)) ?? []
        let present = Set(inventory.map { $0.name.trimmed.lowercased() })
        items = frequent
            .filter { $0.count >= 3 && !present.contains($0.name.trimmed.lowercased()) }
            .sorted { $0.count > $1.count }
        if let foodLogRepository {
            let log = (try? await foodLogRepository.loadAllFor(householdID)) ?? []
            predictionsByName = ReorderPredictor.predictions(foodLog: log, now: now)
        }
        syncSelection()
    }

    /// Cadence prediction for a candidate name (nil when unknown / too few events).
    func prediction(for name: String) -> ReorderPrediction? {
        predictionsByName[name.trimmed.lowercased()]
    }

    /// Defaults the selection to every candidate name on first load; on later loads
    /// intersects the prior selection with the live names so de-selections survive
    /// a refresh and vanished candidates drop out.
    private func syncSelection() {
        let names = Set(items.map(\.name))
        if hasInitializedSelection {
            selectedNames.formIntersection(names)
        } else {
            selectedNames = names
            hasInitializedSelection = true
        }
    }

    // MARK: Mutations

    /// Flips a candidate's membership in the selection set.
    func toggle(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }

    // MARK: Derived view data

    /// Candidates grouped by their canonical food category, in `FoodCategories`
    /// rank order, preserving the count-desc order within each group. (Items keep
    /// the store's normalized category, so this maps cleanly onto the palette.)
    var groupedByCategory: [(category: String, items: [FrequentItem])] {
        var order: [String] = []
        var buckets: [String: [FrequentItem]] = [:]
        for item in items {
            let category = FoodCategories.normalize(item.category) ?? FoodCategories.other
            if buckets[category] == nil { order.append(category) }
            buckets[category, default: []].append(item)
        }
        order.sort { categoryRank($0) < categoryRank($1) }
        return order.map { (category: $0, items: buckets[$0] ?? []) }
    }

    /// The candidates the user has selected (in count-desc list order).
    var chosenItems: [FrequentItem] {
        items.filter { selectedNames.contains($0.name) }
    }

    /// Index of `category` in the canonical order; unknown/blank sorts last.
    private func categoryRank(_ category: String) -> Int {
        let normalized = FoodCategories.normalize(category) ?? FoodCategories.other
        return FoodCategories.values.firstIndex(of: normalized) ?? FoodCategories.values.count
    }
}
