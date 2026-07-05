import Foundation
import Testing
@testable import FreshPantry

/// Tests for `AiRecipeParser.fromText` — the 拍照导入 (OCR text → recipe) flow.
/// The network is never touched: a fake `chatFn` returns crafted raw output. Two
/// purely testable seams are covered: (1) the prompt construction must carry the
/// passed text, and (2) the reply maps through the SHARED `mapToDraft`, so the
/// resulting `RecipeDraft` matches an imported one (no source URL) and inherits
/// the parser's tolerant-field / clamp behavior.
struct AiRecipeParserFromTextTests {
    // MARK: Prompt construction (pure, no network)

    @Test func userPromptCarriesTheText() {
        let text = "番茄炒蛋\n食材：番茄 2个 鸡蛋 3个\n步骤：1 切番茄 2 打蛋 3 翻炒"
        let prompt = AiRecipeParser.buildFromTextUserPrompt(text)
        #expect(prompt.contains("番茄炒蛋"))
        #expect(prompt.contains("鸡蛋 3个"))
        #expect(prompt.contains("翻炒"))
    }

    @Test func userPromptTrimsSurroundingWhitespace() {
        let prompt = AiRecipeParser.buildFromTextUserPrompt("\n\n  红烧肉  \n\n")
        // Leading/trailing whitespace is stripped; the content survives intact.
        #expect(prompt.contains("红烧肉"))
        #expect(!prompt.hasSuffix("\n"))
    }

    // MARK: Empty input guard

    @Test func emptyTextThrowsParse() async {
        await #expect {
            _ = try await AiRecipeParser.fromText("   \n  ", chatFn: { _ in "{}" })
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.emptyText")) }
    }

    // MARK: Reply maps through the shared parser

    @Test func cleanReplyMapsToDraftWithoutSourceUrl() async throws {
        let draft = try await AiRecipeParser.fromText(
            "番茄炒蛋 食材 番茄 鸡蛋 步骤 切炒",
            chatFn: { _ in #"""
            {
              "name": "番茄炒蛋",
              "category": "家常",
              "cookingMinutes": 12,
              "difficulty": 1,
              "description": "纸质菜谱整理",
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
        #expect(draft.description.value == "纸质菜谱整理")
        #expect(draft.ingredients.count == 2)
        #expect(draft.ingredients.first?.name.value == "番茄")
        #expect(draft.steps.map(\.value) == ["切番茄", "打蛋", "翻炒"])
        // OCR-imported from a photo, not a page: no source URL.
        #expect(draft.sourceUrl == nil)
    }

    @Test func difficultyAndMinutesClampInheritedFromParser() async throws {
        let draft = try await AiRecipeParser.fromText(
            "麻婆豆腐",
            chatFn: { _ in #"""
            {"name":"麻婆豆腐","category":"川菜","cookingMinutes":0,"difficulty":9,
             "ingredients":[],"steps":["a"]}
            """# }
        )
        // Same INVARIANT #12 clamps the URL importer applies.
        #expect(draft.difficulty.value == 5)
        #expect(draft.cookingMinutes.value == 30)
    }

    // MARK: Failure branches surfaced via the shared parser

    @Test func aiReportedErrorSurfaces() async {
        await #expect {
            _ = try await AiRecipeParser.fromText(
                "看不清的几个字",
                chatFn: { _ in #"{"error":"文本不足以抽取"}"# }
            )
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.aiReported 文本不足以抽取")) }
    }

    @Test func nonJsonReplyThrowsParse() async {
        await #expect {
            _ = try await AiRecipeParser.fromText(
                "番茄炒蛋",
                chatFn: { _ in "抱歉，我无法整理这段文本。" }
            )
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.invalidJson")) }
    }

    @Test func malformedIngredientEntryIsSkipped() async throws {
        let draft = try await AiRecipeParser.fromText(
            "番茄炒蛋",
            chatFn: { _ in #"""
            {"name":"n","category":"c","cookingMinutes":10,"difficulty":3,
             "ingredients":[
                {"name":"番茄","amount":"2个"},
                {"name":"鸡蛋"},
                "junk"
             ],
             "steps":["切","炒",5]}
            """# }
        )
        // Only the complete {name, amount} row survives; non-string step dropped.
        #expect(draft.ingredients.count == 1)
        #expect(draft.ingredients.first?.name.value == "番茄")
        #expect(draft.steps.map(\.value) == ["切", "炒"])
    }
}
