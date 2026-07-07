import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the 减废统计 screen is demonstrable on a fresh
/// install. Appends ~12 food-departure entries spread across the last ~30 days —
/// a mix of consumed + wasted across the canonical categories, some flagged
/// `wasExpiring` (so 抢救临期 is non-zero). Only seeds when the scope is empty and
/// the run-once flag is unset. Never compiled into release builds.
enum FoodLogSeeder {
    private static let didSeedKey = "fp.foodLog.didSeedSamples.v1"

    /// Specs: (lookupName, nameKey, category, outcome, daysAgo, wasExpiring).
    /// `lookupName` is the stable Chinese identity used in seed ids; the stored
    /// name is the localized `nameKey` so the samples read in the user's own
    /// language (same split as `ShoppingSeeder`). Tuned so the headline use-up
    /// rate is a realistic ~75% with a visible 抢救临期 count and a category
    /// breakdown that has both consumed + wasted rows.
    private static let specs: [(lookupName: String, nameKey: String, category: String, outcome: FoodLogOutcome, daysAgo: Int, wasExpiring: Bool)] = [
        ("牛奶", "food.name.milk", FoodCategories.dairyAndEggs, .consumed, 1, true), // i18n:ignore stable seed identity, not UI text
        ("鸡蛋", "food.name.eggs", FoodCategories.dairyAndEggs, .consumed, 2, false), // i18n:ignore stable seed identity, not UI text
        ("菠菜", "food.name.spinach", FoodCategories.freshProduce, .wasted, 3, true), // i18n:ignore stable seed identity, not UI text
        ("苹果", "food.name.apple", FoodCategories.freshProduce, .consumed, 4, false), // i18n:ignore stable seed identity, not UI text
        ("西兰花", "food.name.broccoli", FoodCategories.freshProduce, .consumed, 6, true), // i18n:ignore stable seed identity, not UI text
        ("鸡胸肉", "food.name.chickenBreast", FoodCategories.meatAndSeafood, .consumed, 8, true), // i18n:ignore stable seed identity, not UI text
        ("三文鱼", "food.name.salmon", FoodCategories.meatAndSeafood, .wasted, 11, true), // i18n:ignore stable seed identity, not UI text
        ("酸奶", "food.name.yogurt", FoodCategories.dairyAndEggs, .consumed, 13, false), // i18n:ignore stable seed identity, not UI text
        ("香菜", "food.name.cilantro", FoodCategories.herbsAndSpices, .wasted, 16, true), // i18n:ignore stable seed identity, not UI text
        ("番茄", "food.name.tomato", FoodCategories.freshProduce, .consumed, 19, false), // i18n:ignore stable seed identity, not UI text
        ("豆腐", "food.name.tofu", FoodCategories.other, .consumed, 23, false), // i18n:ignore stable seed identity, not UI text
        ("生菜", "food.name.lettuce", FoodCategories.freshProduce, .wasted, 27, true), // i18n:ignore stable seed identity, not UI text
    ]

    /// Seeds samples if needed. Safe to call on every launch. `now` is injectable
    /// for determinism in non-production callers.
    static func seedIfNeeded(
        repository: FoodLogRepository,
        householdID: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        for entry in sampleEntries(now: now) {
            try? await repository.append(householdID, entry)
        }
    }

    /// Builds the deterministic sample entries from `specs`, offsetting each by its
    /// `daysAgo` from `now`. Stable seed ids so re-runs upsert in place.
    static func sampleEntries(now: Date = Date()) -> [FoodLogEntry] {
        let calendar = Calendar.current
        return specs.enumerated().map { offset, spec in
            let loggedAt = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now) ?? now
            return FoodLogEntry(
                id: "seed_fl_\(offset)_\(spec.lookupName)",
                name: String(localized: String.LocalizationValue(spec.nameKey)),
                category: spec.category,
                outcome: spec.outcome,
                loggedAt: loggedAt,
                wasExpiring: spec.wasExpiring
            )
        }
    }
}
#endif
