import Foundation

/// AI/manual intake draft for one ingredient before confirmation; converts to
/// an `Ingredient`. Transient (no equality/JSON).
struct IngredientDraft {
    var id: String
    var name: DraftField<String>
    var quantity: DraftField<String>
    var unit: DraftField<String>
    var category: DraftField<String?>
    var storage: DraftField<IconType?>
    var shelfLifeDays: DraftField<Int?>
    var selected: Bool

    init(
        id: String,
        name: DraftField<String>,
        quantity: DraftField<String>,
        unit: DraftField<String>,
        category: DraftField<String?>,
        storage: DraftField<IconType?>,
        shelfLifeDays: DraftField<Int?>,
        selected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
        self.selected = selected
    }

    /// Mirrors Dart `toIngredient()`: derives expiry/freshness from shelfLifeDays.
    func toIngredient(now: Date = Date()) -> Ingredient {
        let days = shelfLifeDays.value
        let expiry = days.map { now.addingTimeInterval(TimeInterval($0 * 86400)) }
        let freshness: Double
        if let expiry {
            freshness = ExpiryCalculator.expiryFreshness(
                expiryDate: expiry,
                totalShelfLifeDays: days ?? 7,
                now: now
            )
        } else {
            freshness = 0.85
        }
        return Ingredient(
            name: name.value,
            quantity: quantity.value,
            unit: unit.value,
            imageUrl: "",
            freshnessPercent: freshness,
            state: ExpiryCalculator.freshnessStateForExpiry(
                freshness: freshness,
                expiryDate: expiry,
                now: now
            ),
            expiryLabel: expiry == nil ? String(localized: "expiry.fresh") : ExpiryCalculator.expiryLabelFor(expiry!, now: now),
            category: category.value,
            storage: storage.value ?? .fridge,
            expiryDate: expiry,
            shelfLifeDays: days
        )
    }
}
