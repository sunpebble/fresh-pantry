import Foundation
import Testing
@testable import FreshPantry

/// Tests for the UserDefaults-backed 忌口 KV store: add/remove, store-owned
/// normalization (trim + lowercase), case-insensitive dedupe, JSON-string-array
/// persistence round-trip, and defensive decode.
@MainActor
struct DietaryPreferencesStoreTests {
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.dietary.\(UUID().uuidString)")!
    }

    // MARK: Add / remove

    @Test func addAndRemoveKeyword() {
        let store = DietaryPreferencesStore(defaults: suite())
        #expect(store.add("香菜") == "香菜")
        #expect(store.keywords == ["香菜"])
        store.remove("香菜")
        #expect(store.keywords.isEmpty)
    }

    // MARK: Normalization (owned by the store)

    @Test func addNormalizesTrimAndLowercase() {
        let store = DietaryPreferencesStore(defaults: suite())
        #expect(store.add("  Cilantro  ") == "cilantro")
        #expect(store.keywords == ["cilantro"])
    }

    @Test func addIgnoresBlankInput() {
        let store = DietaryPreferencesStore(defaults: suite())
        #expect(store.add("   ") == nil)
        #expect(store.keywords.isEmpty)
    }

    @Test func addDedupesCaseInsensitively() {
        let store = DietaryPreferencesStore(defaults: suite())
        store.add("Peanut")
        store.add("peanut")
        store.add("  PEANUT ")
        #expect(store.keywords == ["peanut"])
    }

    @Test func removeMatchesRegardlessOfCasing() {
        let store = DietaryPreferencesStore(defaults: suite())
        store.add("Shrimp")
        store.remove("SHRIMP")
        #expect(store.keywords.isEmpty)
    }

    // MARK: Membership (drives the editor's duplicate feedback)

    @Test func containsMatchesStoredKeywordRegardlessOfCasingOrPadding() {
        let store = DietaryPreferencesStore(defaults: suite())
        store.add("Peanut")
        #expect(store.contains("peanut"))
        #expect(store.contains("  PEANUT "))
        #expect(!store.contains("shrimp"))
    }

    @Test func containsFalseForBlankInput() {
        let store = DietaryPreferencesStore(defaults: suite())
        store.add("egg")
        #expect(!store.contains("   "))
    }

    // MARK: Persistence round-trip

    @Test func keywordsPersistAsSortedJsonArray() throws {
        let defaults = suite()
        let store = DietaryPreferencesStore(defaults: defaults)
        store.add("egg")
        store.add("crab")

        let raw = try #require(defaults.string(forKey: DietaryPreferencesStore.storageKey))
        // Sorted JSON array → diff-stable.
        #expect(raw == #"["crab","egg"]"#)

        // A new store over the same suite reads the persisted blob.
        let reloaded = DietaryPreferencesStore(defaults: defaults)
        #expect(reloaded.keywords == ["crab", "egg"])
        #expect(reloaded.sortedKeywords == ["crab", "egg"])
    }

    // MARK: Defensive decode

    @Test func decodeHandlesNilEmptyAndMalformed() {
        #expect(DietaryPreferencesStore.decode(nil).isEmpty)
        #expect(DietaryPreferencesStore.decode("").isEmpty)
        #expect(DietaryPreferencesStore.decode("not json").isEmpty)
        #expect(DietaryPreferencesStore.decode(#"{"k":"v"}"#).isEmpty) // object, not array
    }

    @Test func decodeNormalizesAndDropsBlankAndNonStringElements() {
        // Mixed casing collapses; blanks/non-strings dropped.
        let decoded = DietaryPreferencesStore.decode(#"["Egg", "egg", 1, "", "  Crab  "]"#)
        #expect(decoded == ["egg", "crab"])
    }
}
