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
    /// Full-snapshot apply: decode → build scope → load local → merge → save →
    /// pulse. Rebuilds the scope per apply (parity with the old `applyXRows`).
    let applyFull: @Sendable (_ rows: [[String: JSONValue]], _ ctx: SyncApplyContext) async -> Void
    /// Incremental delta apply: decode → load local → patch → save → pulse.
    let applyPatch: @Sendable (_ rows: [[String: JSONValue]], _ ctx: SyncApplyContext) async -> Void
    /// Upload still-local-only rows, then mark them `remoteVersion = 1`. Takes the
    /// run's SHARED scope (parity: the old `uploadLocalOnly` built it once).
    let uploadLocalOnly: @Sendable (_ scope: LocalUploadScope, _ ctx: SyncApplyContext) async throws -> Void

    private static let log = Logger(subsystem: "com.kunish.freshPantry", category: "sync")

    static func make<T: SyncableEntity>(
        _ entityType: SyncEntityType,
        load: @escaping @Sendable (_ hid: String) async throws -> [T],
        save: @escaping @Sendable (_ hid: String, _ rows: [T]) async throws -> Void,
        remoteLoad: @escaping @Sendable (_ hid: String, _ since: Date?) async throws -> [[String: JSONValue]],
        remoteUpsert: @escaping @Sendable (_ hid: String, _ rows: [[String: JSONValue]]) async throws -> Void,
        watch: @escaping @Sendable (_ hid: String) async -> AsyncStream<[[String: JSONValue]]>
    ) -> EntitySync {
        EntitySync(
            entityType: entityType,
            remoteLoad: remoteLoad,
            watch: watch,
            applyFull: { rows, ctx in
                guard await ctx.isCurrent() else { return }
                let decoded = rows
                    .compactMap { DomainJSON.fromValueMap(T.self, from: $0) }
                    .filter(\.isWellFormed)
                let scope = LocalUploadScope(householdID: ctx.householdId, pendingOps: await ctx.loadPending())
                let local = (try? await load(ctx.householdId)) ?? []
                let merged = HouseholdMergePolicy.merge(remote: decoded, local: local, scope: scope, entityType: entityType)
                guard await ctx.isCurrent() else { return }
                try? await save(ctx.householdId, merged)
                await ctx.signalMerge()
            },
            applyPatch: { rows, ctx in
                guard await ctx.isCurrent(), !rows.isEmpty else { return }
                let decoded = rows
                    .compactMap { DomainJSON.fromValueMap(T.self, from: $0) }
                    .filter(\.isWellFormed)
                let local = (try? await load(ctx.householdId)) ?? []
                let merged = HouseholdMergePolicy.patch(remoteDelta: decoded, local: local)
                guard await ctx.isCurrent() else { return }
                try? await save(ctx.householdId, merged)
                await ctx.signalMerge()
            },
            uploadLocalOnly: { scope, ctx in
                guard await ctx.isCurrent() else { return }
                let local = (try? await load(ctx.householdId)) ?? []
                let upload = local.filter { $0.isLocalOnly && scope.allows(entityType, $0.id) }
                guard !upload.isEmpty else { return }
                try await remoteUpsert(ctx.householdId, upload.compactMap { DomainJSON.valueMap($0) })
                guard await ctx.isCurrent() else { return }
                let uploaded = Set(upload.map(\.id))
                let bumped = local.map { uploaded.contains($0.id) ? $0.withRemoteVersion(1) : $0 }
                if (try? await save(ctx.householdId, bumped)) == nil {
                    log.error("version bump after \(entityType.rawValue, privacy: .public) upload failed; rows may stay at remoteVersion 0 until the next full pull")
                }
            }
        )
    }
}
