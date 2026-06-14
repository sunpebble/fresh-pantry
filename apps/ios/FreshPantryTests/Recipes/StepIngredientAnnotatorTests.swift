import Foundation
import Testing
@testable import FreshPantry

/// Pure `StepIngredientAnnotator` — inline ingredient+amount segments inside a
/// cooking step. Longest-name-first; only amounts that exist are annotated.
struct StepIngredientAnnotatorTests {
    @Test func annotatesIngredientWithAmount() {
        let segs = StepIngredientAnnotator.annotate(
            "加入番茄翻炒",
            ingredients: [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")]
        )
        #expect(segs == [.text("加入"), .ingredient(name: "番茄", amount: "2个"), .text("翻炒")])
    }

    @Test func longestNameWins() {
        // 豆腐 must win over 豆 so we don't annotate the 豆 inside 豆腐.
        let segs = StepIngredientAnnotator.annotate(
            "放豆腐",
            ingredients: [
                RecipeIngredient(name: "豆", quantity: 1, unit: "把"),
                RecipeIngredient(name: "豆腐", quantity: 1, unit: "块"),
            ]
        )
        #expect(segs == [.text("放"), .ingredient(name: "豆腐", amount: "1块")])
    }

    @Test func ingredientsWithoutAmountAreNotAnnotated() {
        let segs = StepIngredientAnnotator.annotate(
            "撒盐调味",
            ingredients: [RecipeIngredient(name: "盐", note: "适量")]
        )
        // 适量 IS an amount (note) → annotated.
        #expect(segs == [.text("撒"), .ingredient(name: "盐", amount: "适量"), .text("调味")])
    }

    @Test func bareNameNoAmountStaysText() {
        let segs = StepIngredientAnnotator.annotate(
            "翻炒均匀",
            ingredients: [RecipeIngredient(name: "盐")]
        )
        #expect(segs == [.text("翻炒均匀")])
    }

    @Test func noCandidatesReturnsPlainText() {
        #expect(StepIngredientAnnotator.annotate("随便写点", ingredients: []) == [.text("随便写点")])
    }

    @Test func multipleOccurrencesEachAnnotated() {
        let segs = StepIngredientAnnotator.annotate(
            "先放糖再放糖",
            ingredients: [RecipeIngredient(name: "糖", quantity: 5, unit: "克")]
        )
        #expect(segs == [
            .text("先放"), .ingredient(name: "糖", amount: "5克"),
            .text("再放"), .ingredient(name: "糖", amount: "5克"),
        ])
    }

    @Test func hasAnnotationsReflectsMatch() {
        let ings = [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")]
        #expect(StepIngredientAnnotator.hasAnnotations("加入番茄翻炒", ingredients: ings))
        #expect(!StepIngredientAnnotator.hasAnnotations("翻炒均匀", ingredients: ings))
    }
}
