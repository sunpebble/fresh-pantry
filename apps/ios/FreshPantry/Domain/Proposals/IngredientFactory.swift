import Foundation

/// Constructs an inventory `Ingredient` from a `ShoppingItem`, applying
/// `FoodKnowledge` defaults (category/storage/shelf-life). Ported VERBATIM from
/// `lib/services/ingredient_factory.dart`.
///
/// `id` is left empty (local rows have empty id per the identity invariant).
enum IngredientFactory {
    static func fromShoppingItem(_ item: ShoppingItem, now: Date = Date()) -> Ingredient {
        let defaults = FoodKnowledge.lookup(item.name)
        let addedAt = now
        let shelfLifeDays = defaults?.shelfLifeDays
        let expiryDate = shelfLifeDays.map { addedAt.addingTimeInterval(TimeInterval($0 * 86400)) }

        return Ingredient(
            name: item.name,
            quantity: "1",
            unit: "份", // i18n:ignore data identity, not UI text
            imageUrl: item.imageUrl ?? "",
            freshnessPercent: expiryDate == nil ? 0.85 : 1.0,
            state: .fresh,
            expiryLabel: expiryDate == nil ? String(localized: "expiry.fresh") : String(localized: "expiry.inDays \(shelfLifeDays!)"),
            category: FoodKnowledge.categoryFor(item.name),
            storage: defaults?.storage ?? .fridge,
            expiryDate: expiryDate,
            addedAt: addedAt,
            shelfLifeDays: shelfLifeDays
        )
    }
}
