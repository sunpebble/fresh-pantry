import Foundation

/// UserDefaults-backed avoided-ingredient keywords (忌口) — a `Set<String>`
/// persisted as a JSON **string array** under `dietary_exclusions`,
/// byte-compatible with the Flutter `DietaryPreferencesRepo` for sync parity.
///
/// Mirrors the `FavoritesStore` shape (`@Observable @MainActor`, injectable
/// suite, sorted-array persist, defensive `static decode`). The store OWNS input
/// normalization — keywords are trimmed + lowercased on `add` (per blueprint),
/// so the persisted set is always canonical and de-duped case-insensitively.
@Observable
@MainActor
final class DietaryPreferencesStore {
    /// Storage key — matches Flutter `dietary_preferences_repo` for sync parity.
    static let storageKey = "dietary_exclusions"

    private let defaults: UserDefaults

    /// The live avoided-keyword set (already normalized). Mutations persist.
    private(set) var keywords: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keywords = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: Queries

    /// Normalized keyword count (sorted-stable; used by the chips UI).
    var sortedKeywords: [String] { keywords.sorted() }

    /// Whether `keyword` (normalized the same way `add` would) is already stored.
    /// Lets the editor distinguish a new add from a duplicate so a re-add isn't a
    /// silent no-op. Blank input is never "contained".
    func contains(_ keyword: String) -> Bool {
        let normalized = Self.normalize(keyword)
        guard !normalized.isEmpty else { return false }
        return keywords.contains(normalized)
    }

    // MARK: Mutations (normalization owned here)

    /// Normalizes (trim + lowercase) and inserts a keyword; blank input is a
    /// no-op. Returns the keyword actually stored, or `nil` if it was blank.
    @discardableResult
    func add(_ keyword: String) -> String? {
        let normalized = Self.normalize(keyword)
        guard !normalized.isEmpty else { return nil }
        guard !keywords.contains(normalized) else { return normalized }
        keywords.insert(normalized)
        persist()
        return normalized
    }

    /// Removes a keyword (normalizes the argument first so a differently-cased
    /// removal still matches the stored canonical form).
    func remove(_ keyword: String) {
        let normalized = Self.normalize(keyword)
        guard keywords.contains(normalized) else { return }
        keywords.remove(normalized)
        persist()
    }

    // MARK: Normalization (single source of truth for input shaping)

    /// Trim + lowercase — the canonical form every keyword is stored in.
    static func normalize(_ keyword: String) -> String {
        keyword.trimmed.lowercased()
    }

    // MARK: Persistence (the reusable JSON-string-array KV codec)

    /// Encodes the keyword set as a sorted JSON string array (diff-stable) and
    /// writes the blob.
    private func persist() {
        let array = keywords.sorted()
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty set; otherwise the
    /// normalized, non-blank string elements (re-normalized on load so a legacy
    /// blob with mixed casing collapses to the canonical set).
    static func decode(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        let keywords = array
            .compactMap { $0 as? String }
            .map(normalize)
            .filter { !$0.isEmpty }
        return Set(keywords)
    }
}
