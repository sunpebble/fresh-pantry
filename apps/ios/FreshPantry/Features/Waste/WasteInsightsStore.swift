import Foundation

/// Selectable time window for the 减废统计 screen. `last90Days` is the cap and
/// MUST equal `WasteInsightsStore.recentWindowDays` (90) so a query never reaches
/// past the bounded in-memory slice the store hydrates (parity invariant #8).
enum WasteStatsWindow: String, CaseIterable, Sendable {
    case thisMonth
    case last30Days
    case last90Days

    var label: String {
        switch self {
        case .thisMonth: return "本月"
        case .last30Days: return "近 30 天"
        case .last90Days: return "近 90 天"
        }
    }

    /// The inclusive lower bound for this window relative to `now`:
    /// thisMonth = the 1st at local midnight; last30/last90Days = now − N days.
    func since(_ now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        switch self {
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: comps) ?? now
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        }
    }
}

/// Aggregated food-departure stats for one window. All values are item COUNTS,
/// never quantities (quantities are free-text and intentionally not summed).
/// `useUpRate` is the headline metric; `/0` is guarded to 0 (no departures yet).
struct FoodLogStats: Equatable, Sendable {
    var consumed: Int
    var wasted: Int
    /// Consumed AND already past fresh — "抢救临期" credit.
    var rescued: Int

    static let empty = FoodLogStats(consumed: 0, wasted: 0, rescued: 0)

    /// consumed + wasted (rescued is a subset of consumed, not added in).
    var total: Int { consumed + wasted }

    /// consumed / (consumed + wasted), 0 when nothing has departed (guarded /0).
    var useUpRate: Double { total == 0 ? 0 : Double(consumed) / Double(total) }

    /// 0...100 integer percent for the headline (e.g. 85 → "85% 用掉率").
    var useUpPercent: Int { Int((useUpRate * 100).rounded()) }

    var isEmpty: Bool { total == 0 }
}

/// One category's consumed-vs-wasted split, for the breakdown chart/list.
struct WasteCategoryBreakdown: Equatable, Sendable, Identifiable {
    let category: String
    let consumed: Int
    let wasted: Int

    var id: String { category }
    var total: Int { consumed + wasted }
}

/// Feature store for the 减废统计 (waste-insights) slice — the same
/// `@Observable @MainActor` template the other features established.
///
/// Loads a bounded recent window of food-departure entries via
/// `FoodLogRepository.loadRecentFor` (capped at `recentWindowDays`), then derives
/// windowed `FoodLogStats` + a per-category consumed/wasted breakdown for the
/// selected `WasteStatsWindow`. All aggregation is pure and lives here so it can
/// be exercised without SwiftData; the view never touches the repo directly.
@Observable
@MainActor
final class WasteInsightsStore {
    /// Bounded hydration window (days). The widest selectable window
    /// (`last90Days`) must not exceed this, so a query never reaches past the
    /// loaded slice. Mirrors Flutter `foodLogRecentWindow = Duration(days: 90)`.
    static let recentWindowDays = 90

    private let repository: FoodLogRepository
    private let syncWriter: SyncWriter?
    private let householdID: String

    /// All entries inside the bounded hydration window (repo order). The window
    /// selector filters this in-memory slice; it is never re-queried per window.
    private(set) var entries: [FoodLogEntry] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Set to true when `correctOutcome` fails (repo throw or entry-not-found).
    /// The view observes this to surface a toast; reset to false after the toast
    /// is consumed so subsequent failures can re-trigger.
    var correctOutcomeError = false

    /// The active time window. Defaults to 本月 (matches the blueprint default).
    var window: WasteStatsWindow = .thisMonth
    /// Active category drill-down. nil = 全部分类. Matched against the canonical
    /// `FoodCategories.dropdownValue` bucket (so a legacy-alias entry still matches),
    /// narrowing EVERY windowed aggregate at once.
    var categoryFilter: String?

    init(repository: FoodLogRepository, householdID: String, syncWriter: SyncWriter? = nil) {
        self.repository = repository
        self.syncWriter = syncWriter
        self.householdID = householdID
    }

    // MARK: Loading

    /// Hydrates the bounded recent window off the repo actor. A load failure
    /// surfaces an empty slice (the screen then shows its empty state) rather
    /// than crashing this read-only feature.
    func load(now: Date = Date()) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.recentWindowDays, to: now) ?? now
        let sinceMs = Int(cutoff.timeIntervalSince1970 * 1000)
        do {
            entries = try await repository.loadRecentFor(householdID, sinceMs: sinceMs)
        } catch {
            entries = []
        }
    }

    // MARK: Derived view data

    /// Entries inside the selected time window, BEFORE the category drill-down —
    /// the source for the filter chips (which must list every in-window bucket).
    private func windowSlice(now: Date) -> [FoodLogEntry] {
        let since = window.since(now)
        return entries.filter { $0.loggedAt >= since }
    }

    /// Entries at/after the window's lower bound, narrowed to `categoryFilter` when
    /// set (matched on the canonical bucket). Every windowed aggregate derives from
    /// this, so selecting a category drills the whole screen into it at once.
    func windowedEntries(now: Date = Date()) -> [FoodLogEntry] {
        let slice = windowSlice(now: now)
        guard let categoryFilter else { return slice }
        return slice.filter { FoodCategories.dropdownValue($0.category) == categoryFilter }
    }

    /// Distinct categories present in the window (IGNORING the active drill-down) in
    /// canonical order — drives the filter chips. Empty when the window has no
    /// departures, so the view hides the row (no dead control). Reuses the
    /// breakdown's bucketing + sort for a single source of category shaping.
    func categoryOptions(now: Date = Date()) -> [String] {
        Self.computeCategoryBreakdown(windowSlice(now: now)).map(\.category)
    }

    /// Windowed aggregate stats (consumed / wasted / rescued / use-up rate).
    func stats(now: Date = Date()) -> FoodLogStats {
        Self.computeStats(windowedEntries(now: now))
    }

    /// Per-category consumed/wasted breakdown for the selected window, ordered by
    /// `FoodCategories.values` (canonical sort), dropping categories with no
    /// departures. Categories are normalized so legacy aliases collapse correctly.
    func categoryBreakdown(now: Date = Date()) -> [WasteCategoryBreakdown] {
        Self.computeCategoryBreakdown(windowedEntries(now: now))
    }

    /// Categories ranked by WASTED count (desc) for the window — the "最常浪费"
    /// list. Only categories with ≥1 wasted departure appear.
    func mostWasted(now: Date = Date()) -> [WasteCategoryCount] {
        Self.computeMostWasted(windowedEntries(now: now))
    }

    /// All three windowed aggregates for one render pass. A single `now` and a
    /// single window filter back every aggregate, so a body evaluation doesn't
    /// re-filter `entries` per derived value.
    struct Summary {
        let stats: FoodLogStats
        let breakdown: [WasteCategoryBreakdown]
        let mostWasted: [WasteCategoryCount]
    }

    func summary(now: Date = Date()) -> Summary {
        let windowed = windowedEntries(now: now)
        return Summary(
            stats: Self.computeStats(windowed),
            breakdown: Self.computeCategoryBreakdown(windowed),
            mostWasted: Self.computeMostWasted(windowed)
        )
    }

    /// Windowed entries newest-first for the history list.
    func historyEntries(now: Date = Date()) -> [FoodLogEntry] {
        windowedEntries(now: now).sorted { $0.loggedAt > $1.loggedAt }
    }

    /// Correct a mis-logged outcome (吃完 ↔ 扔了) OPTIMISTICALLY — the history row
    /// + the windowed stats re-derive the instant the user taps, before the repo
    /// write. Returns false when the entry is missing (also sets
    /// `correctOutcomeError = true` so the view toasts) or when it already carries
    /// the requested outcome (a benign no-op — no error). A persist failure rolls
    /// the flip back and sets the error flag.
    @discardableResult
    func correctOutcome(entryId: String, to outcome: FoodLogOutcome) async -> Bool {
        let index = entries.firstIndex(where: { $0.id == entryId })
        let prior = index.map { entries[$0] }
        if let index, let prior {
            entries[index] = prior.copyWith(outcome: outcome) // optimistic flip
        }
        do {
            guard let updated = try await repository.updateOutcome(householdID, entryId, outcome) else {
                // The repo found no row to update — roll back the optimistic flip.
                if let index, let prior { entries[index] = prior }
                correctOutcomeError = true
                return false
            }
            // Stamp the persisted row (its bumped remoteVersion / clientUpdatedAt)
            // over the optimistic copy.
            if let index { entries[index] = updated }
            if let patch = DomainJSON.valueMap(updated) {
                await syncWriter?.enqueue(
                    entityType: .foodLogEntry,
                    entityId: updated.id,
                    operation: .update,
                    patch: patch,
                    baseVersion: updated.remoteVersion
                )
            }
            return true
        } catch {
            if let index, let prior { entries[index] = prior } // rollback
            correctOutcomeError = true
            return false
        }
    }

    // MARK: Pure aggregation (testable without SwiftData)

    /// Tallies consumed / wasted / rescued over `entries`. `rescued` counts a
    /// consumed entry whose batch was already expiring (`wasExpiring`).
    static func computeStats(_ entries: [FoodLogEntry]) -> FoodLogStats {
        var consumed = 0
        var wasted = 0
        var rescued = 0
        for entry in entries {
            if entry.isConsumed {
                consumed += 1
                if entry.wasExpiring { rescued += 1 }
            } else {
                wasted += 1
            }
        }
        return FoodLogStats(consumed: consumed, wasted: wasted, rescued: rescued)
    }

    /// Per-category consumed/wasted counts, normalized + sorted by
    /// `FoodCategories.values` position (unknown last), dropping empty categories.
    static func computeCategoryBreakdown(_ entries: [FoodLogEntry]) -> [WasteCategoryBreakdown] {
        var consumedBy: [String: Int] = [:]
        var wastedBy: [String: Int] = [:]
        for entry in entries {
            let category = FoodCategories.dropdownValue(entry.category)
            if entry.isConsumed {
                consumedBy[category, default: 0] += 1
            } else {
                wastedBy[category, default: 0] += 1
            }
        }
        let categories = Set(consumedBy.keys).union(wastedBy.keys)
        return categories
            .map { WasteCategoryBreakdown(category: $0, consumed: consumedBy[$0] ?? 0, wasted: wastedBy[$0] ?? 0) }
            .sorted { lhs, rhs in
                let lRank = FoodCategories.values.firstIndex(of: lhs.category) ?? FoodCategories.values.count
                let rRank = FoodCategories.values.firstIndex(of: rhs.category) ?? FoodCategories.values.count
                if lRank != rRank { return lRank < rRank }
                return lhs.category < rhs.category
            }
    }

    /// Wasted-only counts per (normalized) category, ranked by count desc, ties
    /// by category name. Zero-waste categories never appear (only wasted entries
    /// are tallied). Ports the Flutter "最常浪费" ranking.
    static func computeMostWasted(_ entries: [FoodLogEntry]) -> [WasteCategoryCount] {
        var wastedBy: [String: Int] = [:]
        for entry in entries where !entry.isConsumed {
            wastedBy[FoodCategories.dropdownValue(entry.category), default: 0] += 1
        }
        return wastedBy
            .map { WasteCategoryCount(category: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category < $1.category }
    }
}

/// One row of the 最常浪费 ranking (a category + its wasted count).
struct WasteCategoryCount: Equatable, Sendable, Identifiable {
    let category: String
    let count: Int
    var id: String { category }
}
