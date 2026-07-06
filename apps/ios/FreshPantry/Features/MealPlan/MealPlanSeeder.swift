import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the 膳食计划 screen is demonstrable on a fresh
/// install. Plans ~3 dishes across the current week (one marked done),
/// referencing real shared catalog recipes so the
/// covers/names are self-consistent. Only seeds when the scope is empty and the
/// run-once flag is unset. Never compiled into release builds.
enum MealPlanSeeder {
    private static let didSeedKey = "fp.mealPlan.didSeedSamples.v1"

    /// Day offsets from the Monday of the current week, paired with a `done`
    /// flag. (today-ish spread: Mon, Wed-done, Fri.)
    private static let plan: [(dayOffset: Int, done: Bool)] = [
        (0, false),
        (2, true),
        (4, false),
    ]

    /// Seeds samples if needed. Safe to call on every launch. `today` is
    /// injectable for determinism in non-production callers.
    static func seedIfNeeded(
        repository: MealPlanRepository,
        recipes: [Recipe],
        householdID: String,
        today: Date = Date(),
        defaults: UserDefaults = .standard
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        let entries = sampleEntries(recipes: recipes, today: today)
        guard !entries.isEmpty else { return }
        try? await repository.saveEntries(householdID, entries)
    }

    /// Builds entries by pairing the first few catalog recipes with `plan`'s
    /// day-offsets (from this week's Monday). Returns `[]` when there is no catalog.
    static func sampleEntries(recipes: [Recipe], today: Date) -> [MealPlanEntry] {
        guard !recipes.isEmpty else { return [] }
        let weekStart = MealPlanStore.weekStart(containing: today)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        return plan.enumerated().compactMap { offset, spec in
            let recipe = recipes[offset % recipes.count]
            guard let date = calendar.date(byAdding: .day, value: spec.dayOffset, to: weekStart) else {
                return nil
            }
            return MealPlanEntry(
                id: "seed_mp_\(offset)_\(recipe.id)",
                date: date,
                recipeId: recipe.id,
                recipeName: recipe.name,
                recipeImageUrl: recipe.imageUrl,
                servings: offset == 0 ? 2 : 1,
                done: spec.done
            )
        }
    }
}
#endif
