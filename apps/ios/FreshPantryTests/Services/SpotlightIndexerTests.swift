import CoreSpotlight
import Foundation
import Testing
@testable import FreshPantry

/// The Spotlight integration's pure construction/parsing logic: identifier
/// scheme round-trips, content-description assembly, and expiry formatting.
/// `CSSearchableIndex` itself is a system service and deliberately untested.
struct SpotlightItemIDTests {
    @Test func ingredientIdentifierRoundTrips() {
        let item = SpotlightItemID.ingredient("abc-123")
        #expect(item.identifier == "ingredient:abc-123")
        #expect(SpotlightItemID(identifier: item.identifier) == item)
    }

    @Test func recipeIdentifierRoundTrips() {
        let item = SpotlightItemID.recipe("howtocook_42")
        #expect(item.identifier == "recipe:howtocook_42")
        #expect(SpotlightItemID(identifier: item.identifier) == item)
    }

    @Test func parseRejectsUnknownPrefix() {
        #expect(SpotlightItemID(identifier: "shopping:abc") == nil)
        #expect(SpotlightItemID(identifier: "abc") == nil)
        #expect(SpotlightItemID(identifier: "") == nil)
    }

    @Test func parseRejectsEmptyPayload() {
        #expect(SpotlightItemID(identifier: "ingredient:") == nil)
        #expect(SpotlightItemID(identifier: "recipe:") == nil)
    }

    @Test func payloadMayItselfContainColons() {
        #expect(SpotlightItemID(identifier: "ingredient:a:b") == .ingredient("a:b"))
    }
}

struct SpotlightDescriptionTests {
    private func makeIngredient(
        id: String = "id-1",
        name: String = "牛奶",
        quantity: String = "2",
        unit: String = "盒",
        category: String? = "乳制品",
        expiryDate: Date? = nil
    ) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            imageUrl: "",
            freshnessPercent: 1,
            state: .fresh,
            category: category,
            expiryDate: expiryDate
        )
    }

    @Test func ingredientDescriptionJoinsCategoryQuantityAndExpiry() {
        let expiry = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let item = makeIngredient(expiryDate: expiry)
        let expiryText = String(localized: "spotlight.ingredient.expiresOn \("2026-06-15")")
        #expect(SpotlightIndexer.ingredientDescription(item) == "乳制品 · 2盒 · \(expiryText)")
    }

    @Test func ingredientDescriptionOmitsMissingCategoryAndExpiry() {
        let item = makeIngredient(category: nil, expiryDate: nil)
        #expect(SpotlightIndexer.ingredientDescription(item) == "2盒")
    }

    @Test func ingredientDescriptionEmptyWhenNothingKnown() {
        let item = makeIngredient(quantity: "", unit: "", category: nil, expiryDate: nil)
        #expect(SpotlightIndexer.ingredientDescription(item) == "")
    }

    private func makeRecipe(
        id: String = "r-1",
        name: String = "西红柿炒鸡蛋",
        category: String = "家常菜",
        description: String = "快手下饭菜"
    ) -> Recipe {
        Recipe(
            id: id,
            name: name,
            category: category,
            difficulty: 1,
            cookingMinutes: 10,
            description: description,
            ingredients: [],
            steps: []
        )
    }

    @Test func recipeDescriptionJoinsCategoryAndSummary() {
        let recipe = makeRecipe()
        #expect(SpotlightIndexer.recipeDescription(recipe) == "家常菜 · 快手下饭菜")
    }

    @Test func recipeDescriptionTruncatesLongSummary() {
        let long = String(repeating: "好", count: SpotlightIndexer.descriptionLimit + 10)
        let recipe = makeRecipe(description: long)
        let expectedSummary = String(repeating: "好", count: SpotlightIndexer.descriptionLimit) + "…"
        #expect(SpotlightIndexer.recipeDescription(recipe) == "家常菜 · \(expectedSummary)")
    }

    @Test func recipeDescriptionOmitsEmptySegments() {
        #expect(SpotlightIndexer.recipeDescription(makeRecipe(category: "", description: " ")) == "")
        #expect(SpotlightIndexer.recipeDescription(makeRecipe(description: "")) == "家常菜")
    }

    // MARK: Searchable-item construction (identifier/domain wiring)

    @Test func ingredientItemCarriesPrefixedIdentifierAndInventoryDomain() throws {
        let item = try #require(SpotlightIndexer.searchableItem(for: makeIngredient(id: "abc")))
        #expect(item.uniqueIdentifier == "ingredient:abc")
        #expect(item.domainIdentifier == SpotlightIndexer.inventoryDomain)
        #expect(item.attributeSet.title == "牛奶")
    }

    @Test func localOnlyIngredientIsSkipped() {
        // id == "" means local-only / never-synced — no stable id to deep-link
        // back to, and colliding identifiers would overwrite each other.
        #expect(SpotlightIndexer.searchableItem(for: makeIngredient(id: "")) == nil)
    }

    @Test func recipeItemCarriesPrefixedIdentifierAndRecipesDomain() throws {
        let item = try #require(SpotlightIndexer.searchableItem(for: makeRecipe(id: "r9")))
        #expect(item.uniqueIdentifier == "recipe:r9")
        #expect(item.domainIdentifier == SpotlightIndexer.recipesDomain)
        #expect(item.attributeSet.title == "西红柿炒鸡蛋")
    }

    @Test func emptyIdRecipeIsSkipped() {
        #expect(SpotlightIndexer.searchableItem(for: makeRecipe(id: "")) == nil)
    }
}
