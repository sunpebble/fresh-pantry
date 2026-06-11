import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The manual-add submit's failure notices: a non-persisted apply must surface
/// "入库失败，请重试" (the `IntakeController` contract says the caller surfaces
/// the retry), an inventory-load failure carries its OWN copy (the submit must
/// not degrade to an empty inventory and silently bypass the merge review), and
/// a successful direct apply maps to no notice. The mappings are pure because a
/// real in-memory repository can't be made to throw on demand.
@MainActor
struct AddSubmitFeedbackTests {
    @Test func applyFailureMessageOnlyForNonPersistedOutcome() {
        #expect(AddSubmitFeedback.applyFailureMessage(for: .failed) == "入库失败，请重试")
        #expect(AddSubmitFeedback.applyFailureMessage(
            for: IntakeController.ApplyOutcome(appliedIds: ["p1"], addedItems: [], persisted: true)
        ) == nil)
        // A no-op apply (nothing resolved) still persisted=true → no notice.
        #expect(AddSubmitFeedback.applyFailureMessage(
            for: IntakeController.ApplyOutcome(appliedIds: [], addedItems: [], persisted: true)
        ) == nil)
    }

    @Test func loadFailureCopyIsDistinctFromApplyFailure() {
        #expect(AddSubmitFeedback.loadFailureMessage == "读取库存失败，请重试。")
        // Distinct copy so the user can tell "nothing was even attempted"
        // (load threw, form untouched) from "the save itself failed".
        #expect(
            AddSubmitFeedback.loadFailureMessage
                != AddSubmitFeedback.applyFailureMessage(for: .failed)
        )
    }

    /// The happy direct-apply path (form → proposal → controller) persists and
    /// maps to no notice — guards the notice from ever firing on success.
    @Test func successfulDirectApplyMapsToNoNotice() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let controller = IntakeController(
            repository: InventoryRepository(modelContainer: container),
            householdID: "home"
        )
        let form = AddIngredientForm()
        form.name = "牛奶"
        let proposal = form.buildProposal(inventory: [])
        #expect(proposal.action == .newRow) // empty inventory → direct path

        let outcome = await controller.apply([proposal])

        #expect(outcome.persisted)
        #expect(AddSubmitFeedback.applyFailureMessage(for: outcome) == nil)
    }
}
