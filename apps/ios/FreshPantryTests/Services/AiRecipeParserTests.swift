import Foundation
import Testing
@testable import FreshPantry

/// `AiRecipeParser.fromUrl` parity tests, driven by a fake `AiChatFn` + a fake
/// `RecipePageFetcherFn` so NOTHING hits the network or needs an API key. Covers
/// the happy path, the INVARIANT #12 clamps (difficulty 1–5, cookingMinutes ≤ 0
/// → 30), the `{"error":…}` / non-JSON failure branches, malformed-ingredient
/// skipping, and null `imageUrl` tolerance.
struct AiRecipeParserTests {
    /// A supported host so `ensureRecipeUrl` passes before the fake fetcher runs.
    private let url = "https://www.xiachufang.com/recipe/100"

    /// Builds the parser with a fixed JSON reply and a no-op page fetcher.
    private func parse(replyingWith json: String) async throws -> RecipeDraft {
        try await AiRecipeParser.fromUrl(
            url,
            chatFn: { _ in json },
            pageFetcher: { _ in "网页内容" }
        )
    }

    // MARK: Happy path

    @Test func cleanJsonMapsToDraft() async throws {
        let draft = try await parse(replyingWith: #"""
        {
          "name": "番茄炒蛋",
          "category": "家常",
          "cookingMinutes": 15,
          "difficulty": 2,
          "description": "经典快手菜",
          "imageUrl": "https://img.example.com/a.jpg",
          "ingredients": [
            {"name": "番茄", "amount": "2个"},
            {"name": "鸡蛋", "amount": "3个"}
          ],
          "steps": ["切番茄", "打蛋", "翻炒"]
        }
        """#)

        #expect(draft.name.value == "番茄炒蛋")
        #expect(draft.name.source == .ai)
        #expect(draft.category.value == "家常")
        #expect(draft.cookingMinutes.value == 15)
        #expect(draft.difficulty.value == 2)
        #expect(draft.description.value == "经典快手菜")
        #expect(draft.imageUrl.value == "https://img.example.com/a.jpg")
        #expect(draft.sourceUrl == url)
        #expect(draft.ingredients.count == 2)
        #expect(draft.ingredients.first?.name.value == "番茄")
        #expect(draft.ingredients.first?.amount.value == "2个")
        #expect(draft.steps.map(\.value) == ["切番茄", "打蛋", "翻炒"])
    }

    @Test func numericDifficultyAndMinutesAsDoublesRound() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":20.6,"difficulty":3.4,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.cookingMinutes.value == 21)
        #expect(draft.difficulty.value == 3)
    }

    // MARK: INVARIANT #12 clamps

    @Test func difficultyAboveFiveClampsToFive() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":7,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.difficulty.value == 5)
    }

    @Test func difficultyZeroClampsToOne() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":0,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.difficulty.value == 1)
    }

    @Test func cookingMinutesZeroBecomes30() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":0,"difficulty":3,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.cookingMinutes.value == 30)
    }

    @Test func cookingMinutesNegativeBecomes30() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":-5,"difficulty":3,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.cookingMinutes.value == 30)
    }

    // MARK: Failure branches

    @Test func errorFieldThrowsParseWithMessage() async {
        await #expect {
            try await parse(replyingWith: #"{"error":"内容不足以抽取"}"#)
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.aiReported \("内容不足以抽取")")) }
    }

    @Test func nonJsonThrowsParse() async {
        await #expect {
            try await parse(replyingWith: "抱歉，我无法解析这个网页。")
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.invalidJson")) }
    }

    @Test func missingNameThrowsParse() async {
        await #expect {
            try await parse(replyingWith: #"""
            {"category":"c","cookingMinutes":10,"difficulty":3,"ingredients":[],"steps":[]}
            """#)
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.fieldMissingOrNotString \("name")")) }
    }

    @Test func nonIntCookingMinutesThrowsParse() async {
        await #expect {
            try await parse(replyingWith: #"""
            {"name":"n","category":"c","cookingMinutes":"快","difficulty":3,"ingredients":[],"steps":[]}
            """#)
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.fieldMissingOrNotInt \("cookingMinutes")")) }
    }

    // MARK: Tolerant fields

    @Test func malformedIngredientEntryIsSkipped() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":3,
         "ingredients":[
            {"name":"番茄","amount":"2个"},
            {"name":"鸡蛋"},
            {"amount":"5g"},
            "junk",
            {"name":"盐","amount":""}
         ],
         "steps":["a"]}
        """#)
        // Only the first row has both non-empty name AND amount.
        #expect(draft.ingredients.count == 1)
        #expect(draft.ingredients.first?.name.value == "番茄")
    }

    @Test func nonStringStepsAreDropped() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":3,
         "ingredients":[],"steps":["切","炒",5,null]}
        """#)
        #expect(draft.steps.map(\.value) == ["切", "炒"])
    }

    @Test func nullImageUrlTolerated() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":3,
         "imageUrl":null,"ingredients":[],"steps":[]}
        """#)
        #expect(draft.imageUrl.value == nil)
        #expect(draft.imageUrl.source == .ai)
    }

    @Test func missingDescriptionDefaultsToEmpty() async throws {
        let draft = try await parse(replyingWith: #"""
        {"name":"n","category":"c","cookingMinutes":10,"difficulty":3,
         "ingredients":[],"steps":[]}
        """#)
        #expect(draft.description.value == "")
    }

    @Test func fencedJsonIsExtracted() async throws {
        let draft = try await parse(replyingWith: """
        这是结果：
        ```json
        {"name":"红烧肉","category":"家常","cookingMinutes":60,"difficulty":4,"ingredients":[],"steps":[]}
        ```
        """)
        #expect(draft.name.value == "红烧肉")
        #expect(draft.cookingMinutes.value == 60)
    }

    // MARK: Host gate runs before the fetcher

    @Test func unsupportedHostThrowsBeforeFetch() async {
        await #expect {
            try await AiRecipeParser.fromUrl(
                "https://notxiachufang.com/recipe/1",
                chatFn: { _ in #"{"name":"x"}"# },
                pageFetcher: { _ in "should not run" }
            )
        } throws: { error in
            guard case .parse = error as? AiError else { return false }
            return true
        }
    }
}
