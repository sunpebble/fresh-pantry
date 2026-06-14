import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the 减废统计 feature store: use-up-rate math (with the /0
/// guard), consumed/wasted/rescued + per-category aggregation, and time-window
/// filtering over a bounded in-memory food-log slice.
///
/// The pure aggregation (`computeStats` / `computeCategoryBreakdown`) is exercised
/// directly, and the windowing is exercised end-to-end through a real in-memory
/// `FoodLogRepository` so the bounded `loadRecentFor` hydration + window filter
/// compose correctly.
@MainActor
struct WasteInsightsStoreTests {
    // A fixed reference "now" so window math is deterministic. 2026-06-15 is well
    // past the 1st, so 本月 (thisMonth) excludes anything before 2026-06-01.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var refNow: Date { date(2026, 6, 15) }

    private func entry(
        id: String,
        name: String = "牛奶",
        category: String = FoodCategories.other,
        outcome: FoodLogOutcome,
        loggedAt: Date,
        wasExpiring: Bool = false
    ) -> FoodLogEntry {
        FoodLogEntry(
            id: id, name: name, category: category, outcome: outcome,
            loggedAt: loggedAt, wasExpiring: wasExpiring
        )
    }

    private func makeStore(
        _ entries: [FoodLogEntry] = [],
        household: String = "home"
    ) async throws -> WasteInsightsStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = FoodLogRepository(modelContainer: container)
        for entry in entries { try await repo.append(household, entry) }
        let store = WasteInsightsStore(repository: repo, householdID: household)
        await store.load(now: refNow)
        return store
    }

    // MARK: Use-up rate math + /0 guard

    @Test func useUpRateGuardsDivideByZero() {
        let stats = WasteInsightsStore.computeStats([])
        #expect(stats.total == 0)
        #expect(stats.useUpRate == 0) // guarded — no crash, no NaN
        #expect(stats.useUpPercent == 0)
        #expect(stats.isEmpty)
    }

    @Test func useUpRateIsConsumedOverTotal() {
        // 3 consumed, 1 wasted → 3/4 = 75%.
        let stats = WasteInsightsStore.computeStats([
            entry(id: "1", outcome: .consumed, loggedAt: refNow),
            entry(id: "2", outcome: .consumed, loggedAt: refNow),
            entry(id: "3", outcome: .consumed, loggedAt: refNow),
            entry(id: "4", outcome: .wasted, loggedAt: refNow),
        ])
        #expect(stats.consumed == 3)
        #expect(stats.wasted == 1)
        #expect(stats.total == 4)
        #expect(stats.useUpRate == 0.75)
        #expect(stats.useUpPercent == 75)
        #expect(!stats.isEmpty)
    }

    @Test func useUpPercentRoundsHalfUp() {
        // 2 consumed, 1 wasted → 2/3 = 66.67% → rounds to 67.
        let stats = WasteInsightsStore.computeStats([
            entry(id: "1", outcome: .consumed, loggedAt: refNow),
            entry(id: "2", outcome: .consumed, loggedAt: refNow),
            entry(id: "3", outcome: .wasted, loggedAt: refNow),
        ])
        #expect(stats.useUpPercent == 67)
    }

    // MARK: Rescued (consumed && wasExpiring)

    @Test func rescuedCountsOnlyConsumedThatWasExpiring() {
        let stats = WasteInsightsStore.computeStats([
            entry(id: "1", outcome: .consumed, loggedAt: refNow, wasExpiring: true),  // rescued
            entry(id: "2", outcome: .consumed, loggedAt: refNow, wasExpiring: false), // not rescued
            entry(id: "3", outcome: .wasted, loggedAt: refNow, wasExpiring: true),    // wasted, NOT rescued
        ])
        #expect(stats.consumed == 2)
        #expect(stats.wasted == 1)
        #expect(stats.rescued == 1) // only the consumed-and-expiring one
    }

    // MARK: Category breakdown

    @Test func categoryBreakdownAggregatesAndSortsByCanonicalOrder() {
        let breakdown = WasteInsightsStore.computeCategoryBreakdown([
            entry(id: "1", category: FoodCategories.freshProduce, outcome: .consumed, loggedAt: refNow),
            entry(id: "2", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
            entry(id: "3", category: FoodCategories.dairyAndEggs, outcome: .consumed, loggedAt: refNow),
            entry(id: "4", category: FoodCategories.other, outcome: .wasted, loggedAt: refNow),
        ])
        // Sorted by FoodCategories.values position: 乳品蛋类, 果蔬生鲜, …, 其他.
        #expect(breakdown.map(\.category) == [
            FoodCategories.dairyAndEggs,
            FoodCategories.freshProduce,
            FoodCategories.other,
        ])
        let produce = try! #require(breakdown.first { $0.category == FoodCategories.freshProduce })
        #expect(produce.consumed == 1)
        #expect(produce.wasted == 1)
        #expect(produce.total == 2)
    }

    @Test func categoryBreakdownNormalizesAliases() {
        // A legacy alias ("蔬菜" → 果蔬生鲜) collapses into the canonical bucket.
        let breakdown = WasteInsightsStore.computeCategoryBreakdown([
            entry(id: "1", category: "蔬菜", outcome: .consumed, loggedAt: refNow),
            entry(id: "2", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
        ])
        #expect(breakdown.count == 1)
        #expect(breakdown[0].category == FoodCategories.freshProduce)
        #expect(breakdown[0].consumed == 1)
        #expect(breakdown[0].wasted == 1)
    }

    // MARK: 最常浪费 ranking

    @Test func mostWastedCountsWastedOnlyRankedDescDroppingZero() {
        let rows = WasteInsightsStore.computeMostWasted([
            entry(id: "1", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
            entry(id: "2", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
            entry(id: "3", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
            entry(id: "4", category: FoodCategories.other, outcome: .wasted, loggedAt: refNow),
            entry(id: "5", category: FoodCategories.meatAndSeafood, outcome: .consumed, loggedAt: refNow),
        ])
        // wasted only, count desc; the pure-consumed category never appears.
        #expect(rows.map(\.category) == [FoodCategories.freshProduce, FoodCategories.other])
        #expect(rows.map(\.count) == [3, 1])
        #expect(!rows.contains { $0.category == FoodCategories.meatAndSeafood })
    }

    @Test func mostWastedNormalizesAliases() {
        let rows = WasteInsightsStore.computeMostWasted([
            entry(id: "1", category: "蔬菜", outcome: .wasted, loggedAt: refNow),
            entry(id: "2", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: refNow),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].category == FoodCategories.freshProduce)
        #expect(rows[0].count == 2)
    }

    // MARK: Window filtering (end-to-end through the repo)

    @Test func thisMonthWindowExcludesEntriesBeforeMonthStart() async throws {
        let store = try await makeStore([
            entry(id: "in", outcome: .consumed, loggedAt: date(2026, 6, 5)),   // this month
            entry(id: "out", outcome: .wasted, loggedAt: date(2026, 5, 20)),   // last month
        ])
        store.window = .thisMonth
        let stats = store.stats(now: refNow)
        #expect(stats.total == 1) // only the June entry
        #expect(stats.consumed == 1)
        #expect(stats.wasted == 0)
    }

    @Test func last30DaysWindowIncludesMoreThanThisMonth() async throws {
        // 2026-05-20 is within 30 days of 2026-06-15 but before the month start.
        let store = try await makeStore([
            entry(id: "june", outcome: .consumed, loggedAt: date(2026, 6, 5)),
            entry(id: "may", outcome: .wasted, loggedAt: date(2026, 5, 20)),
        ])
        store.window = .thisMonth
        #expect(store.stats(now: refNow).total == 1)

        store.window = .last30Days
        let stats = store.stats(now: refNow)
        #expect(stats.total == 2) // both now in window
        #expect(stats.consumed == 1)
        #expect(stats.wasted == 1)
    }

    @Test func windowAndCategoryBreakdownComposeOverLoadedSlice() async throws {
        let store = try await makeStore([
            entry(id: "1", category: FoodCategories.meatAndSeafood, outcome: .consumed, loggedAt: date(2026, 6, 10), wasExpiring: true),
            entry(id: "2", category: FoodCategories.meatAndSeafood, outcome: .wasted, loggedAt: date(2026, 6, 12)),
            entry(id: "old", category: FoodCategories.dairyAndEggs, outcome: .wasted, loggedAt: date(2026, 5, 1)),
        ])
        store.window = .thisMonth
        let breakdown = store.categoryBreakdown(now: refNow)
        // The May dairy entry is outside 本月 → only the June meat rows show.
        #expect(breakdown.map(\.category) == [FoodCategories.meatAndSeafood])
        #expect(breakdown[0].consumed == 1)
        #expect(breakdown[0].wasted == 1)
        #expect(store.stats(now: refNow).rescued == 1) // the expiring consumed one
    }

    // MARK: Category drill-down filter

    @Test func categoryFilterNarrowsEveryAggregateToSelectedBucket() async throws {
        let store = try await makeStore([
            entry(id: "p1", category: FoodCategories.freshProduce, outcome: .consumed, loggedAt: date(2026, 6, 10)),
            entry(id: "p2", category: FoodCategories.freshProduce, outcome: .wasted, loggedAt: date(2026, 6, 11)),
            entry(id: "m1", category: FoodCategories.meatAndSeafood, outcome: .wasted, loggedAt: date(2026, 6, 12)),
        ])
        store.window = .thisMonth
        #expect(store.stats(now: refNow).total == 3) // unfiltered

        store.categoryFilter = FoodCategories.freshProduce
        let stats = store.stats(now: refNow)
        #expect(stats.total == 2)        // only produce
        #expect(stats.consumed == 1)
        #expect(stats.wasted == 1)
        #expect(store.historyEntries(now: refNow).allSatisfy {
            FoodCategories.dropdownValue($0.category) == FoodCategories.freshProduce
        })
        #expect(store.categoryBreakdown(now: refNow).map(\.category) == [FoodCategories.freshProduce])
    }

    @Test func categoryFilterMatchesLegacyAliasViaCanonicalBucket() async throws {
        let store = try await makeStore([
            entry(id: "alias", category: "蔬菜", outcome: .wasted, loggedAt: date(2026, 6, 10)),
        ])
        store.window = .thisMonth
        store.categoryFilter = FoodCategories.freshProduce // canonical bucket
        #expect(store.stats(now: refNow).total == 1) // the alias entry matched via dropdownValue
    }

    @Test func categoryOptionsListInWindowBucketsIgnoringActiveFilter() async throws {
        let store = try await makeStore([
            entry(id: "p", category: FoodCategories.freshProduce, outcome: .consumed, loggedAt: date(2026, 6, 10)),
            entry(id: "m", category: FoodCategories.meatAndSeafood, outcome: .wasted, loggedAt: date(2026, 6, 11)),
            entry(id: "old", category: FoodCategories.dairyAndEggs, outcome: .wasted, loggedAt: date(2026, 5, 1)), // outside 本月
        ])
        store.window = .thisMonth
        store.categoryFilter = FoodCategories.freshProduce // a filter is active…
        // …options still list every in-window bucket (not just the selected one),
        // and exclude the out-of-window dairy entry.
        #expect(Set(store.categoryOptions(now: refNow)) == [FoodCategories.freshProduce, FoodCategories.meatAndSeafood])
    }

    @Test func correctOutcomeUpdatesStats() async throws {
        let store = try await makeStore([
            entry(id: "1", outcome: .wasted, loggedAt: date(2026, 6, 10)),
        ])
        store.window = .thisMonth
        #expect(store.stats(now: refNow).wasted == 1)
        let changed = await store.correctOutcome(entryId: "1", to: .consumed)
        #expect(changed)
        #expect(store.stats(now: refNow).consumed == 1)
        #expect(store.stats(now: refNow).wasted == 0)
        #expect(!store.correctOutcomeError) // no error on success
    }

    @Test func correctOutcomeSetErrorFlagWhenEntryNotFound() async throws {
        // An empty store — the entry-not-found guard path sets correctOutcomeError.
        let store = try await makeStore([])
        #expect(!store.correctOutcomeError)
        let ok = await store.correctOutcome(entryId: "ghost", to: .consumed)
        #expect(!ok)
        #expect(store.correctOutcomeError)
    }
}
