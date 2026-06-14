import Foundation
import SwiftData

/// Local store for the favorite-recipes set-membership table. `loadAllFor`
/// returns EVERY row in scope (tombstones included) so the store can derive the
/// active set (`deletedAt == nil`) and the sync layer can inspect
/// `remoteVersion`/`deletedAt`. `upsert` is the optimistic single-row write a
/// toggle uses; `saveEntries` is the replace-all-in-scope a sync apply uses.
@ModelActor
actor FavoriteRecipeRepository {
    func loadAllFor(_ householdID: String) throws -> [FavoriteRecipe] {
        let descriptor = FetchDescriptor<FavoriteRecipeRecord>(
            predicate: #Predicate { $0.householdID == householdID }
        )
        return try modelContext.fetch(descriptor).compactMap { row -> FavoriteRecipe? in
            guard let favorite = try? row.favorite(), !favorite.id.isEmpty else { return nil }
            return favorite
        }
    }

    /// Upsert by id. NO-OP on a blank id (never write an unaddressable row).
    func upsert(_ householdID: String, _ favorite: FavoriteRecipe) throws {
        guard !favorite.id.isEmpty else { return }
        let id = favorite.id
        let existing = try modelContext.fetch(
            FetchDescriptor<FavoriteRecipeRecord>(predicate: #Predicate { $0.id == id })
        )
        if let row = existing.first {
            row.householdID = householdID
            row.apply(favorite)
        } else {
            modelContext.insert(FavoriteRecipeRecord(householdID: householdID, favorite: favorite))
        }
        try modelContext.save()
    }

    /// Sync apply / adoption: replace-all-in-scope of non-blank, de-duped rows.
    func saveEntries(_ householdID: String, _ entries: [FavoriteRecipe]) throws {
        try modelContext.delete(
            model: FavoriteRecipeRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seen = Set<String>()
        for favorite in entries {
            guard !favorite.id.isEmpty, !seen.contains(favorite.id) else { continue }
            seen.insert(favorite.id)
            modelContext.insert(FavoriteRecipeRecord(householdID: householdID, favorite: favorite))
        }
        try modelContext.save()
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: FavoriteRecipeRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }
}
