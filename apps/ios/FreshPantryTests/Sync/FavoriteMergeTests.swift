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
        let merged = HouseholdMergePolicy.merge(
            remote: [remoteRow],
            local: [alreadyRemote, localOnly],
            scope: scope,
            entityType: .favoriteRecipe
        )
        #expect(merged.map(\.recipeID) == ["r1", "r2"]) // remote first, local-only appended
    }

    @Test func favoriteLocalOnlyGuardRejectsSyncedAndDeleted() {
        #expect(FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 0).isLocalOnly)
        #expect(!FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 5).isLocalOnly)
        #expect(!FavoriteRecipe.make(householdID: "home", recipeID: "r1", deletedAt: Date(timeIntervalSince1970: 1)).isLocalOnly)
    }

    @Test func dietaryPatchTombstoneDropsSyncedRow() {
        let local = [DietaryPreference.make(householdID: "home", keyword: "香菜", remoteVersion: 4)]
        let tombstone = DietaryPreference.make(
            householdID: "home", keyword: "香菜", remoteVersion: 5, deletedAt: Date(timeIntervalSince1970: 9)
        )
        let merged = HouseholdMergePolicy.patch(remoteDelta: [tombstone], local: local)
        #expect(merged.isEmpty) // the soft-deleted delta removes the local row
    }
}
