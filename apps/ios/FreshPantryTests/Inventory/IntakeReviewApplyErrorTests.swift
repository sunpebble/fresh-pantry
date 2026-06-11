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
        #expect(IntakeReviewStore.applyErrorMessage(for: .failed) == "入库失败，请重试")
        #expect(IntakeReviewStore.applyErrorMessage(
            for: IntakeController.ApplyOutcome(appliedIds: ["p1"], addedItems: [], persisted: true)
        ) == nil)
        // A no-op apply (nothing selected) still persisted=true → no notice.
        #expect(IntakeReviewStore.applyErrorMessage(
            for: IntakeController.ApplyOutcome(appliedIds: [], addedItems: [], persisted: true)
        ) == nil)
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
