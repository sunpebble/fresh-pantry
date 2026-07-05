import SwiftUI

/// The user-selectable app appearance: follow the system, or force light/dark.
enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The root `preferredColorScheme` override — nil means follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// 外观 picker segment label.
    var label: String {
        switch self {
        case .system: String(localized: "settings.appearance.system")
        case .light: String(localized: "settings.appearance.light")
        case .dark: String(localized: "settings.appearance.dark")
        }
    }
}

/// UserDefaults-backed appearance preference — the raw `AppearanceMode` string
/// under `appearance_mode_v1`. Follows the `ReminderSettingsStore` KV template:
/// `@Observable @MainActor`, injectable suite, defensive decode (missing /
/// unknown → `.system`). Device-local by design: appearance is a per-device
/// display preference, so it is excluded from backup/household sync.
@Observable
@MainActor
final class AppearanceStore {
    static let storageKey = "appearance_mode_v1"

    private let defaults: UserDefaults

    /// The live appearance mode. Mutate via `set` so writes persist.
    private(set) var mode: AppearanceMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    /// Sets the in-memory value first (so observers see it immediately), then
    /// persists the raw value synchronously.
    func set(_ next: AppearanceMode) {
        mode = next
        defaults.set(next.rawValue, forKey: Self.storageKey)
    }

    /// Defensive decode: nil / empty / unknown raw value → `.system`.
    static func decode(_ raw: String?) -> AppearanceMode {
        guard let raw, let mode = AppearanceMode(rawValue: raw) else { return .system }
        return mode
    }
}
