import Foundation

/// Recent global-search queries — an ORDERED `[String]` (most-recent first,
/// max 10, de-duplicated to the front), persisted as a JSON string array under
/// `search_history`. Ports the Flutter `SearchHistoryNotifier`.
///
/// Shares the UserDefaults JSON-array codec shape with `DietaryPreferencesStore`
/// / `FavoritesStore`, but DELIBERATELY does NOT sort — recency order is the whole
/// point, so the persisted array preserves insertion order. UserDefaults-only
/// (no sync), so a fresh instance per overlay-open reads the persisted recents.
@Observable
@MainActor
final class SearchHistoryStore {
    static let storageKey = "search_history"
    static let maxEntries = 10

    private let defaults: UserDefaults

    /// Most-recent-first query list (already normalized + capped).
    private(set) var entries: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: Mutations

    /// Records a query at the FRONT (most recent), removing any prior occurrence
    /// (case-insensitive) so it doesn't duplicate, then caps to `maxEntries`. A
    /// blank query is a no-op. Trims but preserves the original casing for display.
    func record(_ query: String) {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return }
        let key = trimmed.lowercased()
        var next = entries.filter { $0.lowercased() != key }
        next.insert(trimmed, at: 0)
        if next.count > Self.maxEntries { next = Array(next.prefix(Self.maxEntries)) }
        entries = next
        persist()
    }

    /// Removes one entry (case-insensitive match on the displayed value).
    func remove(_ query: String) {
        let key = query.trimmed.lowercased()
        let next = entries.filter { $0.lowercased() != key }
        guard next.count != entries.count else { return }
        entries = next
        persist()
    }

    /// Clears all recent searches.
    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        persist()
    }

    // MARK: Persistence (ordered JSON string array — recency preserved, NOT sorted)

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty; otherwise the
    /// non-blank string elements in stored order, capped to `maxEntries`.
    static func decode(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        let entries = array
            .compactMap { $0 as? String }
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
        return Array(entries.prefix(maxEntries))
    }
}
