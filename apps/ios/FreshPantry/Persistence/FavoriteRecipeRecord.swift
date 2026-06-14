import Foundation
import SwiftData

/// SwiftData row for the favorite-recipes set-membership table. `id` IS the
/// natural key (the deterministic household-scoped id), unique globally. The
/// whole domain object lives in `payloadJSON`; `recipeID`/`remoteVersion`/
/// `deletedAt` are lifted out as columns for predicate filtering. Mirrors
/// `FoodLogRecord`'s payload-blob shape.
@Model
final class FavoriteRecipeRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var recipeID: String = ""
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, favorite: FavoriteRecipe) {
        self.householdID = householdID
        apply(favorite)
    }

    func apply(_ favorite: FavoriteRecipe) {
        id = favorite.id
        recipeID = favorite.recipeID
        remoteVersion = favorite.remoteVersion
        deletedAt = favorite.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(favorite)) ?? payloadJSON
    }

    func favorite() throws -> FavoriteRecipe {
        try DomainJSON.decode(FavoriteRecipe.self, from: payloadJSON)
    }
}
