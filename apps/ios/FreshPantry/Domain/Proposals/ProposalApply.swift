import Foundation

/// Pure apply-time decision logic for confirmed Intake/Deduction proposals,
/// extracted from the Flutter `InventoryNotifier` (`applyIntakeProposals` /
/// `applyDeductionProposals` in `lib/providers/inventory_provider.dart`).
///
/// In Flutter this logic is interleaved with persistence + sync side-effects
/// inside a Riverpod notifier. Here the PURE decision is isolated: given the
/// confirmed proposals + current inventory, it produces the resulting inventory
/// list plus the sync intents the caller (a `@MainActor` controller) translates
/// into outbox writes — so the rules are testable without persistence.
///
/// PARITY INVARIANT (sync-critical): merge targets (Intake) and chosen rows
/// (Deduction) are RE-RESOLVED here by stable identity against the live
/// inventory — never the positional index/`mergeTargetId` captured at compute
/// time. `IngredientIdentity` is the SOLE arbiter at BOTH compute and apply.
enum ProposalApply {
    // MARK: - Sync intents

    /// The minimal description of one inventory-mutation's sync delta, mirroring
    /// the `SyncEnqueueOp` the Flutter apply enqueues (the controller layer fills
    /// in householdId/clientId/createdAt + the JSON patch when persisting).
    struct SyncIntent: Equatable, Sendable {
        var entityId: String
        var operation: SyncOperationType
        /// nil for `.create` (no prior server version to base on), else the
        /// existing row's `remoteVersion`.
        var baseVersion: Int?
    }

    // MARK: - Intake

    struct IntakeApplyResult: Equatable, Sendable {
        /// The resulting inventory list after applying the selected proposals.
        var inventory: [Ingredient]
        /// Ids of the proposals that actually applied (so the caller cleans up
        /// only those source rows — e.g. the shopping list).
        var appliedIds: Set<String>
        /// One intent per applied proposal, in application order.
        var syncIntents: [SyncIntent]
    }

    /// Applies the selected Intake proposals against `inventory`.
    ///
    /// Re-resolves each merge target against the EVOLVING inventory by the domain
    /// identity rule — never the stale positional index captured at proposal
    /// time. A perishable / non-matching item falls back to a new row, which can
    /// never corrupt an unrelated row.
    ///
    /// - Parameters:
    ///   - now: injected for deterministic addedAt/expiry derivation.
    ///   - idGenerator: injected sync-UUID minter (defaults to a v4-style UUID),
    ///     mirroring Flutter `_withSyncId`: a non-UUID id is replaced, a row that
    ///     already carries a UUID keeps it.
    static func applyIntakeProposals(
        _ proposals: [IntakeProposal],
        inventory: [Ingredient],
        now: Date = Date(),
        idGenerator: () -> String = { UUID().uuidString.lowercased() }
    ) -> IntakeApplyResult {
        var current = inventory
        var syncIntents: [SyncIntent] = []
        var appliedIds: Set<String> = []

        for p in proposals {
            if !p.selected { continue }

            let mergeIndex: Int = p.action == .mergeInto
                ? IngredientIdentity.resolveMergeTarget(
                    name: p.name,
                    unit: p.unit,
                    storage: p.storage,
                    category: p.category,
                    inventory: current
                )
                : -1

            // nil when there is no live target OR either quantity is non-numeric
            // (sumQuantity's gate) — such a row degrades to an independent new
            // row rather than summing "适量" as 0 and silently dropping it.
            let summed: String? = mergeIndex >= 0
                ? sumQuantity(current[mergeIndex].quantity, p.quantity)
                : nil

            guard let summed else {
                let item = withSyncId(ingredientFromProposal(p, now: now), idGenerator: idGenerator)
                current.append(item)
                syncIntents.append(
                    SyncIntent(entityId: item.id, operation: .create, baseVersion: nil)
                )
                appliedIds.insert(p.id)
                continue
            }

            let existing = current[mergeIndex]
            let updatedItem = IngredientNormalizer.refreshFreshness(
                existing.copyWith(quantity: summed),
                now: now
            )
            current[mergeIndex] = updatedItem
            syncIntents.append(
                SyncIntent(
                    entityId: updatedItem.id,
                    operation: .intake,
                    baseVersion: existing.remoteVersion
                )
            )
            appliedIds.insert(p.id)
        }

        return IntakeApplyResult(inventory: current, appliedIds: appliedIds, syncIntents: syncIntents)
    }

    // MARK: - Deduction

    struct DeductionApplyResult: Equatable, Sendable {
        /// The resulting inventory list after applying the selected deductions.
        var inventory: [Ingredient]
        /// Rows the deduction emptied out — each is recorded as a consumed
        /// departure in the food log by the caller once the write lands.
        var consumedDepartures: [Ingredient]
        /// One intent per mutated/removed row.
        var syncIntents: [SyncIntent]
    }

    /// Applies the selected Deduction proposals against `inventory`.
    ///
    /// Resolves every selected deduction to a LIVE row index by stable identity,
    /// aggregates per row (two proposals resolving to the same row net into one
    /// deduction), then reduces or removes. Non-numeric stock is left untouched
    /// (never coerced to 0 and deleted). A deduction never silently applies 0.
    static func applyDeductionProposals(
        _ proposals: [DeductionProposal],
        inventory: [Ingredient],
        now: Date = Date()
    ) -> DeductionApplyResult {
        var current = inventory

        // Aggregate amounts per resolved live row index. Preserve first-seen
        // order so the resulting sync intents are deterministic (Dart relies on
        // Map insertion-order iteration).
        var deductByIndex: [Int: Double] = [:]
        var indexOrder: [Int] = []
        for p in proposals {
            if !p.selected { continue }
            if p.action == .skip { continue }
            guard let chosen = chosenCandidate(p) else { continue }
            guard let amount = QuantityText.numeric(p.deductAmount), amount > 0 else { continue }
            let index = resolveDeductionRow(current, chosen)
            if index < 0 { continue } // row gone / ambiguous -> skip wrong-row risk
            if deductByIndex[index] == nil { indexOrder.append(index) }
            deductByIndex[index, default: 0] += amount
        }

        var removalIndices: Set<Int> = []
        var syncIntents: [SyncIntent] = []
        var consumedDepartures: [Ingredient] = []

        for index in indexOrder {
            let totalDeduct = deductByIndex[index]!
            let existing = current[index]
            // Non-numeric stock (e.g. "适量", "半盒") must not be coerced to 0 and
            // deleted — leave the row untouched rather than wiping real inventory.
            guard let existingQty = QuantityText.numeric(existing.quantity) else { continue }
            let remaining = existingQty - totalDeduct
            if remaining <= 0 {
                removalIndices.insert(index)
                consumedDepartures.append(existing)
                syncIntents.append(
                    SyncIntent(
                        entityId: existing.id,
                        operation: .delete,
                        baseVersion: existing.remoteVersion
                    )
                )
            } else {
                let updatedItem = IngredientNormalizer.refreshFreshness(
                    existing.copyWith(quantity: QuantityText.formatQuantity(remaining)),
                    now: now
                )
                current[index] = updatedItem
                syncIntents.append(
                    SyncIntent(
                        entityId: updatedItem.id,
                        operation: .deduction,
                        baseVersion: existing.remoteVersion
                    )
                )
            }
        }

        if !removalIndices.isEmpty {
            for idx in removalIndices.sorted(by: >) {
                current.remove(at: idx)
            }
        }

        return DeductionApplyResult(
            inventory: current,
            consumedDepartures: consumedDepartures,
            syncIntents: syncIntents
        )
    }

    // MARK: - Helpers (ported from InventoryNotifier privates)

    /// The chosen candidate of a deduction, matched by its captured positional
    /// `inventoryRowIndex == chosenIndex`. nil when the chosen index is unknown.
    static func chosenCandidate(_ p: DeductionProposal) -> DeductionCandidate? {
        p.candidates.first { $0.inventoryRowIndex == p.chosenIndex }
    }

    /// Resolves the live inventory index for a chosen deduction candidate by
    /// stable identity, defending against list reordering between proposal
    /// creation and apply. Prefers the row id (household-synced rows); for
    /// local-only rows whose id is empty, falls back to the recorded positional
    /// index guarded by the captured row name. Returns -1 when the target can no
    /// longer be uniquely identified.
    static func resolveDeductionRow(_ current: [Ingredient], _ chosen: DeductionCandidate) -> Int {
        let id = chosen.inventoryRowId.trimmed
        if !id.isEmpty {
            var matches: [Int] = []
            for i in current.indices where current[i].id == id { matches.append(i) }
            if matches.count == 1 { return matches.first! }
            // 0 or ambiguous by id -> fall through to the name-guarded index path.
        }
        let index = chosen.inventoryRowIndex
        if index < 0 || index >= current.count { return -1 }
        let expectedName = chosen.inventoryRowName.trimmed.lowercased()
        if expectedName.isEmpty {
            return index // no captured identity -> trust index
        }
        if current[index].name.trimmed.lowercased() == expectedName { return index }
        // Index drifted; recover only if exactly one row still carries the name.
        var byName: [Int] = []
        for j in current.indices where current[j].name.trimmed.lowercased() == expectedName {
            byName.append(j)
        }
        return byName.count == 1 ? byName.first! : -1
    }

    /// Builds a fresh inventory `Ingredient` from an intake proposal (mirrors
    /// `_ingredientFromProposal`): derives expiry from shelfLifeDays, normalizes
    /// the category, then refreshes freshness/state/label.
    static func ingredientFromProposal(_ p: IntakeProposal, now: Date = Date()) -> Ingredient {
        let shelf = p.shelfLifeDays
        let addedAt = now
        let expiryDate = shelf.map { addedAt.addingTimeInterval(TimeInterval($0 * 86400)) }
        return IngredientNormalizer.refreshFreshness(
            IngredientNormalizer.normalizeCategory(
                Ingredient(
                    name: p.name,
                    quantity: p.quantity,
                    unit: p.unit,
                    imageUrl: "",
                    freshnessPercent: 1.0,
                    state: .fresh,
                    category: p.category,
                    barcode: p.barcode?.trimmed.isEmpty == false ? p.barcode?.trimmed : nil,
                    storage: p.storage,
                    expiryDate: expiryDate,
                    addedAt: addedAt,
                    shelfLifeDays: shelf,
                    tags: p.tags
                )
            ),
            now: now
        )
    }

    /// Sums two free-text quantities via the domain numeric gate
    /// (`QuantityText.numeric`), formatted by `formatQuantity` (≤2dp, no float
    /// artifacts). nil when EITHER side is non-numeric — a non-numeric quantity
    /// never participates in arithmetic; the caller falls back to a separate
    /// row instead of silently summing "适量" as 0.
    static func sumQuantity(_ a: String, _ b: String) -> String? {
        guard let na = QuantityText.numeric(a), let nb = QuantityText.numeric(b) else {
            return nil
        }
        return QuantityText.formatQuantity(na + nb)
    }

    /// Mirrors Flutter `_withSyncId`: keep an existing UUID id, else mint a new
    /// one. Local-only rows (empty / non-UUID id) get a stable sync UUID so each
    /// household transition can't clone the row.
    static func withSyncId(_ item: Ingredient, idGenerator: () -> String) -> Ingredient {
        if isUuid(item.id) { return item }
        return item.copyWith(id: idGenerator())
    }

    /// Canonical UUID-v4 shape check, ported from `lib/sync/sync_ids.dart`.
    static func isUuid(_ value: String) -> Bool {
        uuidRegex.firstMatch(
            in: value,
            options: [],
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
    }

    private static let uuidRegex = try! NSRegularExpression(
        pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
    )
}
