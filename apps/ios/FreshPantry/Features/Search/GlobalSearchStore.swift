import Foundation

/// Read-only cross-domain search store for the global search overlay — a thin
/// snapshot of the inventory + shopping scopes filtered by a single query, ported
/// from the Flutter `filteredInventoryProvider` / `filteredShoppingProvider`.
///
/// Loads ONCE on present (`load()`); a transient overlay doesn't need to track
/// live mutations, and it is NOT a second source of truth (no persistence / sync).
/// Matching is case-insensitive contains on the name OR category, mirroring
/// search_provider.dart. The 食材百科 (online encyclopedia) section is intentionally
/// out of this Phase-1 slice — that lookup already lives inside every ingredient
/// detail screen.
@Observable
@MainActor
final class GlobalSearchStore {
    private let inventoryRepository: InventoryRepository
    private let shoppingRepository: ShoppingRepository
    private let householdID: String

    var query: String = ""
    private(set) var inventory: [Ingredient] = []
    private(set) var shopping: [ShoppingItem] = []
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

    /// Snapshots both scopes off their repo actors. Best-effort: a load failure
    /// surfaces an empty scope rather than blocking the overlay.
    func load() async {
        async let inventoryLoad = (try? await inventoryRepository.loadAllFor(householdID)) ?? []
        async let shoppingLoad = (try? await shoppingRepository.loadAllFor(householdID)) ?? []
        inventory = await inventoryLoad
        shopping = await shoppingLoad
        hasLoaded = true
    }

    var trimmedQuery: String { query.trimmed }
    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Inventory rows whose name OR category contains the query (case-insensitive).
    var filteredInventory: [Ingredient] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return inventory.filter {
            $0.name.lowercased().contains(needle) || ($0.category ?? "").lowercased().contains(needle)
        }
    }

    /// Shopping rows whose name OR category contains the query (case-insensitive).
    var filteredShopping: [ShoppingItem] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return shopping.filter {
            $0.name.lowercased().contains(needle) || $0.category.lowercased().contains(needle)
        }
    }

    var hasResults: Bool { !filteredInventory.isEmpty || !filteredShopping.isEmpty }
}
