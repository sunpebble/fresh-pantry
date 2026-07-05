import Foundation
import Testing
@testable import FreshPantry

/// Tests for `AiRecipeGenerator` — the 清冰箱 (clear-the-fridge) flow. The
/// network is never touched: a fake `chatFn` returns crafted raw output. Two
/// purely testable seams are covered: (1) the prompt construction must list every
/// passed ingredient, and (2) the reply maps through the SHARED
/// `AiRecipeParser.mapToDraft`, so the resulting `RecipeDraft` matches an imported
/// one (no source URL) and inherits the parser's tolerant-field / clamp behavior.
struct AiRecipeGeneratorTests {
    // MARK: Prompt construction (pure, no network)

    @Test func userPromptListsEveryIngredient() {
        let names = ["番茄", "鸡蛋", "青椒"]
        let prompt = AiRecipeGenerator.buildUserPrompt(names)
        for name in names {
            #expect(prompt.contains(name))
        }
    }

    @Test func sanitizeTrimsDropsBlanksAndDeduplicates() {
        let cleaned = AiRecipeGenerator.sanitize(["  番茄 ", "", "鸡蛋", "番茄", "   "])
        #expect(cleaned == ["番茄", "鸡蛋"])
    }

    @Test func sanitizeCapsAtMax() {
        let many = (0..<(AiRecipeGenerator.maxIngredients + 10)).map { "食材\($0)" }
        #expect(AiRecipeGenerator.sanitize(many).count == AiRecipeGenerator.maxIngredients)
    }

    @Test func userPromptOnlyIncludesCappedAndCleanedNames() {
        // Blank + duplicate are dropped before the prompt is built.
        let prompt = AiRecipeGenerator.buildUserPrompt(["菠菜", " ", "菠菜", "豆腐"])
        #expect(prompt.contains("菠菜"))
        #expect(prompt.contains("豆腐"))
        // The duplicate collapses to a single bullet.
        #expect(prompt.components(separatedBy: "菠菜").count - 1 == 1)
    }

    // MARK: Empty input guard

    @Test func emptyIngredientsThrowsParse() async {
        await #expect {
            _ = try await AiRecipeGenerator.fromIngredients(["", "   "], chatFn: { _ in "{}" })
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.emptyIngredientList")) }
    }

    // MARK: Reply maps through the shared parser

    @Test func cleanReplyMapsToDraftWithoutSourceUrl() async throws {
        let draft = try await AiRecipeGenerator.fromIngredients(
            ["番茄", "鸡蛋"],
            chatFn: { _ in #"""
            {
              "name": "番茄炒蛋",
              "category": "家常",
              "cookingMinutes": 12,
              "difficulty": 1,
              "description": "快手清冰箱",
              "ingredients": [
                {"name": "番茄", "amount": "2个"},
                {"name": "鸡蛋", "amount": "3个"}
              ],
              "steps": ["切番茄", "打蛋", "翻炒"]
            }
            """# }
        )

        #expect(draft.name.value == "番茄炒蛋")
        #expect(draft.name.source == .ai)
        #expect(draft.cookingMinutes.value == 12)
        #expect(draft.difficulty.value == 1)
        #expect(draft.ingredients.count == 2)
        #expect(draft.steps.map(\.value) == ["切番茄", "打蛋", "翻炒"])
        // Generated, not imported: no source URL.
        #expect(draft.sourceUrl == nil)
    }

    @Test func difficultyClampInheritedFromParser() async throws {
        let draft = try await AiRecipeGenerator.fromIngredients(
            ["豆腐"],
            chatFn: { _ in #"""
            {"name":"麻婆豆腐","category":"川菜","cookingMinutes":0,"difficulty":9,
             "ingredients":[],"steps":["a"]}
            """# }
        )
        // Same INVARIANT #12 clamps the URL importer applies.
        #expect(draft.difficulty.value == 5)
        #expect(draft.cookingMinutes.value == 30)
    }

    @Test func aiReportedErrorSurfaces() async {
        await #expect {
            _ = try await AiRecipeGenerator.fromIngredients(
                ["白菜"],
                chatFn: { _ in #"{"error":"食材太少"}"# }
            )
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.aiReported 食材太少")) }
    }

    @Test func nonJsonReplyThrowsParse() async {
        await #expect {
            _ = try await AiRecipeGenerator.fromIngredients(
                ["白菜"],
                chatFn: { _ in "抱歉，我无法生成食谱。" }
            )
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.invalidJson")) }
    }
}
