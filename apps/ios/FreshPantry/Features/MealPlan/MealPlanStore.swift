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
    /// Optional device-local cook tally (#7) — marking a planned dish done records
    /// a cook. nil keeps existing tests local-only.
    private let cookHistoryRepository: CookHistoryRepository?

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
        syncWriter: SyncWriter? = nil,
        cookHistoryRepository: CookHistoryRepository? = nil
    ) {
        self.repository = repository
        self.householdID = householdID
        self.syncWriter = syncWriter
        self.cookHistoryRepository = cookHistoryRepository
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

    // MARK: Mutations (offline-first / optimistic)
    //
    // Same contract as ShoppingStore: the calendar tap (加菜 / 完成 toggle /
    // 删除) updates the observable `entries` SYNCHRONOUSLY before any await, so the
    // UI reflects it this tick; the SINGLE touched row then lands in the
    // background (no whole-scope rewrite, no post-save reload), rolling back on a
    // persist failure. Single-row writes can't clobber a peer instance's write to
    // a different day, so no 写前重读 is needed.

    /// FIFO serialization of the BACKGROUND single-row persists — keeps a row
    /// toggled-then-removed landing in order. The optimistic `entries` edit
    /// already happened before this runs, so it no longer gates the visual change.
    @ObservationIgnored
    private var lastMutation: Task<Void, Never>?

    private func serializedPersist<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = lastMutation
        let task: Task<T, Never> = Task {
            await previous?.value
            return await body()
        }
        lastMutation = Task { _ = await task.value }
        return await task.value
    }

    /// Plans `recipe` on `day` OPTIMISTICALLY (the dish appears the instant the
    /// tap lands), servings clamped to ≥ 1, minting a fresh UUID id (sync-clean).
    /// Returns whether a row was added; a persist failure removes it.
    @discardableResult
    func addDish(recipe: Recipe, date: Date, servings: Int = 1, mealType: String? = nil, isLeftover: Bool = false) async -> Bool {
        guard !recipe.id.isEmpty else { return false }
        return await addPlannedEntry(
            recipeId: recipe.id,
            recipeName: recipe.name,
            recipeImageUrl: recipe.imageUrl,
            date: date,
            servings: servings,
            mealType: mealType,
            isLeftover: isLeftover
        )
    }

    /// Plans a free-text NOTE (no recipe) on `day` — "周三吃外卖", "泡面" etc. Empty
    /// title is rejected. Optimistic, same single-row contract as `addDish`.
    @discardableResult
    func addNote(title: String, date: Date, mealType: String? = nil) async -> Bool {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else { return false }
        return await addPlannedEntry(
            recipeId: "",
            recipeName: "",
            recipeImageUrl: nil,
            date: date,
            servings: 1,
            title: trimmed,
            mealType: mealType
        )
    }

    /// Core optimistic add shared by `addDish` / `addNote` / `applyTemplate` —
    /// plans an entry from its identity fields rather than a full `Recipe`. A note
    /// passes an empty recipeId + a `title`.
    @discardableResult
    private func addPlannedEntry(
        recipeId: String,
        recipeName: String,
        recipeImageUrl: String?,
        date: Date,
        servings: Int,
        title: String? = nil,
        mealType: String? = nil,
        isLeftover: Bool = false
    ) async -> Bool {
        // Either a recipe dish (recipeId) or a note (title) must be present.
        guard !recipeId.isEmpty || !(title?.trimmed.isEmpty ?? true) else { return false }
        let entry = MealPlanEntry(
            id: Self.newId(),
            date: date,
            recipeId: recipeId,
            recipeName: recipeName,
            recipeImageUrl: recipeImageUrl,
            servings: max(servings, 1),
            title: title,
            mealType: mealType,
            isLeftover: isLeftover
        )
        entries.append(entry) // optimistic
        return await serializedPersist {
            do {
                try await self.repository.upsert(self.householdID, entry)
            } catch {
                self.entries.removeAll { $0.id == entry.id }
                return false
            }
            if let patch = DomainJSON.valueMap(entry) {
                await self.syncWriter?.enqueue(
                    entityType: .mealPlanEntry,
                    entityId: entry.id,
                    operation: .create,
                    patch: patch,
                    baseVersion: nil
                )
            }
            return true
        }
    }

    /// Flips a row's `done` flag OPTIMISTICALLY by stable id identity, then
    /// persists the single row. Returns whether a row was toggled; a persist
    /// failure rolls the flip back, and a row a peer removed is dropped locally.
    @discardableResult
    func toggleDone(_ target: MealPlanEntry) async -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == target.id }) else { return false }
        let prior = entries[index]
        let updatedEntry = prior.copyWith(done: !prior.done)
        entries[index] = updatedEntry // optimistic
        return await serializedPersist {
            do {
                guard try await self.repository.updateRow(self.householdID, updatedEntry) else {
                    self.entries.removeAll { $0.id == updatedEntry.id }
                    return false
                }
            } catch {
                if let i = self.entries.firstIndex(where: { $0.id == prior.id }) { self.entries[i] = prior }
                return false
            }
            if let patch = DomainJSON.valueMap(updatedEntry) {
                await self.syncWriter?.enqueue(
                    entityType: .mealPlanEntry,
                    entityId: updatedEntry.id,
                    operation: .update,
                    patch: patch,
                    baseVersion: prior.remoteVersion
                )
            }
            // #7: marking a recipe dish done == cooking it → record a cook tally
            // (best-effort; not for notes/leftovers, which weren't freshly cooked).
            if updatedEntry.done, !updatedEntry.recipeId.isEmpty, !updatedEntry.isLeftover {
                try? await self.cookHistoryRepository?.recordCook(recipeId: updatedEntry.recipeId)
            }
            return true
        }
    }

    /// Deletes a row OPTIMISTICALLY by stable id identity, then soft-deletes the
    /// single row in the background. Returns whether a row was removed; a persist
    /// failure re-inserts it.
    @discardableResult
    func remove(_ target: MealPlanEntry) async -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == target.id }) else { return false }
        let removed = entries[index]
        let snapshot = entries
        entries.remove(at: index) // optimistic
        return await serializedPersist {
            do {
                try await self.repository.delete(self.householdID, ids: [removed.id])
            } catch {
                self.entries = snapshot
                return false
            }
            if let patch = DomainJSON.valueMap(removed) {
                await self.syncWriter?.enqueue(
                    entityType: .mealPlanEntry,
                    entityId: removed.id,
                    operation: .delete,
                    patch: patch,
                    baseVersion: removed.remoteVersion
                )
            }
            return true
        }
    }

    /// Reschedules a planned dish to `newDate` OPTIMISTICALLY by stable id identity
    /// (the model normalizes to local midnight), keeping the SAME row so it
    /// reconciles as an in-place `.update` rather than a delete + re-add — sparing
    /// the user the delete-and-recreate dance to move a dish. A move to the same
    /// calendar day is a no-op that still succeeds (no write). Returns whether a row
    /// moved; a persist failure rolls the move back, and a row a peer removed is
    /// dropped locally. Mirrors `toggleDone`'s single-row contract.
    @discardableResult
    func moveDish(_ target: MealPlanEntry, to newDate: Date) async -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == target.id }) else { return false }
        let prior = entries[index]
        let normalized = MealPlanEntry.dateOnly(newDate)
        guard normalized != prior.date else { return true } // already on that day — no write
        let updatedEntry = prior.copyWith(date: normalized)
        entries[index] = updatedEntry // optimistic
        return await serializedPersist {
            do {
                guard try await self.repository.updateRow(self.householdID, updatedEntry) else {
                    self.entries.removeAll { $0.id == updatedEntry.id }
                    return false
                }
            } catch {
                if let i = self.entries.firstIndex(where: { $0.id == prior.id }) { self.entries[i] = prior }
                return false
            }
            if let patch = DomainJSON.valueMap(updatedEntry) {
                await self.syncWriter?.enqueue(
                    entityType: .mealPlanEntry,
                    entityId: updatedEntry.id,
                    operation: .update,
                    patch: patch,
                    baseVersion: prior.remoteVersion
                )
            }
            return true
        }
    }

    // MARK: Templates (#14 — reusable weekly plans, device-local)

    /// Saved templates, newest first.
    func templates() -> [MealPlanTemplate] { MealPlanTemplates.load() }

    /// Serializes the VISIBLE week's dishes into a named template (device-local).
    /// nil when the name is blank or the week has no recipe dishes. Replaces an
    /// existing same-name template.
    @discardableResult
    func saveCurrentWeekAsTemplate(name: String) -> MealPlanTemplate? {
        let trimmed = name.trimmed
        let items = MealPlanTemplates.items(from: entriesInVisibleWeek, weekStart: weekStart)
        guard !trimmed.isEmpty, !items.isEmpty else { return nil }
        let template = MealPlanTemplate(id: Self.newId(), name: trimmed, items: items)
        MealPlanTemplates.save(MealPlanTemplates.upserting(template, into: MealPlanTemplates.load()))
        return template
    }

    func removeTemplate(id: String) {
        MealPlanTemplates.save(MealPlanTemplates.load().filter { $0.id != id })
    }

    /// Applies a template to the VISIBLE week — adds each item at weekStart +
    /// dayOffset. Returns how many dishes were added (additive: it never clears the
    /// existing week). Mirrors `addDish`'s optimistic single-row contract per item.
    @discardableResult
    func applyTemplate(_ template: MealPlanTemplate) async -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var added = 0
        for item in template.items {
            guard let date = calendar.date(byAdding: .day, value: item.dayOffset, to: weekStart) else { continue }
            let ok = await addPlannedEntry(
                recipeId: item.recipeId,
                recipeName: item.recipeName,
                recipeImageUrl: item.recipeImageUrl,
                date: MealPlanEntry.dateOnly(date),
                servings: item.servings
            )
            if ok { added += 1 }
        }
        return added
    }

    // MARK: Static helpers

    /// The recipe a just-completed entry should offer cook-time deduction for —
    /// nil when the recipeId no longer resolves against the corpus (same lookup
    /// the 缺料 derivation uses) or the recipe has no ingredients to deduct.
    nonisolated static func deductionCandidate(
        for entry: MealPlanEntry,
        recipesById: [String: Recipe]
    ) -> Recipe? {
        // Leftovers were already cooked → no deduction; notes have no recipe.
        guard !entry.isLeftover, !entry.recipeId.isEmpty else { return nil }
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
