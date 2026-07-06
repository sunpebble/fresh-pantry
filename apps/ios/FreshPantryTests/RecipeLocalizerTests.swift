import XCTest
@testable import FreshPantry

final class RecipeLocalizerTests: XCTestCase {
    func testOverlayLanguagePicksFirstSupportedLanguage() {
        XCTAssertEqual(RecipeLocalizer.overlayLanguage(preferred: ["ja"]), "ja")
        XCTAssertEqual(RecipeLocalizer.overlayLanguage(preferred: ["en-US"]), "en")
        XCTAssertEqual(RecipeLocalizer.overlayLanguage(preferred: ["de", "fr"]), "fr")
        XCTAssertNil(RecipeLocalizer.overlayLanguage(preferred: ["zh-Hans"]))
        XCTAssertNil(RecipeLocalizer.overlayLanguage(preferred: ["de"]))
    }

    func testApplyReplacesTranslatableFieldsAndKeepsStructure() {
        let recipe = Recipe(
            id: "r1",
            name: "咖喱炒蟹",
            category: "水产",
            difficulty: 4,
            cookingMinutes: 30,
            description: "原描述",
            ingredients: [
                RecipeIngredient(name: "青蟹", quantity: 1, unit: "只"),
                RecipeIngredient(name: "咖喱块", quantity: 15, unit: "克"),
            ],
            steps: ["处理螃蟹", "炒咖喱", "收汁"],
            tags: ["水产"],
            imageUrl: "https://example.com/crab.jpg",
            nutrition: NutritionFacts(energyKcal: 750, protein: 24, carbs: 32, fat: 59),
            stepDurations: [nil, 10, nil]
        )
        let entry = RecipeOverlayEntry(
            name: "Curry Crab",
            description: "A saucy crab dish.",
            category: "Seafood",
            steps: ["Prep the crab", "Fry the curry", "Reduce the sauce"],
            tags: ["seafood"],
            ingredients: [
                .init(name: "mud crab", unit: "whole", note: nil),
                .init(name: "curry block", unit: "g", note: nil),
            ]
        )

        let out = RecipeLocalizer.apply(["r1": entry], to: [recipe])[0]

        XCTAssertEqual(out.name, "Curry Crab")
        XCTAssertEqual(out.description, "A saucy crab dish.")
        XCTAssertEqual(out.category, "Seafood")
        XCTAssertEqual(out.steps, ["Prep the crab", "Fry the curry", "Reduce the sauce"])
        XCTAssertEqual(out.tags, ["seafood"])
        XCTAssertEqual(out.ingredients[0].name, "mud crab")
        XCTAssertEqual(out.ingredients[0].quantity, recipe.ingredients[0].quantity)
        XCTAssertEqual(out.ingredients[0].unit, "whole")
        XCTAssertEqual(out.imageUrl, recipe.imageUrl)
        XCTAssertEqual(out.nutrition, recipe.nutrition)
        XCTAssertEqual(out.stepDurations, recipe.stepDurations)
    }

    func testMissingIdFallsBackToOriginalAndMismatchedArraysKeepTopLevelTranslation() {
        let recipe = Recipe(
            id: "r1",
            name: "番茄炒蛋",
            category: "荤菜",
            difficulty: 1,
            cookingMinutes: 10,
            description: "原描述",
            ingredients: [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")],
            steps: ["切", "炒"],
            tags: []
        )
        let mismatched = RecipeOverlayEntry(
            name: "Tomato Eggs",
            description: "d",
            category: "Meat Dishes",
            steps: ["only one"],
            tags: [],
            ingredients: [.init(name: "tomato", unit: nil, note: nil)]
        )

        let missing = RecipeLocalizer.apply([:], to: [recipe])[0]
        XCTAssertEqual(missing, recipe)
        let partial = RecipeLocalizer.apply(["r1": mismatched], to: [recipe])[0]
        XCTAssertEqual(partial.name, "Tomato Eggs")
        XCTAssertEqual(partial.description, "d")
        XCTAssertEqual(partial.category, "Meat Dishes")
        XCTAssertEqual(partial.ingredients[0].name, "tomato")
        XCTAssertEqual(partial.ingredients[0].unit, recipe.ingredients[0].unit)
        XCTAssertEqual(partial.steps, recipe.steps)
        XCTAssertEqual(RecipeLocalizer.apply(nil, to: [recipe])[0], recipe)
    }
}
