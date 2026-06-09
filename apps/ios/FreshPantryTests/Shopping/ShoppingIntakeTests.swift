import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for the pure `ShoppingIntake` orchestration seam: proposal building
/// against live inventory and the applied-source filtering that decides which
/// rows leave the list after a review.
@MainActor
struct ShoppingIntakeTests {
    private func shoppingItem(id: String, name: String, detail: String = "") -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, category: FoodCategories.other)
    }

    @Test func buildProposalsMintsShoppingProposalIds() {
        let items = [shoppingItem(id: "s1", name: "牛奶"), shoppingItem(id: "s2", name: "鸡蛋")]
        let proposals = ShoppingIntake.buildProposals(items, inventory: [])
        #expect(proposals.map(\.id) == [
            IntakeProposalFactory.proposalIdForShoppingItem("s1"),
            IntakeProposalFactory.proposalIdForShoppingItem("s2"),
        ])
    }

    @Test func appliedSourceItemsKeepsOnlyAppliedRows() {
        let s1 = shoppingItem(id: "s1", name: "牛奶")
        let s2 = shoppingItem(id: "s2", name: "鸡蛋")
        let s3 = shoppingItem(id: "s3", name: "苹果")
        // Only s1 and s3 actually applied.
        let appliedIds: Set<String> = [
            IntakeProposalFactory.proposalIdForShoppingItem("s1"),
            IntakeProposalFactory.proposalIdForShoppingItem("s3"),
        ]
        let applied = ShoppingIntake.appliedSourceItems([s1, s2, s3], appliedIds: appliedIds)
        #expect(applied.map(\.id) == ["s1", "s3"]) // s2 (deselected/cancelled) stays
    }

    @Test func appliedSourceItemsEmptyWhenNothingApplied() {
        let items = [shoppingItem(id: "s1", name: "牛奶")]
        #expect(ShoppingIntake.appliedSourceItems(items, appliedIds: []).isEmpty)
    }
}
