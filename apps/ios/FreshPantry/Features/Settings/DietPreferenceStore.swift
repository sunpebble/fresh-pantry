import Foundation

/// UserDefaults-backed 饮食偏好 (家庭口味偏好) — a `Set<String>` of selected preset
/// labels persisted as a sorted JSON string array under `diet_category_preferences`.
///
/// LOCAL-FIRST by design (an iOS-only enhancement): Flutter stored these in a
/// household-scoped + remote-only `categoryPreferences` column that was **never
/// consumed by recommendation on either side** (a dead toggle) and would be empty
/// in the local-only self-use mode. This store keeps the prefs on-device so they
/// work offline AND actually influence the 现有/今日推荐 ranking via
/// `RecipeMatching.preferenceBoost`. The orphaned remote path was dropped; its
/// dead `households.category_preferences` column was removed from the schema in
/// migration 20260622120000.
///
/// Mirrors `DietaryPreferencesStore` (忌口) shape, but the labels are FIXED Chinese
/// presets compared by exact identity, so normalization is `trimmed` only (no
/// lowercasing). Distinct storage key so it never collides with `dietary_exclusions`.
@Observable
@MainActor
final class DietPreferenceStore {
    static let storageKey = "diet_category_preferences"

    /// The 7 preset labels (single source of truth for the chips), ported from the
    /// Flutter settings screen. `nonisolated` so pure/nonisolated callers (e.g.
    /// `RecipeMatching` tests) can read this immutable constant off the main actor.
    /// These Chinese literals are the STORAGE/matching identity — persisted verbatim
    /// in UserDefaults and used as `RecipeMatching.preferenceSignals` dict keys — so
    /// they must never be localized or renamed (would silently break existing users'
    /// saved prefs + the boost lookup).
    nonisolated static let allLabels = ["高蛋白", "低脂", "素食", "家常菜", "快手菜", "儿童餐", "低碳水"] // i18n:ignore data identity, not UI text

    /// Localization keys for each `allLabels` preset, same order — the display-only
    /// counterpart to the storage identity above. Indexed (not keyed by the Chinese
    /// string) so no case list has to repeat/match those literals.
    nonisolated private static let displayKeys = [
        "settings.dietPreference.highProtein",
        "settings.dietPreference.lowFat",
        "settings.dietPreference.vegetarian",
        "settings.dietPreference.homestyle",
        "settings.dietPreference.quick",
        "settings.dietPreference.kids",
        "settings.dietPreference.lowCarb",
    ]

    /// Localized display text for a preset label, for chip rendering only. Falls
    /// back to the raw label for any value outside the 7 presets (defensive; the
    /// UI only ever iterates `allLabels`, so this should always hit).
    nonisolated static func displayLabel(for label: String) -> String {
        guard let index = allLabels.firstIndex(of: label) else { return label }
        return String(localized: String.LocalizationValue(displayKeys[index]))
    }

    private let defaults: UserDefaults

    /// The live selected-preference set (already normalized). Mutations persist.
    private(set) var selected: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selected = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: Queries

    func isSelected(_ label: String) -> Bool { selected.contains(Self.normalize(label)) }

    var sortedSelected: [String] { selected.sorted() }

    // MARK: Mutations

    func toggle(_ label: String) {
        let normalized = Self.normalize(label)
        guard !normalized.isEmpty else { return }
        if selected.contains(normalized) {
            selected.remove(normalized)
        } else {
            selected.insert(normalized)
        }
        persist()
    }

    func set(_ label: String, on: Bool) {
        let normalized = Self.normalize(label)
        guard !normalized.isEmpty else { return }
        let changed = on ? selected.insert(normalized).inserted : (selected.remove(normalized) != nil)
        if changed { persist() }
    }

    // MARK: Normalization (trim only — presets are exact Chinese identities)

    static func normalize(_ label: String) -> String { label.trimmed }

    // MARK: Persistence (sorted JSON string-array codec)

    private func persist() {
        guard let json = DomainJSON.encodeStringArray(selected.sorted()) else { return }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty set; otherwise the
    /// trimmed, non-blank string elements.
    static func decode(_ raw: String?) -> Set<String> {
        DomainJSON.decodeStringSet(raw, transform: normalize)
    }
}
