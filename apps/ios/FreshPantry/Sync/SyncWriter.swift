import Foundation

/// The single seam every mutating store / controller uses to record an outbox
/// op then kick a (coalesced) push. Mirrors the Flutter `SyncEnqueue` mixin in
/// `lib/sync/sync_enqueue.dart`.
///
/// LOCAL-FIRST CONTRACT: enqueue is a NO-OP (not a dropped write) when no
/// household is selected (`selectedHouseholdId` empty → personal/local-only
/// mode) or the op's `entityId` is blank — mirrors Dart `enqueueSync`'s empty
/// household / empty entity guards. A no-op here is the correct local-first
/// behaviour, not a swallowed failure.
///
/// `coordinator` is nil in local-only mode (no `SupabaseClient`): ops are still
/// recorded so they flush once a backend / household is wired, but no push runs.
@MainActor
final class SyncWriter {
    /// One outbox op to record. The store/controller fills in the wire patch
    /// (`DomainJSON.valueMap` of the resulting row) and the optimistic-lock
    /// `baseVersion` (the mutated row's `remoteVersion`; nil for a fresh create).
    struct PendingOp {
        var entityType: SyncEntityType
        var entityId: String
        var operation: SyncOperationType
        var patch: [String: JSONValue]
        var baseVersion: Int?
    }

    private let outbox: SyncOutboxRepository
    /// nil in local-only mode (no client) — ops are recorded but never pushed.
    private let coordinator: SyncCoordinator?
    private let session: SyncSession

    init(outbox: SyncOutboxRepository, coordinator: SyncCoordinator?, session: SyncSession) {
        self.outbox = outbox
        self.coordinator = coordinator
        self.session = session
    }

    /// Records ONE op then kicks a (coalesced) push. No-op — the correct
    /// local-first behaviour, not a dropped write — when no household is selected
    /// or `entityId` is blank.
    func enqueue(
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperationType,
        patch: [String: JSONValue],
        baseVersion: Int?
    ) async {
        await enqueueBatch([
            PendingOp(
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patch: patch,
                baseVersion: baseVersion
            )
        ])
    }

    /// Records each op IN ORDER (no per-op push), then ONE trailing push. Used by
    /// the Intake/Deduction apply that lands multiple rows. Same no-op guard as
    /// `enqueue`: skips entirely when no household is selected, and skips any
    /// individual op whose `entityId` is blank.
    func enqueueBatch(_ ops: [PendingOp]) async {
        guard !session.selectedHouseholdId.isEmpty else { return }

        var recordedAny = false
        for op in ops {
            guard !op.entityId.trimmed.isEmpty else { continue }
            let operation = SyncOperation(
                id: UUID().uuidString.lowercased(),
                householdId: session.selectedHouseholdId,
                entityType: op.entityType,
                entityId: op.entityId,
                operation: op.operation,
                patch: op.patch,
                baseVersion: op.baseVersion,
                clientId: session.clientId,
                createdAt: Date()
            )
            do {
                try await outbox.enqueue(operation)
                recordedAny = true
            } catch {
                // SwiftData write failed (disk full, migration mismatch, …).
                // Do NOT set recordedAny — this op was never persisted; skipping
                // the trailing push avoids a spurious badge-clear on a lost write.
            }
        }

        // Fire-and-forget a single trailing push; the coordinator coalesces
        // concurrent pushes into one in-flight run + at most one trailing rerun.
        // After it finishes, pulse `pendingSyncRevision` so the per-item 待同步
        // badges re-read the outbox and converge (a successful push clears the
        // op, but nothing else would refresh the badge until the next foreground
        // / reconnect). Bumping regardless of outcome is correct: the refresh
        // re-reads reality, keeping the badge lit if ops remain.
        guard recordedAny else { return }
        let coordinator = coordinator
        let session = session
        Task { @MainActor in
            await coordinator?.pushPending()
            session.bumpPendingSyncRevision()
        }
    }
}
