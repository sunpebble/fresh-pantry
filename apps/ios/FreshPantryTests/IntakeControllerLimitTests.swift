import Foundation
import SwiftData
import Testing
@testable import FreshPantry

@MainActor
struct IntakeControllerLimitTests {
    @Test func freeUserCannotCreateNewRowAtInventoryLimit() async throws {
        let container = try container()
        let repository = repo(container)
        try await repository.saveItems("home", (0..<FreeTier.inventoryLimit).map(pantryRow))

        let controller = IntakeController(repository: repository, householdID: "home", isPro: { false })
        let outcome = await controller.apply([proposal(id: "p_new", name: "新食材")])

        #expect(outcome.limitReached)
        #expect(!outcome.persisted)
        #expect(outcome.appliedIds.isEmpty)
        #expect(try await repository.loadAllFor("home").count == FreeTier.inventoryLimit)
    }

    @Test func proUserCanCreateNewRowPastFreeInventoryLimit() async throws {
        let container = try container()
        let repository = repo(container)
        try await repository.saveItems("home", (0..<FreeTier.inventoryLimit).map(pantryRow))

        let controller = IntakeController(repository: repository, householdID: "home", isPro: { true })
        let outcome = await controller.apply([proposal(id: "p_new", name: "新食材")])

        #expect(!outcome.limitReached)
        #expect(outcome.persisted)
        #expect(outcome.addedItems.count == 1)
        #expect(try await repository.loadAllFor("home").count == FreeTier.inventoryLimit + 1)
    }

    @Test func freeUserCannotBatchCreateRowsPastInventoryLimit() async throws {
        let container = try container()
        let repository = repo(container)
        try await repository.saveItems("home", (0..<(FreeTier.inventoryLimit - 1)).map(pantryRow))

        let controller = IntakeController(repository: repository, householdID: "home", isPro: { false })
        let outcome = await controller.apply([
            proposal(id: "p_a", name: "新食材 A"),
            proposal(id: "p_b", name: "新食材 B"),
        ])

        #expect(outcome.limitReached)
        #expect(!outcome.persisted)
        #expect(try await repository.loadAllFor("home").count == FreeTier.inventoryLimit - 1)
    }

    @Test func freeUserCanMergeIntoExistingRowAtInventoryLimit() async throws {
        let container = try container()
        let repository = repo(container)
        var rows = (1..<FreeTier.inventoryLimit).map(pantryRow)
        rows.append(pantryRow(0, name: "大米", quantity: "1", unit: "袋"))
        try await repository.saveItems("home", rows)

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

        let controller = IntakeController(repository: repository, householdID: "home", isPro: { false })
        let outcome = await controller.apply(proposals)

        #expect(!outcome.limitReached)
        #expect(outcome.persisted)
        #expect(outcome.addedItems.isEmpty)

        let after = try await repository.loadAllFor("home")
        #expect(after.count == FreeTier.inventoryLimit)
        #expect(after.first(where: { $0.id == "ing_0" })?.quantity == "3")
    }

    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func repo(_ container: ModelContainer) -> InventoryRepository {
        InventoryRepository(modelContainer: container)
    }

    private func pantryRow(_ index: Int) -> Ingredient {
        pantryRow(index, name: "库存 \(index)", quantity: "1", unit: "份")
    }

    private func pantryRow(_ index: Int, name: String, quantity: String, unit: String) -> Ingredient {
        Ingredient(
            id: "ing_\(index)",
            name: name,
            quantity: quantity,
            unit: unit,
            imageUrl: "",
            freshnessPercent: 1.0,
            state: .fresh,
            category: FoodCategories.other,
            storage: .pantry
        )
    }

    private func proposal(id: String, name: String, quantity: String = "1", unit: String = "份") -> IntakeProposal {
        IntakeProposal(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            category: FoodCategories.other,
            storage: .pantry,
            shelfLifeDays: 30,
            action: .newRow,
            origin: .user
        )
    }
}
