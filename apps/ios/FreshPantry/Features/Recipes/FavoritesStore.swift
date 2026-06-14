import Foundation

/// Favorite-recipe ids — household-synced when a backend is wired, else a local
/// UserDefaults blob.
///
/// Two construction modes, ONE synchronous UI surface (`favoriteIDs` /
/// `isFavorite` / `toggle`) so views never change:
/// - LOCAL mode (`init(defaults:)`): the original UserDefaults-backed store
///   (tests, backup, previews, local-only mode before sync). Behaviour is
///   byte-identical to the pre-sync store — a `Set<String>` persisted as a sorted
///   JSON string array under `favorite_recipe_ids`.
/// - SYNCED mode (`init(repository:session:syncWriter:)`): the favorite set is
///   backed by the household-scoped `FavoriteRecipeRepository` and every toggle is
///   mirrored to the SET-MEMBERSHIP sync entity (deterministic id, soft-delete on
///   un-favorite) + enqueued so other household members converge. Legacy
///   UserDefaults favorites are migrated into the repository once.
///
/// `@Observable @MainActor` so views observe `favoriteIDs`; the repository write +
/// sync enqueue run in a detached task AFTER the optimistic in-memory flip, so the
/// heart fills instantly.
@Observable
@MainActor
final class FavoritesStore {
    /// Storage key — matches Flutter `favorite_recipes_repo` for sync parity, and
    /// the legacy blob migrated into the repository on the first synced load.
    static let storageKey = "favorite_recipe_ids"

    private let defaults: UserDefaults

    /// The live favorite-id set (recipe ids). Derived from the repository rows in
    /// synced mode, or the UserDefaults blob in local mode.
    private(set) var favoriteIDs: Set<String>

    // MARK: Sync backend (all nil = local UserDefaults mode)

    private let repository: FavoriteRecipeRepository?
    private let session: SyncSession?
    private let syncWriter: SyncWriter?

    /// The synced row per recipe id (active OR tombstoned) — carries the
    /// deterministic id + `remoteVersion` (the optimistic-lock base) a toggle
    /// needs. Empty in local mode.
    private var rows: [String: FavoriteRecipe] = [:]
    /// One-shot guard so the UserDefaults→repository migration runs once per launch
    /// (and the cleared blob keeps it from re-running on later launches).
    private var didMigrateLegacy = false
    /// Serializes the detached repository-write + enqueue of each toggle so rapid
    /// toggles persist IN ORDER, and gives `reload()` / tests a deterministic point
    /// to await in-flight writes (`drainPendingWrites`).
    @ObservationIgnored private var writeChain: Task<Void, Never> = Task {}

    private var householdID: String { session?.selectedHouseholdId ?? "" }

    /// LOCAL mode — UserDefaults-backed, no sync. Unchanged from the pre-sync store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.repository = nil
        self.session = nil
        self.syncWriter = nil
        self.favoriteIDs = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    /// SYNCED mode — repository-backed + household-scoped. `favoriteIDs` is empty
    /// until `reload()` hydrates it; the app root calls `reload()` on launch, on
    /// household switch, and after every remote-merge pulse.
    init(
        repository: FavoriteRecipeRepository,
        session: SyncSession,
        syncWriter: SyncWriter,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.defaults = legacyDefaults
        self.repository = repository
        self.session = session
        self.syncWriter = syncWriter
        self.favoriteIDs = []
    }

    // MARK: Queries

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    // MARK: Mutations

    /// Toggles a recipe id (ignores blank ids), updating the in-memory set
    /// synchronously, then persisting (UserDefaults in local mode, repository +
    /// sync enqueue in synced mode). Returns the resulting favorite state.
    @discardableResult
    func toggle(_ id: String) -> Bool {
        let trimmed = id.trimmed
        guard !trimmed.isEmpty else { return false }
        let nowFavorite = !favoriteIDs.contains(trimmed)
        if nowFavorite {
            favoriteIDs.insert(trimmed)
        } else {
            favoriteIDs.remove(trimmed)
        }
        if repository == nil {
            persistLocal()
        } else {
            persistSynced(recipeID: trimmed, favorite: nowFavorite)
        }
        return nowFavorite
    }

    // MARK: Synced reload + persistence

    /// Re-derives `favoriteIDs` + the per-recipe row map from the repository for the
    /// current household. No-op in local mode. Runs the one-shot legacy migration
    /// on first call.
    func reload() async {
        guard let repository else { return }
        await drainPendingWrites()
        let hid = householdID
        await migrateLegacyIfNeeded(hid: hid, repository: repository)
        let loaded = (try? await repository.loadAllFor(hid)) ?? []
        var byRecipe: [String: FavoriteRecipe] = [:]
        for row in loaded where !row.recipeID.isEmpty {
            // Deterministic ids mean ≤1 row per recipe; if a duplicate ever lands,
            // prefer an active row over a tombstone.
            if let existing = byRecipe[row.recipeID], existing.deletedAt == nil, row.deletedAt != nil { continue }
            byRecipe[row.recipeID] = row
        }
        rows = byRecipe
        favoriteIDs = Set(byRecipe.values.filter { $0.deletedAt == nil }.map(\.recipeID))
    }

    /// Upserts the deterministic-id favorite row (or soft-deletes it on
    /// un-favorite) locally, then enqueues the matching sync op. The op kind
    /// mirrors the gateway contract: a first write is a `create` (no base version),
    /// re-/un-favoriting a synced row is an `update`/`delete` gated on its version.
    private func persistSynced(recipeID: String, favorite: Bool) {
        let hid = householdID
        let existing = rows[recipeID]
        let baseVersion = existing?.remoteVersion ?? 0
        let id = existing?.id ?? FavoriteRecipe.id(householdID: hid, recipeID: recipeID)
        let now = Date()
        let row = FavoriteRecipe(
            id: id,
            recipeID: recipeID,
            remoteVersion: baseVersion,
            clientUpdatedAt: now,
            deletedAt: favorite ? nil : now
        )
        rows[recipeID] = row

        let operation: SyncOperationType = favorite ? (baseVersion <= 0 ? .create : .update) : .delete
        enqueueRow(row, hid: hid, operation: operation, baseVersion: baseVersion)
    }

    /// Awaits all in-flight toggle persistence (test seam + `reload` ordering).
    func drainPendingWrites() async { _ = await writeChain.value }

    /// One-shot import of the legacy UserDefaults favorites into the repository for
    /// the current scope (only ids not already present), then clears the blob so it
    /// never re-imports. Upserts are awaited directly (the caller `reload` awaits
    /// this) so the seeded rows are visible to the load that follows.
    private func migrateLegacyIfNeeded(hid: String, repository: FavoriteRecipeRepository) async {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true
        let legacy = Self.decode(defaults.string(forKey: Self.storageKey))
        guard !legacy.isEmpty else { return }
        let existing = Set(((try? await repository.loadAllFor(hid)) ?? []).map(\.recipeID))
        let now = Date()
        for recipeID in legacy.sorted() where !existing.contains(recipeID) {
            let fav = FavoriteRecipe.make(householdID: hid, recipeID: recipeID, clientUpdatedAt: now)
            rows[recipeID] = fav
            try? await repository.upsert(hid, fav)
            if let patch = DomainJSON.valueMap(fav) {
                await syncWriter?.enqueue(
                    entityType: .favoriteRecipe, entityId: fav.id,
                    operation: .create, patch: patch, baseVersion: nil
                )
            }
        }
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Chains a detached repository-upsert + sync enqueue after any prior write so
    /// rapid toggles persist in order. The in-memory `rows`/`favoriteIDs` were
    /// already updated by the caller (optimistic).
    private func enqueueRow(_ row: FavoriteRecipe, hid: String, operation: SyncOperationType, baseVersion: Int) {
        let prev = writeChain
        let repository = repository
        let syncWriter = syncWriter
        writeChain = Task {
            _ = await prev.value
            try? await repository?.upsert(hid, row)
            guard let patch = DomainJSON.valueMap(row) else { return }
            await syncWriter?.enqueue(
                entityType: .favoriteRecipe,
                entityId: row.id,
                operation: operation,
                patch: patch,
                baseVersion: baseVersion <= 0 ? nil : baseVersion
            )
        }
    }

    // MARK: Local persistence (the reusable JSON-string-array KV codec)

    /// Encodes the id set as a sorted JSON string array and writes the blob.
    private func persistLocal() {
        let array = favoriteIDs.sorted()
        guard
            let data = try? JSONSerialization.data(withJSONObject: array),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty set; otherwise the
    /// non-blank string elements (mirrors the Flutter repo's lenient load).
    static func decode(_ raw: String?) -> Set<String> {
        guard
            let raw, !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        let ids = array.compactMap { $0 as? String }.filter { !$0.isEmpty }
        return Set(ids)
    }
}
