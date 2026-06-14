import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// #12 MealPlan 便签 (free-text notes) + 餐别 (mealType) + 剩菜 (leftover):
/// model round-trip (payload-only, backward compatible) + store/gate behavior.
@MainActor
struct MealPlanNotesTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private var refToday: Date { date(2026, 6, 10) }

    private func recipe(_ id: String, _ ingredients: [String]) -> Recipe {
        Recipe(id: id, name: id, category: "荤菜", difficulty: 1, cookingMinutes: 10,
               description: "", ingredients: ingredients.map { RecipeIngredient(name: $0) }, steps: [], tags: [])
    }

    // MARK: Model

    @Test func newFieldsRoundTrip() throws {
        let entry = MealPlanEntry(
            id: "n1", date: refToday, recipeId: "", recipeName: "",
            title: "外卖", mealType: "晚餐", isLeftover: false
        )
        let json = try DomainJSON.encodeToString(entry)
        let decoded = try DomainJSON.decode(MealPlanEntry.self, from: json)
        #expect(decoded.title == "外卖")
        #expect(decoded.mealType == "晚餐")
        #expect(decoded.isNote)
    }

    @Test func legacyJsonWithoutNewKeysDecodesToDefaults() throws {
        let legacy = #"{"id":"a","date":"2026-06-10","recipeId":"r","recipeName":"番茄炒蛋","servings":1,"done":false,"remoteVersion":0}"#
        let decoded = try DomainJSON.decode(MealPlanEntry.self, from: legacy)
        #expect(decoded.title == nil)
        #expect(decoded.mealType == nil)
        #expect(decoded.isLeftover == false)
        #expect(!decoded.isNote)
    }

    @Test func displayTitlePrefersRecipeNameElseNote() {
        #expect(MealPlanEntry(id: "1", date: refToday, recipeId: "r", recipeName: "红烧肉").displayTitle == "红烧肉")
        #expect(MealPlanEntry(id: "2", date: refToday, recipeId: "", recipeName: "", title: "泡面").displayTitle == "泡面")
    }

    // MARK: Store

    private func makeStore() async throws -> MealPlanStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = MealPlanRepository(modelContainer: container)
        let store = MealPlanStore(repository: repo, householdID: "home", today: refToday)
        await store.load()
        return store
    }

    @Test func addNoteCreatesNoteEntry() async throws {
        let store = try await makeStore()
        let ok = await store.addNote(title: "周三吃外卖", date: refToday, mealType: "晚餐")
        #expect(ok)
        let entry = store.entries(forDay: refToday).first
        #expect(entry?.isNote == true)
        #expect(entry?.title == "周三吃外卖")
        #expect(entry?.mealType == "晚餐")
    }

    @Test func addNoteRejectsBlank() async throws {
        let store = try await makeStore()
        #expect(await store.addNote(title: "   ", date: refToday) == false)
        #expect(store.entries(forDay: refToday).isEmpty)
    }

    @Test func addLeftoverDishMarksLeftover() async throws {
        let store = try await makeStore()
        _ = await store.addDish(recipe: recipe("r1", ["番茄"]), date: refToday, isLeftover: true)
        #expect(store.entries(forDay: refToday).first?.isLeftover == true)
    }

    // MARK: Gates

    @Test func deductionSkipsLeftoverAndNote() {
        let recipes = ["r1": recipe("r1", ["番茄"])]
        let leftover = MealPlanEntry(id: "l", date: refToday, recipeId: "r1", recipeName: "r1", isLeftover: true)
        let note = MealPlanEntry(id: "n", date: refToday, recipeId: "", recipeName: "", title: "外卖")
        let normal = MealPlanEntry(id: "d", date: refToday, recipeId: "r1", recipeName: "r1")
        #expect(MealPlanStore.deductionCandidate(for: leftover, recipesById: recipes) == nil)
        #expect(MealPlanStore.deductionCandidate(for: note, recipesById: recipes) == nil)
        #expect(MealPlanStore.deductionCandidate(for: normal, recipesById: recipes) != nil)
    }

    @Test func missingIngredientsSkipsLeftovers() {
        let recipes = ["r1": recipe("r1", ["番茄"])]
        let entries = [
            MealPlanEntry(id: "d", date: refToday, recipeId: "r1", recipeName: "r1"),
            MealPlanEntry(id: "l", date: refToday, recipeId: "r1", recipeName: "r1", isLeftover: true),
        ]
        // Only the normal dish contributes 番茄; the leftover is skipped (so the
        // count is 1, not double).
        let missing = MealPlanMissing.missingIngredientNames(entries: entries, recipesById: recipes, inventoryNames: [])
        #expect(missing == ["番茄"])
    }
}
