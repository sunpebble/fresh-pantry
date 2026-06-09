import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Add-Ingredient + Intake Review flow: the
/// `IntakeController` persistence seam, the `AddIngredientForm` smart-default
/// autofill + proposal building, and the `IntakeReviewStore` select/edit/apply.
///
/// Backed by a real in-memory `InventoryRepository` so the load → apply → persist
/// → frequency-memory path is exercised end-to-end through the P4 `ProposalApply`
/// pipeline (identity re-resolution preserved).
@MainActor
struct IntakeFlowTests {
    // MARK: Fixtures

    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func repo(_ container: ModelContainer) -> InventoryRepository {
        InventoryRepository(modelContainer: container)
    }

    /// A non-perishable pantry row with a numeric quantity (so an intake of the
    /// same name×unit×storage MERGES per ADR-0001 rule γ).
    private func pantryRow(id: String, name: String, quantity: String, unit: String = "袋") -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: quantity, unit: unit, imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .pantry, remoteVersion: 3
        )
    }

    // MARK: IntakeController — new row persists + records addition

    @Test func controllerAppliesNewRowAndRecordsAddition() async throws {
        let container = try container()
        let repository = repo(container)
        let controller = IntakeController(repository: repository, householdID: "home")

        let outcome = await controller.apply([proposal(id: "p_new", name: "意大利面", quantity: "2", unit: "袋")])

        #expect(outcome.persisted)
        #expect(outcome.addedItems.count == 1)
        #expect(outcome.appliedIds.count == 1)

        // Persisted as a brand-new inventory row.
        let inventory = try await repository.loadAllFor("home")
        #expect(inventory.count == 1)
        #expect(inventory[0].name == "意大利面")
        #expect(inventory[0].quantity == "2")
        // A new row gets a sync UUID minted by ProposalApply.
        #expect(ProposalApply.isUuid(inventory[0].id))

        // Frequency memory bumped for the newly-added item.
        let frequent = try await repository.loadFrequentItems()
        #expect(frequent.contains { $0.name == "意大利面" && $0.count == 1 })
    }

    // MARK: IntakeController — merge into an existing row through the repo

    @Test func controllerMergesIntoExistingRow() async throws {
        let container = try container()
        let repository = repo(container)
        // Seed a non-perishable row with numeric stock.
        try await repository.saveItems("home", [pantryRow(id: "ing_rice", name: "大米", quantity: "1", unit: "袋")])

        let controller = IntakeController(repository: repository, householdID: "home")
        // Build the proposal via the factory so the default action resolves to
        // mergeInto against the seeded inventory (identity matches name×unit×storage).
        let inventory = try await repository.loadAllFor("home")
        let proposals = IntakeProposalFactory.fromDrafts([
            IngredientDraft(
                id: "p_rice",
                name: .user("大米"),
                quantity: .user("2"),
                unit: .user("袋"),
                category: .user(FoodCategories.other),
                storage: .user(.pantry),
                shelfLifeDays: .user(nil)
            )
        ], inventory)
        #expect(proposals[0].action == .mergeInto)

        let outcome = await controller.apply(proposals)
        #expect(outcome.persisted)
        // A merge is NOT a new addition (no added item, no frequency bump).
        #expect(outcome.addedItems.isEmpty)

        let after = try await repository.loadAllFor("home")
        #expect(after.count == 1) // merged, not appended
        #expect(after[0].id == "ing_rice") // same row, kept identity
        #expect(after[0].quantity == "3") // 1 + 2 summed

        // No frequency bump for a merge.
        let frequent = try await repository.loadFrequentItems()
        #expect(frequent.isEmpty)
    }

    // MARK: IntakeController — deselected proposals never apply

    @Test func controllerSkipsDeselectedProposals() async throws {
        let container = try container()
        let repository = repo(container)
        let controller = IntakeController(repository: repository, householdID: "home")

        let deselected = proposal(id: "p_oat", name: "燕麦").copyWith(selected: false)
        let outcome = await controller.apply([deselected])

        #expect(outcome.persisted)
        #expect(outcome.appliedIds.isEmpty)
        #expect(try await repository.loadAllFor("home").isEmpty)
    }

    // MARK: AddIngredientForm — smart-default autofill

    @Test func formAutofillsSmartDefaultsFromKnowledge() {
        let form = AddIngredientForm()
        form.name = "牛奶"
        form.applySmartDefaults()
        // 牛奶 → 乳品蛋类 / 冰箱 / 7 天 (FoodKnowledge).
        #expect(form.category == FoodCategories.dairyAndEggs)
        #expect(form.storage == .fridge)
        #expect(form.shelfLifeDays == 7)
    }

    @Test func formAutofillRespectsUserOverrides() {
        let form = AddIngredientForm()
        form.setStorage(.freezer) // user override before autofill
        form.name = "牛奶"
        form.applySmartDefaults()
        // Storage stays the user's choice; the un-touched fields still autofill.
        #expect(form.storage == .freezer)
        #expect(form.category == FoodCategories.dairyAndEggs)
        #expect(form.shelfLifeDays == 7)
    }

    @Test func formUnknownNameLeavesDefaultsUntouched() {
        let form = AddIngredientForm()
        let originalCategory = form.category
        form.name = "某种不在知识库的东西"
        form.applySmartDefaults()
        #expect(form.category == originalCategory)
    }

    // MARK: AddIngredientForm — proposal building routes through the factory

    @Test func formBuildsNewRowProposalForEmptyInventory() {
        let form = AddIngredientForm()
        form.name = "苹果"
        form.quantity = "3"
        form.setUnit("个")
        form.applySmartDefaults()

        let proposal = form.buildProposal(inventory: [])
        #expect(proposal.name == "苹果")
        #expect(proposal.quantity == "3")
        #expect(proposal.unit == "个")
        #expect(proposal.action == .newRow)
        #expect(proposal.origin == .user) // hand-filled
    }

    @Test func formBuildsMergeProposalAgainstMatchingInventory() {
        let form = AddIngredientForm()
        form.name = "大米"
        form.setUnit("袋")
        form.setStorage(.pantry)
        form.setCategory(FoodCategories.other)

        let inventory = [pantryRow(id: "ing_rice", name: "大米", quantity: "1", unit: "袋")]
        let proposal = form.buildProposal(inventory: inventory)
        #expect(proposal.action == .mergeInto)
        #expect(proposal.mergeTargetLabel != nil)
    }

    // MARK: IntakeReviewStore — select / deselect

    @Test func reviewStoreToggleSelectionAndSelectAll() async throws {
        let store = makeReviewStore([
            proposal(id: "a", name: "A"),
            proposal(id: "b", name: "B"),
        ])
        #expect(store.selectedCount == 2)
        #expect(store.allSelected)

        store.toggleSelected("a")
        #expect(store.selectedCount == 1)
        #expect(!store.allSelected)
        store.toggleSelectAll() // not all selected -> select all
        #expect(store.selectedCount == 2)
        store.toggleSelectAll() // all selected -> deselect all
        #expect(store.selectedCount == 0)
        #expect(!store.canConfirm)
    }

    // MARK: IntakeReviewStore — action editing (merge target + perishable lock)

    @Test func reviewStoreToggleActionFlipsWhenMergeTargetExists() {
        var p = proposal(id: "a", name: "大米")
        p = p.copyWith(action: .mergeInto, mergeTargetId: "0", mergeTargetLabel: "大米 1袋")
        let store = makeReviewStore([p])

        store.toggleAction("a")
        #expect(store.proposals[0].action == .newRow)
        #expect(store.proposals[0].userEdited)
        store.toggleAction("a")
        #expect(store.proposals[0].action == .mergeInto)
    }

    @Test func reviewStoreToggleActionNoOpWithoutMergeTarget() {
        let store = makeReviewStore([proposal(id: "a", name: "大米")]) // no mergeTargetId
        store.toggleAction("a")
        #expect(store.proposals[0].action == .newRow) // unchanged
        #expect(!store.proposals[0].userEdited)
    }

    @Test func reviewStorePerishableNewRowIsLocked() {
        // A perishable (肉类海鲜 / 鸡肉) is locked to a new batch even if a stale
        // mergeTargetId is present.
        let p = IntakeProposal(
            id: "a", name: "鸡肉", quantity: "1", unit: "份",
            category: FoodCategories.meatAndSeafood, storage: .fridge,
            shelfLifeDays: 2, action: .newRow, mergeTargetId: "0", mergeTargetLabel: "鸡肉 1份"
        )
        #expect(IntakeReviewStore.isActionLocked(p))
        let store = makeReviewStore([p])
        store.toggleAction("a")
        #expect(store.proposals[0].action == .newRow) // stayed locked
    }

    @Test func reviewStoreUpdateProposalAppliesNameEdit() {
        // The inline name-edit routes through updateProposal (same path as the
        // unit/category edits). A non-perishable rename persists the name + marks
        // userEdited, and keeps the merge action (coerceActionForRules no-ops).
        var p = proposal(id: "a", name: "大米")
        p = p.copyWith(action: .mergeInto, mergeTargetId: "0", mergeTargetLabel: "大米 1袋")
        let store = makeReviewStore([p])

        store.updateProposal(p.copyWith(name: "糙米", userEdited: true))
        #expect(store.proposals[0].name == "糙米")
        #expect(store.proposals[0].userEdited)
        #expect(store.proposals[0].action == .mergeInto)
    }

    @Test func copyWithClearsShelfLifeDays() {
        let p = proposal(id: "a", name: "牛奶") // shelfLifeDays 30 from the builder
        #expect(p.shelfLifeDays == 30)
        // `shelfLifeDays: nil` can't clear (?? self); `clearShelfLifeDays` does.
        #expect(p.copyWith(shelfLifeDays: nil).shelfLifeDays == 30)
        #expect(p.copyWith(clearShelfLifeDays: true).shelfLifeDays == nil)
    }

    // MARK: IntakeReviewStore — atomic apply of only selected

    @Test func reviewStoreAppliesOnlySelectedAtomically() async throws {
        let container = try container()
        let repository = repo(container)
        let controller = IntakeController(repository: repository, householdID: "home")
        let store = IntakeReviewStore(
            proposals: [
                proposal(id: "keep", name: "意面", quantity: "2"),
                proposal(id: "drop", name: "燕麦", quantity: "1"),
            ],
            controller: controller
        )
        store.toggleSelected("drop") // deselect the second

        let outcome = await store.apply()
        #expect(outcome.persisted)
        #expect(outcome.appliedIds == ["keep"])

        let inventory = try await repository.loadAllFor("home")
        #expect(inventory.map(\.name) == ["意面"]) // only the selected one landed
    }

    // MARK: Helpers

    private func proposal(id: String, name: String, quantity: String = "1", unit: String = "份") -> IntakeProposal {
        IntakeProposal(
            id: id, name: name, quantity: quantity, unit: unit,
            category: FoodCategories.other, storage: .pantry, shelfLifeDays: 30,
            action: .newRow, origin: .user
        )
    }

    private func makeReviewStore(_ proposals: [IntakeProposal]) -> IntakeReviewStore {
        let container = try! ModelContainerFactory.makeInMemory()
        let controller = IntakeController(repository: repo(container), householdID: "home")
        return IntakeReviewStore(proposals: proposals, controller: controller)
    }
}
