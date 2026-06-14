import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the 膳食计划 feature store: per-day grouping, visible-week
/// windowing, week navigation, and the add / toggle / remove mutations. Backed
/// by a real in-memory repository so the load / persist round-trip (with its
/// empty-id filter + JSON re-encode/decode) is exercised end-to-end. Date
/// helpers (local-midnight normalization, `yyyy-MM-dd` round-trip) are asserted
/// against the domain type so the calendar math stays parity-correct.
@MainActor
struct MealPlanStoreTests {
    // A fixed reference "today" so week math is deterministic regardless of the
    // wall clock. 2026-06-10 is a Wednesday → its week (Mon-anchored) starts
    // 2026-06-08 and ends 2026-06-14.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var refToday: Date { date(2026, 6, 10) } // Wednesday

    private func makeStore(
        _ entries: [MealPlanEntry] = [],
        household: String = "home",
        today: Date? = nil
    ) async throws -> MealPlanStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = MealPlanRepository(modelContainer: container)
        if !entries.isEmpty { try await repo.saveEntries(household, entries) }
        let store = MealPlanStore(repository: repo, householdID: household, today: today ?? refToday)
        await store.load()
        return store
    }

    private func entry(
        id: String,
        date: Date,
        recipeId: String = "r1",
        recipeName: String = "番茄炒蛋",
        servings: Int = 1,
        done: Bool = false
    ) -> MealPlanEntry {
        MealPlanEntry(
            id: id,
            date: date,
            recipeId: recipeId,
            recipeName: recipeName,
            servings: servings,
            done: done
        )
    }

    private func recipe(id: String = "rx", name: String = "红烧肉") -> Recipe {
        Recipe(
            id: id,
            name: name,
            category: "荤菜",
            difficulty: 2,
            cookingMinutes: 40,
            description: "",
            ingredients: [],
            steps: []
        )
    }

    // MARK: Loading

    @Test func loadPopulatesEntriesAndSetsFlags() async throws {
        let store = try await makeStore([entry(id: "a", date: refToday)])
        #expect(store.entries.count == 1)
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Week window

    @Test func weekStartIsMondayOfTheContainingWeek() async throws {
        let store = try await makeStore(today: refToday) // Wed 2026-06-10
        #expect(MealPlanEntry.dateKey(store.weekStart) == "2026-06-08") // Monday
        #expect(store.weekDays.map(MealPlanEntry.dateKey) == [
            "2026-06-08", "2026-06-09", "2026-06-10",
            "2026-06-11", "2026-06-12", "2026-06-13", "2026-06-14",
        ])
    }

    @Test func entriesInVisibleWeekExcludeOtherWeeks() async throws {
        let store = try await makeStore([
            entry(id: "in_mon", date: date(2026, 6, 8)),   // this week
            entry(id: "in_sun", date: date(2026, 6, 14)),  // this week (Sun)
            entry(id: "prev", date: date(2026, 6, 7)),     // previous week (Sun)
            entry(id: "next", date: date(2026, 6, 15)),    // next week (Mon)
        ], today: refToday)
        #expect(Set(store.entriesInVisibleWeek.map(\.id)) == ["in_mon", "in_sun"])
    }

    @Test func nextAndPreviousWeekShiftTheWindowBySevenDays() async throws {
        let store = try await makeStore(today: refToday)
        store.goToNextWeek()
        #expect(MealPlanEntry.dateKey(store.weekStart) == "2026-06-15")
        store.goToPreviousWeek()
        store.goToPreviousWeek()
        #expect(MealPlanEntry.dateKey(store.weekStart) == "2026-06-01")
    }

    @Test func weekNavigationPreservesSelectedWeekday() async throws {
        let store = try await makeStore(today: refToday) // selects Wed (offset 2)
        #expect(MealPlanEntry.dateKey(store.selectedDay) == "2026-06-10")
        store.goToNextWeek()
        // Same offset (Wed) in the next week.
        #expect(MealPlanEntry.dateKey(store.selectedDay) == "2026-06-17")
    }

    @Test func goToTodayResetsWindowAndSelection() async throws {
        let store = try await makeStore(today: refToday)
        store.goToNextWeek()
        store.goToNextWeek()
        store.goToToday(refToday)
        #expect(MealPlanEntry.dateKey(store.weekStart) == "2026-06-08")
        #expect(MealPlanEntry.dateKey(store.selectedDay) == "2026-06-10")
    }

    // MARK: Per-day grouping

    @Test func entriesForDayGroupByLocalDayKey() async throws {
        let store = try await makeStore([
            entry(id: "w1", date: date(2026, 6, 10)),
            entry(id: "w2", date: date(2026, 6, 10), recipeName: "青椒土豆丝"),
            entry(id: "other", date: date(2026, 6, 11)),
        ], today: refToday)
        #expect(Set(store.entries(forDay: date(2026, 6, 10)).map(\.id)) == ["w1", "w2"])
        #expect(store.entries(forDay: date(2026, 6, 11)).map(\.id) == ["other"])
        #expect(store.dishCount(forDay: date(2026, 6, 10)) == 2)
        #expect(store.dishCount(forDay: date(2026, 6, 9)) == 0)
    }

    @Test func groupingIgnoresTimeOfDay() async throws {
        // An entry minted late in the day must still land on its calendar day.
        let store = try await makeStore([
            entry(id: "late", date: date(2026, 6, 10, hour: 23)),
        ], today: refToday)
        #expect(store.entries(forDay: date(2026, 6, 10)).map(\.id) == ["late"])
    }

    @Test func selectedDayEntriesTrackSelection() async throws {
        let store = try await makeStore([
            entry(id: "wed", date: date(2026, 6, 10)),
            entry(id: "thu", date: date(2026, 6, 11)),
        ], today: refToday)
        #expect(store.selectedDayEntries.map(\.id) == ["wed"]) // selection defaults to today (Wed)
        store.select(date(2026, 6, 11))
        #expect(store.selectedDayEntries.map(\.id) == ["thu"])
    }

    // MARK: Date normalization / round-trip

    @Test func dateNormalizedToLocalMidnight() async throws {
        let store = try await makeStore([
            entry(id: "noon", date: date(2026, 6, 10, hour: 13)),
        ], today: refToday)
        let stored = store.entries.first { $0.id == "noon" }!
        // Stored date is truncated to local midnight.
        #expect(stored.date == MealPlanEntry.dateOnly(date(2026, 6, 10)))
        let comps = calendar.dateComponents([.hour, .minute, .second], from: stored.date)
        #expect(comps.hour == 0 && comps.minute == 0 && comps.second == 0)
    }

    @Test func yyyyMMddRoundTripsThroughPersistence() async throws {
        // The repo re-encodes the entry to JSON (date → "yyyy-MM-dd") and back;
        // the key must survive the round-trip unchanged.
        let store = try await makeStore([
            entry(id: "rt", date: date(2026, 6, 9)),
        ], today: refToday)
        let stored = store.entries.first { $0.id == "rt" }!
        #expect(MealPlanEntry.dateKey(stored.date) == "2026-06-09")
    }

    // MARK: Add

    @Test func addDishPlansRecipeOnDayWithDefaultServings() async throws {
        let store = try await makeStore(today: refToday)
        let added = await store.addDish(recipe: recipe(id: "rx", name: "红烧肉"), date: date(2026, 6, 12))
        #expect(added)
        let day = store.entries(forDay: date(2026, 6, 12))
        #expect(day.count == 1)
        let planned = day.first!
        #expect(planned.recipeId == "rx")
        #expect(planned.recipeName == "红烧肉")
        #expect(planned.servings == 1)
        #expect(!planned.done)
        #expect(ProposalApply.isUuid(planned.id)) // sync-clean UUID id
    }

    @Test func addDishClampsServingsToAtLeastOne() async throws {
        let store = try await makeStore(today: refToday)
        _ = await store.addDish(recipe: recipe(), date: refToday, servings: 0)
        #expect(store.selectedDayEntries.first?.servings == 1)
    }

    @Test func addDishKeepsExplicitServings() async throws {
        let store = try await makeStore(today: refToday)
        _ = await store.addDish(recipe: recipe(), date: refToday, servings: 3)
        #expect(store.selectedDayEntries.first?.servings == 3)
    }

    @Test func addDishSurvivesReload() async throws {
        let store = try await makeStore(today: refToday)
        _ = await store.addDish(recipe: recipe(id: "rp"), date: refToday)
        await store.load()
        #expect(store.selectedDayEntries.contains { $0.recipeId == "rp" })
    }

    // MARK: Toggle

    @Test func toggleDoneFlipsAndPersists() async throws {
        let store = try await makeStore([entry(id: "a", date: refToday)], today: refToday)
        let target = store.entries.first { $0.id == "a" }!
        #expect(!target.done)

        let toggled = await store.toggleDone(target)
        #expect(toggled)
        #expect(store.entries.first { $0.id == "a" }?.done == true)

        await store.load()
        #expect(store.entries.first { $0.id == "a" }?.done == true)

        let again = store.entries.first { $0.id == "a" }!
        _ = await store.toggleDone(again)
        #expect(store.entries.first { $0.id == "a" }?.done == false)
    }

    @Test func toggleUnknownEntryReturnsFalse() async throws {
        let store = try await makeStore([entry(id: "a", date: refToday)], today: refToday)
        let ghost = entry(id: "zzz", date: refToday)
        #expect(await store.toggleDone(ghost) == false)
    }

    // MARK: Remove

    @Test func removeDeletesByIdAndPersists() async throws {
        let store = try await makeStore([
            entry(id: "a", date: refToday),
            entry(id: "b", date: refToday),
        ], today: refToday)
        let target = store.entries.first { $0.id == "a" }!
        let removed = await store.remove(target)
        #expect(removed)
        #expect(store.entries.map(\.id) == ["b"])

        await store.load()
        #expect(store.entries.map(\.id) == ["b"])
    }

    @Test func removeUnknownEntryReturnsFalse() async throws {
        let store = try await makeStore([entry(id: "a", date: refToday)], today: refToday)
        let ghost = entry(id: "zzz", date: refToday)
        #expect(await store.remove(ghost) == false)
        #expect(store.entries.count == 1)
    }

    // MARK: Move (reschedule to another day)

    @Test func moveDishChangesDayInPlaceKeepingId() async throws {
        let store = try await makeStore([entry(id: "a", date: date(2026, 6, 10))], today: refToday)
        let target = store.entries.first { $0.id == "a" }!
        let moved = await store.moveDish(target, to: date(2026, 6, 12))
        #expect(moved)
        #expect(store.entries(forDay: date(2026, 6, 10)).isEmpty)         // left old day
        #expect(store.entries(forDay: date(2026, 6, 12)).map(\.id) == ["a"]) // same id, new day
    }

    @Test func moveDishNormalizesToLocalMidnightAndPersists() async throws {
        let store = try await makeStore([entry(id: "a", date: date(2026, 6, 10))], today: refToday)
        let target = store.entries.first { $0.id == "a" }!
        _ = await store.moveDish(target, to: date(2026, 6, 13, hour: 15))
        await store.load()
        let stored = store.entries.first { $0.id == "a" }!
        #expect(MealPlanEntry.dateKey(stored.date) == "2026-06-13") // survives reload, time stripped
    }

    @Test func moveDishToSameDayIsNoOpButSucceeds() async throws {
        let store = try await makeStore([entry(id: "a", date: date(2026, 6, 10))], today: refToday)
        let target = store.entries.first { $0.id == "a" }!
        #expect(await store.moveDish(target, to: date(2026, 6, 10, hour: 9))) // same calendar day
        #expect(store.entries(forDay: date(2026, 6, 10)).map(\.id) == ["a"])
    }

    @Test func moveUnknownEntryReturnsFalse() async throws {
        let store = try await makeStore([entry(id: "a", date: refToday)], today: refToday)
        let ghost = entry(id: "zzz", date: refToday)
        #expect(await store.moveDish(ghost, to: date(2026, 6, 12)) == false)
    }

    // MARK: Serialized mutations (concurrency)

    /// Two concurrent mutations must both land — the second must not overwrite the
    /// first's write by reading a stale snapshot. Without `serializedMutation` the
    /// second toggleDone races the first's `persist` double-await and silently
    /// drops the first toggle.
    @Test func concurrentTogglesBothLand() async throws {
        let store = try await makeStore([
            entry(id: "a", date: refToday),
            entry(id: "b", date: refToday),
        ], today: refToday)
        let a = store.entries.first { $0.id == "a" }!
        let b = store.entries.first { $0.id == "b" }!

        // Fire both without awaiting individually — the store must serialise them.
        async let r1 = store.toggleDone(a)
        async let r2 = store.toggleDone(b)
        let (ok1, ok2) = await (r1, r2)

        #expect(ok1)
        #expect(ok2)
        #expect(store.entries.first { $0.id == "a" }?.done == true)
        #expect(store.entries.first { $0.id == "b" }?.done == true)
    }

    /// A toggleDone immediately followed by a remove must both land: the entry
    /// must first be toggled then deleted (not silently resurrected by the toggle's
    /// stale-snapshot persist racing the remove).
    @Test func toggleThenRemoveSerializesCorrectly() async throws {
        let store = try await makeStore([
            entry(id: "a", date: refToday),
            entry(id: "b", date: refToday),
        ], today: refToday)
        let a = store.entries.first { $0.id == "a" }!
        let b = store.entries.first { $0.id == "b" }!

        async let r1 = store.toggleDone(a)
        async let r2 = store.remove(b)
        let (ok1, ok2) = await (r1, r2)

        #expect(ok1)
        #expect(ok2)
        #expect(store.entries.map(\.id) == ["a"])
        #expect(store.entries.first { $0.id == "a" }?.done == true)
    }
}
