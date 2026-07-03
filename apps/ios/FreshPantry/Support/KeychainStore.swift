import Foundation
import Security

/// Production `SecretStore` backed by the iOS Keychain (`kSecClassGenericPassword`).
///
/// The reusable secret-storage template: AI settings store their whole JSON blob
/// here today; P7 auth/session tokens will reuse the same `get/set/delete` shape.
/// Items are scoped by a fixed `service` (defaults to the bundle id) plus the
/// caller's `key` as the account, and protected with
/// `kSecAttrAccessibleAfterFirstUnlock` (readable in the background after the
/// first post-boot unlock — appropriate for tokens a sync layer may need).
///
/// `set` is upsert: it `SecItemDelete`s any existing item, then `SecItemAdd`s the
/// new blob, so a write is always last-writer-wins with no stale-attribute drift.
struct KeychainStore: SecretStore {
    /// Keychain service namespace shared by every item this store writes.
    let service: String

    /// Defaults `service` to the running app's bundle id so secrets are scoped to
    /// this app and don't collide with other Keychain consumers on device.
    init(service: String = Bundle.main.bundleIdentifier ?? "com.sunpebble.freshpantry") {
        self.service = service
    }

    func get(_ key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func set(_ value: Data, forKey key: String) -> Bool {
        // Upsert via delete-then-add so attributes never go stale.
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    func delete(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// The identifying attributes for an item (`service` + `account`); the shared
    /// base for get/set/delete so all three address the exact same row.
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
