import Foundation

/// One household's avoided-ingredient keyword (忌口) — a SET-MEMBERSHIP sync
/// entity, the 忌口 sibling of `FavoriteRecipe`. Identity is by `id` ONLY, where
/// `id` is the deterministic, household-scoped key for the NORMALIZED `keyword`
/// (trim + lowercase, owned by `DietaryPreferencesStore.normalize`), so the same
/// keyword resolves to ONE row across devices. Removing a keyword is a soft delete.
struct DietaryPreference: Hashable, Sendable, Codable {
    var id: String
    /// The normalized avoided keyword (trim + lowercase). Lives in the payload blob.
    var keyword: String
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    var syncMetadata: SyncMetadata {
        SyncMetadata(remoteVersion: remoteVersion, clientUpdatedAt: clientUpdatedAt, deletedAt: deletedAt)
    }

    init(
        id: String,
        keyword: String,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.keyword = keyword
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    /// The deterministic, household-scoped id for `(household, keyword)`. The
    /// keyword is expected pre-normalized by the store; the id is whitespace-/
    /// case-sensitive to whatever is passed, matching the store's canonical form.
    static func id(householdID: String, keyword: String) -> String {
        SyncIdentity.deterministicUUID(namespace: "diet", household: householdID, key: keyword)
    }

    static func make(
        householdID: String,
        keyword: String,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> DietaryPreference {
        DietaryPreference(
            id: id(householdID: householdID, keyword: keyword),
            keyword: keyword,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            deletedAt: deletedAt
        )
    }

    static func == (lhs: DietaryPreference, rhs: DietaryPreference) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, keyword, remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(keyword, forKey: .keyword)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            keyword: c.decodeLenientIfPresent(String.self, forKey: .keyword) ?? "",
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        keyword: String? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> DietaryPreference {
        DietaryPreference(
            id: id ?? self.id,
            keyword: keyword ?? self.keyword,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}
