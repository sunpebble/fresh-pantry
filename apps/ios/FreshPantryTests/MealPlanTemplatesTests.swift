import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// #14 reusable weekly meal-plan templates — pure builder + persistence + the
/// MealPlanStore apply path.
@MainActor
struct MealPlanTemplatesTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private var refToday: Date { date(2026, 6, 10) } // Wed → week starts Mon 6/8
    private var weekStart: Date { date(2026, 6, 8) }

    private func entry(_ recipeId: String, on day: Date, servings: Int = 1) -> MealPlanEntry {
        MealPlanEntry(id: MealPlanStore.newId(), date: day, recipeId: recipeId, recipeName: recipeId, servings: servings)
    }

    // MARK: Pure builder

    @Test func itemsCaptureDayOffsetFromWeekStart() {
        let entries = [entry("a", on: date(2026, 6, 8)), entry("b", on: date(2026, 6, 10))]
        let items = MealPlanTemplates.items(from: entries, weekStart: weekStart)
        #expect(items.count == 2)
        #expect(items.first { $0.recipeId == "a" }?.dayOffset == 0)
        #expect(items.first { $0.recipeId == "b" }?.dayOffset == 2)
    }

    @Test func itemsDropOutOfWeekAndNotes() {
        let entries = [
            entry("inWeek", on: date(2026, 6, 9)),
            entry("nextWeek", on: date(2026, 6, 16)), // offset 8 → dropped
            entry("", on: date(2026, 6, 9)), // note-only (empty recipeId) → dropped
        ]
        let items = MealPlanTemplates.items(from: entries, weekStart: weekStart)
        #expect(items.map(\.recipeId) == ["inWeek"])
    }

    @Test func upsertingReplacesByNameNewestFirst() {
        let old = MealPlanTemplate(id: "1", name: "工作日", items: [])
        let other = MealPlanTemplate(id: "2", name: "周末", items: [])
        let updated = MealPlanTemplate(id: "3", name: "工作日", items: [])
        let result = MealPlanTemplates.upserting(updated, into: [old, other])
        #expect(result.map(\.id) == ["3", "2"]) // replaced "1", newest first
    }

    @Test func saveLoadRoundTrips() {
        let defaults = UserDefaults(suiteName: "test.mealtemplates.\(UUID().uuidString)")!
        let template = MealPlanTemplate(
            id: "t1", name: "我的一周",
            items: [MealPlanTemplateItem(recipeId: "a", recipeName: "A", recipeImageUrl: nil, dayOffset: 0, servings: 2)]
        )
        MealPlanTemplates.save([template], to: defaults)
        #expect(MealPlanTemplates.load(defaults) == [template])
    }

    // MARK: Store apply

    private func makeStore() async throws -> MealPlanStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = MealPlanRepository(modelContainer: container)
        let store = MealPlanStore(repository: repo, householdID: "home", today: refToday)
        await store.load()
        return store
    }

    @Test func applyTemplateAddsDishesAtOffsets() async throws {
        let store = try await makeStore()
        let template = MealPlanTemplate(
            id: "t", name: "x",
            items: [
                MealPlanTemplateItem(recipeId: "r1", recipeName: "番茄炒蛋", recipeImageUrl: nil, dayOffset: 0, servings: 1),
                MealPlanTemplateItem(recipeId: "r2", recipeName: "可乐鸡翅", recipeImageUrl: nil, dayOffset: 2, servings: 3),
            ]
        )
        let added = await store.applyTemplate(template)
        #expect(added == 2)
        #expect(store.entries(forDay: date(2026, 6, 8)).first?.recipeId == "r1")
        let wed = store.entries(forDay: date(2026, 6, 10))
        #expect(wed.first?.recipeId == "r2")
        #expect(wed.first?.servings == 3)
    }
}
