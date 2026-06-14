import Foundation

/// Rewrites an EXISTING recipe per a user instruction (转素食 / 低卡少油 / 用我现有
/// 的食材替换 / 替换过敏原…) — #6. Feeds the recipe + instruction (+ optional
/// inventory & 忌口) to the model and maps the reply through the SHARED
/// `AiRecipeParser.mapToDraft`, so the rewritten result is a normal `RecipeDraft`
/// the user reviews + saves as a custom recipe (one parser, one field contract).
enum AiRecipeRewriter {
    static let systemPrompt =
        "你是食谱改写助手。用户会给出一份现有食谱和改写要求，请在尽量保留这道菜风味与可操作性的前提下改写。"
        + "只根据给定内容改写，不要编造无关菜品。只返回 JSON，不要前后文。如果无法改写，返回 {\"error\":\"...\"}。"
        + "JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), "
        + "description, ingredients ([{name, amount}]), steps (string array)。"
        + AiRecipeParser.stepAtomizationRule

    /// Builds the user message: the source recipe (name/食材/步骤) + the rewrite
    /// instruction, plus optional 现有食材 (prefer reusing) and 忌口. Pure / testable.
    static func buildUserPrompt(
        recipe: Recipe,
        instruction: String,
        inventoryNames: [String] = [],
        exclusions: [String] = []
    ) -> String {
        let ingredients = recipe.ingredients
            .map { ingredient -> String in
                let amount = ingredient.displayAmount.trimmingCharacters(in: .whitespacesAndNewlines)
                return amount.isEmpty ? ingredient.name : "\(ingredient.name) \(amount)"
            }
            .joined(separator: "、")
        let steps = recipe.steps.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        var prompt = "现有食谱:\n名称:\(recipe.name)\n分类:\(recipe.category)\n食材:\(ingredients)\n步骤:\n\(steps)\n\n"
        prompt += "改写要求:\(instruction.trimmingCharacters(in: .whitespacesAndNewlines))\n"

        let inventory = inventoryNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !inventory.isEmpty {
            prompt += "我现有的食材(改写时优先使用):\(inventory.joined(separator: "、"))\n"
        }
        let cleanExclusions = exclusions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanExclusions.isEmpty {
            prompt += "忌口(请勿使用):\(cleanExclusions.joined(separator: "、"))\n"
        }
        prompt += "请输出改写后的完整食谱 JSON。"
        return prompt
    }

    /// Runs the rewrite via the injected `chatFn` and maps the reply through the
    /// shared parser. Throws `AiError.parse` on a blank instruction or malformed
    /// reply.
    static func rewrite(
        recipe: Recipe,
        instruction: String,
        inventoryNames: [String] = [],
        exclusions: [String] = [],
        chatFn: AiChatFn
    ) async throws -> RecipeDraft {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AiError.parse("请填写改写要求")
        }
        let messages: [AiMessage] = [
            .text("system", systemPrompt),
            .text("user", buildUserPrompt(
                recipe: recipe, instruction: instruction,
                inventoryNames: inventoryNames, exclusions: exclusions
            )),
        ]
        let raw = try await chatFn(messages)
        return try AiRecipeParser.mapToDraft(raw, sourceUrl: nil)
    }
}
