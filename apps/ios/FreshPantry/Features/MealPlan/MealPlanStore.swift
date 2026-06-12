import Foundation

/// Feature store for the 膳食计划 weekly-calendar slice — the same
/// `@Observable @MainActor` template the Inventory / Shopping / Recipes stores
/// established.
///
/// Owns the household's meal-plan entries (one record == one dish on one LOCAL
/// calendar day) and a `weekStart` cursor (Monday-anchored local midnight) that
/// drives the visible 7-day strip. All scoping, week-windowing, per-day
/// grouping, and persistence live here (or the repo); views never touch
/// SwiftData directly. Mutations route through `MealPlanRepository` then reload
/// the canonical scope (mirrors `ShoppingStore.persist`).
@Observable
@MainActor
final class MealPlanStore {
    private let repository: MealPlanRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?

    /// Repo-ordered entries (the source of truth for the whole household scope —
    /// every persist re-syncs this from a canonical reload).
    private(set) var entries: [MealPlanEntry] = []
    /// Monday (local midnight) of the visible week. Prev/next shift by 7 days.
    private(set) var weekStart: Date
    /// The day whose dishes the detail list renders. Always inside the visible
    /// week; clamped back into range on week navigation.
    private(set) var selectedDay: Date
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    /// `today` is injected so tests can pin "now"; production passes `Date()`.
    init(
        repository: MealPlanRepository,
        householdID: String,
        today: Date = Date(),
        syncWriter: SyncWriter? = nil
    ) {
        self.repository = repository
        self.householdID = householdID
        self.syncWriter = syncWriter
        let start = MealPlanStore.weekStart(containing: today)
        self.weekStart = start
        self.selectedDay = MealPlanEntry.dateOnly(today)
    }

    // MARK: Loading

    /// Loads the household scope off the repo actor and assigns on the main actor.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            entries = try await repository.loadAllFor(householdID)
        } catch {
            // A load failure simply means "nothing to show"; never crash the tab.
            entries = []
        }
    }

    // MARK: Week navigation

    /// The 7 LOCAL-midnight days of the visible week (Monday → Sunday).
    var weekDays: [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            .map(MealPlanEntry.dateOnly)
    }

    /// Shifts the visible week back/forward by 7 days, keeping the selected
    /// weekday (same offset within the week) so navigation feels continuous.
    func goToPreviousWeek() { shiftWeek(by: -7) }
    func goToNextWeek() { shiftWeek(by: 7) }

    /// Jumps the cursor back to the week containing today and selects today.
    func goToToday(_ now: Date = Date()) {
        weekStart = MealPlanStore.weekStart(containing: now)
        selectedDay = MealPlanEntry.dateOnly(now)
    }

    /// Whether the visible week contains `now` — gates the week strip's 「今天」
    /// jump-back pill and the 缺料 card's 「本周」 wording.
    func isShowingWeek(containing now: Date = Date()) -> Bool {
        weekStart == MealPlanStore.weekStart(containing: now)
    }

    func select(_ day: Date) {
        selectedDay = MealPlanEntry.dateOnly(day)
    }

    private func shiftWeek(by days: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let offset = weekdayOffset(of: selectedDay, from: weekStart)
        guard
            let nextStart = calendar.date(byAdding: .day, value: days, to: weekStart),
            let nextSelected = calendar.date(byAdding: .day, value: offset, to: nextStart)
        else { return }
        weekStart = MealPlanEntry.dateOnly(nextStart)
        selectedDay = MealPlanEntry.dateOnly(nextSelected)
    }

    /// 0...6 offset of `day` within the week starting at `start` (clamped 0...6).
    private func weekdayOffset(of day: Date, from start: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let diff = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return min(max(diff, 0), 6)
    }

    // MARK: Derived view data

    /// Entries planned for `day` (matched by `yyyy-MM-dd` key), in stable repo
    /// order. The grouping is by local-day key so a row minted at any time of day
    /// lands on the right calendar day.
    func entries(forDay day: Date) -> [MealPlanEntry] {
        let key = MealPlanEntry.dateKey(day)
        return entries.filter { MealPlanEntry.dateKey($0.date) == key }
    }

    /// Entries inside the currently visible week (Mon...Sun), in repo order.
    var entriesInVisibleWeek: [MealPlanEntry] {
        let keys = Set(weekDays.map(MealPlanEntry.dateKey))
        return entries.filter { keys.contains(MealPlanEntry.dateKey($0.date)) }
    }

    /// Count of planned dishes on `day` (drives the strip's per-day dot/badge).
    func dishCount(forDay day: Date) -> Int {
        entries(forDay: day).count
    }

    /// The selected day's dishes — what the detail list renders.
    var selectedDayEntries: [MealPlanEntry] {
        entries(forDay: selectedDay)
    }

    // MARK: Mutations

    /// FIFO mutation chain: every mutation awaits its predecessor before its
    /// read-modify-write runs. `persist` suspends twice (`saveEntries` +
    /// `loadAllFor`), and during those suspension points actor reentrancy allows
    /// a second mutation to enter and read the same stale snapshot — the second
    /// `saveEntries` would then silently overwrite the first. The chain prevents
    /// this: mutations execute in the order they were enqueued.
    @ObservationIgnored
    private var lastMutation: Task<Void, Never>?

    /// Runs `body` after every previously-enqueued mutation finished, and makes
    /// the next mutation wait for `body` in turn. MainActor-only, so reading +
    /// relinking `lastMutation` between two mutations is race-free.
    private func serializedMutation<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = lastMutation
        let task: Task<T, Never> = Task {
            await previous?.value
            return await body()
        }
        lastMutation = Task { _ = await task.value }
        return await task.value
    }

    /// Plans `recipe` on `day` (servings clamped to ≥ 1). Mints a fresh UUID id
    /// (sync-clean; no factory on the domain type). Returns whether a row was added.
    @discardableResult
    func addDish(recipe: Recipe, date: Date, servings: Int = 1) async -> Bool {
        await serializedMutation { await self.performAddDish(recipe: recipe, date: date, servings: servings) }
    }

    private func performAddDish(recipe: Recipe, date: Date, servings: Int) async -> Bool {
        guard !recipe.id.isEmpty else { return false }
        let entry = MealPlanEntry(
            id: Self.newId(),
            date: date,
            recipeId: recipe.id,
            recipeName: recipe.name,
            recipeImageUrl: recipe.imageUrl,
            servings: max(servings, 1)
        )
        guard await persist(entries + [entry]) else { return false }
        if let patch = DomainJSON.valueMap(entry) {
            await syncWriter?.enqueue(
                entityType: .mealPlanEntry,
                entityId: entry.id,
                operation: .create,
                patch: patch,
                baseVersion: nil
            )
        }
        return true
    }

    /// Flips a row's `done` flag by stable id identity, persists, reloads.
    @discardableResult
    func toggleDone(_ target: MealPlanEntry) async -> Bool {
        await serializedMutation { await self.performToggleDone(target) }
    }

    private func performToggleDone(_ target: MealPlanEntry) async -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == target.id }) else { return false }
        let entry = entries[index]
        let updatedEntry = entry.copyWith(done: !entry.done)
        var next = entries
        next[index] = updatedEntry
        guard await persist(next) else { return false }
        if let patch = DomainJSON.valueMap(updatedEntry) {
            await syncWriter?.enqueue(
                entityType: .mealPlanEntry,
                entityId: updatedEntry.id,
                operation: .update,
                patch: patch,
                baseVersion: entry.remoteVersion
            )
        }
        return true
    }

    /// Deletes a row by stable id identity, persists the survivors, reloads.
    @discardableResult
    func remove(_ target: MealPlanEntry) async -> Bool {
        await serializedMutation { await self.performRemove(target) }
    }

    private func performRemove(_ target: MealPlanEntry) async -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == target.id }) else { return false }
        let removed = entries[index]
        var survivors = entries
        survivors.remove(at: index)
        guard await persist(survivors) else { return false }
        if let patch = DomainJSON.valueMap(removed) {
            await syncWriter?.enqueue(
                entityType: .mealPlanEntry,
                entityId: removed.id,
                operation: .delete,
                patch: patch,
                baseVersion: removed.remoteVersion
            )
        }
        return true
    }

    /// Persists `next` through the repo actor (which filters empty id/recipeId +
    /// de-dupes id), then re-syncs local state from the canonical reload.
    private func persist(_ next: [MealPlanEntry]) async -> Bool {
        do {
            try await repository.saveEntries(householdID, next)
            entries = try await repository.loadAllFor(householdID)
            return true
        } catch {
            return false
        }
    }

    // MARK: Static helpers

    /// The recipe a just-completed entry should offer cook-time deduction for —
    /// nil when the recipeId no longer resolves against the corpus (same lookup
    /// the 缺料 derivation uses) or the recipe has no ingredients to deduct.
    nonisolated static func deductionCandidate(
        for entry: MealPlanEntry,
        recipesById: [String: Recipe]
    ) -> Recipe? {
        guard let recipe = recipesById[entry.recipeId], !recipe.ingredients.isEmpty else { return nil }
        return recipe
    }

    /// A fresh lowercased UUID — a SYNC-CLEAN id (the household sync engine
    /// reconciles by id and writes only a UUID id remotely, so a non-UUID local
    /// id would duplicate on upload). Minted here as the domain type has no
    /// `newId()`. `nonisolated` so the DEBUG seeder (a nonisolated enum) can mint ids.
    nonisolated static func newId() -> String { UUID().uuidString.lowercased() }

    /// Monday (local midnight) of the week containing `value`. The calendar's
    /// firstWeekday is forced to Monday so the strip is always Mon → Sun,
    /// independent of locale (matches the blueprint's Mon-anchored week).
    /// `nonisolated` — pure date math, also called by the seeder + formatters.
    nonisolated static func weekStart(containing value: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2 // Monday
        let day = MealPlanEntry.dateOnly(value)
        guard
            let interval = calendar.dateInterval(of: .weekOfYear, for: day)
        else { return day }
        return MealPlanEntry.dateOnly(interval.start)
    }
}
