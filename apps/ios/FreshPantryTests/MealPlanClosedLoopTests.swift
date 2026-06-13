import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Closed-loop behavior on the 膳食计划 slice: the visible-week 缺料 scope (the
/// card count must match what the week strip shows), the week-aware card title,
/// the `isShowingWeek` gate behind the 「今天」 jump-back pill, and the
/// completion → cook-time-deduction candidate resolution.
@MainActor
struct MealPlanClosedLoopTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Wednesday → its Mon-anchored week is 2026-06-08 … 2026-06-14.
    private var refToday: Date { date(2026, 6, 10) }

    private func makeStore(
        _ entries: [MealPlanEntry] = [],
        today: Date? = nil
    ) async throws -> MealPlanStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = MealPlanRepository(modelContainer: container)
        if !entries.isEmpty { try await repo.saveEntries("home", entries) }
        let store = MealPlanStore(repository: repo, householdID: "home", today: today ?? refToday)
        await store.load()
        return store
    }

    private func entry(_ id: String, date: Date, recipeId: String, done: Bool = false) -> MealPlanEntry {
        MealPlanEntry(id: id, date: date, recipeId: recipeId, recipeName: recipeId, servings: 1, done: done)
    }

    private func recipe(_ id: String, _ ingredients: [String]) -> Recipe {
        Recipe(
            id: id, name: id, category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "",
            ingredients: ingredients.map { RecipeIngredient(name: $0, quantity: 1, unit: "份") },
            steps: [], tags: []
        )
    }

    // MARK: 缺料窗口 = 可见周

    @Test func missingOverVisibleWeekIgnoresOtherWeeksLeftovers() async throws {
        let store = try await makeStore([
            entry("cur", date: refToday, recipeId: "r1"),         // visible week
            entry("old", date: date(2026, 6, 1), recipeId: "r2"), // past-week leftover
        ], today: refToday)
        let recipes = ["r1": recipe("r1", ["鸡蛋"]), "r2": recipe("r2", ["葱"])]
        let missing = MealPlanMissing.missingIngredientNames(
            entries: store.entriesInVisibleWeek, recipesById: recipes, inventoryNames: []
        )
        // The past week's 葱 must not leak into the visible week's count.
        #expect(missing == ["鸡蛋"])
    }

    @Test func missingFollowsTheWeekCursor() async throws {
        let store = try await makeStore([
            entry("cur", date: refToday, recipeId: "r1"),
            entry("next", date: date(2026, 6, 15), recipeId: "r2"), // next week (Mon)
        ], today: refToday)
        let recipes = ["r1": recipe("r1", ["鸡蛋"]), "r2": recipe("r2", ["葱"])]
        store.goToNextWeek()
        let missing = MealPlanMissing.missingIngredientNames(
            entries: store.entriesInVisibleWeek, recipesById: recipes, inventoryNames: []
        )
        #expect(missing == ["葱"])
    }

    // MARK: 缺料卡标题

    @Test func cardTitleSaysThisWeekOnlyOnTheCurrentWeek() {
        #expect(MealPlanMissing.cardTitle(count: 3, isCurrentWeek: true) == "本周还缺 3 样食材")
        #expect(MealPlanMissing.cardTitle(count: 1, isCurrentWeek: false) == "这一周还缺 1 样食材")
    }

    // MARK: 「今天」入口显隐

    @Test func isShowingWeekTracksTheCursor() async throws {
        let store = try await makeStore(today: refToday)
        #expect(store.isShowingWeek(containing: refToday))
        store.goToNextWeek()
        #expect(!store.isShowingWeek(containing: refToday))
        store.goToToday(refToday)
        #expect(store.isShowingWeek(containing: refToday))
        #expect(MealPlanEntry.dateKey(store.selectedDay) == "2026-06-10")
    }

    // MARK: 完成 → 扣减候选

    @Test func deductionCandidateRequiresResolvableRecipeWithIngredients() {
        let cookable = recipe("r1", ["鸡蛋"])
        let bare = recipe("r2", [])
        let recipes = ["r1": cookable, "r2": bare]
        #expect(
            MealPlanStore.deductionCandidate(
                for: entry("a", date: refToday, recipeId: "r1"), recipesById: recipes
            ) == cookable
        )
        // No ingredients → nothing to deduct → no prompt.
        #expect(
            MealPlanStore.deductionCandidate(
                for: entry("b", date: refToday, recipeId: "r2"), recipesById: recipes
            ) == nil
        )
        // Unresolvable recipeId → no prompt.
        #expect(
            MealPlanStore.deductionCandidate(
                for: entry("c", date: refToday, recipeId: "ghost"), recipesById: recipes
            ) == nil
        )
    }
}
