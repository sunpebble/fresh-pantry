import Foundation

/// Persistence layer over the pure `ProposalApply` intake decision logic — the
/// `@MainActor` seam between the Review/Add-form UI and the repository.
///
/// The decision (merge-vs-new-row, identity re-resolution, freshness refresh) is
/// owned entirely by `ProposalApply.applyIntakeProposals`; this controller only
/// loads the live inventory, hands it to that pure function, persists the
/// result, and bumps the frequency memory for each newly-added row. Keeping the
/// rules out of here means they stay testable without SwiftData.
@MainActor
final class IntakeController {
    private let repository: InventoryRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?
    /// Optional Pro-state seam. Nil keeps lower-level tests and previews unlimited.
    private let isPro: (() -> Bool)?

    init(
        repository: InventoryRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil,
        isPro: (() -> Bool)? = nil
    ) {
        self.repository = repository
        self.householdID = householdID
        self.syncWriter = syncWriter
        self.isPro = isPro
    }

    /// Outcome of applying a batch of intake proposals, enough for the caller to
    /// refresh the list + show feedback (and, in the shopping flow, clean up only
    /// the source rows that actually landed).
    struct ApplyOutcome: Equatable {
        /// Proposals that actually applied (their ids), so the shopping flow can
        /// remove only the source rows that entered inventory.
        var appliedIds: Set<String>
        /// Inventory rows newly created by this apply (merges excluded). The
        /// controller already recorded each one in the add-history frequency
        /// memory; kept on the outcome for tests/inspection — note the
        /// "已入库 N 项" feedback counts `appliedIds`, not this.
        var addedItems: [Ingredient]
        /// Whether the apply persisted successfully. `false` leaves inventory
        /// untouched (the save threw); the caller should surface a retry.
        var persisted: Bool
        /// True when a free user tried to create rows past the inventory cap.
        var limitReached: Bool = false

        static let failed = ApplyOutcome(appliedIds: [], addedItems: [], persisted: false)
        static let limitBlocked = ApplyOutcome(appliedIds: [], addedItems: [], persisted: false, limitReached: true)
    }

    /// Loads the live inventory, applies the SELECTED proposals through the pure
    /// `ProposalApply` pipeline (which re-resolves merge targets by identity at
    /// apply time), persists the full new scope, and records each newly-added row
    /// in the add-history frequency memory.
    ///
    /// On a load/persist failure nothing is mutated and `.failed` is returned —
    /// no silent partial write.
    func apply(_ proposals: [IntakeProposal]) async -> ApplyOutcome {
        let inventory: [Ingredient]
        do {
            inventory = try await repository.loadAllFor(householdID)
        } catch {
            return .failed
        }

        // Snapshot the pre-apply ids so we can tell which result rows are NEW
        // (vs merged into an existing row) for the frequency-memory bump.
        let existingIds = Set(inventory.map(\.id))

        let result = ProposalApply.applyIntakeProposals(proposals, inventory: inventory)
        if result.appliedIds.isEmpty {
            // Nothing selected / nothing resolved — a no-op success.
            return ApplyOutcome(appliedIds: [], addedItems: [], persisted: true)
        }

        let addedItems = result.inventory.filter { !existingIds.contains($0.id) }
        if let isPro, !addedItems.isEmpty {
            // Check the last row this apply would create: 49 + 1 is allowed,
            // while 49 + 2 (or any write starting at 50+) is blocked.
            let lastCreatedRowIndex = inventory.count + addedItems.count - 1
            if FreeTier.inventoryLimitReached(isPro: isPro(), currentCount: lastCreatedRowIndex) {
                return .limitBlocked
            }
        }

        do {
            try await repository.saveItems(householdID, result.inventory)
        } catch {
            return .failed
        }

        // Frequency memory: only newly-added rows count as an "addition" (a merge
        // bumps an existing batch's quantity, not the add-history). ONE batched
        // read+write — `recordAddition`-per-item whole-rewrote the history every
        // call (O(N²) over the batch).
        try? await repository.recordAdditions(addedItems)

        // OUTBOX SEAM: enqueue one outbox op per applied intent AFTER the local
        // save + frequency bump land. Each patch is the resulting inventory row's
        // JSON (the wire form the gateway consumes); a `.create`/`.intake` carries
        // the intent's `baseVersion` (nil for a new row, else the prior version).
        // No-op when no household is selected — the writer's local-first guard.
        let ops: [SyncWriter.PendingOp] = result.syncIntents.compactMap { intent in
            guard let row = result.inventory.first(where: { $0.id == intent.entityId }) else { return nil }
            return SyncWriter.PendingOp(row, type: .inventoryItem, operation: intent.operation, baseVersion: intent.baseVersion)
        }
        await syncWriter?.enqueueBatch(ops)

        return ApplyOutcome(
            appliedIds: result.appliedIds,
            addedItems: addedItems,
            persisted: true
        )
    }
}
