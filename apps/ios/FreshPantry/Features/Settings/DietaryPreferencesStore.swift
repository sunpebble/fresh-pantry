import Foundation

/// Avoided-ingredient keywords (忌口) — household-synced when a backend is wired,
/// else a local UserDefaults blob. The 忌口 sibling of `FavoritesStore`: same
/// dual-mode shape and ONE synchronous UI surface (`keywords` / `add` / `remove` /
/// `contains` / `sortedKeywords`) so views never change.
///
/// The store OWNS input normalization — keywords are trimmed + lowercased on
/// `add` — so the persisted set and the deterministic sync id are always built
/// from the canonical form.
/// - LOCAL mode (`init(defaults:)`): unchanged UserDefaults-backed store.
/// - SYNCED mode (`init(repository:session:syncWriter:)`): backed by the
///   household-scoped `DietaryPreferenceRepository`; every add/remove mirrors to
///   the set-membership sync entity (deterministic id, soft-delete on remove) and
///   is enqueued. Legacy UserDefaults keywords migrate into the repository once.
@Observable
@MainActor
final class DietaryPreferencesStore {
    /// Storage key — matches Flutter `dietary_preferences_repo` for sync parity,
    /// and the legacy blob migrated into the repository on the first synced load.
    static let storageKey = "dietary_exclusions"

    private let defaults: UserDefaults

    /// The live avoided-keyword set (already normalized).
    private(set) var keywords: Set<String>

    // MARK: Sync backend (all nil = local UserDefaults mode)

    private let repository: DietaryPreferenceRepository?
    private let session: SyncSession?
    private let syncWriter: SyncWriter?

    /// The synced row per normalized keyword (active OR tombstoned).
    private var rows: [String: DietaryPreference] = [:]
    private var didMigrateLegacy = false
    /// Serializes detached add/remove persistence (ordered + awaitable).
    @ObservationIgnored private var writeChain: Task<Void, Never> = Task {}

    private var householdID: String { session?.selectedHouseholdId ?? "" }

    /// LOCAL mode — UserDefaults-backed, no sync. Unchanged from the pre-sync store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.repository = nil
        self.session = nil
        self.syncWriter = nil
        self.keywords = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    /// SYNCED mode — repository-backed + household-scoped. `keywords` is empty until
    /// `reload()` hydrates it.
    init(
        repository: DietaryPreferenceRepository,
        session: SyncSession,
        syncWriter: SyncWriter,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.defaults = legacyDefaults
        self.repository = repository
        self.session = session
        self.syncWriter = syncWriter
        self.keywords = []
    }

    // MARK: Queries

    var sortedKeywords: [String] { keywords.sorted() }

    func contains(_ keyword: String) -> Bool {
        let normalized = Self.normalize(keyword)
        guard !normalized.isEmpty else { return false }
        return keywords.contains(normalized)
    }

    // MARK: Mutations (normalization owned here)

    /// Normalizes (trim + lowercase) and inserts a keyword; blank input is a no-op.
    /// Returns the keyword actually stored, or `nil` if it was blank.
    @discardableResult
    func add(_ keyword: String) -> String? {
        let normalized = Self.normalize(keyword)
        guard !normalized.isEmpty else { return nil }
        guard !keywords.contains(normalized) else { return normalized }
        keywords.insert(normalized)
        if repository == nil {
            persistLocal()
        } else {
            persistSynced(keyword: normalized, present: true)
        }
        return normalized
    }

    /// Removes a keyword (normalizes the argument first so a differently-cased
    /// removal still matches the stored canonical form).
    func remove(_ keyword: String) {
        let normalized = Self.normalize(keyword)
        guard keywords.contains(normalized) else { return }
        keywords.remove(normalized)
        if repository == nil {
            persistLocal()
        } else {
            persistSynced(keyword: normalized, present: false)
        }
    }

    // MARK: Normalization (single source of truth for input shaping)

    static func normalize(_ keyword: String) -> String {
        keyword.trimmed.lowercased()
    }

    // MARK: Synced reload + persistence

    func reload() async {
        guard let repository else { return }
        await drainPendingWrites()
        let hid = householdID
        await migrateLegacyIfNeeded(hid: hid, repository: repository)
        let loaded = (try? await repository.loadAllFor(hid)) ?? []
        var byKeyword: [String: DietaryPreference] = [:]
        for row in loaded where !row.keyword.isEmpty {
            if let existing = byKeyword[row.keyword], existing.deletedAt == nil, row.deletedAt != nil { continue }
            byKeyword[row.keyword] = row
        }
        rows = byKeyword
        keywords = Set(byKeyword.values.filter { $0.deletedAt == nil }.map(\.keyword))
    }

    private func persistSynced(keyword: String, present: Bool) {
        let hid = householdID
        let existing = rows[keyword]
        let baseVersion = existing?.remoteVersion ?? 0
        let id = existing?.id ?? DietaryPreference.id(householdID: hid, keyword: keyword)
        let now = Date()
        let row = DietaryPreference(
            id: id,
            keyword: keyword,
            remoteVersion: baseVersion,
            clientUpdatedAt: now,
            deletedAt: present ? nil : now
        )
        rows[keyword] = row

        let operation: SyncOperationType = present ? (baseVersion <= 0 ? .create : .update) : .delete
        enqueueRow(row, hid: hid, operation: operation, baseVersion: baseVersion)
    }

    /// Awaits all in-flight add/remove persistence (test seam + `reload` ordering).
    func drainPendingWrites() async { _ = await writeChain.value }

    private func migrateLegacyIfNeeded(hid: String, repository: DietaryPreferenceRepository) async {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true
        let legacy = Self.decode(defaults.string(forKey: Self.storageKey))
        guard !legacy.isEmpty else { return }
        let existing = Set(((try? await repository.loadAllFor(hid)) ?? []).map(\.keyword))
        let now = Date()
        for keyword in legacy.sorted() where !existing.contains(keyword) {
            let pref = DietaryPreference.make(householdID: hid, keyword: keyword, clientUpdatedAt: now)
            rows[keyword] = pref
            try? await repository.upsert(hid, pref)
            if let patch = DomainJSON.valueMap(pref) {
                await syncWriter?.enqueue(
                    entityType: .dietaryPreference, entityId: pref.id,
                    operation: .create, patch: patch, baseVersion: nil
                )
            }
        }
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func enqueueRow(_ row: DietaryPreference, hid: String, operation: SyncOperationType, baseVersion: Int) {
        let prev = writeChain
        let repository = repository
        let syncWriter = syncWriter
        writeChain = Task {
            _ = await prev.value
            try? await repository?.upsert(hid, row)
            guard let patch = DomainJSON.valueMap(row) else { return }
            await syncWriter?.enqueue(
                entityType: .dietaryPreference,
                entityId: row.id,
                operation: operation,
                patch: patch,
                baseVersion: baseVersion <= 0 ? nil : baseVersion
            )
        }
    }

    // MARK: Local persistence (the reusable JSON-string-array KV codec)

    private func persistLocal() {
        let array = keywords.sorted()
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty set; otherwise the
    /// normalized, non-blank string elements (re-normalized on load so a legacy
    /// blob with mixed casing collapses to the canonical set).
    static func decode(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        let keywords = array
            .compactMap { $0 as? String }
            .map(normalize)
            .filter { !$0.isEmpty }
        return Set(keywords)
    }
}
