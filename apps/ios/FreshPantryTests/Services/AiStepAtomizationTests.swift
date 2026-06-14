import Foundation
import Testing
@testable import FreshPantry

/// #16 AI step atomization — both import prompts carry the "one action per step"
/// instruction while keeping the JSON field contract intact.
struct AiStepAtomizationTests {
    @Test func urlPromptCarriesAtomizationRule() {
        #expect(AiRecipeParser.systemPrompt.contains("单一动作"))
        #expect(AiRecipeParser.systemPrompt.contains("steps (string array)"))
    }

    @Test func ocrPromptCarriesAtomizationRule() {
        #expect(AiRecipeParser.fromTextSystemPrompt.contains("单一动作"))
        #expect(AiRecipeParser.fromTextSystemPrompt.contains("steps (string array)"))
    }

    @Test func ruleForbidsMergingAndInventing() {
        #expect(AiRecipeParser.stepAtomizationRule.contains("不要合并"))
        #expect(AiRecipeParser.stepAtomizationRule.contains("不要编造"))
    }
}
