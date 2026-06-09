import Foundation
import SwiftData

/// Weekly meal-plan entry CRUD. Filters rows missing id or recipeId; a dirty
/// date throws on decode and the row is skipped. Mirrors
/// `lib/storage/meal_plan_repo.dart`.
@ModelActor
actor MealPlanRepository {
    func loadAllFor(_ householdID: String) throws -> [MealPlanEntry] {
        // Sorted by id so fetch order is deterministic across reloads — SwiftData
        // fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<MealPlanRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row -> MealPlanEntry? in
            // A malformed date throws inside decode -> skip the row.
            guard let entry = try? row.entry() else { return nil }
            guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { return nil }
            return entry
        }
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: MealPlanRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    func saveEntries(_ householdID: String, _ entries: [MealPlanEntry]) throws {
        try modelContext.delete(
            model: MealPlanRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for entry in entries {
            guard !entry.id.isEmpty, !entry.recipeId.isEmpty else { continue }
            if seenIds.contains(entry.id) { continue }
            seenIds.insert(entry.id)
            modelContext.insert(MealPlanRecord(householdID: householdID, entry: entry))
        }
        try modelContext.save()
    }
}
