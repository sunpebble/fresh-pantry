import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the post-cook leftover intake (剩菜入库): the pure
/// `LeftoverDraft` prefill + proposal rules, and the end-to-end persist through
/// `IntakeController` — the canonical outbox-capable add path the sheet uses.
@MainActor
struct LeftoverDraftTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)

    private func recipe(name: String = "番茄炒蛋") -> Recipe {
        Recipe(
            id: "r1",
            name: name,
            category: "家常菜",
            difficulty: 1,
            cookingMinutes: 10,
            description: "",
            ingredients: [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")],
            steps: ["炒熟"]
        )
    }

    // MARK: Prefill

    @Test func fromRecipePrefillsConservativeDefaults() {
        let draft = LeftoverDraft.from(recipe: recipe(name: " 红烧肉 "))
        #expect(draft.name == "红烧肉") // trimmed recipe name, user-editable
        #expect(draft.servings == 1)
        #expect(draft.days == LeftoverDraft.defaultShelfLifeDays)
        #expect(LeftoverDraft.defaultShelfLifeDays == 3) // 3-day fridge rule
    }

    @Test func canSaveRequiresNonBlankName() {
        var draft = LeftoverDraft.from(recipe: recipe())
        #expect(draft.canSave)
        draft.name = "   "
        #expect(!draft.canSave)
    }

    // MARK: Proposal building

    @Test func proposalCarriesLeftoverFields() {
        let proposal = LeftoverDraft.from(recipe: recipe(name: "番茄炒蛋")).proposal(now: fixedNow)
        #expect(proposal.name == "番茄炒蛋")
        #expect(proposal.quantity == "1")
        #expect(proposal.unit == LeftoverDraft.unit)
        #expect(proposal.unit == "份")
        // No cooked-food bucket among the 5 canonical categories — 其他 is the
        // closest; refrigerated per the 3-day leftover rule.
        #expect(proposal.category == FoodCategories.other)
        #expect(proposal.storage == .fridge)
        #expect(proposal.shelfLifeDays == 3)
        #expect(proposal.action == .newRow)
        #expect(proposal.origin == .user)
        #expect(proposal.selected)
    }

    @Test func proposalExpiryIsThreeDaysOut() {
        let proposal = LeftoverDraft.from(recipe: recipe()).proposal(now: fixedNow)
        let row = ProposalApply.ingredientFromProposal(proposal, now: fixedNow)
        #expect(row.expiryDate == fixedNow.addingTimeInterval(3 * 86400))
        #expect(row.shelfLifeDays == 3)
    }

    @Test func proposalClampsEditedFieldsToValidFloor() {
        var draft = LeftoverDraft.from(recipe: recipe())
        draft.servings = 0
        draft.days = 0
        let proposal = draft.proposal(now: fixedNow)
        #expect(proposal.quantity == "1")
        #expect(proposal.shelfLifeDays == 1)
    }

    // MARK: End-to-end through the canonical add path

    @Test func savingLeftoverAddsOneInventoryRow() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = InventoryRepository(modelContainer: container)
        let controller = IntakeController(repository: repository, householdID: "home")

        let proposal = LeftoverDraft.from(recipe: recipe(name: "麻婆豆腐")).proposal(now: fixedNow)
        let outcome = await controller.apply([proposal])
        #expect(outcome.persisted)
        #expect(outcome.addedItems.count == 1)

        let inventory = try await repository.loadAllFor("home")
        #expect(inventory.count == 1)
        let row = try #require(inventory.first)
        #expect(row.name == "麻婆豆腐")
        #expect(row.quantity == "1")
        #expect(row.unit == "份")
        #expect(FoodCategories.normalize(row.category) == FoodCategories.other)
        #expect(row.storage == .fridge)
        #expect(row.shelfLifeDays == 3)
        #expect(row.expiryDate != nil)
        // A new row gets a sync UUID minted by ProposalApply.
        #expect(ProposalApply.isUuid(row.id))
    }

    @Test func leftoverNeverMergesIntoAnExistingBatch() async throws {
        // An older same-name/unit/storage leftover is already in stock: the new
        // cook must land as a NEW batch with its own 3-day window — merging
        // would silently inherit the stale batch's expiry.
        let container = try ModelContainerFactory.makeInMemory()
        let repository = InventoryRepository(modelContainer: container)
        try await repository.saveItems("home", [
            Ingredient(
                id: "ing_old", name: "麻婆豆腐", quantity: "1", unit: "份", imageUrl: "",
                freshnessPercent: 0.4, state: .expiringSoon, category: FoodCategories.other,
                storage: .fridge, expiryDate: fixedNow.addingTimeInterval(86400)
            ),
        ])
        let controller = IntakeController(repository: repository, householdID: "home")

        let proposal = LeftoverDraft.from(recipe: recipe(name: "麻婆豆腐")).proposal(now: fixedNow)
        let outcome = await controller.apply([proposal])
        #expect(outcome.persisted)
        #expect(outcome.addedItems.count == 1)

        let inventory = try await repository.loadAllFor("home")
        #expect(inventory.count == 2) // appended, not merged
        #expect(inventory.contains { $0.id == "ing_old" && $0.quantity == "1" })
    }
}
