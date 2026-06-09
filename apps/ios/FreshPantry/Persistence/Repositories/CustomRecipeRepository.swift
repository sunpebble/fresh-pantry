import Foundation
import SwiftData

/// User-created recipe CRUD. Both load and save enforce the non-empty id+name
/// guard. Mirrors `lib/storage/custom_recipe_repo.dart`.
@ModelActor
actor CustomRecipeRepository {
    func loadAllFor(_ householdID: String) throws -> [Recipe] {
        // Sorted by id so fetch order is deterministic across reloads — SwiftData
        // fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<CustomRecipeRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row -> Recipe? in
            guard let recipe = try? row.recipe() else { return nil }
            guard !recipe.id.isEmpty, !recipe.name.isEmpty else { return nil }
            return recipe
        }
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: CustomRecipeRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    /// Replace the whole household scope, inserting only non-empty id+name recipes.
    func saveRecipes(_ householdID: String, _ recipes: [Recipe]) throws {
        try modelContext.delete(
            model: CustomRecipeRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for recipe in recipes {
            guard !recipe.id.isEmpty, !recipe.name.isEmpty else { continue }
            if seenIds.contains(recipe.id) { continue }
            seenIds.insert(recipe.id)
            modelContext.insert(CustomRecipeRecord(householdID: householdID, recipe: recipe))
        }
        try modelContext.save()
    }
}
