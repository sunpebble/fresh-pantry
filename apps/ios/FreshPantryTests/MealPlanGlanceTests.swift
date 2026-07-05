import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for `MealPlanGlance` — the 首页 meal-plan entry-card summary and
/// its shared [today, today+7) window, which the 还缺 badge derivation must
/// consume too (so a stale past week's pending dishes never inflate the badge).
struct MealPlanGlanceTests {
    private let now = Date()

    /// Local midnight `days` from today, via the same gregorian/local calendar
    /// the production window math uses (DST-safe, unlike adding 86400s).
    private func day(_ days: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = MealPlanEntry.dateOnly(now)
        return calendar.date(byAdding: .day, value: days, to: today) ?? today
    }

    private func entry(_ id: String, dayOffset: Int, recipeId: String = "r1", done: Bool = false) -> MealPlanEntry {
        MealPlanEntry(id: id, date: day(dayOffset), recipeId: recipeId, recipeName: recipeId, servings: 1, done: done)
    }

    private func recipe(_ id: String, _ ingredients: [String]) -> Recipe {
        Recipe(
            id: id, name: id, category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "",
            ingredients: ingredients.map { RecipeIngredient(name: $0, quantity: 1, unit: "份") },
            steps: [], tags: []
        )
    }

    // MARK: windowedEntries — the [today, today+7) span

    @Test func windowKeepsTodayThroughDaySixOnly() {
        let entries = [
            entry("past", dayOffset: -1),   // yesterday → out
            entry("today", dayOffset: 0),   // lower bound → in
            entry("edge", dayOffset: 6),    // last in-window day → in
            entry("next", dayOffset: 7),    // upper bound (exclusive) → out
        ]
        let windowed = MealPlanGlance.windowedEntries(entries, now: now)
        #expect(windowed.map(\.id) == ["today", "edge"])
    }

    @Test func windowPreservesSourceOrder() {
        let entries = [entry("b", dayOffset: 3), entry("a", dayOffset: 1), entry("c", dayOffset: 2)]
        #expect(MealPlanGlance.windowedEntries(entries, now: now).map(\.id) == ["b", "a", "c"])
    }

    // MARK: from — upcoming/today counts (unchanged semantics over the window)

    @Test func fromCountsUpcomingAndTodayInsideWindow() {
        let entries = [
            entry("past", dayOffset: -1),
            entry("t1", dayOffset: 0),
            entry("t2", dayOffset: 0),
            entry("later", dayOffset: 5),
            entry("next", dayOffset: 8),
        ]
        let glance = MealPlanGlance.from(entries: entries, missingCount: 2, now: now)
        #expect(glance.upcoming == 3)
        #expect(glance.today == 2)
        #expect(glance.missing == 2)
    }

    @Test func fromIsZeroedWhenNothingInWindow() {
        let glance = MealPlanGlance.from(
            entries: [entry("past", dayOffset: -3), entry("far", dayOffset: 10)],
            missingCount: 0, now: now
        )
        #expect(glance == MealPlanGlance(upcoming: 0, today: 0, missing: 0))
    }

    // MARK: subtitle — rolling-window copy must say 未来 7 天, never 本周

    @Test func subtitleSaysNext7DaysNotThisWeek() {
        // The glance span is [today, today+7) — a ROLLING window that crosses
        // into next week on any day but Monday — so 本周 would mislabel it.
        let glance = MealPlanGlance(upcoming: 3, today: 0, missing: 0)
        #expect(glance.subtitle == String(localized: "dashboard.mealPlan.upcoming \(3)"))
        #expect(!glance.subtitle.contains("本周")) // i18n:ignore negative-match probe against the zh copy, not UI text
    }

    @Test func subtitleAppendsTodayCountWhenPresent() {
        let glance = MealPlanGlance(upcoming: 3, today: 1, missing: 0)
        #expect(glance.subtitle == String(localized: "dashboard.mealPlan.upcomingWithToday \(3) \(1)"))
    }

    @Test func subtitleFallsBackToInviteWhenNothingPlanned() {
        let glance = MealPlanGlance(upcoming: 0, today: 0, missing: 0)
        #expect(glance.subtitle == String(localized: "dashboard.mealPlan.empty"))
    }

    // MARK: 还缺 badge口径 — windowed entries feed MealPlanMissing

    @Test func missingBadgeIgnoresPendingEntriesOutsideWindow() {
        // A stale past entry and a beyond-window entry both demand 葱; only
        // today's dish demands 鸡蛋. Windowing first → the badge counts 鸡蛋 only.
        let recipes = ["stale": recipe("stale", ["葱"]), "today": recipe("today", ["鸡蛋"])]
        let entries = [
            entry("e1", dayOffset: -7, recipeId: "stale"),
            entry("e2", dayOffset: 0, recipeId: "today"),
            entry("e3", dayOffset: 9, recipeId: "stale"),
        ]
        let missing = MealPlanMissing.missingIngredientNames(
            entries: MealPlanGlance.windowedEntries(entries, now: now),
            recipesById: recipes,
            inventoryNames: []
        )
        #expect(missing == ["鸡蛋"])
    }
}
