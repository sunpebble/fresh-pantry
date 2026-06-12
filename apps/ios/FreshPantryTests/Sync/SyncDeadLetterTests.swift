import Foundation
import Testing
@testable import FreshPantry

/// Dead-letter (poison-op quarantine) tests for `SyncCoordinator`, driven through
/// deterministic fakes (NEVER the Supabase SDK or SwiftData). The contract under
/// test: a permanently-failing op at the FIFO head must stop blocking OTHER
/// entities after `deadLetterThreshold` consecutive failures — but its own
/// entity's later ops must be held back with it (per-entity FIFO survives, so a
/// relaunch replay can't roll back newer writes) — while transient / offline
/// failures must never be quarantined (leave-in-outbox self-heals them) and an
/// offline→online flip grants quarantined entities a fresh replay.
struct SyncDeadLetterTests {
    // MARK: - Fakes

    /// A validation/auth failure — the permanent (non-retryable) error class.
    private struct ValidationError: Error {}

    /// A local persistence failure (SwiftData delete/save) — NOT a sync error,
    /// and (like SwiftData errors) carries no network-ish substring, so the
    /// transient classifier calls it permanent.
    private struct BookkeepingError: Error {}

    /// Mutable connectivity flag backing a scripted `onlineProbe`.
    private actor OnlineFlag {
        private(set) var isOnline: Bool

        init(_ value: Bool) { isOnline = value }

        func set(_ value: Bool) { isOnline = value }
    }

    private func operation(
        id: String,
        householdId: String = "home",
        entityType: SyncEntityType = .inventoryItem,
        entityId: String = "ing_1"
    ) -> SyncOperation {
        SyncOperation(
            id: id, householdId: householdId, entityType: entityType,
            entityId: entityId, operation: .create, patch: [:],
            clientId: "client", createdAt: Date(timeIntervalSince1970: 1000)
        )
    }

    /// Deterministic in-memory outbox. Records the ack sets it was asked to drop
    /// and supports an external clear (simulating the queue being drained
    /// elsewhere) for the bookkeeping-reset test, plus a throwing-removal mode
    /// (simulating a SwiftData delete failure) for the misattribution test.
    private actor FakeOutbox: OutboxReading {
        private var pending: [SyncOperation]
        private var removeThrows = false

        init(pending: [SyncOperation]) { self.pending = pending }

        func loadPending() async throws -> [SyncOperation] { pending }

        func removeAcknowledged(_ ids: Set<String>) async throws {
            if removeThrows { throw BookkeepingError() }
            pending.removeAll { ids.contains($0.id) }
        }

        func clearAll() { pending = [] }

        func setRemoveThrows(_ value: Bool) { removeThrows = value }

        func remainingIDs() -> Set<String> { Set(pending.map(\.id)) }
    }

    /// Gateway that records every pushed batch and replays a scripted
    /// result/throw per call. Mirrors the REAL gateway's contract when scripted
    /// with `.acknowledge`: FIFO + stop-on-first-failure means a partial ack's
    /// first unacknowledged op is the failed one.
    private actor FakeGateway: RemoteSyncGateway {
        enum Outcome: Sendable {
            case acknowledge(Set<String>)
            case fail(any Error)
        }

        private var script: [Outcome]
        private(set) var pushedBatches: [[SyncOperation]] = []

        init(script: [Outcome]) { self.script = script }

        var pushCount: Int { pushedBatches.count }

        func batchIDs(_ index: Int) -> [String] { pushedBatches[index].map(\.id) }

        func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String> {
            pushedBatches.append(ops)
            let outcome = script.isEmpty ? Outcome.acknowledge([]) : script.removeFirst()
            switch outcome {
            case .acknowledge(let ids): return ids
            case .fail(let error): throw error
            }
        }
    }

    // MARK: - Quarantine via silent partial ack (the real gateway's failure shape)

    @Test func partialAckHeadFailureQuarantinesAfterThresholdAndUnblocksQueue() async {
        // The live op targets a DIFFERENT entity — quarantine is per entity, so
        // only another entity's op may overtake the poisoned head.
        let outbox = FakeOutbox(pending: [
            operation(id: "op_poison", entityId: "ing_1"),
            operation(id: "op_live", entityId: "ing_2"),
        ])
        // Three runs fail at the head (empty ack), then the unblocked run acks
        // the live op.
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge([]),
            .acknowledge(["op_live"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)

        await coordinator.pushPending()
        await coordinator.pushPending()
        #expect(await coordinator.deadLetterCount == 0) // two strikes — not yet
        await coordinator.pushPending()
        #expect(await coordinator.deadLetterCount == 1) // third strike quarantines
        #expect(await coordinator.deadLetteredOpIds == ["op_poison"])

        // The next run skips the quarantined entity: only the live one is
        // pushed, acked, and removed — the poison op no longer head-blocks
        // other entities.
        await coordinator.pushPending()
        #expect(await gateway.batchIDs(3) == ["op_live"])
        #expect(await outbox.remainingIDs() == ["op_poison"])
        #expect(await coordinator.deadLetterCount == 1)
    }

    @Test func quarantineHoldsBackLaterOpsOfTheSameEntity() async {
        // Two ops for ing_1 (the poisoned entity) and one for ing_2. When ing_1
        // is quarantined, BOTH its ops must be skipped — letting op_b overtake
        // op_a would break per-entity FIFO, and op_a's relaunch replay would
        // then roll back op_b's write via the client-wins merge.
        let outbox = FakeOutbox(pending: [
            operation(id: "op_a", entityId: "ing_1"),
            operation(id: "op_b", entityId: "ing_1"),
            operation(id: "op_c", entityId: "ing_2"),
        ])
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge([]),
            .acknowledge(["op_c"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)

        for _ in 0..<3 { await coordinator.pushPending() }
        // The banner counts EVERY held-back op of the entity, not just the
        // struck head.
        #expect(await coordinator.deadLetterCount == 2)
        #expect(await coordinator.deadLetteredOpIds == ["op_a", "op_b"])

        // The next run pushes only the healthy entity; both ing_1 ops stay
        // queued in order for the next-session replay.
        await coordinator.pushPending()
        #expect(await gateway.batchIDs(3) == ["op_c"])
        #expect(await outbox.remainingIDs() == ["op_a", "op_b"])
    }

    @Test func ackClearsStrikesBeforeQuarantine() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        // Two head failures, then the op succeeds — it must NOT be quarantined.
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge(["op_1"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)

        await coordinator.pushPending()
        await coordinator.pushPending()
        await coordinator.pushPending()

        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs().isEmpty)
    }

    @Test func offlinePartialAckNeverStrikes() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge([]), .acknowledge([]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)
        // Device offline: a silent head failure is indistinguishable from a
        // network drop, so it must not count toward quarantine.
        await coordinator.setOnlineProbe { false }

        for _ in 0..<4 { await coordinator.pushPending() }

        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs() == ["op_1"]) // left for the next trigger
    }

    @Test func reconnectFlipClearsQuarantineForAFreshReplay() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge([]),
            .acknowledge(["op_1"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)
        let online = OnlineFlag(true)
        await coordinator.setOnlineProbe { await online.isOnline }

        // Quarantined while online (e.g. a transient server fault the device-
        // level probe can't see).
        for _ in 0..<3 { await coordinator.pushPending() }
        #expect(await coordinator.deadLetterCount == 1)

        // Offline run: the quarantined entity is skipped, nothing hits the wire.
        await online.set(false)
        await coordinator.pushPending()
        #expect(await gateway.pushCount == 3)
        #expect(await coordinator.deadLetterCount == 1)

        // Reconnect: the offline→online flip clears the quarantine, the op gets
        // a fresh FIFO replay, the (recovered) server acks it.
        await online.set(true)
        await coordinator.pushPending()
        #expect(await gateway.pushCount == 4)
        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs().isEmpty)
    }

    // MARK: - Quarantine via thrown permanent error (protocol fakes / future gateways)

    @Test func thrownPermanentErrorStrikesHeadEvenOffline() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [
            .fail(ValidationError()), .fail(ValidationError()), .fail(ValidationError()),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)
        // A THROWN error carries its type — permanence is known, so the online
        // gate (for silent failures) must not apply.
        await coordinator.setOnlineProbe { false }

        for _ in 0..<3 { await coordinator.pushPending() }
        #expect(await coordinator.deadLetterCount == 1)

        // Everything pending is quarantined → the next run never hits the wire.
        await coordinator.pushPending()
        #expect(await gateway.pushCount == 3)
        #expect(await outbox.remainingIDs() == ["op_1"])
    }

    @Test func transientThrowNeverStrikes() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        // Every attempt of every run fails transiently.
        let gateway = FakeGateway(script: (0..<8).map { _ in FakeGateway.Outcome.fail(URLError(.timedOut)) })
        let retry = SyncRetryPolicy(
            maxAttempts: 2, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2))
        let coordinator = SyncCoordinator(
            outbox: outbox, remote: gateway, retry: retry, deadLetterThreshold: 2)

        for _ in 0..<3 { await coordinator.pushPending() }

        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs() == ["op_1"])
    }

    // MARK: - Local bookkeeping failures are not sync failures

    @Test func ackRemovalFailureNeverStrikesTheAcknowledgedHead() async {
        // The remote acks the op every run, but the LOCAL outbox delete throws
        // (SwiftData failure). That must never strike — the op did not fail to
        // sync — even past the threshold; it stays queued for an idempotent
        // re-push until the removal succeeds.
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        await outbox.setRemoveThrows(true)
        let gateway = FakeGateway(script: [
            .acknowledge(["op_1"]), .acknowledge(["op_1"]), .acknowledge(["op_1"]),
            .acknowledge(["op_1"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)

        for _ in 0..<3 { await coordinator.pushPending() }
        #expect(await coordinator.deadLetterCount == 0)
        #expect(await gateway.pushCount == 3) // re-pushed each run, never quarantined
        #expect(await outbox.remainingIDs() == ["op_1"]) // removal kept failing

        // Once the local store recovers, the next run drains the backlog.
        await outbox.setRemoveThrows(false)
        await coordinator.pushPending()
        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs().isEmpty)
    }

    // MARK: - Bookkeeping hygiene

    @Test func clearDeadLettersRemovesQuarantinedOpsFromOutbox() async {
        let outbox = FakeOutbox(pending: [
            operation(id: "op_a", entityId: "ing_1"),
            operation(id: "op_b", entityId: "ing_2"),
        ])
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]), .acknowledge([]),
            .acknowledge(["op_b"]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 3)

        for _ in 0..<3 { await coordinator.pushPending() }
        #expect(await coordinator.deadLetterCount == 1)

        await coordinator.clearDeadLetters()
        #expect(await coordinator.deadLetterCount == 0)
        #expect(await outbox.remainingIDs() == ["op_b"])
    }

    @Test func externallyDrainedOutboxResetsQuarantine() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [
            .acknowledge([]), .acknowledge([]),
        ])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, deadLetterThreshold: 2)

        await coordinator.pushPending()
        await coordinator.pushPending()
        #expect(await coordinator.deadLetterCount == 1)

        // The queue is cleared elsewhere → the quarantined id no longer exists,
        // so the failed count must drop back to zero on the next run.
        await outbox.clearAll()
        await coordinator.pushPending()
        #expect(await coordinator.deadLetterCount == 0)
    }
}
