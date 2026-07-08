import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for the P4 proposal/intake/deduction domain logic:
/// `ProposalPlanner`, `IntakeProposalFactory`, `DeductionProposalFactory`,
/// `IngredientFactory`, and `ProposalApply` (the pure apply-time decision
/// logic extracted from the Flutter `InventoryNotifier`).
struct ProposalParityTests {
    // MARK: - Fixtures

    private func row(
        id: String = "",
        name: String,
        unit: String,
        quantity: String = "1",
        storage: IconType = .pantry,
        category: String? = nil,
        expiryLabel: String? = nil,
        expiryDate: Date? = nil,
        remoteVersion: Int = 0
    ) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            imageUrl: "",
            freshnessPercent: 1.0,
            state: .fresh,
            expiryLabel: expiryLabel,
            category: category,
            storage: storage,
            expiryDate: expiryDate,
            remoteVersion: remoteVersion
        )
    }

    private func date(_ daysFromNow: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(daysFromNow * 86400))
    }

    private func shopping(
        id: String = "si_1",
        name: String,
        detail: String,
        category: String = "其他",
        imageUrl: String? = nil
    ) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, imageUrl: imageUrl, category: category)
    }

    private func draft(
        id: String = "ai_1",
        name: String,
        quantity: String = "1",
        unit: String = "份",
        category: String? = nil,
        storage: IconType? = nil,
        shelfLifeDays: Int? = nil
    ) -> IngredientDraft {
        IngredientDraft(
            id: id,
            name: .ai(name),
            quantity: .ai(quantity),
            unit: .ai(unit),
            category: .ai(category),
            storage: .ai(storage),
            shelfLifeDays: .ai(shelfLifeDays)
        )
    }

    // MARK: - IntakeProposalFactory: defaults (new-row vs merge)

    @Test func intakeDefaultNewRowWhenNoMatch() {
        let inventory: [Ingredient] = []
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "白糖", quantity: "1", unit: "袋", category: "其他", storage: .pantry)],
            inventory
        )
        #expect(proposals.count == 1)
        #expect(proposals[0].action == .newRow)
        #expect(proposals[0].mergeTargetId == nil)
        #expect(proposals[0].mergeTargetLabel == nil)
        #expect(proposals[0].origin == .ai)
    }

    @Test func intakeDefaultMergeWhenNonPerishableMatches() {
        // 白糖 (sugar) is a non-perishable pantry staple — name×unit×storage match
        // with a numeric existing quantity merges.
        let inventory = [
            row(name: "白糖", unit: "袋", quantity: "2", storage: .pantry, category: "其他")
        ]
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "白糖", quantity: "1", unit: "袋", category: "其他", storage: .pantry)],
            inventory
        )
        #expect(proposals[0].action == .mergeInto)
        #expect(proposals[0].mergeTargetId == "0") // index as string
        #expect(proposals[0].mergeTargetLabel == "白糖 2\(UnitLabels.displayLabel(for: "袋"))")
        #expect(proposals[0].unit == "袋")
    }

    @Test func intakePerishableAlwaysNewBatch() {
        // 牛肉 is a knowledge-base perishable -> new batch even with a matching row.
        let inventory = [
            row(name: "牛肉", unit: "份", quantity: "1", storage: .fridge, category: "肉类海鲜")
        ]
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "牛肉", quantity: "1", unit: "份", category: "肉类海鲜", storage: .fridge)],
            inventory
        )
        #expect(proposals[0].action == .newRow)
        #expect(proposals[0].mergeTargetId == nil)
    }

    @Test func intakeNonNumericExistingQuantityYieldsNewRow() {
        // Existing stock "适量" is non-numeric — merging would discard it, so new row.
        let inventory = [
            row(name: "盐", unit: "g", quantity: "适量", storage: .pantry, category: "其他")
        ]
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "盐", quantity: "5", unit: "g", category: "其他", storage: .pantry)],
            inventory
        )
        #expect(proposals[0].action == .newRow)
        #expect(proposals[0].mergeTargetId == nil)
    }

    @Test func intakeUnitMatchIsCaseSensitive() {
        // Unit match is trim-only, CASE-SENSITIVE: "G" != "g" -> new row.
        let inventory = [
            row(name: "米", unit: "G", quantity: "100", storage: .pantry, category: "其他")
        ]
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "米", quantity: "50", unit: "g", category: "其他", storage: .pantry)],
            inventory
        )
        #expect(proposals[0].action == .newRow)
    }

    @Test func intakeStorageMismatchYieldsNewRow() {
        let inventory = [
            row(name: "米", unit: "g", quantity: "100", storage: .pantry, category: "其他")
        ]
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "米", quantity: "50", unit: "g", category: "其他", storage: .fridge)],
            inventory
        )
        #expect(proposals[0].action == .newRow)
    }

    @Test func intakeDraftNilStorageDefaultsToFridge() {
        let inventory: [Ingredient] = []
        let proposals = IntakeProposalFactory.fromDrafts(
            [draft(name: "番茄", storage: nil)],
            inventory
        )
        #expect(proposals[0].storage == .fridge)
    }

    // MARK: - IntakeProposalFactory: shopping items

    @Test func intakeFromShoppingItemUsesIxIdAndSystemOrigin() {
        let inventory: [Ingredient] = []
        let proposals = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_42", name: "白糖", detail: "2 袋")],
            inventory
        )
        #expect(proposals[0].id == "ix_si_42")
        #expect(proposals[0].origin == .system)
        #expect(proposals[0].quantity == "2")
        #expect(proposals[0].unit == "袋")
    }

    @Test func intakeShoppingDetailParsing() {
        // Empty detail -> ("1", "份"); pure-text detail -> ("1", text);
        // leading number with unit -> (number, unit).
        let inventory: [Ingredient] = []
        let empty = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_a", name: "鸡蛋", detail: "")], inventory)
        #expect(empty[0].quantity == "1")
        #expect(empty[0].unit == "份")

        let text = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_b", name: "酱油", detail: "一瓶")], inventory)
        #expect(text[0].quantity == "1")
        #expect(text[0].unit == "一瓶")

        let numbered = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_c", name: "苹果", detail: "3 个")], inventory)
        #expect(numbered[0].quantity == "3")
        #expect(numbered[0].unit == "个")
    }

    @Test func intakeShoppingInheritsStorageFromMatchingRow() {
        // A pantry 白糖 row lets the shopping intake inherit pantry storage so the
        // non-perishable merge rule γ (name+unit+storage) fires.
        let inventory = [
            row(name: "白糖", unit: "袋", quantity: "1", storage: .pantry, category: "其他")
        ]
        let proposals = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_x", name: "白糖", detail: "1 袋", category: "其他")],
            inventory
        )
        #expect(proposals[0].storage == .pantry)
        #expect(proposals[0].action == .mergeInto)
    }

    @Test func intakeIsSinglePrefill() {
        let newRow = IntakeProposalFactory.fromDrafts(
            [draft(name: "面粉", unit: "袋", category: "其他", storage: .pantry)], [])
        #expect(IntakeProposalFactory.isSinglePrefill(newRow))

        // A single MERGE proposal must still go through Review.
        let inventory = [row(name: "白糖", unit: "袋", quantity: "1", storage: .pantry, category: "其他")]
        let merge = IntakeProposalFactory.fromDrafts(
            [draft(name: "白糖", unit: "袋", category: "其他", storage: .pantry)], inventory)
        #expect(merge[0].action == .mergeInto)
        #expect(!IntakeProposalFactory.isSinglePrefill(merge))

        // Two proposals are never a single prefill.
        let two = IntakeProposalFactory.fromDrafts(
            [draft(id: "a", name: "面粉", unit: "袋"), draft(id: "b", name: "糖", unit: "袋")], [])
        #expect(!IntakeProposalFactory.isSinglePrefill(two))
    }

    // MARK: - ProposalPlanner: fuzzy matching

    @Test func fuzzyExactMatch() {
        let inventory = [row(name: "牛奶", unit: "瓶")]
        let candidates = ProposalPlanner.fuzzyMatchInventoryRows("牛奶", inventory)
        #expect(candidates.count == 1)
        #expect(candidates[0].inventoryRowIndex == 0)
        #expect(candidates[0].inventoryRowName == "牛奶")
    }

    @Test func fuzzyRecipeTermInsideLongerInventoryName() {
        // Recipe "肉" inside inventory "猪肉末" — reverse direction stays loose.
        let inventory = [row(name: "猪肉末", unit: "g", quantity: "200")]
        let candidates = ProposalPlanner.fuzzyMatchInventoryRows("肉", inventory)
        #expect(candidates.count == 1)
    }

    @Test func fuzzyLengthOneInventoryNeverMatchesLongerRecipeTerm() {
        // Inventory "蛋" (length 1) must NOT match recipe "蛋糕".
        let inventory = [row(name: "蛋", unit: "个")]
        let candidates = ProposalPlanner.fuzzyMatchInventoryRows("蛋糕", inventory)
        #expect(candidates.isEmpty)
    }

    @Test func fuzzyNoMatch() {
        let inventory = [row(name: "牛奶", unit: "瓶")]
        #expect(ProposalPlanner.fuzzyMatchInventoryRows("土豆", inventory).isEmpty)
    }

    @Test func fuzzyEmptyQueryReturnsEmpty() {
        let inventory = [row(name: "牛奶", unit: "瓶")]
        #expect(ProposalPlanner.fuzzyMatchInventoryRows("   ", inventory).isEmpty)
    }

    @Test func fuzzyMultiCandidateSortedByExpiryNullsLast() {
        // Two rows match; the one expiring sooner sorts first, the null-expiry last.
        let inventory = [
            row(name: "牛奶A", unit: "瓶", expiryDate: nil),           // index 0, no expiry
            row(name: "牛奶B", unit: "瓶", expiryDate: date(10)),      // index 1, later
            row(name: "牛奶C", unit: "瓶", expiryDate: date(2)),       // index 2, sooner
        ]
        let candidates = ProposalPlanner.fuzzyMatchInventoryRows("牛奶", inventory)
        #expect(candidates.count == 3)
        // sooner -> later -> null
        #expect(candidates[0].inventoryRowIndex == 2)
        #expect(candidates[1].inventoryRowIndex == 1)
        #expect(candidates[2].inventoryRowIndex == 0)
    }

    @Test func fuzzyDisplayLabelIncludesExpiryWhenPresent() {
        let inventory = [
            row(name: "牛奶", unit: "瓶", quantity: "2", expiryLabel: "3天后过期", expiryDate: date(3))
        ]
        let candidates = ProposalPlanner.fuzzyMatchInventoryRows("牛奶", inventory)
        #expect(candidates[0].displayLabel == "牛奶 2\(UnitLabels.displayLabel(for: "瓶")) · 3天后过期")
        #expect(candidates[0].inventoryRowUnit == "瓶")

        let noLabel = [row(name: "盐", unit: "g", quantity: "100")]
        let c2 = ProposalPlanner.fuzzyMatchInventoryRows("盐", noLabel)
        #expect(c2[0].displayLabel == "盐 100g")
    }

    // MARK: - DeductionProposalFactory

    @Test func deductionNoMatchProducesSkip() {
        let recipe = makeRecipe(id: "r1", ingredients: [RecipeIngredient(name: "海带", quantity: 2, unit: "片")])
        let inventory: [Ingredient] = []
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals.count == 1)
        #expect(proposals[0].action == .skip)
        #expect(proposals[0].selected == false)
        #expect(proposals[0].chosenIndex == -1)
        #expect(proposals[0].deductAmount == "0")
        #expect(proposals[0].id == "d_r1_0")
    }

    @Test func deductionMatchPicksFirstCandidateAndComputesAmount() {
        let recipe = makeRecipe(id: "r2", ingredients: [RecipeIngredient(name: "牛奶", quantity: 1, unit: "瓶")])
        let inventory = [row(name: "牛奶", unit: "瓶", quantity: "3")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals[0].action == .deduct)
        #expect(proposals[0].chosenIndex == 0)
        #expect(proposals[0].deductAmount == "1")
        #expect(proposals[0].id == "d_r2_0")
    }

    @Test func deductionUnitMismatchFallsBackToOne() {
        // Recipe unit "片" vs inventory unit "g" -> incompatible -> "1".
        let recipe = makeRecipe(id: "r3", ingredients: [RecipeIngredient(name: "姜", quantity: 3, unit: "片")])
        let inventory = [row(name: "姜", unit: "g", quantity: "200")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals[0].deductAmount == "1")
    }

    @Test func deductionCompatibleUnitUsesRecipeMagnitude() {
        let recipe = makeRecipe(id: "r4", ingredients: [RecipeIngredient(name: "米", quantity: 2.5, unit: "g")])
        let inventory = [row(name: "米", unit: "g", quantity: "100")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals[0].deductAmount == "2.5")
    }

    @Test func deductionEmptyUnitIsCompatible() {
        // Recipe with no unit (nil) is treated as compatible with any row unit.
        let recipe = makeRecipe(id: "r5", ingredients: [RecipeIngredient(name: "鸡蛋", quantity: 2)])
        let inventory = [row(name: "鸡蛋", unit: "个", quantity: "6")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals[0].deductAmount == "2")
    }

    @Test func deductionZeroOrNegativeMagnitudeFallsBackToOne() {
        // Fuzzy amount (note, no numeric quantity) -> magnitude nil -> "1".
        let recipe = makeRecipe(id: "r6", ingredients: [RecipeIngredient(name: "盐", note: "适量")])
        let inventory = [row(name: "盐", unit: "g", quantity: "100")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        // No leading number -> magnitude nil -> "1" (never silently 0).
        #expect(proposals[0].deductAmount == "1")
    }

    // MARK: - IngredientFactory

    @Test func ingredientFactoryAppliesKnowledgeDefaults() {
        // 牛奶 is a known perishable with a shelf life in the knowledge base.
        let item = shopping(name: "牛奶", detail: "anything")
        let ingredient = IngredientFactory.fromShoppingItem(item, now: Date())
        #expect(ingredient.id.isEmpty) // local rows have empty id
        #expect(ingredient.quantity == "1")
        #expect(ingredient.unit == "份")
        #expect(ingredient.shelfLifeDays != nil)
        #expect(ingredient.expiryDate != nil)
        #expect(ingredient.freshnessPercent == 1.0)
        #expect(ingredient.expiryLabel == String(localized: "expiry.inDays \(ingredient.shelfLifeDays!)"))
        #expect(ingredient.category == FoodKnowledge.categoryFor("牛奶"))
    }

    @Test func ingredientFactoryUnknownNameNoExpiry() {
        // An unknown name has no knowledge default -> nil shelf life, 0.85 freshness.
        let item = shopping(name: "zzz未知食材zzz", detail: "x")
        let ingredient = IngredientFactory.fromShoppingItem(item, now: Date())
        #expect(ingredient.shelfLifeDays == nil)
        #expect(ingredient.expiryDate == nil)
        #expect(ingredient.freshnessPercent == 0.85)
        #expect(ingredient.expiryLabel == String(localized: "expiry.fresh"))
        #expect(ingredient.storage == .fridge) // default when no knowledge
    }

    @Test func ingredientFactoryCarriesImageUrl() {
        let item = shopping(name: "苹果", detail: "x", imageUrl: "http://img")
        #expect(IngredientFactory.fromShoppingItem(item).imageUrl == "http://img")
        let noImg = shopping(name: "苹果", detail: "x", imageUrl: nil)
        #expect(IngredientFactory.fromShoppingItem(noImg).imageUrl == "")
    }

    // MARK: - Apply: Intake (new row, merge, re-resolution)

    @Test func applyIntakeNewRowAppends() {
        let inventory: [Ingredient] = []
        let proposal = IntakeProposal(
            id: "p1", name: "面粉", quantity: "2", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil, action: .newRow
        )
        var counter = 0
        let result = ProposalApply.applyIntakeProposals(
            [proposal], inventory: inventory,
            idGenerator: { counter += 1; return "uuid-\(counter)" }
        )
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].name == "面粉")
        #expect(result.inventory[0].quantity == "2")
        #expect(result.appliedIds == ["p1"])
        #expect(result.syncIntents.count == 1)
        #expect(result.syncIntents[0].operation == .create)
        #expect(result.syncIntents[0].baseVersion == nil)
    }

    @Test func applyIntakeMergeSumsQuantitiesViaFormatQuantity() {
        let inventory = [
            row(id: "row-uuid", name: "白糖", unit: "袋", quantity: "1.5", storage: .pantry,
                category: "其他", remoteVersion: 7)
        ]
        let proposal = IntakeProposal(
            id: "p2", name: "白糖", quantity: "0.75", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0"
        )
        let result = ProposalApply.applyIntakeProposals([proposal], inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "2.25") // 1.5 + 0.75, 2dp via formatQuantity
        #expect(result.inventory[0].id == "row-uuid") // merge keeps existing id
        #expect(result.syncIntents[0].operation == .intake)
        #expect(result.syncIntents[0].baseVersion == 7)
    }

    @Test func applyIntakeReResolvesMergeByIdentityWhenListReordered() {
        // mergeTargetId "0" points at index 0 at compute time, but the live list
        // has been REORDERED so the real 白糖 row is now at index 2. Apply must
        // re-resolve by identity (name×unit×storage), not blindly trust index 0.
        let inventory = [
            row(id: "a", name: "酱油", unit: "瓶", quantity: "1", storage: .pantry, category: "其他"),
            row(id: "b", name: "醋", unit: "瓶", quantity: "1", storage: .pantry, category: "其他"),
            row(id: "c", name: "白糖", unit: "袋", quantity: "2", storage: .pantry, category: "其他"),
        ]
        let proposal = IntakeProposal(
            id: "p3", name: "白糖", quantity: "1", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0" // stale index!
        )
        let result = ProposalApply.applyIntakeProposals([proposal], inventory: inventory)
        #expect(result.inventory.count == 3) // merged, no new row
        #expect(result.inventory[2].name == "白糖")
        #expect(result.inventory[2].quantity == "3") // 2 + 1 on the RIGHT row
        // The unrelated rows are untouched.
        #expect(result.inventory[0].quantity == "1")
        #expect(result.inventory[1].quantity == "1")
    }

    @Test func applyIntakeMergeTargetGoneFallsBackToNewRow() {
        // The 白糖 row the proposal wanted to merge into has been REMOVED via sync.
        // Re-resolution finds no target -> a safe new row, never corrupting another.
        let inventory = [
            row(id: "a", name: "酱油", unit: "瓶", quantity: "1", storage: .pantry, category: "其他")
        ]
        let proposal = IntakeProposal(
            id: "p4", name: "白糖", quantity: "1", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0"
        )
        let result = ProposalApply.applyIntakeProposals(
            [proposal], inventory: inventory, idGenerator: { "minted" }
        )
        #expect(result.inventory.count == 2)
        #expect(result.inventory[1].name == "白糖")
        #expect(result.inventory[1].id == "minted")
        #expect(result.syncIntents[0].operation == .create)
    }

    @Test func applyIntakeNonNumericProposalQuantityFallsBackToNewRow() {
        // 「适量」merging into "2" must NOT yield "2" — the intake would silently
        // vanish. It degrades to an independent new row instead.
        let inventory = [
            row(id: "row-uuid", name: "米", unit: "袋", quantity: "2", storage: .pantry, category: "其他")
        ]
        let proposal = IntakeProposal(
            id: "p7", name: "米", quantity: "适量", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0"
        )
        let result = ProposalApply.applyIntakeProposals(
            [proposal], inventory: inventory, idGenerator: { "minted" }
        )
        #expect(result.inventory.count == 2)
        #expect(result.inventory[0].quantity == "2") // target untouched
        #expect(result.inventory[1].quantity == "适量") // intake preserved as its own row
        #expect(result.syncIntents[0].operation == .create)
    }

    @Test func applyIntakeNonNumericTargetQuantityFallsBackToNewRow() {
        // The mirror case: numeric intake, non-numeric existing stock. Merging
        // would coerce "适量" to 0 and destroy the existing row's meaning.
        let inventory = [
            row(id: "row-uuid", name: "盐", unit: "g", quantity: "适量", storage: .pantry, category: "其他")
        ]
        let proposal = IntakeProposal(
            id: "p8", name: "盐", quantity: "5", unit: "g",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .mergeInto, mergeTargetId: "0"
        )
        let result = ProposalApply.applyIntakeProposals(
            [proposal], inventory: inventory, idGenerator: { "minted" }
        )
        #expect(result.inventory.count == 2)
        #expect(result.inventory[0].quantity == "适量") // existing stock preserved
        #expect(result.inventory[1].quantity == "5")
        #expect(result.syncIntents[0].operation == .create)
    }

    @Test func sumQuantityGatesNonNumericSides() {
        #expect(ProposalApply.sumQuantity("适量", "2") == nil)
        #expect(ProposalApply.sumQuantity("2", "适量") == nil)
        #expect(ProposalApply.sumQuantity("1.5", "0.75") == "2.25")
        #expect(ProposalApply.sumQuantity(" 2 ", "1") == "3") // trimmed via the gate
        // Non-finite parses are gated too — formatQuantity would trap on Int(inf).
        #expect(ProposalApply.sumQuantity("inf", "2") == nil)
        #expect(ProposalApply.sumQuantity("nan", "2") == nil)
        #expect(ProposalApply.sumQuantity("1e999", "2") == nil)
        #expect(QuantityText.numeric("inf") == nil)
        #expect(QuantityText.numeric("nan") == nil)
        #expect(QuantityText.numeric(" 2.5 ") == 2.5)
    }

    @Test func applyIntakeSkipsDeselected() {
        let proposal = IntakeProposal(
            id: "p5", name: "面粉", quantity: "1", unit: "袋",
            category: "其他", storage: .pantry, shelfLifeDays: nil,
            action: .newRow, selected: false
        )
        let result = ProposalApply.applyIntakeProposals([proposal], inventory: [])
        #expect(result.inventory.isEmpty)
        #expect(result.appliedIds.isEmpty)
        #expect(result.syncIntents.isEmpty)
    }

    @Test func applyIntakeMintsUuidForNonUuidId() {
        // A new-row intake's ingredient is born with empty id -> withSyncId mints.
        let proposal = IntakeProposal(
            id: "p6", name: "盐", quantity: "1", unit: "g",
            category: "其他", storage: .pantry, shelfLifeDays: nil, action: .newRow
        )
        let result = ProposalApply.applyIntakeProposals(
            [proposal], inventory: [], idGenerator: { "fresh-uuid" }
        )
        #expect(result.inventory[0].id == "fresh-uuid")
        #expect(result.syncIntents[0].entityId == "fresh-uuid")
    }

    // MARK: - Apply: Deduction (reduce, remove, re-resolution)

    @Test func applyDeductionReducesQuantity() {
        let inventory = [row(id: "milk", name: "牛奶", unit: "瓶", quantity: "3", remoteVersion: 4)]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "牛奶 3瓶",
            inventoryRowId: "milk", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let proposal = DeductionProposal(
            id: "d1", recipeIngredientName: "牛奶", requiredQty: "1瓶",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "2")
        #expect(result.consumedDepartures.isEmpty)
        #expect(result.syncIntents[0].operation == .deduction)
        #expect(result.syncIntents[0].baseVersion == 4)
    }

    @Test func applyDeductionEmptiesRowAndLogsConsumed() {
        let inventory = [row(id: "egg", name: "鸡蛋", unit: "个", quantity: "2", remoteVersion: 1)]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "鸡蛋 2个",
            inventoryRowId: "egg", inventoryRowName: "鸡蛋", inventoryRowUnit: "个"
        )
        let proposal = DeductionProposal(
            id: "d2", recipeIngredientName: "鸡蛋", requiredQty: "2个",
            candidates: [candidate], chosenIndex: 0, deductAmount: "2"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory.isEmpty) // fully deducted -> removed
        #expect(result.consumedDepartures.count == 1)
        #expect(result.consumedDepartures[0].name == "鸡蛋")
        #expect(result.syncIntents[0].operation == .delete)
        #expect(result.syncIntents[0].baseVersion == 1)
    }

    @Test func applyDeductionNonNumericStockLeftUntouched() {
        // "适量" can't be coerced to 0 and deleted — leave the row.
        let inventory = [row(id: "salt", name: "盐", unit: "g", quantity: "适量")]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "盐 适量g",
            inventoryRowId: "salt", inventoryRowName: "盐", inventoryRowUnit: "g"
        )
        let proposal = DeductionProposal(
            id: "d3", recipeIngredientName: "盐", requiredQty: "1g",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "适量")
        #expect(result.syncIntents.isEmpty)
        #expect(result.consumedDepartures.isEmpty)
    }

    @Test func applyDeductionReResolvesRowByIdWhenListReordered() {
        // The chosen candidate captured index 0, but the live list reordered so
        // the 牛奶 row (id "milk") is now at index 2. Resolve by id, not index.
        let inventory = [
            row(id: "x", name: "醋", unit: "瓶", quantity: "1"),
            row(id: "y", name: "酱油", unit: "瓶", quantity: "1"),
            row(id: "milk", name: "牛奶", unit: "瓶", quantity: "3"),
        ]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "牛奶 3瓶", // stale index 0!
            inventoryRowId: "milk", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let proposal = DeductionProposal(
            id: "d4", recipeIngredientName: "牛奶", requiredQty: "1瓶",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory[2].quantity == "2") // deducted the RIGHT row
        #expect(result.inventory[0].quantity == "1") // 醋 untouched
        #expect(result.inventory[1].quantity == "1") // 酱油 untouched
    }

    @Test func applyDeductionEmptyIdFallsBackToNameGuardedIndex() {
        // Local-only row (empty id): resolve by the captured index guarded by name.
        let inventory = [row(id: "", name: "牛奶", unit: "瓶", quantity: "3")]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "牛奶 3瓶",
            inventoryRowId: "", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let proposal = DeductionProposal(
            id: "d5", recipeIngredientName: "牛奶", requiredQty: "1瓶",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory[0].quantity == "2")
    }

    @Test func applyDeductionNameDriftRecoversWhenUnique() {
        // Empty id, captured index 0 now holds a DIFFERENT row, but exactly one
        // row still carries the captured name -> recover to that row.
        let inventory = [
            row(id: "", name: "醋", unit: "瓶", quantity: "1"),
            row(id: "", name: "牛奶", unit: "瓶", quantity: "3"),
        ]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "牛奶 3瓶", // drifted; index 0 is now 醋
            inventoryRowId: "", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let proposal = DeductionProposal(
            id: "d6", recipeIngredientName: "牛奶", requiredQty: "1瓶",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory[0].quantity == "1") // 醋 untouched
        #expect(result.inventory[1].quantity == "2") // 牛奶 deducted
    }

    @Test func applyDeductionAggregatesTwoProposalsOntoSameRow() {
        // Two deductions resolving to the same row net into ONE deduction.
        let inventory = [row(id: "rice", name: "米", unit: "g", quantity: "100")]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "米 100g",
            inventoryRowId: "rice", inventoryRowName: "米", inventoryRowUnit: "g"
        )
        let p1 = DeductionProposal(
            id: "d7a", recipeIngredientName: "米", requiredQty: "30g",
            candidates: [candidate], chosenIndex: 0, deductAmount: "30"
        )
        let p2 = DeductionProposal(
            id: "d7b", recipeIngredientName: "米饭", requiredQty: "20g",
            candidates: [candidate], chosenIndex: 0, deductAmount: "20"
        )
        let result = ProposalApply.applyDeductionProposals([p1, p2], inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "50") // 100 - (30+20), one sync op
        #expect(result.syncIntents.count == 1)
    }

    @Test func applyDeductionSkipsZeroAmountAndDeselected() {
        let inventory = [row(id: "milk", name: "牛奶", unit: "瓶", quantity: "3")]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 0, displayLabel: "牛奶 3瓶",
            inventoryRowId: "milk", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let zero = DeductionProposal(
            id: "z", recipeIngredientName: "牛奶", requiredQty: "0",
            candidates: [candidate], chosenIndex: 0, deductAmount: "0"
        )
        let deselected = DeductionProposal(
            id: "d", recipeIngredientName: "牛奶", requiredQty: "1",
            candidates: [candidate], chosenIndex: 0, deductAmount: "1", selected: false
        )
        let skipped = DeductionProposal.empty(
            id: "s", recipeIngredientName: "牛奶", requiredQty: "1")
        let result = ProposalApply.applyDeductionProposals(
            [zero, deselected, skipped], inventory: inventory)
        #expect(result.inventory[0].quantity == "3") // nothing applied
        #expect(result.syncIntents.isEmpty)
    }

    @Test func applyDeductionRowGoneIsSkipped() {
        // Chosen row id no longer in inventory and the name doesn't exist -> skip.
        let inventory = [row(id: "other", name: "醋", unit: "瓶", quantity: "1")]
        let candidate = DeductionCandidate(
            inventoryRowIndex: 5, displayLabel: "牛奶 3瓶",
            inventoryRowId: "gone", inventoryRowName: "牛奶", inventoryRowUnit: "瓶"
        )
        let proposal = DeductionProposal(
            id: "d8", recipeIngredientName: "牛奶", requiredQty: "1瓶",
            candidates: [candidate], chosenIndex: 5, deductAmount: "1"
        )
        let result = ProposalApply.applyDeductionProposals([proposal], inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "1") // 醋 untouched
        #expect(result.syncIntents.isEmpty)
    }

    // MARK: - Apply: end-to-end through the factories (compute -> apply parity)

    @Test func endToEndIntakeFromShoppingThenApply() {
        // Compute proposals against inventory, then apply them — IngredientIdentity
        // is the sole arbiter at BOTH steps, so a merge resolved at compute time
        // still merges at apply time.
        let inventory = [
            row(id: "sugar-uuid", name: "白糖", unit: "袋", quantity: "1",
                storage: .pantry, category: "其他", remoteVersion: 2)
        ]
        let proposals = IntakeProposalFactory.fromShoppingItems(
            [shopping(id: "si_z", name: "白糖", detail: "2 袋", category: "其他")],
            inventory
        )
        #expect(proposals[0].action == .mergeInto)
        let result = ProposalApply.applyIntakeProposals(proposals, inventory: inventory)
        #expect(result.inventory.count == 1)
        #expect(result.inventory[0].quantity == "3") // 1 + 2
        #expect(result.appliedIds == ["ix_si_z"])
    }

    @Test func endToEndDeductionFromRecipeThenApply() {
        let recipe = makeRecipe(
            id: "rE",
            ingredients: [
                RecipeIngredient(name: "牛奶", quantity: 1, unit: "瓶"),
                RecipeIngredient(name: "海带", quantity: 2, unit: "片"), // no match -> skip
            ]
        )
        let inventory = [row(id: "milk", name: "牛奶", unit: "瓶", quantity: "2")]
        let proposals = DeductionProposalFactory.forRecipe(recipe, inventory)
        #expect(proposals.count == 2)
        #expect(proposals[0].action == .deduct)
        #expect(proposals[1].action == .skip)
        let result = ProposalApply.applyDeductionProposals(proposals, inventory: inventory)
        #expect(result.inventory[0].quantity == "1") // 牛奶 2 - 1; 海带 skipped silently
        #expect(result.syncIntents.count == 1)
    }

    // MARK: - isUuid / withSyncId parity

    @Test func isUuidMatchesCanonicalShape() {
        #expect(ProposalApply.isUuid("550e8400-e29b-41d4-a716-446655440000"))
        #expect(!ProposalApply.isUuid(""))
        #expect(!ProposalApply.isUuid("si_123"))
        #expect(!ProposalApply.isUuid("550e8400-e29b-41d4-a716"))
    }

    @Test func withSyncIdKeepsExistingUuid() {
        let item = row(id: "550e8400-e29b-41d4-a716-446655440000", name: "x", unit: "g")
        let kept = ProposalApply.withSyncId(item, idGenerator: { "SHOULD-NOT-BE-USED" })
        #expect(kept.id == "550e8400-e29b-41d4-a716-446655440000")
    }

    // MARK: - Helpers

    private func makeRecipe(id: String, ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(
            id: id, name: "测试", category: "其他", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: ingredients, steps: []
        )
    }
}
