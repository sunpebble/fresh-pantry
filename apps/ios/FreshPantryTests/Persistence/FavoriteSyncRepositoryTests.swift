import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The two set-membership repositories: scoped load (tombstones included),
/// upsert-by-id, replace-all-in-scope, and household isolation.
struct FavoriteSyncRepositoryTests {
    private func favRepo() throws -> FavoriteRecipeRepository {
        FavoriteRecipeRepository(modelContainer: try ModelContainerFactory.makeInMemory())
    }

    private func dietRepo() throws -> DietaryPreferenceRepository {
        DietaryPreferenceRepository(modelContainer: try ModelContainerFactory.makeInMemory())
    }

    // MARK: Favorites

    @Test func favoriteUpsertReplacesByIdAndLoadsTombstones() async throws {
        let repo = try favRepo()
        let active = FavoriteRecipe.make(householdID: "home", recipeID: "r1")
        try await repo.upsert("home", active)
        // Soft-delete the SAME id (un-favorite) → upsert replaces, not appends.
        try await repo.upsert("home", active.copyWith(remoteVersion: 1, deletedAt: Date(timeIntervalSince1970: 1)))

        let all = try await repo.loadAllFor("home")
        #expect(all.count == 1) // one row per (household, recipe)
        #expect(all.first?.recipeID == "r1")
        #expect(all.first?.deletedAt != nil) // tombstone is returned, not filtered
    }

    @Test func favoriteSaveEntriesReplacesScopeAndIsHouseholdIsolated() async throws {
        let repo = try favRepo()
        try await repo.upsert("home", FavoriteRecipe.make(householdID: "home", recipeID: "stale"))
        try await repo.upsert("other", FavoriteRecipe.make(householdID: "other", recipeID: "keep"))

        try await repo.saveEntries("home", [FavoriteRecipe.make(householdID: "home", recipeID: "fresh")])

        let home = try await repo.loadAllFor("home").map(\.recipeID).sorted()
        let other = try await repo.loadAllFor("other").map(\.recipeID)
        #expect(home == ["fresh"]) // "stale" replaced
        #expect(other == ["keep"]) // other household untouched
    }

    @Test func favoriteUpsertIgnoresBlankId() async throws {
        let repo = try favRepo()
        try await repo.upsert("home", FavoriteRecipe(id: "", recipeID: "r1"))
        #expect(try await repo.loadAllFor("home").isEmpty)
    }

    // MARK: Dietary

    @Test func dietaryUpsertAndSaveEntriesRoundTrip() async throws {
        let repo = try dietRepo()
        try await repo.upsert("home", DietaryPreference.make(householdID: "home", keyword: "香菜"))
        #expect(try await repo.loadAllFor("home").map(\.keyword) == ["香菜"])

        try await repo.saveEntries("home", [
            DietaryPreference.make(householdID: "home", keyword: "花生"),
            DietaryPreference.make(householdID: "home", keyword: "海鲜"),
        ])
        #expect(try await repo.loadAllFor("home").map(\.keyword).sorted() == ["海鲜", "花生"])
    }
}
