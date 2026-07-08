import Foundation
import OSLog

/// The per-call externalities the generic reconciliation sequence needs from the
/// live coordinator: its generation guard, the outbox snapshot, and the
/// merge-pulse. Built at the call site (where `self` / `gen` / `hid` are in
/// scope), so `[EntitySync]` itself stays `Sendable` and captures only the
/// (Sendable) repositories + remote — never the coordinator. See ADR-0004.
struct SyncApplyContext: Sendable {
    let householdId: String
    let isCurrent: @Sendable () async -> Bool
    let loadPending: @Sendable () async -> [SyncOperation]
    let signalMerge: @Sendable () async -> Void
}

/// One synced entity's local⇄remote reconciliation, type-erased so the seven live
/// in a single `[EntitySync]` the coordinator loops over (apply / patch / upload /
/// subscribe / cursor-advance). The decode → merge → save → signal sequence is
/// written ONCE in `make`; adding an eighth synced entity is one `make(…)` line.
///
/// Replaces the 21 hand-rolled blocks of the verbatim Dart port (ADR-0004). The
/// generation guard and `signalMerge` are reached through `SyncApplyContext`, not
/// captured, so the struct is `Sendable` and usable from `subscribe`'s tasks.
struct EntitySync: Sendable {
    let entityType: SyncEntityType
    let remoteLoad: @Sendable (_ hid: String, _ since: Date?) async throws -> [[String: JSONValue]]
    let watch: @Sendable (_ hid: String) async -> AsyncStream<[[String: JSONValue]]>
    /// Full-snapshot apply: decode → build scope → atomic merge-save (one
    /// repository `mutate` call) → pulse. Rebuilds the scope per apply (parity
    /// with the old `applyXRows`). Returns false when the run went stale
    /// (generation bump) or the save failed — the coordinator must then hold
    /// the cursor back so the rows re-deliver on the next pull instead of
    /// being skipped forever.
    let applyFull: @Sendable (_ rows: [[String: JSONValue]], _ ctx: SyncApplyContext) async -> Bool
    /// Incremental delta apply: decode → atomic patch-save → pulse.
    /// Same Bool contract as `applyFull`; an empty (but current) delta is a
    /// successful no-op.
    let applyPatch: @Sendable (_ rows: [[String: JSONValue]], _ ctx: SyncApplyContext) async -> Bool
    /// Upload still-local-only rows, then mark the rows the remote actually
    /// accepted — inserted, or PK-collision-resolved through the gateway — as
    /// `remoteVersion = 1`. Takes the run's SHARED scope (parity: the old
    /// `uploadLocalOnly` built it once).
    let uploadLocalOnly: @Sendable (_ scope: LocalUploadScope, _ ctx: SyncApplyContext) async throws -> Void

    private static let log = Logger(subsystem: "com.sunpebble.freshpantry", category: "sync")

    static func make<T: SyncableEntity>(
        _ entityType: SyncEntityType,
        load: @escaping @Sendable (_ hid: String) async throws -> [T],
        mutate: @escaping @Sendable (_ hid: String, _ transform: @escaping @Sendable ([T]) -> [T]) async throws -> Void,
        remoteLoad: @escaping @Sendable (_ hid: String, _ since: Date?) async throws -> [[String: JSONValue]],
        remoteUpsert: @escaping @Sendable (_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Set<String>,
        resolveCollided: @escaping @Sendable (_ entityType: SyncEntityType, _ hid: String, _ rows: [[String: JSONValue]]) async -> Set<String>,
        watch: @escaping @Sendable (_ hid: String) async -> AsyncStream<[[String: JSONValue]]>
    ) -> EntitySync {
        // Every local write below goes through `mutate` — the repository's
        // ATOMIC load→transform→save (one actor call, no suspension inside).
        // A separate load + save pair opens a window where a concurrent local
        // write (a user edit landing mid-apply, another sync path's save)
        // lands between the snapshot and the full-scope replace and is
        // silently reverted — the race behind the resurrected-tombstone
        // zombie rows. With `mutate`, a concurrent write either lands before
        // (the transform sees it) or after (it is never overwritten).
        // A failed load inside `mutate` now fails the apply (cursor holds
        // back) instead of merging against an empty snapshot, which would
        // have dropped every local-only row.
        EntitySync(
            entityType: entityType,
            remoteLoad: remoteLoad,
            watch: watch,
            applyFull: { rows, ctx in
                guard await ctx.isCurrent() else { return false }
                let decoded = rows
                    .compactMap { DomainJSON.fromValueMap(T.self, from: $0) }
                    .filter(\.isWellFormed)
                let scope = LocalUploadScope(householdID: ctx.householdId, pendingOps: await ctx.loadPending())
                guard await ctx.isCurrent() else { return false }
                guard await Self.saveReporting(entityType, {
                    try await mutate(ctx.householdId) { local in
                        HouseholdMergePolicy.merge(remote: decoded, local: local, scope: scope, entityType: entityType)
                    }
                }) else { return false }
                await ctx.signalMerge()
                return true
            },
            applyPatch: { rows, ctx in
                guard await ctx.isCurrent() else { return false }
                guard !rows.isEmpty else { return true }
                let decoded = rows
                    .compactMap { DomainJSON.fromValueMap(T.self, from: $0) }
                    .filter(\.isWellFormed)
                guard await ctx.isCurrent() else { return false }
                guard await Self.saveReporting(entityType, {
                    try await mutate(ctx.householdId) { local in
                        HouseholdMergePolicy.patch(remoteDelta: decoded, local: local)
                    }
                }) else { return false }
                await ctx.signalMerge()
                return true
            },
            // ponytail: uploadLocalOnly keeps its existing log-and-continue on
            // save failure — a missed version bump self-heals via re-upsert
            // (ignoreDuplicates: an own-live-row conflict just resolves through
            // the collision path below and re-bumps), unlike a missed apply
            // which the cursor would skip past.
            uploadLocalOnly: { scope, ctx in
                guard await ctx.isCurrent() else { return }
                let local = (try? await load(ctx.householdId)) ?? []
                let upload = local.filter { $0.isLocalOnly && scope.allows(entityType, $0.id) }
                guard !upload.isEmpty else { return }
                let rows = upload.compactMap { DomainJSON.valueMap($0) }
                let inserted = try await remoteUpsert(ctx.householdId, rows)
                guard await ctx.isCurrent() else { return }
                // A UUID id missing from the inserted set was ON-CONFLICT-
                // DO-NOTHING'd against an existing remote row. Marking it v1 on
                // faith would let the next full pull (tombstones filtered out)
                // silently drop the row — the lost-toggle defect. Route those
                // rows through the gateway's revive-if-tombstone resolution: a
                // tombstone is revived by the version-gated client-wins UPDATE
                // (nothing else can deliver it), a live row is confirmed
                // WITHOUT a write (remote is authoritative and the pull adopts
                // it — the missed-version-bump self-heal, and a concurrent
                // outbox push's newer write is never rolled back), and only
                // then is the v1 mark truthful; unresolved rows stay at
                // remoteVersion 0 and retry next run. Non-UUID ids never ship
                // an id column (the DB mints one), so their absence from
                // `inserted` is the normal fresh insert — or inventory's
                // designed dedupe skip — and they bump as before.
                let collided = rows.filter { row in
                    guard case let .string(id) = row["id"], ProposalApply.isUuid(id) else { return false }
                    return !inserted.contains(id)
                }
                var synced = Set(upload.map(\.id))
                if !collided.isEmpty {
                    synced.subtract(collided.compactMap { row in
                        if case let .string(id) = row["id"] { id } else { nil }
                    })
                    synced.formUnion(await resolveCollided(entityType, ctx.householdId, collided))
                    guard await ctx.isCurrent() else { return }
                }
                // Bump atomically from the repository's CURRENT rows: the
                // upload/resolution round-trips are a wide window, and even a
                // fresh re-load + separate save let a concurrent apply (e.g. a
                // delta's tombstone) slip between the two calls and be
                // resurrected by the full-scope replace. Skipping on a failed
                // bump is safe (the missed bump self-heals next run).
                let confirmed = synced
                if (try? await mutate(ctx.householdId, { fresh in
                    fresh.map { confirmed.contains($0.id) ? $0.withRemoteVersion(1) : $0 }
                })) == nil {
                    log.error("version bump after \(entityType.rawValue, privacy: .public) upload failed; rows may stay at remoteVersion 0 until the next run")
                }
            }
        )
    }

    /// Runs the local save, logging and reporting failure instead of the old
    /// silent `try?` — a swallowed save must not let the cursor advance past
    /// rows that never landed locally.
    private static func saveReporting(
        _ entityType: SyncEntityType,
        _ save: () async throws -> Void
    ) async -> Bool {
        do {
            try await save()
            return true
        } catch {
            log.error("saving merged \(entityType.rawValue, privacy: .public) rows failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
