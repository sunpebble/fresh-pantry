import Foundation
import SwiftData

/// Device-local "I cooked this" tally for a recipe (#7) — drives 「最常做 / 好久
/// 没做」 sorting and a 做过 N 次 badge, turning the static catalog into a
/// personal cooking log.
///
/// SCOPE — DELIBERATELY NOT SYNCED (like `BarcodeMemoryRecord`): this is one
/// person's cooking behavior on THIS device; merging it across a household would
/// conflate who actually cooked what. Keep it out of `RemoteRowCodec` / the sync
/// schema.
@Model
final class CookHistoryRecord {
    /// Recipe id — the natural unique key.
    @Attribute(.unique) var recipeId: String = ""
    /// How many times the user has cooked this recipe.
    var cookCount: Int = 0
    /// When it was most recently cooked (drives 「好久没做」).
    var lastCookedAt: Date = Date.distantPast

    init(recipeId: String, cookCount: Int, lastCookedAt: Date) {
        self.recipeId = recipeId
        self.cookCount = cookCount
        self.lastCookedAt = lastCookedAt
    }

    func value() -> CookHistory {
        CookHistory(recipeId: recipeId, cookCount: cookCount, lastCookedAt: lastCookedAt)
    }
}

/// Sendable snapshot returned across the `CookHistoryRepository` actor boundary.
struct CookHistory: Equatable, Sendable {
    let recipeId: String
    let cookCount: Int
    let lastCookedAt: Date
}
