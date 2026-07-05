import Foundation

/// Generates a single home-style recipe from a list of (expiring) ingredient
/// names — the "清冰箱" (clear-the-fridge) AI flow. Unlike `AiRecipeParser`, which
/// extracts a recipe from a fetched web page, this ASKS the model to invent a
/// dish that prioritizes the ingredients the user already has on hand.
///
/// Single source of truth on PURPOSE: the model is told to emit the SAME recipe
/// JSON schema as the URL importer, and the raw reply is mapped through the very
/// same `AiRecipeParser.mapToDraft`. So the output `RecipeDraft` (and thus the
/// downstream form / `CustomRecipe` save) is identical in shape to an imported
/// recipe — one parser, one field contract. Stateless `enum` namespace.
enum AiRecipeGenerator {
    /// Caps how many ingredient names ride along — a runaway pantry shouldn't
    /// balloon the prompt (the model only needs the leading临期 items anyway).
    static let maxIngredients = 30

    /// System prompt — pins the model to the SHARED recipe JSON contract (same
    /// fields `AiRecipeParser` expects) so one parser handles both flows. Chinese,
    /// per the product requirement. Do NOT add fields here without teaching
    /// `AiRecipeParser.mapToDraft` about them.
    static let systemPrompt =
        "你是家常菜食谱生成助手。用户会给出一份家里现有(尤其临期)的食材清单，" // i18n:ignore LLM prompt text, not UI text
        + "请据此生成一道好做的家常菜，尽量优先用掉这些食材，可补充少量常见调料。" // i18n:ignore LLM prompt text, not UI text
        + "只返回 JSON，不要前后文。如果无法生成，返回 {\"error\":\"...\"}。" // i18n:ignore LLM prompt text, not UI text
        + "JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), " // i18n:ignore LLM prompt text, not UI text
        + "description, ingredients ([{name, amount}]), steps (string array)。" // i18n:ignore LLM prompt text, not UI text

    /// Builds the user-message text from the ingredient names. Exposed (not
    /// inlined) so the prompt construction — "must list every passed ingredient" —
    /// is unit-testable WITHOUT the network. Names are trimmed + de-duplicated
    /// (order-preserving) and capped at `maxIngredients`; blanks are dropped.
    static func buildUserPrompt(
        _ ingredientNames: [String],
        constraint: String? = nil,
        exclusions: [String] = []
    ) -> String {
        let cleaned = sanitize(ingredientNames)
        let list = cleaned.map { "- \($0)" }.joined(separator: "\n")
        var prompt = "现有食材(优先用掉)：\n\(list)\n\n" // i18n:ignore LLM prompt text, not UI text
        // #5: free-text constraint (口味/时间/餐次/无麸质…) + 忌口, fed into the prompt
        // so the same generator becomes a conversational "用我现有食材做点…" assistant.
        if let constraint = constraint?.trimmingCharacters(in: .whitespacesAndNewlines), !constraint.isEmpty {
            prompt += "额外要求:\(constraint)\n" // i18n:ignore LLM prompt text, not UI text
        }
        let cleanExclusions = exclusions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanExclusions.isEmpty {
            prompt += "忌口(请勿使用):\(cleanExclusions.joined(separator: "、"))\n" // i18n:ignore LLM prompt text, not UI text
        }
        prompt += "请生成一道用到上述食材的家常菜。" // i18n:ignore LLM prompt text, not UI text
        return prompt
    }

    /// Trims, drops blanks, de-duplicates (first occurrence wins), and caps the
    /// list. Shared by `buildUserPrompt` and the empty-input guard so the prompt
    /// and the guard agree on what counts as "no ingredients".
    static func sanitize(_ ingredientNames: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ingredientNames {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
            if result.count >= maxIngredients { break }
        }
        return result
    }

    /// Generates the recipe: builds the prompt from `ingredientNames`, runs the
    /// injected `chatFn` (the prod call wraps `AiClient.chat`; tests inject a fake
    /// so NO network/key is needed), and maps the reply via the SHARED
    /// `AiRecipeParser.mapToDraft`. Throws `AiError.parse("食材清单为空")` when no
    /// usable name was passed (parity with the other parsers' empty-input guard);
    /// propagates the parser's `AiError.parse` on malformed / missing JSON.
    static func fromIngredients(
        _ ingredientNames: [String],
        constraint: String? = nil,
        exclusions: [String] = [],
        chatFn: AiChatFn
    ) async throws -> RecipeDraft {
        let cleaned = sanitize(ingredientNames)
        if cleaned.isEmpty { throw AiError.parse(String(localized: "error.recipeParse.emptyIngredientList")) }

        let messages: [AiMessage] = [
            .text("system", systemPrompt),
            .text("user", buildUserPrompt(cleaned, constraint: constraint, exclusions: exclusions)),
        ]
        let raw = try await chatFn(messages)
        // No source URL — this recipe is generated, not imported from a page.
        return try AiRecipeParser.mapToDraft(raw, sourceUrl: nil)
    }
}
