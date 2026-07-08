import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The intake review's apply-failure notice: a non-persisted outcome must
/// surface "入库失败，请重试" (the `IntakeController` contract says the caller
/// surfaces the retry), and a successful apply must leave no stale notice.
/// The mapping is a pure function because a real in-memory repository can't be
/// made to throw on demand.
@MainActor
struct IntakeReviewApplyErrorTests {
    @Test func applyErrorMessageOnlyForNonPersistedOutcome() {
        #expect(IntakeReviewStore.applyErrorMessage(for: .failed) == String(localized: "inventory.intake.failedRetry"))
        #expect(IntakeReviewStore.applyErrorMessage(
            for: IntakeController.ApplyOutcome(appliedIds: ["p1"], addedItems: [], persisted: true)
        ) == nil)
        // A no-op apply (nothing selected) still persisted=true → no notice.
        #expect(IntakeReviewStore.applyErrorMessage(
            for: IntakeController.ApplyOutcome(appliedIds: [], addedItems: [], persisted: true)
        ) == nil)
        #expect(IntakeReviewStore.applyErrorMessage(for: .limitBlocked) == nil)
    }

    @Test func successfulApplyLeavesApplyErrorNil() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let controller = IntakeController(
            repository: InventoryRepository(modelContainer: container),
            householdID: "home"
        )
        let store = IntakeReviewStore(
            proposals: [
                IntakeProposal(
                    id: "p1", name: "意大利面", quantity: "2", unit: "袋",
                    category: FoodCategories.other, storage: .pantry, shelfLifeDays: 30,
                    action: .newRow, origin: .user
                )
            ],
            controller: controller
        )

        let outcome = await store.apply()

        #expect(outcome.persisted)
        #expect(store.applyError == nil)
    }
}

/// The review screen's quantity rules: the tap-to-edit commit gate and the
/// merge-chip coercion for non-numeric quantities (the chip must never promise
/// a merge that `ProposalApply` will degrade to a new row).
@MainActor
struct IntakeReviewQuantityRuleTests {
    private func makeStore(_ proposals: [IntakeProposal]) throws -> IntakeReviewStore {
        let container = try ModelContainerFactory.makeInMemory()
        return IntakeReviewStore(
            proposals: proposals,
            controller: IntakeController(
                repository: InventoryRepository(modelContainer: container),
                householdID: "home"
            )
        )
    }

    private func mergeProposal(quantity: String) -> IntakeProposal {
        IntakeProposal(
            id: "p1", name: "米", quantity: quantity, unit: "袋",
            category: FoodCategories.other, storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0", mergeTargetLabel: "米 2袋"
        )
    }

    @Test func sanitizedQuantityEditGatesInput() {
        // Discarded: blank, unchanged, and numeric-but-not-positive-finite.
        #expect(IntakeReviewStore.sanitizedQuantityEdit("  ", current: "2") == nil)
        #expect(IntakeReviewStore.sanitizedQuantityEdit("2", current: "2") == nil)
        #expect(IntakeReviewStore.sanitizedQuantityEdit("0", current: "2") == nil)
        #expect(IntakeReviewStore.sanitizedQuantityEdit("-3", current: "2") == nil)
        #expect(IntakeReviewStore.sanitizedQuantityEdit("inf", current: "2") == nil)
        #expect(IntakeReviewStore.sanitizedQuantityEdit("nan", current: "2") == nil)
        // Committed: positive numbers (trimmed) and free text.
        #expect(IntakeReviewStore.sanitizedQuantityEdit(" 2.5 ", current: "2") == "2.5")
        #expect(IntakeReviewStore.sanitizedQuantityEdit("适量", current: "2") == "适量")
    }

    @Test func updateProposalCoercesNonNumericQuantityMergeToNewRow() throws {
        let store = try makeStore([mergeProposal(quantity: "1")])
        store.updateProposal(store.proposals[0].copyWith(quantity: "适量", userEdited: true))
        #expect(store.proposals[0].action == .newRow) // chip stops promising a merge
        #expect(store.proposals[0].quantity == "适量")
    }

    @Test func toggleActionIsNoOpForNonNumericQuantity() throws {
        let store = try makeStore([
            mergeProposal(quantity: "适量").copyWith(action: .newRow)
        ])
        store.toggleAction("p1")
        #expect(store.proposals[0].action == .newRow) // can't toggle into a false promise
    }

    @Test func isActionLockedForNonNumericQuantity() {
        #expect(IntakeReviewStore.isActionLocked(mergeProposal(quantity: "适量")))
        #expect(!IntakeReviewStore.isActionLocked(mergeProposal(quantity: "2")))
    }
}
