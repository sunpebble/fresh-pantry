import Foundation

/// The default Intake action computed against live inventory.
/// Mirrors the Dart `IntakeDefaultAction` (`.newRow()` / `.mergeInto(index)`).
struct IntakeDefaultAction {
    let kind: IntakeAction
    let targetIndex: Int?

    static func newRow() -> IntakeDefaultAction {
        IntakeDefaultAction(kind: .newRow, targetIndex: nil)
    }

    static func mergeInto(_ index: Int) -> IntakeDefaultAction {
        IntakeDefaultAction(kind: .mergeInto, targetIndex: index)
    }
}

/// Core Intake/Deduction matching engine — fuzzy inventory matching for
/// deductions and ADR-0001 merge-target resolution for intakes. Ported VERBATIM
/// from `lib/services/proposal_planner.dart`. Pure, side-effect free.
enum ProposalPlanner {
    /// Fuzzy-matches a recipe ingredient name against inventory rows.
    ///
    /// Bidirectional substring match, but a length-1 inventory name must NEVER be
    /// a substring of a longer recipe term (row "蛋" must not match recipe "蛋糕").
    /// The reverse direction (recipe term inside a longer inventory name, e.g.
    /// "肉" → "猪肉末") stays intentionally loose. Candidates are sorted by expiry
    /// ascending (nulls last) — this order is user-visible.
    static func fuzzyMatchInventoryRows(
        _ recipeIngredientName: String,
        _ inventory: [Ingredient]
    ) -> [DeductionCandidate] {
        let query = recipeIngredientName.trimmed.lowercased()
        if query.isEmpty { return [] }
        var matches: [(Int, Ingredient)] = []
        for i in inventory.indices {
            let n = inventory[i].name.trimmed.lowercased()
            if n.isEmpty { continue }
            if n == query || n.contains(query) || (query.contains(n) && n.count >= 2) {
                matches.append((i, inventory[i]))
            }
        }
        matches.sort { a, b in
            let ea = a.1.expiryDate
            let eb = b.1.expiryDate
            if ea == nil && eb == nil { return false }
            if ea == nil { return false } // a sinks below b
            if eb == nil { return true }   // b sinks below a
            return ea! < eb!
        }
        return matches.map { match in
            let row = match.1
            let expirySuffix = row.expiryLabel == nil ? "" : " · \(row.expiryLabel!)"
            return DeductionCandidate(
                inventoryRowIndex: match.0,
                displayLabel: "\(row.name) \(row.quantity)\(row.unit)\(expirySuffix)",
                inventoryRowId: row.id,
                inventoryRowName: row.name,
                inventoryRowUnit: row.unit
            )
        }
    }

    /// Implements ADR-0001 merge rule γ via `IngredientIdentity`: perishables
    /// always start a new batch; non-perishables merge when name×unit×storage
    /// match and the target row's quantity is numeric.
    static func computeIntakeDefaultAction(
        name: String,
        unit: String,
        storage: IconType,
        category: String?,
        inventory: [Ingredient]
    ) -> IntakeDefaultAction {
        let index = IngredientIdentity.resolveMergeTarget(
            name: name,
            unit: unit,
            storage: storage,
            category: category,
            inventory: inventory
        )
        return index < 0 ? .newRow() : .mergeInto(index)
    }
}
