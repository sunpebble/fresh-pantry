import Foundation

/// One household's favorite mark for a recipe — a SET-MEMBERSHIP sync entity.
/// Identity (`Hashable`/`Equatable`) is by `id` ONLY, where `id` is the
/// deterministic, household-scoped key for `recipeID` (see `SyncIdentity`), so
/// the same favorite resolves to ONE row on every device. Un-favoriting is a
/// soft delete (`deletedAt` set), so the membership state converges last-write-wins
/// rather than leaving an orphan row.
struct FavoriteRecipe: Hashable, Sendable, Codable {
    var id: String
    /// The catalog / custom recipe id the UI toggles (the bare key the favorites
    /// set is derived from). Lives in the payload blob, distinct from the synced
    /// `id` column.
    var recipeID: String
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    var syncMetadata: SyncMetadata {
        SyncMetadata(remoteVersion: remoteVersion, clientUpdatedAt: clientUpdatedAt, deletedAt: deletedAt)
    }

    init(
        id: String,
        recipeID: String,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.recipeID = recipeID
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    /// The deterministic, household-scoped id for `(household, recipe)`.
    static func id(householdID: String, recipeID: String) -> String {
        SyncIdentity.deterministicUUID(namespace: "fav", household: householdID, key: recipeID)
    }

    /// Builds a favorite with its deterministic id already resolved.
    static func make(
        householdID: String,
        recipeID: String,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> FavoriteRecipe {
        FavoriteRecipe(
            id: id(householdID: householdID, recipeID: recipeID),
            recipeID: recipeID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            deletedAt: deletedAt
        )
    }

    static func == (lhs: FavoriteRecipe, rhs: FavoriteRecipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, recipeID, remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(recipeID, forKey: .recipeID)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            recipeID: c.decodeLenientIfPresent(String.self, forKey: .recipeID) ?? "",
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        recipeID: String? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> FavoriteRecipe {
        FavoriteRecipe(
            id: id ?? self.id,
            recipeID: recipeID ?? self.recipeID,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}
