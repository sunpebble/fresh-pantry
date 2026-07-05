import Foundation
import os

/// Remote push surface the coordinator depends on, so retry logic can be unit
/// tested without binding to the Supabase SDK. The SDK-backed gateway conforms
/// in a later slice. Mirrors the Dart `RemoteSyncGateway`.
protocol RemoteSyncGateway: Sendable {
    /// Pushes `ops` and returns the set of operation ids the server
    /// acknowledged (and therefore may be dropped from the outbox).
    func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String>
}

/// Outbox read/ack surface the coordinator depends on, so retry logic can be
/// unit tested without binding to SwiftData. The real `SyncOutboxRepository`
/// actor conforms in a later slice. Mirrors the Dart `OutboxReader`.
protocol OutboxReading: Sendable {
    /// Pending operations, oldest first.
    func loadPending() async throws -> [SyncOperation]

    /// Drops the acknowledged operations from the outbox.
    func removeAcknowledged(_ ids: Set<String>) async throws
}

/// The push surface the **Sync Finish** seam depends on, so a write path can be
/// asserted to actually KICK a push — not merely bump the `pendingSyncRevision`
/// proxy — in tests. The concrete `actor SyncCoordinator` conforms; tests inject
/// a counting spy. Its absence (a bare concrete actor with no seam) is the
/// structural reason `c0defc8` / `dabcbd4` shipped invisibly past the suite: the
/// only observable effect was the revision bump, which can fire independently of
/// an actual push.
protocol CoordinatorPushing: Sendable {
    func pushPending() async
}

/// Drives outbox push without overlapping runs, ported from
/// `lib/sync/sync_coordinator.dart`.
///
/// `pushPending` is invoked after every enqueue and during startup, so
/// concurrent callers must be coalesced: overlapping the snapshot → push →
/// remove cycle would double-push the same operations (a second run reads a
/// stale snapshot that still contains operations the first run is
/// acknowledging). Callers that arrive while a run is in flight join it, and
/// exactly one trailing run is scheduled afterwards so operations enqueued
/// mid-run (which the in-flight snapshot missed) are still pushed promptly.
///
/// Single-flight is enforced by actor isolation rather than a Dart `Future`
/// field: the `inFlight` task and `rerunRequested` flag are only ever touched
/// inside the actor.
actor SyncCoordinator: CoordinatorPushing {
    private let outbox: OutboxReading
    private let remote: RemoteSyncGateway
    private let retry: SyncRetryPolicy
    private let diagnostics: Diagnostics

    private var inFlight: Task<Void, Never>?
    private var rerunRequested = false

    /// DEAD-LETTER bookkeeping. The gateway is FIFO + stop-on-first-failure, so
    /// one permanently-failing op (an RLS rejection, a poisoned payload) would
    /// otherwise head-block every later op forever while the banner shows an
    /// eternal 「同步中」. Ops that fail at the head of the queue accumulate
    /// strikes; at `deadLetterThreshold` their WHOLE ENTITY is quarantined —
    /// every queued op for that `(entityType, entityId)` is skipped from
    /// subsequent pushes so the rest of the queue drains, surfaced as
    /// 「N 条同步失败」. Quarantining the entity (not just the struck op) preserves
    /// per-entity FIFO: skipping only the struck op would let later ops of the
    /// same entity overtake it, and the struck op's eventual replay (next
    /// launch) would then roll the newer write back via the client-patch-wins
    /// contended-write merge. Held IN MEMORY only (no outbox schema change): a
    /// relaunch — or an offline→online flip, see `lastProbedOnline` — clears the
    /// quarantine, so a falsely-flagged entity self-heals while a true poison op
    /// re-quarantines within a few triggers.
    private struct EntityKey: Hashable {
        let type: SyncEntityType
        let id: String

        init(_ op: SyncOperation) {
            type = op.entityType
            id = op.entityId
        }
    }

    private var headFailureCounts: [EntityKey: Int] = [:]
    private var deadLetteredEntities: Set<EntityKey> = []
    /// Pending op ids currently held back by an entity quarantine — kept as the
    /// banner count so 「N 条同步失败」 reflects every write that isn't syncing,
    /// not just the struck op. Recomputed from the outbox snapshot each run and
    /// extended at strike time (so the count is fresh the moment the banner asks).
    private var quarantinedOpIds: Set<String> = []
    private let deadLetterThreshold: Int

    /// Last reading of `onlineProbe` observed by a push run. A false→true flip
    /// (reconnect) clears the strike counts AND the quarantine: whatever caused
    /// the strikes (a transient server fault, a captive portal) had a window to
    /// clear, so the quarantined entities get one fresh FIFO replay instead of
    /// staying parked until relaunch. A true poison op simply re-quarantines.
    private var lastProbedOnline: Bool?

    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "sync")

    /// Connectivity probe gating the silent-failure strike: the real gateway
    /// swallows error types, so a partial ack alone can't be told apart from an
    /// offline drop — strikes only count while this reports online. Also feeds
    /// the offline→online flip detection (see `lastProbedOnline`). Defaults to
    /// always-online; the app root injects the live monitor.
    private var onlineProbe: @Sendable () async -> Bool = { true }

    init(
        outbox: OutboxReading,
        remote: RemoteSyncGateway,
        retry: SyncRetryPolicy = SyncRetryPolicy(),
        deadLetterThreshold: Int = 3,
        diagnostics: Diagnostics = NoopDiagnostics()
    ) {
        self.outbox = outbox
        self.remote = remote
        self.retry = retry
        self.deadLetterThreshold = deadLetterThreshold
        self.diagnostics = diagnostics
    }

    /// Injects the reachability check used to gate dead-letter strikes (see
    /// `onlineProbe`). Called once by the app root after launch.
    func setOnlineProbe(_ probe: @escaping @Sendable () async -> Bool) {
        onlineProbe = probe
    }

    /// Number of outbox ops held back by a quarantined entity — the status
    /// banner's 「N 条同步失败」 count. Counts every skipped op (not just the
    /// struck one) so the banner stays truthful about how many writes are
    /// parked.
    var deadLetterCount: Int { quarantinedOpIds.count }

    /// Read-only view of the held-back op ids (diagnostics / tests).
    var deadLetteredOpIds: Set<String> { quarantinedOpIds }

    /// Human-readable rows for the failure sheet — one per quarantined entity,
    /// preferring the `name` field from the earliest queued op's patch.
    func deadLetterDisplayItems(pending: [SyncOperation]) -> [DeadLetterDisplayItem] {
        let quarantined = Set(deadLetteredEntities)
        var seen = Set<EntityKey>()
        var items: [DeadLetterDisplayItem] = []
        for op in pending {
            let key = EntityKey(op)
            guard quarantined.contains(key), seen.insert(key).inserted else { continue }
            let name = Self.displayName(from: op.patch)
            items.append(DeadLetterDisplayItem(
                entityType: op.entityType,
                entityId: op.entityId,
                name: name
            ))
        }
        return items.sorted { $0.sortKey < $1.sortKey }
    }

    /// Drops every quarantined op from the outbox and clears the in-memory
    /// dead-letter state. Destructive — the user's unsynced writes are discarded.
    func clearDeadLetters() async {
        let ids = quarantinedOpIds
        guard !ids.isEmpty else { return }
        diagnostics.breadcrumb("sync.deadletter.cleared", ["count": String(ids.count)])
        resetQuarantine()
        try? await outbox.removeAcknowledged(ids)
    }

    private static func displayName(from patch: [String: JSONValue]) -> String? {
        guard case .string(let raw) = patch["name"] else { return nil }
        let trimmed = raw.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pushes the queued outbox operations without overlapping runs. A caller
    /// arriving mid-run requests a trailing rerun and joins the in-flight task
    /// instead of starting a second concurrent run.
    func pushPending() async {
        if let inFlight {
            rerunRequested = true
            await inFlight.value
            return
        }
        await start().value
    }

    /// Starts a run and registers its completion handler. On completion it
    /// clears `inFlight` and, if a rerun was requested during the run, clears
    /// the flag and starts exactly one more run — the trailing rerun that
    /// catches ops enqueued mid-run. Returns the task so `pushPending` can join.
    private func start() -> Task<Void, Never> {
        let task = Task { [self] in
            await pushOnce()
            onRunComplete()
        }
        inFlight = task
        return task
    }

    /// Completion bookkeeping, run on the actor. Kept separate from `start` so
    /// the trailing-rerun decision is a single atomic, actor-isolated step.
    private func onRunComplete() {
        inFlight = nil
        guard rerunRequested else { return }
        rerunRequested = false
        _ = start()
    }

    /// Read-only view of the coalescing state, for deterministic testing of the
    /// single-flight + exactly-one-trailing-rerun guard. `(true, true)` means a
    /// run is in flight and a trailing rerun is already queued — the point at
    /// which any further `pushPending` caller must simply join.
    var coalescingState: (inFlight: Bool, rerunRequested: Bool) {
        (inFlight != nil, rerunRequested)
    }

    /// One snapshot → push → ack cycle with bounded retries. Leaves operations
    /// in the outbox (for the next trigger) on a permanent error or exhausted
    /// retries; never crashes. Mirrors the Dart `_pushPending`, plus the
    /// dead-letter skip + strike accounting (see the actor doc).
    private func pushOnce() async {
        guard let pending = try? await outbox.loadPending(), !pending.isEmpty else {
            // Queue drained externally → nothing can still be failing.
            resetQuarantine()
            return
        }

        // CONNECTIVITY SELF-HEAL: one probe per run feeds both the flip check
        // and the strike gate below. On a false→true flip give the quarantined
        // entities a fresh FIFO replay (see `lastProbedOnline`).
        let isOnline = await onlineProbe()
        if isOnline, lastProbedOnline == false { resetQuarantine() }
        lastProbedOnline = isOnline

        // Prune bookkeeping for entities no longer queued.
        let pendingKeys = Set(pending.map(EntityKey.init))
        deadLetteredEntities.formIntersection(pendingKeys)
        headFailureCounts = headFailureCounts.filter { pendingKeys.contains($0.key) }

        // DEAD-LETTER SKIP: every op of a quarantined entity stays in the
        // outbox (visible as 「同步失败」, retried fresh after a reconnect or
        // next launch) so per-entity FIFO survives, while other entities still
        // drain past the blockage.
        let active = pending.filter { !deadLetteredEntities.contains(EntityKey($0)) }
        quarantinedOpIds = Set(pending.map(\.id)).subtracting(active.map(\.id))
        guard !active.isEmpty else { return }

        for attempt in 1...retry.maxAttempts {
            let acknowledged: Set<String>
            do {
                acknowledged = try await remote.pushOperations(active)
            } catch {
                let lastAttempt = attempt == retry.maxAttempts
                if !isTransientSyncError(error) {
                    // Permanent error thrown (protocol fakes / future gateways
                    // surface these): the FIFO head op is the failure — strike
                    // it regardless of connectivity, then leave the ops queued.
                    if let head = active.first { strike(head, pending: pending) }
                    return
                }
                if lastAttempt {
                    // Transient retries exhausted: leave ops in the outbox to
                    // be retried on the next trigger (reconnect / foreground /
                    // background) — never a strike.
                    return
                }
                try? await Task.sleep(for: retry.delayFor(attempt: attempt))
                continue
            }
            // LOCAL ack bookkeeping sits OUTSIDE the push do/catch: the remote
            // accepted these ops, so a SwiftData delete failure is NOT a sync
            // failure — never a strike. Log and move on; the acked ops stay
            // queued and the next run re-pushes them idempotently (version
            // gate + ignore-duplicates upsert) before retrying the removal.
            do {
                try await outbox.removeAcknowledged(acknowledged)
            } catch {
                Self.logger.error(
                    "outbox removeAcknowledged failed (retried next run): \(String(describing: error), privacy: .public)"
                )
                diagnostics.failure("sync.ack_removal", error: error, [:])
            }
            for op in active where acknowledged.contains(op.id) {
                headFailureCounts[EntityKey(op)] = nil
            }
            // The REAL gateway never throws — it breaks at the first failed
            // op and acks only the ones before it, so a partial ack
            // identifies the failure as the first unacknowledged op in
            // order. The error type is swallowed in the gateway, hence the
            // online gate: only strike when the device is reachable (an
            // offline drop is transient by definition).
            if acknowledged.count < active.count,
               let failed = active.first(where: { !acknowledged.contains($0.id) }),
               isOnline {
                diagnostics.breadcrumb("sync.partial_ack", ["entityType": failed.entityType.rawValue])
                strike(failed, pending: pending)
            }
            return
        }
    }

    /// Drops all dead-letter state — the queue drained externally, the device
    /// reconnected, or (implicitly, being in-memory) the app relaunched.
    private func resetQuarantine() {
        headFailureCounts = [:]
        deadLetteredEntities = []
        quarantinedOpIds = []
    }

    /// One consecutive head-failure strike against the op's entity; at
    /// `deadLetterThreshold` the whole entity is quarantined and every pending
    /// op it owns joins the banner count. A later ack of the same entity clears
    /// the strikes (see `pushOnce`).
    private func strike(_ op: SyncOperation, pending: [SyncOperation]) {
        let key = EntityKey(op)
        let count = (headFailureCounts[key] ?? 0) + 1
        guard count >= deadLetterThreshold else {
            headFailureCounts[key] = count
            diagnostics.breadcrumb(
                "sync.push.strike",
                ["entityType": op.entityType.rawValue, "count": String(count)]
            )
            return
        }
        headFailureCounts[key] = nil
        deadLetteredEntities.insert(key)
        quarantinedOpIds.formUnion(pending.filter { EntityKey($0) == key }.map(\.id))
        diagnostics.failure("sync.deadletter", error: nil, ["entityType": op.entityType.rawValue])
    }
}

/// A quarantined entity with an optional display name from the outbox patch —
/// the failure sheet's row identity.
struct DeadLetterDisplayItem: Sendable, Hashable, Identifiable {
    let entityType: SyncEntityType
    let entityId: String
    let name: String?

    var id: String { "\(entityType.rawValue):\(entityId)" }

    var typeLabel: String { Self.label(for: entityType) }

    var title: String { name ?? entityId }

    var sortKey: String { "\(typeLabel):\(title)" }

    static func label(for type: SyncEntityType) -> String {
        switch type {
        case .inventoryItem: String(localized: "sync.entity.inventoryItem")
        case .shoppingItem: String(localized: "sync.entity.shoppingItem")
        case .customRecipe: String(localized: "sync.entity.customRecipe")
        case .mealPlanEntry: String(localized: "sync.entity.mealPlanEntry")
        case .foodLogEntry: String(localized: "sync.entity.foodLogEntry")
        case .favoriteRecipe: String(localized: "sync.entity.favoriteRecipe")
        case .dietaryPreference: String(localized: "sync.entity.dietaryPreference")
        case .householdConfig: String(localized: "sync.entity.householdConfig")
        }
    }
}
