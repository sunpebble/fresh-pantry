import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the custom-recipe CRUD store + the pure form draft
/// validation. The store runs against a REAL in-memory `CustomRecipeRepository`;
/// the sync side is exercised with a coordinator-less `SyncWriter` over a real
/// in-memory outbox + a session with a set household, so we can assert the
/// enqueued op shape without any Supabase SDK / credentials.
@MainActor
struct CustomRecipeStoreTests {
    // MARK: Fixture

    private struct Fixture {
        let store: CustomRecipeStore
        let outbox: SyncOutboxRepository
        let repository: CustomRecipeRepository
    }

    /// Builds a store wired to a writer when `household` is non-empty (so enqueue
    /// records), or local-only (writer present but household blank → enqueue
    /// no-ops, matching production local mode).
    private func makeFixture(household: String = "home") throws -> Fixture {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = CustomRecipeRepository(modelContainer: container)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let defaults = UserDefaults(suiteName: "test.customrecipe.\(UUID().uuidString)")!
        let session = SyncSession(selectedHouseholdId: household, defaults: defaults)
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let store = CustomRecipeStore(repository: repository, householdID: household, syncWriter: writer)
        return Fixture(store: store, outbox: outbox, repository: repository)
    }

    private func recipe(
        id: String = UUID().uuidString.lowercased(),
        name: String = "番茄炒蛋",
        remoteVersion: Int = 0
    ) -> Recipe {
        Recipe(
            id: id,
            name: name,
            category: "家常",
            difficulty: 2,
            cookingMinutes: 15,
            description: "经典家常菜",
            ingredients: [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")],
            steps: ["切番茄", "炒蛋"],
            remoteVersion: remoteVersion
        )
    }

    // MARK: add

    @Test func addPersistsAppearsAndEnqueuesCreate() async throws {
        let fixture = try makeFixture()
        let new = recipe(name: "麻婆豆腐")

        let ok = await fixture.store.add(new)

        #expect(ok)
        #expect(fixture.store.recipes.contains { $0.id == new.id })
        let persisted = try await fixture.repository.loadAllFor("home")
        #expect(persisted.contains { $0.id == new.id })

        let pending = try await fixture.outbox.loadPending()
        #expect(pending.count == 1)
        let op = try #require(pending.first)
        #expect(op.entityType == .customRecipe)
        #expect(op.operation == .create)
        #expect(op.entityId == new.id)
        #expect(op.baseVersion == nil)
    }

    // MARK: update

    @Test func updateReplacesByIdAndEnqueuesUpdate() async throws {
        let fixture = try makeFixture()
        let original = recipe(name: "原味", remoteVersion: 3)
        _ = await fixture.store.add(original)

        let edited = original.copyWith(name: "改良味")
        let ok = await fixture.store.update(edited)

        #expect(ok)
        let row = try #require(fixture.store.recipes.first { $0.id == original.id })
        #expect(row.name == "改良味")
        #expect(fixture.store.recipes.count == 1) // replaced, not appended

        let pending = try await fixture.outbox.loadPending()
        let updateOp = try #require(pending.last)
        #expect(updateOp.operation == .update)
        #expect(updateOp.entityId == original.id)
        #expect(updateOp.baseVersion == 3) // = the recipe's remoteVersion
    }

    @Test func updateOnMissingIdReturnsFalse() async throws {
        let fixture = try makeFixture()
        let ok = await fixture.store.update(recipe(id: "ghost"))
        #expect(!ok)
        #expect(fixture.store.recipes.isEmpty)
    }

    // MARK: remove

    @Test func removeDropsByIdAndEnqueuesDelete() async throws {
        let fixture = try makeFixture()
        let target = recipe(name: "待删", remoteVersion: 5)
        _ = await fixture.store.add(target)

        let ok = await fixture.store.remove(target.id)

        #expect(ok)
        #expect(!fixture.store.recipes.contains { $0.id == target.id })
        let persisted = try await fixture.repository.loadAllFor("home")
        #expect(!persisted.contains { $0.id == target.id })

        let pending = try await fixture.outbox.loadPending()
        let deleteOp = try #require(pending.last)
        #expect(deleteOp.operation == .delete)
        #expect(deleteOp.entityId == target.id)
        #expect(deleteOp.baseVersion == 5)
        // The delete patch carries the full row so the gateway derives deleted_at.
        #expect(deleteOp.patch["id"] == .string(target.id))
    }

    @Test func removeOnMissingIdReturnsFalse() async throws {
        let fixture = try makeFixture()
        let ok = await fixture.store.remove("ghost")
        #expect(!ok)
    }

    // MARK: local-only mode (no household)

    @Test func addWithoutHouseholdPersistsLocallyButEnqueuesNothing() async throws {
        let fixture = try makeFixture(household: "")
        let new = recipe()

        let ok = await fixture.store.add(new)

        #expect(ok)
        #expect(fixture.store.recipes.contains { $0.id == new.id })
        // Blank household = local-only: the enqueue is a no-op, not a dropped write.
        #expect(try await fixture.outbox.pendingCount() == 0)
    }

    // MARK: draft → recipe id

    @Test func newRecipeGetsLowercasedUUIDId() {
        let built = CustomRecipeDraft(
            name: "测试",
            cookingMinutes: "20",
            difficulty: 3,
            ingredients: [.init(name: "盐", quantity: "1", unit: "勺")],
            steps: [.init(text: "拌匀")]
        ).buildRecipe()

        // A new recipe id MUST be a lowercased UUID (sync-clean), not custom_<ms>.
        #expect(UUID(uuidString: built.id) != nil)
        #expect(built.id == built.id.lowercased())
        #expect(!built.id.hasPrefix("custom_"))
    }

    @Test func editPreservesIdTagsAndRemoteVersion() {
        let existing = recipe(id: "abc", remoteVersion: 7).copyWith(tags: ["快手"])
        let built = CustomRecipeDraft(recipe: existing).buildRecipe(existing: existing)
        #expect(built.id == "abc")
        #expect(built.tags == ["快手"])
        #expect(built.remoteVersion == 7)
    }

    @Test func editPreservesRangeQuantity() {
        // 编辑带范围用量的食材时,上界必须经文本框往返保留(回归:曾退化成下界,丢 quantityMax)
        let existing = recipe(id: "r1").copyWith(
            ingredients: [RecipeIngredient(name: "白糖", quantity: 6, quantityMax: 15, unit: "克")]
        )
        let built = CustomRecipeDraft(recipe: existing).buildRecipe(existing: existing)
        #expect(built.ingredients[0].quantity == 6)
        #expect(built.ingredients[0].quantityMax == 15)
        #expect(built.ingredients[0].unit == "克")
    }

    // MARK: validation

    private func validDraft() -> CustomRecipeDraft {
        CustomRecipeDraft(
            name: "番茄炒蛋",
            category: "家常",
            cookingMinutes: "15",
            difficulty: 3,
            ingredients: [.init(name: "番茄", quantity: "2", unit: "个")],
            steps: [.init(text: "切番茄")]
        )
    }

    @Test func validateAcceptsCompleteDraft() {
        #expect(validDraft().validate().isEmpty)
    }

    @Test func validateRejectsEmptyName() {
        var draft = validDraft()
        draft.name = "   "
        #expect(draft.validate()[.name] != nil)
    }

    @Test func validateRejectsEmptyCategory() {
        var draft = validDraft()
        draft.category = ""
        #expect(draft.validate()[.category] != nil)
    }

    @Test func validateRejectsNonPositiveCookingMinutes() {
        var draft = validDraft()
        draft.cookingMinutes = "0"
        #expect(draft.validate()[.cookingMinutes] != nil)
        draft.cookingMinutes = "abc"
        #expect(draft.validate()[.cookingMinutes] != nil)
    }

    @Test func validateRejectsOutOfRangeDifficulty() {
        var draft = validDraft()
        draft.difficulty = 0
        #expect(draft.validate()[.difficulty] != nil)
        draft.difficulty = 6
        #expect(draft.validate()[.difficulty] != nil)
    }

    @Test func validateRejectsIncompleteIngredient() {
        // A name with no quantity is an error.
        var nameOnly = validDraft()
        nameOnly.ingredients = [.init(name: "番茄", quantity: "", unit: "个")]
        #expect(nameOnly.validate()[.ingredients] != nil)

        // A quantity with no name is an error.
        var qtyOnly = validDraft()
        qtyOnly.ingredients = [.init(name: "", quantity: "2", unit: "个")]
        #expect(qtyOnly.validate()[.ingredients] != nil)

        // No ingredient text at all is an error.
        var blank = validDraft()
        blank.ingredients = [.init()]
        #expect(blank.validate()[.ingredients] != nil)
    }

    @Test func validateRejectsNoSteps() {
        var draft = validDraft()
        draft.steps = [.init(text: "   ")]
        #expect(draft.validate()[.steps] != nil)
    }
}
