import Foundation

/// Extracts a structured `RecipeDraft` from a recipe-page URL: normalize + gate
/// the URL, fetch the page text, ask the LLM for structured JSON, then map it
/// into a draft (difficulty clamped 1–5, cookingMinutes ≤ 0 → 30 — services
/// INVARIANT #12). Stateless `enum` namespace. Ported from
/// `lib/services/ai_recipe_parser.dart`.
enum AiRecipeParser {
    /// System prompt — copied VERBATIM from the Dart parser (the field contract
    /// the UI keys off of). Do NOT reword.
    static let systemPrompt =
        "你是食谱抽取助手。用户会提供食谱网页的正文内容，请从中抽取结构化食谱。"
        + "不要声称无法访问网页；只根据提供的内容工作。"
        + "只返回 JSON，不要前后文。如果内容不足以抽取，返回 {\"error\":\"...\"}。"
        + "JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), "
        + "description, imageUrl (可空；如果网页内容包含“封面图片”，优先使用该 URL), "
        + "ingredients ([{name, amount}]), steps (string array)。"
        + stepAtomizationRule

    /// iOS-only addition (#16): instructs the model to keep steps atomic (one
    /// action per step) so Cook Mode's one-step-per-screen pager reads cleanly.
    /// Appended to both import prompts; does NOT change the JSON field contract the
    /// "do NOT reword" parity note above protects.
    static let stepAtomizationRule =
        "steps 请拆成单一动作的短句：一步只做一件事，把“一大段塞进一步”拆成多步，"
        + "保持原有先后顺序，不要合并步骤，也不要编造原文没有的步骤。"

    /// System prompt for the OCR-text path. The input is raw recognized text from
    /// a photographed / screenshotted recipe — lines may be out of order, broken
    /// mid-word, or carry OCR garble — so the model is told to TIDY the mess into
    /// the SAME recipe JSON schema the URL importer uses (so one `mapToDraft`
    /// handles both). No `imageUrl` field here: a photo has no cover URL to lift.
    /// Chinese, per the product requirement. Do NOT add fields without teaching
    /// `mapToDraft` about them.
    static let fromTextSystemPrompt =
        "你是食谱整理助手。用户会提供一段从纸质菜谱或截图 OCR 识别出来的杂乱文本，"
        + "可能有错别字、断行、顺序混乱或多余内容。请把它整理成一份结构化食谱。"
        + "尽量纠正明显的识别错误，合理拆分食材与步骤；只根据提供的文本工作，不要编造原文没有的内容。"
        + "只返回 JSON，不要前后文。如果文本不足以抽取出食谱，返回 {\"error\":\"...\"}。"
        + "JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), "
        + "description, ingredients ([{name, amount}]), steps (string array)。"
        + stepAtomizationRule

    /// Normalizes + gates the URL, fetches the page, runs the LLM, and parses the
    /// result into a `RecipeDraft`. `pageFetcher` is injectable so tests run with
    /// NO network/key. Throws `AiError.parse` on malformed / missing JSON and
    /// surfaces an AI-reported `error` field as `AiError.parse("AI 报告：…")`.
    static func fromUrl(
        _ url: String,
        chatFn: AiChatFn,
        pageFetcher: RecipePageFetcherFn = { try await RecipePageFetcher.fetchText($0) }
    ) async throws -> RecipeDraft {
        let normalized = try ensureRecipeUrl(url)
        let pageText = try await pageFetcher(normalized)

        let messages: [AiMessage] = [
            .text("system", systemPrompt),
            .text("user", "来源 URL：\(normalized)\n\n网页内容：\n\(pageText)"),
        ]

        let raw = try await chatFn(messages)
        return try mapToDraft(raw, sourceUrl: normalized)
    }

    /// Builds the user-message text wrapping the OCR'd recipe text. Exposed (not
    /// inlined) so the prompt construction — "must carry the recognized text" — is
    /// unit-testable WITHOUT the network. Trims surrounding whitespace; the body is
    /// passed through verbatim so the model sees exactly what OCR produced.
    static func buildFromTextUserPrompt(_ text: String) -> String {
        "食谱文本（OCR 识别，可能有误）：\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Extracts a structured `RecipeDraft` from a block of free-form recipe text —
    /// the photo-import (OCR) path. Mirrors `fromUrl`/`fromIngredients`: feed the
    /// text to the LLM under the OCR system prompt, then funnel the raw reply
    /// through the SHARED `mapToDraft` (no source URL — a photo isn't imported from
    /// a page). `chatFn` is injectable so tests run with NO network/key. Throws
    /// `AiError.parse("食谱文本为空")` when the input is blank (parity with the other
    /// parsers' empty-input guard); propagates the parser's `AiError.parse` on
    /// malformed / missing JSON and surfaces an AI-reported `error` field.
    static func fromText(_ text: String, chatFn: AiChatFn) async throws -> RecipeDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AiError.parse("食谱文本为空") }

        let messages: [AiMessage] = [
            .text("system", fromTextSystemPrompt),
            .text("user", buildFromTextUserPrompt(trimmed)),
        ]
        let raw = try await chatFn(messages)
        return try mapToDraft(raw, sourceUrl: nil)
    }

    /// Maps a raw LLM reply (the shared recipe JSON schema) into a `RecipeDraft`,
    /// applying the field coercion + INVARIANT #12 clamps. The single source of
    /// truth for "recipe JSON → draft": both the URL importer and the clear-fridge
    /// generator funnel their raw replies through here, so they share ONE schema
    /// and one set of tolerant-field rules. `sourceUrl` is the import provenance
    /// (nil for a generated recipe). Throws `AiError.parse` on malformed / missing
    /// JSON and surfaces an AI-reported `error` field as `AiError.parse("AI 报告：…")`.
    static func mapToDraft(_ raw: String, sourceUrl: String?) throws -> RecipeDraft {
        guard let json = extractJsonObjectWithFallbacks(raw) else {
            throw AiError.parse("AI 返回不是合法 JSON")
        }
        if let errorValue = json["error"] {
            throw AiError.parse("AI 报告：\(describeError(errorValue))")
        }

        return RecipeDraft(
            sourceUrl: sourceUrl,
            name: .ai(try requireString(json, "name")),
            category: .ai(try requireString(json, "category")),
            cookingMinutes: .ai(try requireInt(json, "cookingMinutes")),
            difficulty: .ai(try requireInt(json, "difficulty")),
            description: .ai(stringOrEmpty(json["description"])),
            imageUrl: DraftField(value: optionalString(json["imageUrl"]), source: .ai),
            ingredients: parseIngredients(json["ingredients"]),
            steps: parseSteps(json["steps"])
        )
    }

    // MARK: - Field coercion (parity with Dart `_requireString` / `_requireInt`)

    /// Non-empty string at `key`, else `AiError.parse`.
    private static func requireString(_ map: [String: JSONValue], _ key: String) throws -> String {
        guard case let .string(value) = map[key], !value.isEmpty else {
            throw AiError.parse("字段 \(key) 缺失或非字符串")
        }
        return value
    }

    /// Int at `key` (int or rounded number), with the INVARIANT #12 clamps:
    /// `difficulty` → clamp(1, 5); `cookingMinutes` ≤ 0 → 30. Else `AiError.parse`.
    private static func requireInt(_ map: [String: JSONValue], _ key: String) throws -> Int {
        let raw: Int
        switch map[key] {
        case let .int(value):
            raw = value
        case let .double(value):
            raw = Int(value.rounded())
        default:
            throw AiError.parse("字段 \(key) 缺失或非整数")
        }
        if key == "difficulty" { return min(max(raw, 1), 5) }
        if key == "cookingMinutes" { return raw <= 0 ? 30 : raw }
        return raw
    }

    /// Ingredients: array of `{name, amount}` objects; a row missing either
    /// non-empty string is SKIPPED so one malformed entry never discards the
    /// batch (parity with the Dart `_requireString` + `whereType` filtering).
    private static func parseIngredients(_ value: JSONValue?) -> [RecipeIngredientDraft] {
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            guard case let .object(map) = item,
                  case let .string(name) = map["name"], !name.isEmpty,
                  case let .string(amount) = map["amount"], !amount.isEmpty
            else { return nil }
            return RecipeIngredientDraft(name: .ai(name), amount: .ai(amount))
        }
    }

    /// Steps: a string array; non-string entries dropped (Dart `whereType<String>`).
    private static func parseSteps(_ value: JSONValue?) -> [DraftField<String>] {
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            guard case let .string(step) = item else { return nil }
            return DraftField<String>.ai(step)
        }
    }

    /// `description` default "" (Dart `(json['description'] as String?) ?? ''`).
    private static func stringOrEmpty(_ value: JSONValue?) -> String {
        if case let .string(string) = value { return string }
        return ""
    }

    /// `imageUrl` is nullable — a string survives, anything else (incl. null) → nil.
    private static func optionalString(_ value: JSONValue?) -> String? {
        if case let .string(string) = value { return string }
        return nil
    }

    /// Stringifies the AI `error` payload for the surfaced message (it is usually
    /// a string but tolerate a number/bool so the report never reads "nil").
    private static func describeError(_ value: JSONValue) -> String {
        switch value {
        case let .string(string): return string
        case let .int(int): return String(int)
        case let .double(double): return String(double)
        case let .bool(bool): return String(bool)
        case .null, .array, .object: return "内容不足以抽取"
        }
    }
}
