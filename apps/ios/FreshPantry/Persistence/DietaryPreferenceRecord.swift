import Foundation
import SwiftData

/// SwiftData row for the dietary-preferences (忌口) set-membership table — the
/// sibling of `FavoriteRecipeRecord`. `id` is the deterministic household-scoped
/// key; the normalized `keyword`/`remoteVersion`/`deletedAt` are lifted out as
/// columns, the whole domain object lives in `payloadJSON`.
@Model
final class DietaryPreferenceRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var keyword: String = ""
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, preference: DietaryPreference) {
        self.householdID = householdID
        apply(preference)
    }

    func apply(_ preference: DietaryPreference) {
        id = preference.id
        keyword = preference.keyword
        remoteVersion = preference.remoteVersion
        deletedAt = preference.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(preference)) ?? payloadJSON
    }

    func preference() throws -> DietaryPreference {
        try DomainJSON.decode(DietaryPreference.self, from: payloadJSON)
    }
}
