import Foundation

/// Builds `IntakeProposal` rows from AI ingredient drafts or shopping items,
/// resolving the default merge/new-row action against live inventory. Ported
/// VERBATIM from `lib/services/intake_proposal_factory.dart`.
///
/// Owns the `ix_` shopping-derived proposal-id scheme (single owner — the
/// shopping flow uses it to know which source rows applied). `mergeTargetId` is
/// the inventory list INDEX as a string at compute time, NOT a stable id —
/// callers MUST re-resolve by identity before applying.
enum IntakeProposalFactory {
    static func fromDrafts(
        _ drafts: [IngredientDraft],
        _ inventory: [Ingredient]
    ) -> [IntakeProposal] {
        drafts.map { d in
            build(
                id: d.id,
                name: d.name.value,
                quantity: d.quantity.value,
                unit: d.unit.value,
                category: d.category.value,
                storage: d.storage.value ?? .fridge,
                shelfLifeDays: d.shelfLifeDays.value,
                inventory: inventory
            )
        }
    }

    /// Whether a parsed batch should bypass Review and go straight to the richer
    /// prefill add-form: exactly one proposal that is a brand-new row. A single
    /// proposal that would merge must still go through Review (the append-only
    /// prefill form would otherwise create a duplicate row).
    static func isSinglePrefill(_ proposals: [IntakeProposal]) -> Bool {
        proposals.count == 1 && proposals.first!.action == .newRow
    }

    /// The Review-proposal id minted for a shopping-derived intake. Single owner
    /// of this scheme so the shopping cleanup can't silently break.
    static func proposalIdForShoppingItem(_ itemId: String) -> String { "ix_\(itemId)" }

    static func fromShoppingItems(
        _ items: [ShoppingItem],
        _ inventory: [Ingredient]
    ) -> [IntakeProposal] {
        items.map { item in
            let (qty, unit) = parseDetail(item.detail)
            // Inherit storage from a matching inventory row (name+unit) so the
            // planner's merge rule γ (name+unit+storage) can fire for non-perishables.
            let storage = inferStorage(item.name, unit, inventory)
            return build(
                id: proposalIdForShoppingItem(item.id),
                name: item.name,
                quantity: qty,
                unit: unit,
                category: item.category,
                storage: storage,
                shelfLifeDays: nil,
                inventory: inventory,
                origin: .system
            )
        }
    }

    /// Builds one `IntakeProposal`, resolving its default Intake action against
    /// the live inventory and capturing the merge-target hint + label.
    private static func build(
        id: String,
        name: String,
        quantity: String,
        unit: String,
        category: String?,
        storage: IconType,
        shelfLifeDays: Int?,
        inventory: [Ingredient],
        origin: FieldOrigin = .ai
    ) -> IntakeProposal {
        let action = ProposalPlanner.computeIntakeDefaultAction(
            name: name,
            unit: unit,
            storage: storage,
            category: category,
            inventory: inventory
        )
        let i = action.targetIndex
        let mergeTargetLabel: String?
        if let i {
            let row = inventory[i]
            mergeTargetLabel = "\(row.name) \(row.quantity)\(row.unit)"
        } else {
            mergeTargetLabel = nil
        }
        return IntakeProposal(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            storage: storage,
            shelfLifeDays: shelfLifeDays,
            action: action.kind,
            mergeTargetId: i.map(String.init),
            mergeTargetLabel: mergeTargetLabel,
            origin: origin
        )
    }

    private static func parseDetail(_ detail: String) -> (qty: String, unit: String) {
        let trimmed = detail.trimmed
        if trimmed.isEmpty { return ("1", "份") }
        guard let parsed = QuantityText.parseLeadingQuantity(trimmed) else {
            return ("1", trimmed)
        }
        return (parsed.magnitude, parsed.remainder.isEmpty ? "份" : parsed.remainder)
    }

    /// Storage of the first inventory row matching name+unit, else `.fridge`.
    private static func inferStorage(
        _ name: String,
        _ unit: String,
        _ inventory: [Ingredient]
    ) -> IconType {
        let lowerName = name.trimmed.lowercased()
        let trimmedUnit = unit.trimmed
        for row in inventory {
            if row.name.trimmed.lowercased() == lowerName && row.unit.trimmed == trimmedUnit {
                return row.storage
            }
        }
        return .fridge
    }
}
