import Foundation
import Testing
@testable import FreshPantry

/// `AiSettingsStore.save` must surface the Keychain write result: a rejected
/// write returns `false` and leaves the live value untouched, so the UI can
/// report the failure instead of showing a config that reverts on next launch.
@MainActor
struct AiSettingsStoreSaveFailureTests {
    /// `SecretStore` fake that rejects every write — models a Keychain that is
    /// entitlement-gated (unsigned simulator build) or otherwise refusing writes.
    final class RejectingSecretStore: SecretStore, @unchecked Sendable {
        func get(_ key: String) -> Data? { nil }
        func set(_ value: Data, forKey key: String) -> Bool { false }
        func delete(_ key: String) {}
    }

    @Test func rejectedWriteReturnsFalseAndKeepsLiveValueInSync() {
        let store = AiSettingsStore(secrets: RejectingSecretStore())
        let next = AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "gpt-4o")

        #expect(!store.save(next))
        // Live value stays in sync with (empty) storage — no session-only config.
        #expect(store.settings == .empty)
        #expect(!store.isConfigured)
    }

    @Test func acceptedWriteReturnsTrueAndUpdatesLiveValue() {
        let store = AiSettingsStore(secrets: InMemorySecretStore())
        let next = AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "gpt-4o")

        #expect(store.save(next))
        #expect(store.settings == next)
    }
}
