import Foundation

/// Keychain-backed AI provider config — the whole `AiSettings` JSON blob is
/// stored in a `SecretStore` (NOT UserDefaults) because it carries the `apiKey`
/// secret. The JSON shape (keys baseUrl/apiKey/model/timeoutSeconds) stays
/// byte-compatible with the Flutter `AiSettingsRepo` under `ai_settings_v1`.
///
/// Follows the KV-store template (`@Observable @MainActor`, defensive decode)
/// but swaps the `UserDefaults` backing for an injectable `SecretStore` — the
/// prod app injects `KeychainStore`, tests inject `InMemorySecretStore` so the
/// suite never depends on Keychain availability in the test host.
@Observable
@MainActor
final class AiSettingsStore {
    /// Storage key — matches Flutter `ai_settings_repo` for sync parity.
    static let storageKey = "ai_settings_v1"

    private let secrets: SecretStore

    /// The live AI settings. Mutate via `save`; reads are synchronous.
    private(set) var settings: AiSettings

    init(secrets: SecretStore) {
        self.secrets = secrets
        self.settings = Self.decode(secrets.get(Self.storageKey))
    }

    /// Convenience for the configured-state indicator in the UI.
    var isConfigured: Bool { settings.isConfigured }

    // MARK: Mutations

    /// Persists the whole settings blob to the secret store and updates the live
    /// value (set-after-write so a failed Keychain write doesn't desync state).
    /// Returns `false` — leaving `settings` untouched — when encoding or the
    /// Keychain write fails, so callers surface the failure instead of showing a
    /// config that silently reverts on next launch.
    @discardableResult
    func save(_ next: AiSettings) -> Bool {
        guard let data = try? DomainJSON.encoder.encode(next) else { return false }
        guard secrets.set(data, forKey: Self.storageKey) else { return false }
        settings = next
        return true
    }

    /// Clears the stored AI config (resets to `.empty`).
    func clear() {
        secrets.delete(Self.storageKey)
        settings = .empty
    }

    // MARK: Persistence (defensive decode)

    /// nil/malformed/wrong-shape → `.empty`; otherwise the lenient-decoded
    /// `AiSettings` (per-field fallbacks live in the model's `init(from:)`).
    static func decode(_ data: Data?) -> AiSettings {
        guard let data,
              let settings = try? DomainJSON.decoder.decode(AiSettings.self, from: data)
        else {
            return .empty
        }
        return settings
    }
}
