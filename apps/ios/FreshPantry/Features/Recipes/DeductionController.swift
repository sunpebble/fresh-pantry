import Foundation
import os

/// Persistence layer over the pure `ProposalApply` deduction decision logic — the
/// `@MainActor` seam between the DeductionReview UI ("做菜" cook flow) and the
/// repositories. The mirror of `IntakeController` for the cook → deduction path.
///
/// The decision (identity re-resolution, per-row aggregation, non-numeric-stock
/// guard, emptied-row collection) is owned entirely by
/// `ProposalApply.applyDeductionProposals`; this controller only loads the live
/// inventory, hands it to that pure function, persists the reduced inventory, and
/// auto-logs a CONSUMED food-departure for each row the cook emptied (the
/// waste-stats source of truth for the cook flow). Keeping the rules out of here
/// means they stay testable without SwiftData.
@MainActor
final class DeductionController {
    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "food-log")

    private let inventoryRepository: InventoryRepository
    private let foodLogRepository: FoodLogRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?

    init(
        inventoryRepository: InventoryRepository,
        foodLogRepository: FoodLogRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil
    ) {
        self.inventoryRepository = inventoryRepository
        self.foodLogRepository = foodLogRepository
        self.householdID = householdID
        self.syncWriter = syncWriter
    }

    /// Outcome of applying a batch of deduction proposals, enough for the caller
    /// to show feedback ("已扣减 N 项库存…").
    struct ApplyOutcome: Equatable {
        /// Rows whose stock was reduced (not emptied) by this apply.
        var reducedCount: Int
        /// Rows the cook emptied out — each was removed from inventory and logged
        /// as a consumed departure in the food log.
        var consumedCount: Int
        /// Whether the apply persisted successfully. `false` leaves inventory and
        /// the food log untouched (the load/save threw); the caller surfaces retry.
        var persisted: Bool

        /// Total inventory rows the deduction touched (reduced + emptied).
        var affectedCount: Int { reducedCount + consumedCount }

        static let failed = ApplyOutcome(reducedCount: 0, consumedCount: 0, persisted: false)
    }

    /// Loads the live inventory, applies the SELECTED deduct proposals through the
    /// pure `ProposalApply` pipeline (which re-resolves each chosen row by stable
    /// identity at apply time, aggregates per row, and never coerces non-numeric
    /// stock to 0), persists the reduced inventory, then appends one CONSUMED
    /// `FoodLogEntry` per emptied row.
    ///
    /// On a load/persist failure nothing is mutated and `.failed` is returned —
    /// no silent partial write. The food-log append happens only AFTER the
    /// inventory save lands (mirrors Flutter's `_logDeparture` ordering); a
    /// food-log write failure does not roll back the already-committed inventory
    /// reduction — it's logged for diagnosis, and the entry still syncs remotely
    /// (a household pull brings it back into the local log).
    func apply(_ proposals: [DeductionProposal], now: Date = Date()) async -> ApplyOutcome {
        let inventory: [Ingredient]
        do {
            inventory = try await inventoryRepository.loadAllFor(householdID)
        } catch {
            return .failed
        }

        let result = ProposalApply.applyDeductionProposals(proposals, inventory: inventory, now: now)

        // Nothing resolved to a real deduction (all skipped / non-numeric / no
        // match) — a no-op success that leaves inventory untouched.
        if result.inventory == inventory && result.consumedDepartures.isEmpty {
            return ApplyOutcome(reducedCount: 0, consumedCount: 0, persisted: true)
        }

        do {
            try await inventoryRepository.saveItems(householdID, result.inventory)
        } catch {
            return .failed
        }

        // Auto-log a CONSUMED departure per emptied row (the cook flow's only
        // waste-stats input). `wasExpiring` snapshots whether the eaten batch was
        // already past fresh (state ∈ {expiringSoon, urgent, expired}), so the
        // stats can credit "抢救临期". Mirrors Flutter `_logDeparture(item, consumed)`.
        var loggedEntries: [FoodLogEntry] = []
        for departure in result.consumedDepartures {
            let entry = FoodLogEntry(
                id: FoodLogEntry.newId(),
                name: departure.name,
                category: FoodCategories.normalize(departure.category) ?? FoodCategories.other,
                outcome: .consumed,
                loggedAt: now,
                wasExpiring: departure.state != .fresh
            )
            do {
                try await foodLogRepository.append(householdID, entry)
            } catch {
                // Rare SwiftData write failure: leave a diagnostic trail (never
                // silently swallow) but keep the entry in `loggedEntries` — the
                // remote create below is the rescue channel (the entry pulls back
                // into the local log on the next sync cycle).
                Self.logger.error("FoodLog append failed for cook departure: \(error.localizedDescription, privacy: .public)")
            }
            loggedEntries.append(entry)
        }

        // OUTBOX SEAM: enqueue one outbox op per intent AFTER the inventory save +
        // food-log appends land. A `.delete` intent's row is an emptied departure
        // (its `deletedAt` is nil locally — the gateway derives `deleted_at` from
        // the op); any other op's row is in the reduced inventory. patch = the
        // row's JSON. No-op when no household is selected. FoodLog departures now
        // sync too (append-only creates appended below).
        var ops: [SyncWriter.PendingOp] = result.syncIntents.compactMap { intent in
            let row: Ingredient?
            if intent.operation == .delete {
                row = result.consumedDepartures.first { $0.id == intent.entityId }
            } else {
                row = result.inventory.first { $0.id == intent.entityId }
            }
            guard let row else { return nil }
            return SyncWriter.PendingOp(row, type: .inventoryItem, operation: intent.operation, baseVersion: intent.baseVersion)
        }
        // FoodLog departures now sync to the household (append-only creates).
        ops.append(contentsOf: loggedEntries.compactMap { entry in
            SyncWriter.PendingOp(entry, type: .foodLogEntry, operation: .create, baseVersion: entry.remoteVersion)
        })
        await syncWriter?.enqueueBatch(ops)

        return ApplyOutcome(
            reducedCount: result.syncIntents.count - result.consumedDepartures.count,
            consumedCount: result.consumedDepartures.count,
            persisted: true
        )
    }
}
