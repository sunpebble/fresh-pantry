import Foundation

/// User-customizable shelf-aisle order for the shopping list's category sections
/// (Listonic/Bring-style). The canonical `FoodCategories.values` is the default;
/// a stored permutation overrides it. Pure normalization + rank live here so they
/// stay unit-testable; persistence is a thin UserDefaults wrapper.
enum ShoppingCategoryOrder {
    static let storageKey = "shopping_category_order"

    /// The default order (canonical category dropdown values).
    static var canonical: [String] { FoodCategories.values }

    /// Repairs a stored order into a complete, valid permutation: keep the stored
    /// entries that are real categories (deduped, in their saved order), then
    /// append any canonical categories the stored list is missing (in canonical
    /// order). This tolerates stale/partial saves and future new categories.
    static func normalizedOrder(_ stored: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for raw in stored {
            guard let normalized = FoodCategories.normalize(raw), !seen.contains(normalized) else { continue }
            result.append(normalized)
            seen.insert(normalized)
        }
        for category in canonical where !seen.contains(category) {
            result.append(category)
            seen.insert(category)
        }
        return result
    }

    /// Rank of a (possibly raw) category within `order`; unknown/blank sorts last.
    static func rank(_ category: String, order: [String]) -> Int {
        let normalized = FoodCategories.normalize(category) ?? FoodCategories.other
        return order.firstIndex(of: normalized) ?? order.count
    }

    // MARK: Persistence (device-local; the aisle layout is a per-device preference)

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        normalizedOrder(defaults.stringArray(forKey: storageKey) ?? [])
    }

    static func save(_ order: [String], to defaults: UserDefaults = .standard) {
        defaults.set(normalizedOrder(order), forKey: storageKey)
    }
}
