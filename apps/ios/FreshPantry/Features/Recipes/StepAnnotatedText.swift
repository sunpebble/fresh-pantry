import SwiftUI

/// Renders a cooking step with inline ingredient amounts: the (already-scaled)
/// quantity is shown right after each ingredient name found in the step text
/// ("加入番茄 2个 翻炒"), so the cook never hunts the ingredient list for "这一步放
/// 多少". Driven by the pure `StepIngredientAnnotator`; the result is a single
/// flowing `Text`, so the caller's `.font` / `.foregroundStyle` / `.lineSpacing`
/// modifiers apply as if it were a plain `Text`. Falls back to plain text when no
/// ingredient (with an amount) is mentioned.
struct StepAnnotatedText: View {
    let step: String
    /// Ingredients ALREADY scaled by the caller's 备料倍数 (single scaling source).
    let ingredients: [RecipeIngredient]

    var body: some View { Text(composed) }

    private var composed: AttributedString {
        var result = AttributedString()
        for segment in StepIngredientAnnotator.annotate(step, ingredients: ingredients) {
            switch segment {
            case let .text(text):
                result += AttributedString(text)
            case let .ingredient(name, amount):
                // Name stays in the sentence flow; the amount is the colored cue.
                result += AttributedString(name)
                var amt = AttributedString(" \(amount)")
                amt.font = .fkLabelMedium
                amt.foregroundColor = .fkPrimary
                result += amt
            }
        }
        return result
    }
}
