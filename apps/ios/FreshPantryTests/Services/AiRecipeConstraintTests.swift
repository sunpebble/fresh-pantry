import Foundation
import Testing
@testable import FreshPantry

/// #5 conversational constraint generation — `AiRecipeGenerator.buildUserPrompt`
/// folds a free-text constraint + 忌口 into the prompt (backward compatible: no
/// constraint → the original prompt).
struct AiRecipeConstraintTests {
    @Test func noConstraintMatchesBasePrompt() {
        let prompt = AiRecipeGenerator.buildUserPrompt(["番茄", "鸡蛋"])
        #expect(prompt.contains("- 番茄"))
        #expect(prompt.contains("- 鸡蛋"))
        #expect(!prompt.contains("额外要求"))
        #expect(!prompt.contains("忌口"))
        #expect(prompt.hasSuffix("请生成一道用到上述食材的家常菜。"))
    }

    @Test func constraintIsIncluded() {
        let prompt = AiRecipeGenerator.buildUserPrompt(["番茄"], constraint: "清淡、15分钟内、晚餐")
        #expect(prompt.contains("额外要求:清淡、15分钟内、晚餐"))
    }

    @Test func blankConstraintIsOmitted() {
        let prompt = AiRecipeGenerator.buildUserPrompt(["番茄"], constraint: "   ")
        #expect(!prompt.contains("额外要求"))
    }

    @Test func exclusionsAreListed() {
        let prompt = AiRecipeGenerator.buildUserPrompt(["豆腐"], exclusions: ["花生", "  ", "香菜"])
        #expect(prompt.contains("忌口(请勿使用):花生、香菜"))
    }

    @Test func constraintAndExclusionsBothAppear() {
        let prompt = AiRecipeGenerator.buildUserPrompt(["鸡胸"], constraint: "高蛋白", exclusions: ["麸质"])
        #expect(prompt.contains("额外要求:高蛋白"))
        #expect(prompt.contains("忌口(请勿使用):麸质"))
    }
}
