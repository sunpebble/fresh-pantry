import Foundation
import Testing
@testable import FreshPantry

/// The two SET-MEMBERSHIP sync models (收藏 / 忌口): deterministic household-scoped
/// id (stable, uuid-shaped, household + key sensitive) and a lossless Codable
/// payload round-trip.
struct FavoriteSyncModelsTests {
    // MARK: FavoriteRecipe

    @Test func favoriteIdIsStableAndUuidShaped() {
        let a = FavoriteRecipe.id(householdID: "home", recipeID: "r1")
        let b = FavoriteRecipe.id(householdID: "home", recipeID: "r1")
        #expect(a == b)
        #expect(ProposalApply.isUuid(a))
    }

    @Test func favoriteIdDiffersByHouseholdAndRecipe() {
        let base = FavoriteRecipe.id(householdID: "home", recipeID: "r1")
        #expect(FavoriteRecipe.id(householdID: "other", recipeID: "r1") != base)
        #expect(FavoriteRecipe.id(householdID: "home", recipeID: "r2") != base)
        // Local-only ("") scope is distinct from any real household.
        #expect(FavoriteRecipe.id(householdID: "", recipeID: "r1") != base)
    }

    @Test func favoriteCodableRoundTripPreservesFields() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let fav = FavoriteRecipe.make(householdID: "home", recipeID: "r1", remoteVersion: 3, clientUpdatedAt: t)
        let map = try #require(DomainJSON.valueMap(fav))
        let back = try #require(DomainJSON.fromValueMap(FavoriteRecipe.self, from: map))
        #expect(back == fav) // identity by id
        #expect(back.recipeID == "r1")
        #expect(back.remoteVersion == 3)
        #expect(back.clientUpdatedAt == t)
        #expect(back.deletedAt == nil)
    }

    // MARK: DietaryPreference

    @Test func dietaryIdIsStableUuidShapedAndKeySensitive() {
        let a = DietaryPreference.id(householdID: "home", keyword: "香菜")
        #expect(a == DietaryPreference.id(householdID: "home", keyword: "香菜"))
        #expect(ProposalApply.isUuid(a))
        #expect(DietaryPreference.id(householdID: "home", keyword: "花生") != a)
        #expect(DietaryPreference.id(householdID: "other", keyword: "香菜") != a)
    }

    @Test func dietaryCodableRoundTripPreservesFields() throws {
        let p = DietaryPreference.make(householdID: "home", keyword: "香菜", remoteVersion: 2)
        let map = try #require(DomainJSON.valueMap(p))
        let back = try #require(DomainJSON.fromValueMap(DietaryPreference.self, from: map))
        #expect(back == p)
        #expect(back.keyword == "香菜")
        #expect(back.remoteVersion == 2)
    }
}
