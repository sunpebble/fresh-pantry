import Foundation

/// Pure orchestration seam for the shopping → intake-review flow (mirrors the
/// Flutter `ShoppingIntakeController`). Keeps the `ix_` proposal-id scheme out of
/// the View and stays unit-testable without SwiftData/SwiftUI: the View loads the
/// live inventory + drives navigation; this owns only the data rules.
enum ShoppingIntake {
    /// Builds intake proposals for `items` against the live `inventory` (resolves
    /// the default merge-vs-new-batch action via the shared factory).
    static func buildProposals(_ items: [ShoppingItem], inventory: [Ingredient]) -> [IntakeProposal] {
        IntakeProposalFactory.fromShoppingItems(items, inventory)
    }

    /// The `source` rows whose intake proposal actually applied (present in
    /// `appliedIds`), so the caller removes ONLY those from the list — a cancelled
    /// review or a deselected proposal leaves its row untouched rather than
    /// silently discarding it without it ever entering inventory.
    static func appliedSourceItems(_ source: [ShoppingItem], appliedIds: Set<String>) -> [ShoppingItem] {
        guard !appliedIds.isEmpty else { return [] }
        return source.filter {
            appliedIds.contains(IntakeProposalFactory.proposalIdForShoppingItem($0.id))
        }
    }
}
