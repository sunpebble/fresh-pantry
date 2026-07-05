import Foundation

/// The injected chat seam — a closure that runs the LLM call. Keeps the parser
/// testable without the network (the prod call wraps `AiClient.chat`). Mirrors
/// the Dart `typedef AiChatFn = Future<String> Function(List<AiMessage>)`.
typealias AiChatFn = @Sendable ([AiMessage]) async throws -> String

/// Parses free text OR a photo into a list of `IngredientDraft` via the LLM.
/// Stateless `enum` namespace. Ported from `lib/services/ai_ingredient_parser.dart`
/// (`fromText` + `fromImage`, both reusing the same `parseList`).
enum AiIngredientParser {
    static let maxTextLength = 5000

    /// System prompt — copied VERBATIM from the Dart parser (the field contract
    /// the model must honor: name/quantity/unit/category/storage/shelfLifeDays).
    static let systemPrompt =
        "你是食材清单解析助手。把用户输入的食材文本拆为多条结构化条目。" // i18n:ignore LLM prompt text, not UI text
        + "只返回 JSON 数组，每条 {name, quantity, unit, category, storage (fridge/pantry), shelfLifeDays}。" // i18n:ignore LLM prompt text, not UI text
        + "估算合理的数量、单位、分类、存储、保质期。" // i18n:ignore LLM prompt text, not UI text

    /// Vision system prompt — copied VERBATIM from the Dart `fromImage` (the same
    /// field contract as the text path, scoped to recognizing items in a photo).
    static let imageSystemPrompt =
        "你是食材识别助手。识别图中所有可入库的食材，返回 JSON 数组：" // i18n:ignore LLM prompt text, not UI text
        + "{name, quantity, unit, category, storage (fridge/pantry), shelfLifeDays}。" // i18n:ignore LLM prompt text, not UI text

    /// Trims + truncates the input, runs the chat call, and parses the result.
    /// Throws `AiError.parse("文本不能为空")` on empty input.
    static func fromText(_ text: String, chatFn: AiChatFn) async throws -> [IngredientDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AiError.parse(String(localized: "error.ingredientParse.emptyText")) }
        let input = trimmed.count > maxTextLength ? String(trimmed.prefix(maxTextLength)) : trimmed

        let messages: [AiMessage] = [
            .text("system", systemPrompt),
            .text("user", input),
        ]
        let raw = try await chatFn(messages)
        return try parseList(raw)
    }

    /// Recognizes ingredients in a photo (groceries / a fridge) via the vision
    /// chat call and parses the result with the SAME `parseList` as the text path.
    /// `imageData` is JPEG bytes (the caller downscales before passing). Throws
    /// `AiError.parse("图片为空")` when the data is empty (parity with the Dart
    /// `ArgumentError('图片为空')`).
    static func fromImage(_ imageData: Data, chatFn: AiChatFn) async throws -> [IngredientDraft] {
        if imageData.isEmpty { throw AiError.parse(String(localized: "error.ingredientParse.emptyImage")) }
        let dataUrl = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let messages: [AiMessage] = [
            .text("system", imageSystemPrompt),
            .userWithImage("请识别图中食材", dataUrl), // i18n:ignore LLM prompt text, not UI text
        ]
        let raw = try await chatFn(messages)
        return try parseList(raw)
    }

    /// Decodes the LLM array into drafts, skipping malformed entries so one bad
    /// row never discards the whole batch (parity with the Dart `_parseList`).
    static func parseList(_ raw: String) throws -> [IngredientDraft] {
        guard let list = extractJsonArrayWithFallbacks(raw) else {
            throw AiError.parse(String(localized: "error.ingredientParse.invalidJsonArray"))
        }
        var items: [IngredientDraft] = []
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var idCounter = 0
        for entry in list {
            guard case let .object(map) = entry else { continue }
            guard let name = string(map["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { continue }

            let category: String? = string(map["category"]) ?? FoodCategories.other
            items.append(
                IngredientDraft(
                    id: "ai_\(nowMs)_\(idCounter)",
                    name: .ai(name),
                    quantity: .ai(stringValue(map["quantity"]) ?? "1"),
                    unit: .ai(string(map["unit"]) ?? "个"), // i18n:ignore domain unit-default identity (used app-wide in Inventory), not new UI text
                    category: .ai(category),
                    storage: .ai(parseStorage(string(map["storage"]))),
                    shelfLifeDays: .ai(parsePositiveInt(map["shelfLifeDays"]))
                )
            )
            idCounter += 1
        }
        return items
    }

    // MARK: - Field coercion

    /// `'pantry'→.pantry`, `'freezer'→.freezer`, `'fridge'→.fridge`, else nil.
    static func parseStorage(_ raw: String?) -> IconType? {
        switch raw {
        case "pantry": return .pantry
        case "freezer": return .freezer
        case "fridge": return .fridge
        default: return nil
        }
    }

    /// Int from an int/number(rounded)/numeric-string. nil for anything else.
    private static func parseInt(_ value: JSONValue?) -> Int? {
        switch value {
        case let .int(int): return int
        case let .double(double): return Int(double.rounded())
        case let .string(string): return Int(string)
        default: return nil
        }
    }

    /// Shelf life must be a positive day count — a hallucinated `<= 0` would make
    /// the row expire on (or before) the day it is added, so treat it as unknown
    /// (nil) and let the row default to no expiry.
    static func parsePositiveInt(_ value: JSONValue?) -> Int? {
        guard let parsed = parseInt(value), parsed > 0 else { return nil }
        return parsed
    }

    /// A `JSONValue` interpreted as a string ONLY when it is a string.
    private static func string(_ value: JSONValue?) -> String? {
        if case let .string(string) = value { return string }
        return nil
    }

    /// A `JSONValue` stringified for the quantity field, which Dart accepts as a
    /// string OR a number (`(entry['quantity'] ?? '1').toString()`).
    private static func stringValue(_ value: JSONValue?) -> String? {
        switch value {
        case let .string(string): return string
        case let .int(int): return String(int)
        case let .double(double):
            // Match Dart `num.toString()`: whole doubles keep a `.0`, but the LLM
            // typically returns ints/strings — this is the rare numeric-quantity case.
            return double == double.rounded() ? String(format: "%.1f", double) : String(double)
        case let .bool(bool): return String(bool)
        case .null, .array, .object, .none: return nil
        }
    }
}
