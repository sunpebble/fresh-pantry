import Foundation

/// Editable state for the shared Intake Review screen: a list of proposals the
/// user can select/deselect, edit, and re-target (new batch vs merge), plus the
/// atomic apply through `IntakeController`. Built generically over
/// `[IntakeProposal]` so it later serves AI-parsed proposals too, not just the
/// manual add.
///
/// The action-toggle rules mirror the Flutter `IntakeReviewNotifier`:
///   - a proposal with no merge target can't toggle (nothing to merge into),
///   - a perishable is LOCKED to a new batch (ADR-0001: perishables always start
///     a new batch — merging would hide a fresher/older batch distinction),
///   - otherwise the action flips newRow ↔ mergeInto and marks the row userEdited.
@Observable
@MainActor
final class IntakeReviewStore {
    private(set) var proposals: [IntakeProposal]

    /// Inline failure notice for the last apply (the controller's load/save
    /// threw — inventory untouched, shopping rows kept, so retry is safe).
    /// Cleared when the next apply starts.
    private(set) var applyError: String?
    /// True when the last apply was blocked by the free inventory cap.
    /// Cleared when the next apply starts.
    private(set) var limitReached = false

    private let controller: IntakeController

    init(proposals: [IntakeProposal], controller: IntakeController) {
        self.proposals = proposals
        self.controller = controller
    }

    // MARK: Derived

    var selectedCount: Int { proposals.filter(\.selected).count }
    var allSelected: Bool { !proposals.isEmpty && selectedCount == proposals.count }
    var canConfirm: Bool { selectedCount > 0 }

    // MARK: Edits

    func toggleSelected(_ id: String) {
        update(id) { $0.copyWith(selected: !$0.selected) }
    }

    func toggleSelectAll() {
        let next = !allSelected
        proposals = proposals.map { $0.copyWith(selected: next) }
    }

    /// Flips a proposal's action, honoring the rules above. A no-op when there's
    /// no merge target, or when the row is a locked perishable new-batch.
    func toggleAction(_ id: String) {
        update(id) { proposal in
            guard proposal.mergeTargetId != nil else { return proposal }
            if Self.isPerishableLocked(proposal) { return proposal }
            let next: IntakeAction = proposal.action == .newRow ? .mergeInto : .newRow
            return proposal.copyWith(action: next, userEdited: true)
        }
    }

    /// Replaces a proposal with an edited copy, coercing the action back to a new
    /// batch if the edit made it a perishable that's still set to merge (keeps
    /// the rule invariant after a category change).
    func updateProposal(_ updated: IntakeProposal) {
        let coerced = Self.coerceActionForRules(updated)
        guard let index = proposals.firstIndex(where: { $0.id == coerced.id }) else { return }
        proposals[index] = coerced
    }

    /// Whether a row's action toggle is locked (perishable new-batch). Exposed so
    /// the row view can hide the chevron / disable the chip.
    static func isActionLocked(_ proposal: IntakeProposal) -> Bool {
        proposal.mergeTargetId == nil || isPerishableLocked(proposal)
    }

    // MARK: Apply

    /// Applies only the SELECTED proposals atomically via `IntakeController`
    /// (which runs the full P4 `ProposalApply` pipeline + persist). Returns the
    /// outcome so the view can refresh + show feedback; a non-persisted outcome
    /// also sets `applyError` (the controller's documented "caller should
    /// surface a retry" contract).
    func apply() async -> IntakeController.ApplyOutcome {
        applyError = nil
        limitReached = false
        let outcome = await controller.apply(proposals)
        limitReached = outcome.limitReached
        applyError = Self.applyErrorMessage(for: outcome)
        return outcome
    }

    /// Failure-notice mapping kept pure so it's testable without forcing a real
    /// repository to throw: only a non-persisted outcome carries a message.
    static func applyErrorMessage(for outcome: IntakeController.ApplyOutcome) -> String? {
        outcome.persisted || outcome.limitReached ? nil : String(localized: "inventory.intake.failedRetry")
    }

    // MARK: Rules

    private static func isPerishableLocked(_ proposal: IntakeProposal) -> Bool {
        proposal.action == .newRow
            && IngredientIdentity.isPerishable(category: proposal.category, name: proposal.name)
    }

    private static func coerceActionForRules(_ proposal: IntakeProposal) -> IntakeProposal {
        guard proposal.action == .mergeInto else { return proposal }
        if IngredientIdentity.isPerishable(category: proposal.category, name: proposal.name) {
            return proposal.copyWith(action: .newRow)
        }
        return proposal
    }

    private func update(_ id: String, _ transform: (IntakeProposal) -> IntakeProposal) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[index] = transform(proposals[index])
    }
}
