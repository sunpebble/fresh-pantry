import Foundation
import Testing
@testable import FreshPantry

/// #6 AI recipe rewrite — prompt construction + the shared-parser mapping.
struct AiRecipeRewriterTests {
    private func recipe() -> Recipe {
        Recipe(
            id: "r", name: "红烧肉", category: "荤菜", difficulty: 2, cookingMinutes: 60,
            description: "", ingredients: [
                RecipeIngredient(name: "五花肉", quantity: 500, unit: "克"),
                RecipeIngredient(name: "冰糖", note: "适量"),
            ],
            steps: ["五花肉切块", "焯水", "炒糖色"], tags: []
        )
    }

    @Test func promptCarriesRecipeAndInstruction() {
        let p = AiRecipeRewriter.buildUserPrompt(recipe: recipe(), instruction: "改成低卡少油版")
        #expect(p.contains("名称:红烧肉"))
        #expect(p.contains("五花肉 500克"))
        #expect(p.contains("冰糖 适量"))
        #expect(p.contains("1. 五花肉切块"))
        #expect(p.contains("改写要求:改成低卡少油版"))
    }

    @Test func promptIncludesInventoryAndExclusions() {
        let p = AiRecipeRewriter.buildUserPrompt(
            recipe: recipe(), instruction: "换成在库食材",
            inventoryNames: ["鸡胸肉", "  "], exclusions: ["花生"]
        )
        #expect(p.contains("我现有的食材(改写时优先使用):鸡胸肉"))
        #expect(p.contains("忌口(请勿使用):花生"))
    }

    @Test func blankInstructionThrows() async {
        await #expect {
            try await AiRecipeRewriter.rewrite(recipe: recipe(), instruction: "  ") { _ in "{}" }
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.emptyInstruction")) }
    }

    @Test func rewriteMapsReplyThroughSharedParser() async throws {
        let json = #"{"name":"低卡红烧肉","category":"荤菜","cookingMinutes":40,"difficulty":2,"description":"少油版","ingredients":[{"name":"五花肉","amount":"300克"}],"steps":["切块","少油炒"]}"#
        let draft = try await AiRecipeRewriter.rewrite(recipe: recipe(), instruction: "低卡") { _ in json }
        #expect(draft.name.value == "低卡红烧肉")
        #expect(draft.cookingMinutes.value == 40)
    }
}
