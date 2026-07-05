import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the Shopping screen is demonstrable on a fresh
/// install. Inserts ~6 varied sample items (across categories, a couple
/// pre-checked) only when the scope is empty and the run-once flag is unset.
/// Never compiled into release builds.
enum ShoppingSeeder {
    private static let didSeedKey = "fp.shopping.didSeedSamples.v1"

    /// Seeds samples if needed. Safe to call on every launch.
    static func seedIfNeeded(
        repository: ShoppingRepository,
        householdID: String,
        defaults: UserDefaults = .standard
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        try? await repository.saveItems(householdID, sampleItems())
    }

    /// Specs: (lookupName, nameKey, detailKey, isChecked). `lookupName` is the
    /// Chinese identity `FoodKnowledge` matches against (its database is
    /// Chinese-keyed) — it drives the category lookup ONLY; the row's displayed
    /// name is the localized `nameKey` so a fresh install's FIRST seen shopping
    /// list reads in the user's own language (unlike `InventorySeeder`'s
    /// DEBUG-only samples, this data becomes a real, user-editable row).
    private static let specs: [(lookupName: String, nameKey: String, detailKey: String, isChecked: Bool)] = [
        ("牛奶", "shopping.seed.milk.name", "shopping.seed.milk.detail", false), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("鸡蛋", "shopping.seed.eggs.name", "shopping.seed.eggs.detail", true), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("西红柿", "shopping.seed.tomato.name", "shopping.seed.tomato.detail", false), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("猪肉", "shopping.seed.pork.name", "shopping.seed.pork.detail", false), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("酱油", "shopping.seed.soySauce.name", "shopping.seed.soySauce.detail", true), // i18n:ignore FoodKnowledge lookup key, not UI text
        ("苹果", "shopping.seed.apple.name", "shopping.seed.apple.detail", false), // i18n:ignore FoodKnowledge lookup key, not UI text
    ]

    static func sampleItems() -> [ShoppingItem] {
        specs.enumerated().map { offset, spec in
            ShoppingItem(
                id: "seed_si_\(offset)_\(spec.lookupName)",
                name: String(localized: String.LocalizationValue(spec.nameKey)),
                detail: String(localized: String.LocalizationValue(spec.detailKey)),
                category: FoodKnowledge.categoryFor(spec.lookupName),
                isChecked: spec.isChecked
            )
        }
    }
}
#endif
