import Foundation
import SwiftData

/// Device-local store for per-recipe cook tallies (see `CookHistoryRecord` for the
/// no-sync scope decision). `recordCook` is called when the user actually cooks a
/// dish (做菜扣减 success / 膳食计划标记完成); `loadAll` feeds the Recipes sort +
/// 做过 N 次 display.
///
/// FAILURE POLICY: a convenience log, never a data path — both methods can throw
/// and the caller degrades silently (a missed tally must never block cooking).
@ModelActor
actor CookHistoryRepository {
    /// Increments the cook count for `recipeId` (insert at 1 if new) and stamps
    /// `lastCookedAt`. Blank id is a no-op.
    func recordCook(recipeId: String, now: Date = Date()) throws {
        let key = recipeId.trimmed
        guard !key.isEmpty else { return }
        let descriptor = FetchDescriptor<CookHistoryRecord>(
            predicate: #Predicate { $0.recipeId == key }
        )
        if let row = try modelContext.fetch(descriptor).first {
            row.cookCount += 1
            row.lastCookedAt = now
        } else {
            modelContext.insert(CookHistoryRecord(recipeId: key, cookCount: 1, lastCookedAt: now))
        }
        try modelContext.save()
    }

    /// Snapshot of all cook tallies, keyed by recipe id for O(1) lookup.
    func loadAll() throws -> [String: CookHistory] {
        let rows = try modelContext.fetch(FetchDescriptor<CookHistoryRecord>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.recipeId, $0.value()) })
    }
}
