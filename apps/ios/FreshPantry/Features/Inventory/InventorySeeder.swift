import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the Inventory screen is demonstrable on a fresh
/// install. Inserts ~8 varied sample ingredients (different storage areas +
/// freshness tiers) only when the scope is empty and the run-once flag is unset.
/// Never compiled into release builds.
enum InventorySeeder {
    private static let didSeedKey = "fp.inventory.didSeedSamples.v1"

    /// Seeds samples if needed. Safe to call on every launch.
    static func seedIfNeeded(
        repository: InventoryRepository,
        householdID: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        let samples = sampleIngredients(now: now)
        try? await repository.saveItems(householdID, samples)
        for sample in samples {
            try? await repository.recordAddition(sample)
        }
    }

    /// Specs: (lookupName, nameKey, quantity, unit, days-until-expiry). `lookupName`
    /// is the Chinese identity `FoodKnowledge` matches against (its database is
    /// Chinese-keyed) — it drives category / storage / shelf life ONLY; the stored
    /// name is the localized `nameKey` so the samples read in the user's own
    /// language (same split as `ShoppingSeeder`). Units stay canonical Chinese —
    /// `UnitLabels.displayLabel` localizes them at display time. Freshness/state
    /// come from `ExpiryCalculator`, so the data is realistic and self-consistent.
    private static let specs: [(lookupName: String, nameKey: String, quantity: String, unit: String, daysUntilExpiry: Int)] = [
        ("牛奶", "food.name.milk", "2", "盒", 5), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("菠菜", "food.name.spinach", "1", "袋", -1), // i18n:ignore FoodKnowledge lookup key, not UI text — 已过期
        ("鸡胸肉", "food.name.chickenBreast", "500", "g", 1), // i18n:ignore FoodKnowledge lookup key, not UI text — 紧急
        ("鸡蛋", "food.name.eggs", "10", "个", 20), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("苹果", "food.name.apple", "6", "个", 9), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("酱油", "food.name.soySauce", "1", "瓶", 300), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("三文鱼", "food.name.salmon", "1", "盒", 2), // i18n:ignore FoodKnowledge lookup key, not UI text — 紧急
        ("酸奶", "food.name.yogurt", "4", "杯", 11), // i18n:ignore FoodKnowledge lookup key, not UI text
    ]

    static func sampleIngredients(now: Date = Date()) -> [Ingredient] {
        let calendar = Calendar.current
        return specs.enumerated().map { offset, spec in
            let defaults = FoodKnowledge.lookup(spec.lookupName)
            let category = FoodCategories.dropdownValue(defaults?.category)
            let storage = defaults?.storage ?? .fridge
            let shelfLife = defaults?.shelfLifeDays
            let expiryDate = calendar.date(byAdding: .day, value: spec.daysUntilExpiry, to: now)

            let freshness: Double
            if let expiryDate, let shelfLife, shelfLife > 0 {
                freshness = ExpiryCalculator.expiryFreshness(
                    expiryDate: expiryDate,
                    totalShelfLifeDays: shelfLife,
                    now: now
                )
            } else {
                freshness = 0.85
            }
            let state = ExpiryCalculator.freshnessStateForExpiry(
                freshness: freshness,
                expiryDate: expiryDate,
                now: now
            )

            return Ingredient(
                id: "seed_\(offset)_\(spec.lookupName)",
                name: String(localized: String.LocalizationValue(spec.nameKey)),
                quantity: spec.quantity,
                unit: spec.unit,
                imageUrl: "",
                freshnessPercent: freshness,
                state: state,
                expiryLabel: expiryDate.map { ExpiryCalculator.expiryLabelFor($0, now: now) },
                category: category,
                storage: storage,
                expiryDate: expiryDate,
                addedAt: now,
                shelfLifeDays: shelfLife
            )
        }
    }
}
#endif
