import Foundation
import Testing
@testable import FreshPantry

/// The favorite / dietary payload-blob codecs round-trip a domain object through
/// the Supabase row shape without field loss (mirrors the food-log codec).
struct FavoriteSyncCodecTests {
    @Test func favoriteRoundTripPreservesFields() throws {
        let fav = FavoriteRecipe.make(householdID: "home", recipeID: "r1")
        let domain = try #require(DomainJSON.valueMap(fav))
        let row = RemoteRowCodec.favoriteRecipeRowForUpsert(householdID: "home", favorite: domain)

        #expect(row["household_id"] == .string("home"))
        #expect(row["version"] == .int(1)) // remoteVersion 0 → first write version 1
        #expect(row["id"] == .string(fav.id)) // uuid-shaped id is written as a column
        guard case .object = row["payload"] else { Issue.record("payload not object"); return }

        var back = row
        back["id"] = .string(fav.id) // server echoes the uuid PK
        let decoded = try #require(
            DomainJSON.fromValueMap(FavoriteRecipe.self, from: RemoteRowCodec.favoriteRecipeRowFromJson(back))
        )
        #expect(decoded.id == fav.id)
        #expect(decoded.recipeID == "r1")
    }

    @Test func dietaryRoundTripPreservesFields() throws {
        let pref = DietaryPreference.make(householdID: "home", keyword: "香菜")
        let domain = try #require(DomainJSON.valueMap(pref))
        let row = RemoteRowCodec.dietaryPreferenceRowForUpsert(householdID: "home", preference: domain)

        #expect(row["household_id"] == .string("home"))
        #expect(row["id"] == .string(pref.id))
        var back = row
        back["id"] = .string(pref.id)
        let decoded = try #require(
            DomainJSON.fromValueMap(DietaryPreference.self, from: RemoteRowCodec.dietaryPreferenceRowFromJson(back))
        )
        #expect(decoded.id == pref.id)
        #expect(decoded.keyword == "香菜")
    }
}
