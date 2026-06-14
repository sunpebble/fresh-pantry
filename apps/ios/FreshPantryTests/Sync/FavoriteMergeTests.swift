import Foundation
import Testing
@testable import FreshPantry

/// Set-membership merge: remote rows win, local-only (never-synced, non-deleted)
/// rows survive; tombstones / synced rows don't re-appear as local-only.
struct FavoriteMergeTests {
    @Test func favoriteMergeIsUnionOfRemoteAndLocalOnly() {
        let remoteRow = FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 3)
        let localOnly = FavoriteRecipe.make(householdID: "home", recipeID: "r2", remoteVersion: 0)
        let alreadyRemote = FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 3)
        let scope = LocalUploadScope(householdID: "home", pendingOps: [])
        let merged = HouseholdMergePolicy.mergeFavoriteRecipe(
            remote: [remoteRow],
            local: [alreadyRemote, localOnly],
            scope: scope
        )
        #expect(merged.map(\.recipeID) == ["r1", "r2"]) // remote first, local-only appended
    }

    @Test func favoriteLocalOnlyGuardRejectsSyncedAndDeleted() {
        #expect(HouseholdMergePolicy.isLocalOnlyFavoriteRecipe(
            FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 0)
        ))
        #expect(!HouseholdMergePolicy.isLocalOnlyFavoriteRecipe(
            FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 5)
        ))
        #expect(!HouseholdMergePolicy.isLocalOnlyFavoriteRecipe(
            FavoriteRecipe.make(householdID: "home", recipeID: "r1", deletedAt: Date(timeIntervalSince1970: 1))
        ))
    }

    @Test func dietaryPatchTombstoneDropsSyncedRow() {
        let local = [DietaryPreference.make(householdID: "home", keyword: "香菜", remoteVersion: 4)]
        let tombstone = DietaryPreference.make(
            householdID: "home", keyword: "香菜", remoteVersion: 5, deletedAt: Date(timeIntervalSince1970: 9)
        )
        let merged = HouseholdMergePolicy.patchDietaryPreference(remoteDelta: [tombstone], local: local)
        #expect(merged.isEmpty) // the soft-deleted delta removes the local row
    }
}
