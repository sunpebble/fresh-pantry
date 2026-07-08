import Foundation
import OSLog
import Supabase

/// Errors surfaced by the remote repository, mirroring the Dart `StateError` /
/// `ArgumentError` throws so failures stay visible rather than silently no-oping.
///
/// `notSignedIn` stands in for the Dart `StateError('Cannot … without a
/// signed-in user.')` guards; `invalidArgument` for the `ArgumentError.value`
/// shape (invalid uuid / token / empty name); `previewUnavailable` for the
/// `StateError('Invite preview is not available.')` empty-result case.
enum RemotePantryError: Error, Equatable {
    case notSignedIn(action: String)
    case invalidArgument(name: String, reason: String)
    case previewUnavailable
}

/// All Supabase table CRUD, the household-management RPCs, create-household /
/// create-invite, and the four realtime streams. Ported from
/// `lib/sync/remote_pantry_repository.dart`.
///
/// This is the READ + household-management half of the sync engine; the
/// versioned write half lives in `SupabaseSyncGateway` (the `RemoteSyncGateway`
/// conformer). The wire contract is parity-critical: table names, RPC names and
/// their EXACT snake_case parameter names, the column↔field encoding (delegated
/// to `RemoteRowCodec`), soft-delete filtering, and the id-minting rules must
/// match the Flutter client byte-for-byte so both talk to the same backend.
///
/// `actor` isolation is the concurrency model: the repository owns the
/// `SupabaseClient` and serializes access to it. Realtime watches are `AsyncStream`s
/// whose producer re-enters the actor on each change to re-fetch the full filtered
/// snapshot (parity with Flutter's `.stream`, which yields the whole set per event).
actor RemotePantryRepository {
    private let client: SupabaseClient
    private let apiBaseURL: String

    /// Realtime-channel diagnostics. Transient subscribe/channel errors are logged
    /// here and swallowed (invariant #9: reporting them as fatal previously caused
    /// production crashes), never propagated.
    private let log = Logger(subsystem: "com.sunpebble.freshpantry", category: "RemotePantryRepository")

    init(
        client: SupabaseClient,
        apiBaseURL: String = "https://api.freshpantry.sunpebblelabs.com"
    ) {
        self.client = client
        self.apiBaseURL = apiBaseURL
    }

    // MARK: - Table names

    private enum Table {
        static let households = "households"
        static let householdMembers = "household_members"
        static let householdInvites = "household_invites"
        static let inventory = "inventory_items"
        static let shopping = "shopping_items"
        static let customRecipes = "custom_recipes"
        static let mealPlanEntries = "meal_plan_entries"
        static let foodLogEntries = "food_log_entries"
        static let favoriteRecipes = "favorite_recipes"
        static let dietaryPreferences = "dietary_preferences"
    }

    // MARK: - Content loads (soft-delete filtered)

    /// `from('inventory_items').select().eq('household_id',id).is('deleted_at',null)`
    /// → domain maps. `is("deleted_at", value: nil)` emits `deleted_at=is.null`,
    /// matching the Dart `isFilter('deleted_at', null)` — soft-deleted rows are
    /// excluded at the source.
    func loadInventory(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.inventory, hid: hid, since: since, decode: RemoteRowCodec.inventoryRowFromJson)
    }

    func loadShopping(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.shopping, hid: hid, since: since, decode: RemoteRowCodec.shoppingRowFromJson)
    }

    func loadCustomRecipes(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.customRecipes, hid: hid, since: since, decode: RemoteRowCodec.customRecipeRowFromJson)
    }

    func loadMealPlanEntries(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.mealPlanEntries, hid: hid, since: since, decode: RemoteRowCodec.mealPlanEntryRowFromJson)
    }

    func loadFoodLogEntries(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.foodLogEntries, hid: hid, since: since, decode: RemoteRowCodec.foodLogEntryRowFromJson)
    }

    func loadFavoriteRecipes(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.favoriteRecipes, hid: hid, since: since, decode: RemoteRowCodec.favoriteRecipeRowFromJson)
    }

    func loadDietaryPreferences(_ hid: String, since: Date? = nil) async throws -> [[String: JSONValue]] {
        try await loadRows(from: Table.dietaryPreferences, hid: hid, since: since, decode: RemoteRowCodec.dietaryPreferenceRowFromJson)
    }

    /// Shared load path: fetch household rows as `[String: AnyJSON]`, run each
    /// through `decodeRow`. A nil `since` is a full pull (non-deleted rows only);
    /// a non-nil `since` is an incremental pull (`updated_at >= since - overlap`,
    /// tombstones included).
    private func loadRows(
        from table: String,
        hid: String,
        since: Date? = nil,
        decode: ([String: JSONValue]) -> [String: JSONValue]
    ) async throws -> [[String: JSONValue]] {
        var query = client
            .from(table)
            .select()
            .eq("household_id", value: hid)
        if let since {
            // Overlap window against the commit-order race: touch_updated_at
            // stamps now() = transaction START time, so a write committing
            // after our select can carry an updated_at older than the cursor
            // we just advanced — a bare `gte` would then skip it forever.
            // Re-delivered rows are idempotent through HouseholdMergePolicy.
            // ponytail: fixed 60s window; if commit latencies ever exceed it,
            // clamp the cursor to a server-reported pull-start time instead.
            let overlapped = since.addingTimeInterval(-Self.deltaOverlap)
            query = query.gte("updated_at", value: JSONDate.iso8601(overlapped))
        } else {
            query = query.is("deleted_at", value: nil)
        }
        let rows: [[String: AnyJSON]] = try await query.execute().value
        return rows.map { Self.decodeRow($0, decode: decode) }
    }

    /// How far a delta pull reaches back before the cursor (see `loadRows`).
    private static let deltaOverlap: TimeInterval = 60

    /// One pulled row: bridge the SDK's `AnyJSON` into the codec currency, run
    /// the per-entity decode, then re-stamp the raw row's `updated_at` — the
    /// codecs drop unmapped wire columns, and without that key the sync cursor
    /// (`SyncCursor.maxUpdatedAt`) could never advance, making incremental
    /// pulls a permanent no-op. The key never leaks: applies decode into typed
    /// domain models (Codable ignores it) and upserts encode from local models
    /// (never these maps). `nonisolated static` so the whole per-row transform
    /// is unit-testable without a live client (pinned by `SyncCursorTests`).
    nonisolated static func decodeRow(
        _ anyRow: [String: AnyJSON],
        decode: ([String: JSONValue]) -> [String: JSONValue]
    ) -> [String: JSONValue] {
        let raw = SyncJSONBridge.fromAnyObject(anyRow)
        return SyncCursor.stampUpdatedAt(decode(raw), from: raw)
    }

    // MARK: - Content upserts (bulk, local-only rows only)

    /// `from('inventory_items').upsert(rows.map(rowForUpsert), ignoreDuplicates:true)`.
    /// Rejects any versioned row (`remoteVersion > 0`) — those must travel the
    /// gateway's conditional sync-op path so they never downgrade a remote row.
    /// Mirrors the Dart `ArgumentError` guard.
    func upsertInventory(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.inventory,
            hid: hid,
            rows: rows,
            method: "upsertInventory",
            encode: RemoteRowCodec.inventoryRowForUpsert
        )
    }

    func upsertShopping(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.shopping,
            hid: hid,
            rows: rows,
            method: "upsertShopping",
            encode: RemoteRowCodec.shoppingRowForUpsert
        )
    }

    func upsertCustomRecipes(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.customRecipes,
            hid: hid,
            rows: rows,
            method: "upsertCustomRecipes",
            encode: RemoteRowCodec.customRecipeRowForUpsert
        )
    }

    func upsertMealPlanEntries(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.mealPlanEntries,
            hid: hid,
            rows: rows,
            method: "upsertMealPlanEntries",
            encode: RemoteRowCodec.mealPlanEntryRowForUpsert
        )
    }

    func upsertFoodLogEntries(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.foodLogEntries,
            hid: hid,
            rows: rows,
            method: "upsertFoodLogEntries",
            encode: RemoteRowCodec.foodLogEntryRowForUpsert
        )
    }

    func upsertFavoriteRecipes(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.favoriteRecipes,
            hid: hid,
            rows: rows,
            method: "upsertFavoriteRecipes",
            encode: RemoteRowCodec.favoriteRecipeRowForUpsert
        )
    }

    func upsertDietaryPreferences(_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String> {
        try await upsertRows(
            into: Table.dietaryPreferences,
            hid: hid,
            rows: rows,
            method: "upsertDietaryPreferences",
            encode: RemoteRowCodec.dietaryPreferenceRowForUpsert
        )
    }

    /// Shared upsert path: no-op on empty (mirrors Dart `if (rows.isEmpty) return`),
    /// reject versioned rows, build the per-entity upsert row, bridge to `AnyJSON`,
    /// and `upsert(..., ignoreDuplicates: true)` so a first write never downgrades an
    /// existing remote version.
    ///
    /// Returns the ids the upsert ACTUALLY INSERTED, decoded from the
    /// representation the request already asks for (the SDK's default `Prefer:
    /// return=representation` — no wire change). An uploaded id missing from
    /// the result was ON-CONFLICT-DO-NOTHING'd against an existing row (live or
    /// tombstone); the caller must not mark it synced on faith.
    private func upsertRows(
        into table: String,
        hid: String,
        rows: [[String: JSONValue]],
        method: String,
        encode: (String, [String: JSONValue]) -> [String: JSONValue]
    ) async throws -> Set<String> {
        guard !rows.isEmpty else { return [] }
        guard !rows.contains(where: Self.hasRemoteVersion) else {
            throw RemotePantryError.invalidArgument(
                name: "rows",
                reason: "\(method) only accepts unsynced local rows; versioned sync "
                    + "writes must use a conditional remote operation."
            )
        }

        let payload = rows.map { SyncJSONBridge.toAnyObject(encode(hid, $0)) }
        let inserted: [[String: AnyJSON]] = try await client
            .from(table)
            .upsert(payload, ignoreDuplicates: true)
            .execute()
            .value
        return Set(inserted.compactMap { row in
            if case let .string(id) = row["id"] { id } else { nil }
        })
    }

    /// `row['remoteVersion'] is num && > 0` — a row that already has a server
    /// version must not be bulk-upserted.
    private static func hasRemoteVersion(_ row: [String: JSONValue]) -> Bool {
        switch row["remoteVersion"] {
        case let .int(version): return version > 0
        case let .double(version): return version > 0
        default: return false
        }
    }

    // MARK: - Realtime watches

    /// Streams the FULL current inventory set on every change. Mirrors Flutter's
    /// `from('inventory_items').stream(primaryKey:['id']).eq('household_id',id)`,
    /// which yields the whole filtered set per event — the per-row `AnyAction`
    /// payload is only the trigger; we re-fetch the snapshot so the coordinator's
    /// full-snapshot apply contract holds. The stream does NOT filter `deleted_at`
    /// (the apply side drops soft-deleted rows), matching the Dart stream.
    func watchInventory(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.inventory, hid: hid) { [weak self] in
            try? await self?.loadInventory(hid)
        }
    }

    func watchShopping(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.shopping, hid: hid) { [weak self] in
            try? await self?.loadShopping(hid)
        }
    }

    func watchCustomRecipes(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.customRecipes, hid: hid) { [weak self] in
            try? await self?.loadCustomRecipes(hid)
        }
    }

    func watchMealPlanEntries(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.mealPlanEntries, hid: hid) { [weak self] in
            try? await self?.loadMealPlanEntries(hid)
        }
    }

    func watchFoodLogEntries(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.foodLogEntries, hid: hid) { [weak self] in
            try? await self?.loadFoodLogEntries(hid)
        }
    }

    func watchFavoriteRecipes(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.favoriteRecipes, hid: hid) { [weak self] in
            try? await self?.loadFavoriteRecipes(hid)
        }
    }

    func watchDietaryPreferences(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
        watch(table: Table.dietaryPreferences, hid: hid) { [weak self] in
            try? await self?.loadDietaryPreferences(hid)
        }
    }

    /// Shared realtime path. Opens a channel filtered by `household_id`, subscribes
    /// to all postgres changes, and on EACH action re-fetches the full snapshot via
    /// `refetch` and yields it. SWALLOWS subscribe/channel errors (invariant #9:
    /// transient — log + continue, never crash). On stream termination it
    /// unsubscribes and removes the channel.
    ///
    /// `refetch` re-enters the actor (it calls `loadX`), so the snapshot stays
    /// consistent with `loadX`'s soft-delete filter even though realtime itself
    /// streams deleted rows too. It returns nil when the re-fetch FAILS (a
    /// transient network/token blip) — distinct from a successful EMPTY snapshot —
    /// so a failure skips the apply rather than yielding an authoritative empty set
    /// that would make the coordinator wipe every already-synced local row.
    private func watch(
        table: String,
        hid: String,
        refetch: @escaping @Sendable () async -> [[String: JSONValue]]?
    ) -> AsyncStream<[[String: JSONValue]]> {
        let client = client
        let log = log
        let channelName = "\(table):\(hid)"

        return AsyncStream { continuation in
            let task = Task {
                let channel = client.channel(channelName)
                // Open the change feed BEFORE subscribing so no event is missed
                // between subscribe and first consume, mirroring the SDK pattern.
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: table,
                    filter: .eq("household_id", value: hid)
                )
                do {
                    try await channel.subscribeWithError()
                } catch {
                    // Realtime is an accelerator, not the source of truth (the
                    // bulk pull + outbox still reconcile) — log and fall through:
                    // the stream just never yields, and a channel failure never
                    // crashes (invariant #9). Same behavior the deprecated
                    // error-swallowing `subscribe()` had, minus the silence.
                    log.error("Realtime subscribe failed: \(channelName, privacy: .public) \(error.localizedDescription, privacy: .public)")
                }

                for await _ in changes {
                    if Task.isCancelled { break }
                    // Skip (don't yield) when the re-fetch failed: an empty yield
                    // would be treated as an authoritative snapshot and wipe synced
                    // rows locally. A successful empty fetch still yields [].
                    if let rows = await refetch() {
                        continuation.yield(rows)
                    }
                }

                continuation.finish()
                await client.removeChannel(channel)
                log.debug("Realtime channel closed: \(channelName, privacy: .public)")
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Households

    /// `from('households').select()` → `[Household]`.
    func loadHouseholds() async throws -> [Household] {
        try await client.from(Table.households).select().execute().value
    }

    /// Inserts a household + the owner membership row, then returns the household.
    /// Two non-atomic writes (mirroring Dart): a partial failure surfaces as the
    /// thrown error. The id is a fresh lowercase v4 UUID and `default_storage_area`
    /// defaults to `fridge`, matching the Flutter insert.
    func createHousehold(name: String) async throws -> Household {
        let userId = try requireUserId(action: "create household")

        let household = Household(
            id: UUID().uuidString.lowercased(),
            name: name,
            ownerId: userId,
            defaultStorageArea: "fridge"
        )

        let householdRow: [String: AnyJSON] = [
            "id": .string(household.id),
            "name": .string(household.name),
            "owner_id": .string(userId),
            "default_storage_area": .string(household.defaultStorageArea),
        ]
        try await client.from(Table.households).insert(householdRow).execute()

        let memberRow: [String: AnyJSON] = [
            "household_id": .string(household.id),
            "user_id": .string(userId),
            "role": .string("owner"),
        ]
        try await client.from(Table.householdMembers).insert(memberRow).execute()

        return household
    }

    /// Inserts a `household_invites` row and returns its share link. An open
    /// (email-less) link is a bearer credential embedded in the URL, so it gets a
    /// 24h window; an email-bound invite re-checks the email on acceptance and can
    /// live 72h — matching the Dart expiry policy exactly.
    func createInvite(householdId: String, email: String?) async throws -> String {
        let userId = try requireUserId(action: "create invite")

        let trimmedEmail = email?.trimmed
        let targetEmail = (trimmedEmail?.isEmpty ?? true) ? nil : trimmedEmail

        let token = InviteToken.generate()
        let lifetime: TimeInterval = targetEmail == nil ? openInviteLifetime : emailInviteLifetime
        let expiresAt = JSONDate.iso8601(Date().addingTimeInterval(lifetime))

        let row: [String: AnyJSON] = [
            "household_id": .string(householdId),
            "email": targetEmail.map(AnyJSON.string) ?? .null,
            "token_hash": .string(InviteToken.hash(token)),
            "expires_at": .string(expiresAt),
            "created_by": .string(userId),
        ]
        try await client.from(Table.householdInvites).insert(row).execute()

        return InviteToken.inviteURL(apiBaseURL: apiBaseURL, token: token)
    }

    /// 24h for an open link (bearer credential in the URL).
    private let openInviteLifetime: TimeInterval = 24 * 60 * 60
    /// 72h for an email-bound invite (acceptance re-checks the email).
    private let emailInviteLifetime: TimeInterval = 3 * 24 * 60 * 60

    /// `from('households').update({'name':name}).eq('id',id)`. Requires a non-empty
    /// trimmed name + a valid household uuid + a signed-in user, mirroring Dart.
    func updateHouseholdName(_ hid: String, name: String) async throws {
        let trimmedId = try requireHouseholdUuid(hid)
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else {
            throw RemotePantryError.invalidArgument(name: "name", reason: "Household name cannot be empty")
        }
        _ = try requireUserId(action: "update household")

        let update: [String: AnyJSON] = ["name": .string(trimmedName)]
        try await client.from(Table.households).update(update).eq("id", value: trimmedId).execute()
    }

    // MARK: - Profile (user-scoped, single writer)

    /// `from('profiles').select().eq('id', myId)` → my `UserProfile`, or nil when
    /// the row doesn't exist yet (first sign-in before onboarding saves it).
    func loadMyProfile() async throws -> UserProfile? {
        let userId = try requireUserId(action: "load profile")
        let rows: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .execute()
            .value
        return rows.first
    }

    /// Upserts the signed-in user's profile row. id + email come from the session
    /// (never the caller) so a client can only ever write its OWN profile; empty
    /// nickname/avatar are stored as null. `updated_at` is set explicitly so an
    /// update (not just insert) bumps it.
    func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws {
        let userId = try requireUserId(action: "update profile")
        let email = client.auth.currentUser?.email ?? ""
        let row: [String: AnyJSON] = [
            "id": .string(userId),
            "email": .string(email),
            "display_name": .string(displayName),
            "nickname": nickname.isEmpty ? .null : .string(nickname),
            "avatar_path": avatarPath.isEmpty ? .null : .string(avatarPath),
            "updated_at": .string(JSONDate.iso8601(Date())),
        ]
        try await client.from("profiles").upsert(row).execute()
    }

    /// Uploads avatar bytes to `avatars/{userId}/{uuid}.jpg` and returns the path.
    /// A fresh uuid filename per upload means the public URL changes on every
    /// change (natural cache-bust); old objects are left in place (small, A-mode).
    func uploadAvatar(_ data: Data) async throws -> String {
        let userId = try requireUserId(action: "upload avatar")
        let path = "\(userId)/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    /// Public URL for an avatar path. `nonisolated` so a SwiftUI row builds it
    /// inline; reads only the actor's immutable `Sendable` client.
    nonisolated func avatarPublicURL(path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return try? client.storage.from("avatars").getPublicURL(path: path)
    }

    // MARK: - Household / invite RPCs

    /// `list_household_members(target_household_id)` → `[HouseholdMember]`. An empty
    /// (trimmed-blank) household id short-circuits to `[]`, mirroring Dart.
    func loadHouseholdMembers(_ hid: String) async throws -> [HouseholdMember] {
        let trimmed = hid.trimmed
        guard !trimmed.isEmpty else { return [] }
        _ = try requireUserId(action: "list household members")

        return try await client
            .rpc("list_household_members", params: ["target_household_id": trimmed])
            .execute()
            .value
    }

    /// `list_pending_household_invites()` → `[HouseholdInvitePreview]`.
    func loadPendingInvites() async throws -> [HouseholdInvitePreview] {
        _ = try requireUserId(action: "list pending invites")
        return try await client.rpc("list_pending_household_invites").execute().value
    }

    /// `preview_household_invite(invite_token_hash)` → the first preview row.
    /// Validates the token shape first (Dart `ArgumentError`), and throws
    /// `previewUnavailable` when the RPC returns no row.
    func previewInvite(token: String) async throws -> HouseholdInvitePreview {
        let validToken = try requireInviteTokenShape(token)
        _ = try requireUserId(action: "preview invite")

        let previews: [HouseholdInvitePreview] = try await client
            .rpc("preview_household_invite", params: ["invite_token_hash": InviteToken.hash(validToken)])
            .execute()
            .value
        guard let preview = previews.first else {
            throw RemotePantryError.previewUnavailable
        }
        return preview
    }

    /// `accept_household_invite(invite_token_hash)`. Void RPC.
    func acceptInvite(token: String) async throws {
        let validToken = try requireInviteTokenShape(token)
        _ = try requireUserId(action: "accept invite")

        try await client
            .rpc("accept_household_invite", params: ["invite_token_hash": InviteToken.hash(validToken)])
            .execute()
    }

    /// `accept_household_invite_by_id(target_invite_id)`. Void RPC.
    func acceptInviteById(inviteId: String) async throws {
        let trimmedId = try requireUuid(inviteId, name: "inviteId", reason: "Invalid invite id")
        _ = try requireUserId(action: "accept invite")

        try await client
            .rpc("accept_household_invite_by_id", params: ["target_invite_id": trimmedId])
            .execute()
    }

    /// `remove_household_member(target_household_id, target_user_id)`. Void RPC.
    func removeMember(householdId: String, userId: String) async throws {
        let trimmedHousehold = try requireUuid(householdId, name: "householdId", reason: "Invalid household id")
        let trimmedUser = try requireUuid(userId, name: "userId", reason: "Invalid user id")
        _ = try requireUserId(action: "remove member")

        try await client
            .rpc(
                "remove_household_member",
                params: ["target_household_id": trimmedHousehold, "target_user_id": trimmedUser]
            )
            .execute()
    }

    /// `revoke_household_invite(target_invite_id)`. Void RPC.
    func revokeInvite(inviteId: String) async throws {
        let trimmedId = try requireUuid(inviteId, name: "inviteId", reason: "Invalid invite id")
        _ = try requireUserId(action: "revoke invite")

        try await client
            .rpc("revoke_household_invite", params: ["target_invite_id": trimmedId])
            .execute()
    }

    /// `dissolve_household(target_household_id)`. Void RPC.
    func dissolveHousehold(_ hid: String) async throws {
        let trimmedId = try requireUuid(hid, name: "householdId", reason: "Invalid household id")
        _ = try requireUserId(action: "dissolve household")

        try await client
            .rpc("dissolve_household", params: ["target_household_id": trimmedId])
            .execute()
    }

    /// `leave_household(target_household_id)`. Void RPC.
    func leaveHousehold(_ hid: String) async throws {
        let trimmedId = try requireUuid(hid, name: "householdId", reason: "Invalid household id")
        _ = try requireUserId(action: "leave a household")

        try await client
            .rpc("leave_household", params: ["target_household_id": trimmedId])
            .execute()
    }

    /// `list_owner_pending_invites(target_household_id)` → `[OwnerPendingInvite]`. An
    /// empty (trimmed-blank) household id short-circuits to `[]`, mirroring Dart.
    func fetchOwnerPendingInvites(_ hid: String) async throws -> [OwnerPendingInvite] {
        let trimmed = hid.trimmed
        guard !trimmed.isEmpty else { return [] }
        _ = try requireUserId(action: "list owner pending invites")

        return try await client
            .rpc("list_owner_pending_invites", params: ["target_household_id": trimmed])
            .execute()
            .value
    }

    // MARK: - Guards (mirror the Dart signed-in / uuid / token validation)

    /// The signed-in user's id as the lowercase canonical UUID string the backend
    /// stores. Throws `notSignedIn` (Dart `StateError`) when there is no session.
    private func requireUserId(action: String) throws -> String {
        guard let id = client.auth.currentUser?.id else {
            throw RemotePantryError.notSignedIn(action: action)
        }
        return id.uuidString.lowercased()
    }

    /// Trimmed household id, validated as a UUID. Throws `invalidArgument` (Dart
    /// `ArgumentError`) otherwise.
    private func requireHouseholdUuid(_ hid: String) throws -> String {
        try requireUuid(hid, name: "householdId", reason: "Invalid household id")
    }

    /// Trims `value` and validates the canonical UUID shape, throwing
    /// `invalidArgument` on failure (mirrors Dart `isUuid` + `ArgumentError.value`).
    private func requireUuid(_ value: String, name: String, reason: String) throws -> String {
        let trimmed = value.trimmed
        guard ProposalApply.isUuid(trimmed) else {
            throw RemotePantryError.invalidArgument(name: name, reason: reason)
        }
        return trimmed
    }

    /// Trims `token` and validates the invite-token shape, throwing
    /// `invalidArgument` on failure (mirrors Dart `isInviteTokenShapeValid`).
    private func requireInviteTokenShape(_ token: String) throws -> String {
        let trimmed = token.trimmed
        guard InviteToken.isShapeValid(trimmed) else {
            throw RemotePantryError.invalidArgument(name: "token", reason: "Invalid invite token")
        }
        return trimmed
    }
}

extension RemotePantryRepository: ProfileRemote {}
