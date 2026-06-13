import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for the pure `BackupService` codec: the version-2 envelope, the
/// encode→decode round-trip over every field, the verbatim `addHistory` map, the
/// optional `aiSettings` key, and the STRICT decode validation that rejects bad
/// blobs with the right typed error BEFORE any write (invariant #8).
struct BackupServiceTests {
    /// A fixed `exportedAt` so encoded output (and any timestamp assertion) is
    /// deterministic.
    private let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Fixtures

    private func sampleData(aiSettings: AiSettings? = nil) -> BackupData {
        BackupData(
            inventory: [
                Ingredient(
                    id: "ing_1", name: "牛奶", quantity: "2", unit: "盒",
                    imageUrl: "", freshnessPercent: 0.8, state: .fresh,
                    category: "乳品蛋类", storage: .fridge
                ),
                Ingredient(
                    id: "", name: "鸡蛋", quantity: "12", unit: "个",
                    imageUrl: "", freshnessPercent: 1.0, state: .fresh
                ),
            ],
            addHistory: [
                "牛奶": AddHistoryEntry(count: 3, category: "乳品蛋类", storage: "fridge", unit: "盒"),
                "鸡蛋": AddHistoryEntry(count: 7, category: "乳品蛋类", storage: "fridge", unit: "个"),
            ],
            shopping: [
                ShoppingItem(id: "sh_1", name: "面包", detail: "全麦", category: "其他", isChecked: true),
            ],
            customRecipes: [
                Recipe(
                    id: "r_1", name: "番茄炒蛋", category: "家常菜", difficulty: 2,
                    cookingMinutes: 15, description: "经典快手菜",
                    ingredients: [RecipeIngredient(name: "鸡蛋", quantity: 3, unit: "个")],
                    steps: ["打蛋", "下锅"], tags: ["快手"]
                ),
            ],
            mealPlan: [
                MealPlanEntry(
                    id: "m_1",
                    date: Date(timeIntervalSince1970: 1_700_100_000),
                    recipeId: "r_1", recipeName: "番茄炒蛋", servings: 2, done: false
                ),
            ],
            aiSettings: aiSettings
        )
    }

    // MARK: Encode → decode round-trip

    @Test func roundTripPreservesEveryField() throws {
        let original = sampleData()
        let blob = BackupService.encode(original, exportedAt: exportedAt)
        let decoded = try BackupService.decode(blob)
        #expect(decoded == original)
    }

    @Test func roundTripWithAiSettings() throws {
        let original = sampleData(
            aiSettings: AiSettings(baseUrl: "https://x/v1", apiKey: "sk-1", model: "gpt-4o", timeout: 45)
        )
        let blob = BackupService.encode(original, exportedAt: exportedAt)
        let decoded = try BackupService.decode(blob)
        #expect(decoded == original)
        #expect(decoded.aiSettings == original.aiSettings)
    }

    @Test func addHistoryMapRoundTripsVerbatim() throws {
        let original = sampleData()
        let decoded = try BackupService.decode(BackupService.encode(original, exportedAt: exportedAt))
        #expect(decoded.addHistory == original.addHistory)
        #expect(decoded.addHistory["牛奶"]?.count == 3)
        #expect(decoded.addHistory["鸡蛋"]?.unit == "个")
    }

    // MARK: Envelope shape

    @Test func encodeWritesVersion2EnvelopeWithTimestamp() throws {
        let blob = BackupService.encode(sampleData(), exportedAt: exportedAt)
        let root = try jsonObject(blob)
        #expect(root["version"] as? Int == 2)
        #expect((root["exportedAt"] as? String)?.hasSuffix("Z") == true)
        #expect(root["data"] is [String: Any])
    }

    @Test func encodeIsPrettyPrintedWithTwoSpaceIndent() {
        let blob = BackupService.encode(sampleData(), exportedAt: exportedAt)
        // Pretty-printed multi-line output indents nested keys by two spaces.
        #expect(blob.contains("\n  \"data\""))
    }

    @Test func encodeOmitsAiSettingsKeyWhenNil() throws {
        let blob = BackupService.encode(sampleData(aiSettings: nil), exportedAt: exportedAt)
        let payload = try dataPayload(blob)
        #expect(payload["aiSettings"] == nil)
    }

    @Test func encodeIncludesAiSettingsKeyWhenPresent() throws {
        let blob = BackupService.encode(
            sampleData(aiSettings: AiSettings(baseUrl: "https://x", apiKey: "k", model: "m")),
            exportedAt: exportedAt
        )
        let payload = try dataPayload(blob)
        #expect(payload["aiSettings"] is [String: Any])
    }

    // MARK: Decode — accepts

    @Test func decodeAcceptsEnvelopeWithUnknownExtraKeys() throws {
        let original = sampleData()
        var root = try jsonObject(BackupService.encode(original, exportedAt: exportedAt))
        root["__unknown"] = "ignored"
        var payload = root["data"] as! [String: Any]
        payload["__alsoUnknown"] = 42
        root["data"] = payload
        let blob = try string(from: root)
        let decoded = try BackupService.decode(blob)
        #expect(decoded == original)
    }

    @Test func decodeTreatsMissingScopesAsEmpty() throws {
        // A minimal valid envelope: version + empty data.
        let blob = #"{"version":2,"data":{}}"#
        let decoded = try BackupService.decode(blob)
        #expect(decoded.inventory.isEmpty)
        #expect(decoded.addHistory.isEmpty)
        #expect(decoded.shopping.isEmpty)
        #expect(decoded.customRecipes.isEmpty)
        #expect(decoded.mealPlan.isEmpty)
        #expect(decoded.aiSettings == nil)
    }

    // MARK: Decode — rejects

    @Test func decodeRejectsInvalidJSON() {
        #expect(throws: BackupService.BackupError.format("Backup blob is not valid JSON")) {
            try BackupService.decode("not json {{{")
        }
    }

    @Test func decodeRejectsNonObjectRoot() {
        #expect(throws: BackupService.BackupError.format("Backup blob is not a JSON object")) {
            try BackupService.decode("[1, 2, 3]")
        }
    }

    @Test func decodeRejectsMissingVersion() {
        #expect {
            try BackupService.decode(#"{"data":{}}"#)
        } throws: { error in
            // A .version error (message includes the captured "got:" detail).
            if case .version = (error as? BackupService.BackupError) { return true }
            return false
        }
    }

    @Test func decodeRejectsNonIntVersion() {
        #expect {
            try BackupService.decode(#"{"version":"2","data":{}}"#)
        } throws: { error in
            if case .version = (error as? BackupService.BackupError) { return true }
            return false
        }
    }

    @Test func decodeRejectsLegacyVersion1() {
        #expect(throws: BackupService.BackupError.version("Unsupported backup version 1 (expected 2)")) {
            try BackupService.decode(#"{"version":1,"data":{}}"#)
        }
    }

    @Test func decodeRejectsFutureVersion3() {
        #expect(throws: BackupService.BackupError.version("Unsupported backup version 3 (expected 2)")) {
            try BackupService.decode(#"{"version":3,"data":{}}"#)
        }
    }

    @Test func decodeRejectsNonObjectData() {
        #expect(throws: BackupService.BackupError.format("Backup data is not a JSON object")) {
            try BackupService.decode(#"{"version":2,"data":[]}"#)
        }
    }

    @Test func decodeRejectsNonListInventory() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"inventory\" must be a JSON list")) {
            try BackupService.decode(#"{"version":2,"data":{"inventory":{}}}"#)
        }
    }

    @Test func decodeRejectsNonObjectAddHistory() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"addHistory\" must be a JSON object")) {
            try BackupService.decode(#"{"version":2,"data":{"addHistory":[]}}"#)
        }
    }

    @Test func decodeRejectsNonObjectAiSettings() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"aiSettings\" must be a JSON object")) {
            try BackupService.decode(#"{"version":2,"data":{"aiSettings":[]}}"#)
        }
    }

    // MARK: JSON helpers

    private func jsonObject(_ string: String) throws -> [String: Any] {
        let data = string.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func dataPayload(_ string: String) throws -> [String: Any] {
        try jsonObject(string)["data"] as! [String: Any]
    }

    private func string(from object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }
}
