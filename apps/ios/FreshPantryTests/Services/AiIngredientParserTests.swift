import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for `AiIngredientParser` driven by a fake `chatFn` returning
/// crafted raw output — no network. Covers clean JSON, code-fenced JSON, the
/// skip-malformed-entry rule, empty-name skipping, defaults for missing fields,
/// the `shelfLifeDays <= 0 -> nil` guard, and the non-array `.parse` throw.
struct AiIngredientParserTests {
    private func chat(returning raw: String) -> AiChatFn {
        { _ in raw }
    }

    // MARK: Empty input

    @Test func emptyTextThrowsParse() async {
        await #expect {
            _ = try await AiIngredientParser.fromText("   ", chatFn: chat(returning: "[]"))
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.ingredientParse.emptyText")) }
    }

    // MARK: Clean array

    @Test func parsesCleanJSONArray() async throws {
        let raw = #"[{"name":"牛奶","quantity":"2","unit":"盒","category":"乳品蛋类","storage":"fridge","shelfLifeDays":7}]"#
        let drafts = try await AiIngredientParser.fromText("牛奶", chatFn: chat(returning: raw))
        #expect(drafts.count == 1)
        let d = drafts[0]
        #expect(d.name.value == "牛奶")
        #expect(d.quantity.value == "2")
        #expect(d.unit.value == "盒")
        #expect(d.category.value == "乳品蛋类")
        #expect(d.storage.value == .fridge)
        #expect(d.shelfLifeDays.value == 7)
        #expect(d.name.source == .ai)
    }

    // MARK: Code-fenced array (LLMs wrap output in ```json … ```)

    @Test func parsesCodeFencedArray() async throws {
        let raw = """
        这是结果:
        ```json
        [{"name":"鸡蛋","storage":"pantry"}]
        ```
        """
        let drafts = try await AiIngredientParser.fromText("鸡蛋", chatFn: chat(returning: raw))
        #expect(drafts.count == 1)
        #expect(drafts[0].name.value == "鸡蛋")
        #expect(drafts[0].storage.value == .pantry)
    }

    // MARK: Malformed entry skipped, partial results kept

    @Test func skipsMalformedEntryKeepsPartialResults() async throws {
        // A non-object entry (a bare string) must be skipped, not throw.
        let raw = #"[{"name":"苹果"}, "garbage", {"name":"香蕉"}]"#
        let drafts = try await AiIngredientParser.fromText("水果", chatFn: chat(returning: raw))
        #expect(drafts.map(\.name.value) == ["苹果", "香蕉"])
    }

    // MARK: Empty name skipped

    @Test func skipsEntriesWithEmptyName() async throws {
        let raw = #"[{"name":"  "}, {"name":"土豆"}, {"quantity":"3"}]"#
        let drafts = try await AiIngredientParser.fromText("x", chatFn: chat(returning: raw))
        #expect(drafts.map(\.name.value) == ["土豆"])
    }

    // MARK: Defaults for missing quantity/unit/category/storage

    @Test func appliesDefaultsForMissingFields() async throws {
        let raw = #"[{"name":"盐"}]"#
        let drafts = try await AiIngredientParser.fromText("盐", chatFn: chat(returning: raw))
        let d = drafts[0]
        #expect(d.quantity.value == "1")
        #expect(d.unit.value == "个")
        #expect(d.category.value == FoodCategories.other)
        #expect(d.storage.value == nil) // unknown storage -> nil (row defaults later)
        #expect(d.shelfLifeDays.value == nil)
    }

    // MARK: Numeric quantity stringified

    @Test func stringifiesNumericQuantity() async throws {
        let raw = #"[{"name":"米","quantity":5}]"#
        let drafts = try await AiIngredientParser.fromText("米", chatFn: chat(returning: raw))
        #expect(drafts[0].quantity.value == "5")
    }

    // MARK: shelfLifeDays <= 0 -> nil (no same-day expiry from a hallucination)

    @Test func nonPositiveShelfLifeBecomesNil() async throws {
        let raw = #"[{"name":"a","shelfLifeDays":0},{"name":"b","shelfLifeDays":-3},{"name":"c","shelfLifeDays":5}]"#
        let drafts = try await AiIngredientParser.fromText("x", chatFn: chat(returning: raw))
        #expect(drafts.map(\.shelfLifeDays.value) == [nil, nil, 5])
    }

    @Test func parsesShelfLifeFromNumericStringAndDouble() async throws {
        let raw = #"[{"name":"a","shelfLifeDays":"14"},{"name":"b","shelfLifeDays":3.7}]"#
        let drafts = try await AiIngredientParser.fromText("x", chatFn: chat(returning: raw))
        // "14" -> 14; 3.7 rounds to 4.
        #expect(drafts.map(\.shelfLifeDays.value) == [14, 4])
    }

    // MARK: Non-array raw -> .parse

    @Test func nonArrayThrowsParse() async {
        await #expect {
            _ = try await AiIngredientParser.fromText("x", chatFn: chat(returning: "not json at all"))
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.ingredientParse.invalidJsonArray")) }
    }

    // MARK: parseStorage mapping

    @Test func parseStorageMapsKnownValues() {
        #expect(AiIngredientParser.parseStorage("fridge") == .fridge)
        #expect(AiIngredientParser.parseStorage("freezer") == .freezer)
        #expect(AiIngredientParser.parseStorage("pantry") == .pantry)
        #expect(AiIngredientParser.parseStorage("cupboard") == nil)
        #expect(AiIngredientParser.parseStorage(nil) == nil)
    }

    // MARK: fromImage — empty data throws

    @Test func emptyImageDataThrowsParse() async {
        await #expect {
            _ = try await AiIngredientParser.fromImage(Data(), chatFn: chat(returning: "[]"))
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.ingredientParse.emptyImage")) }
    }

    // MARK: fromImage — valid array parses (reuses parseList, same draft shape)

    @Test func fromImageParsesArray() async throws {
        let raw = #"[{"name":"西红柿","quantity":"3","unit":"个","category":"蔬菜","storage":"fridge","shelfLifeDays":5}]"#
        let drafts = try await AiIngredientParser.fromImage(Data([0xFF, 0xD8, 0xFF]), chatFn: chat(returning: raw))
        #expect(drafts.count == 1)
        let d = drafts[0]
        #expect(d.name.value == "西红柿")
        #expect(d.quantity.value == "3")
        #expect(d.unit.value == "个")
        #expect(d.storage.value == .fridge)
        #expect(d.shelfLifeDays.value == 5)
        #expect(d.name.source == .ai)
    }

    // MARK: fromImage — defaults + skip-malformed parity with the text path

    @Test func fromImageAppliesDefaultsAndSkipsMalformed() async throws {
        let raw = #"[{"name":"鸡蛋"}, "garbage", {"name":"  "}]"#
        let drafts = try await AiIngredientParser.fromImage(Data([0x01]), chatFn: chat(returning: raw))
        #expect(drafts.map(\.name.value) == ["鸡蛋"])
        #expect(drafts[0].quantity.value == "1")
        #expect(drafts[0].unit.value == "个")
        #expect(drafts[0].category.value == FoodCategories.other)
    }

    // MARK: fromImage — the message carries a base64 image_url data URL

    @Test func fromImageSendsBase64ImageDataURL() async throws {
        let captured = CapturedMessages()
        let chatFn: AiChatFn = { messages in
            captured.store(messages)
            return "[]"
        }
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        _ = try? await AiIngredientParser.fromImage(bytes, chatFn: chatFn)

        let messages = try #require(captured.value)
        // system + user-with-image.
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content.first?.text == AiIngredientParser.imageSystemPrompt)

        let userParts = messages[1].content
        #expect(messages[1].role == "user")
        #expect(userParts.contains { $0.kind == .text && $0.text == "请识别图中食材" })

        let imagePart = try #require(userParts.first { $0.kind == .imageURL })
        let url = try #require(imagePart.imageDataURL)
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
        #expect(url == "data:image/jpeg;base64,\(bytes.base64EncodedString())")
    }
}

/// Thread-safe box so a `@Sendable` fake `chatFn` can capture the messages it
/// receives for assertion (the closure may run on a non-test executor).
private final class CapturedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [AiMessage]?
    func store(_ value: [AiMessage]) { lock.lock(); messages = value; lock.unlock() }
    var value: [AiMessage]? { lock.lock(); defer { lock.unlock() }; return messages }
}
