import Foundation
import SwiftData

/// Local store for the dietary-preferences (忌口) set-membership table — the
/// sibling of `FavoriteRecipeRepository`. Same contract: `loadAllFor` returns
/// every row in scope (tombstones included), `upsert` is the optimistic
/// single-row write, `saveEntries` the replace-all-in-scope.
@ModelActor
actor DietaryPreferenceRepository {
    func loadAllFor(_ householdID: String) throws -> [DietaryPreference] {
        let descriptor = FetchDescriptor<DietaryPreferenceRecord>(
            predicate: #Predicate { $0.householdID == householdID }
        )
        return try modelContext.fetch(descriptor).compactMap { row -> DietaryPreference? in
            guard let preference = try? row.preference(), !preference.id.isEmpty else { return nil }
            return preference
        }
    }

    func upsert(_ householdID: String, _ preference: DietaryPreference) throws {
        guard !preference.id.isEmpty else { return }
        let id = preference.id
        let existing = try modelContext.fetch(
            FetchDescriptor<DietaryPreferenceRecord>(predicate: #Predicate { $0.id == id })
        )
        if let row = existing.first {
            row.householdID = householdID
            row.apply(preference)
        } else {
            modelContext.insert(DietaryPreferenceRecord(householdID: householdID, preference: preference))
        }
        try modelContext.save()
    }

    func saveEntries(_ householdID: String, _ entries: [DietaryPreference]) throws {
        try modelContext.delete(
            model: DietaryPreferenceRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seen = Set<String>()
        for preference in entries {
            guard !preference.id.isEmpty, !seen.contains(preference.id) else { continue }
            seen.insert(preference.id)
            modelContext.insert(DietaryPreferenceRecord(householdID: householdID, preference: preference))
        }
        try modelContext.save()
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: DietaryPreferenceRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }
}
