import Foundation

// MARK: - Storage / FreshnessState

/// Urgency tiers, least → most severe. `urgent` is a near-expiry refinement of
/// `expiringSoon`. rawValue == the Dart `.name` for sync-wire parity.
enum FreshnessState: String, Codable, Sendable, CaseIterable {
    case fresh
    case expiringSoon
    case urgent
    case expired

    /// Parse-fail fallback mirroring `FreshnessState.values.byName(... 'fresh')`
    /// with a `.fresh` catch — any unknown / dirty value resolves to `.fresh`.
    static func fromName(_ name: String?) -> FreshnessState {
        guard let name, let value = FreshnessState(rawValue: name) else {
            return .fresh
        }
        return value
    }
}

/// Storage location. rawValue == Dart `IconType.name`.
enum IconType: String, Codable, Sendable, CaseIterable {
    case fridge
    case freezer
    case pantry

    /// Mirrors Dart `iconTypeFromName`: pantry/freezer map literally,
    /// `fridge` / `nil` / any unknown all fall back to `.fridge`.
    static func fromName(_ name: String?) -> IconType {
        switch name {
        case "pantry": return .pantry
        case "freezer": return .freezer
        case "fridge", nil: return .fridge
        default: return .fridge
        }
    }

    /// Human-readable label — single source of truth for chips/providers.
    var storageAreaLabel: String {
        switch self {
        case .fridge: return String(localized: "storage.fridge")
        case .freezer: return String(localized: "storage.freezer")
        case .pantry: return String(localized: "storage.pantry")
        }
    }
}

// MARK: - Food log

/// Departure outcome. `donated` (捐了) / `composted` (堆肥) are POSITIVE去向 —
/// the food left the kitchen but was NOT wasted, so they're counted as "saved",
/// never as waste. Unknown / dirty data conservatively resolves to `.consumed`
/// (don't overstate waste).
enum FoodLogOutcome: String, Codable, Sendable, CaseIterable {
    case consumed
    case wasted
    case donated
    case composted

    /// 非浪费的正向去向(捐赠/堆肥)——保留过期临期食物的价值,计入"减废"而非浪费。
    var isSaved: Bool { self == .donated || self == .composted }

    static func fromName(_ name: String?) -> FoodLogOutcome {
        for outcome in FoodLogOutcome.allCases where outcome.rawValue == name {
            return outcome
        }
        return .consumed
    }
}

// MARK: - Proposal hierarchy enums

enum IntakeAction: String, Codable, Sendable, CaseIterable {
    case newRow
    case mergeInto
}

enum DeductionAction: String, Codable, Sendable, CaseIterable {
    case deduct
    case skip
}

/// Source of a Proposal field's value — drives Review-UI origin dots.
enum FieldOrigin: String, Codable, Sendable, CaseIterable {
    case ai
    case system
    case user
}

// MARK: - Draft

enum DraftSource: String, Codable, Sendable, CaseIterable {
    case ai
    case user
}

// MARK: - Notifications

enum ScheduledNotificationKind: String, Codable, Sendable, CaseIterable {
    case expiry
    case dailySummary
}

// MARK: - Sync

/// Outbox entity discriminator. rawValue == Dart `SyncEntityType.name`.
enum SyncEntityType: String, Codable, Sendable, CaseIterable {
    case inventoryItem
    case shoppingItem
    case customRecipe
    case mealPlanEntry
    case foodLogEntry
    case favoriteRecipe
    case dietaryPreference
    case householdConfig
}

/// Outbox operation discriminator. rawValue == Dart `SyncOperationType.name`.
enum SyncOperationType: String, Codable, Sendable, CaseIterable {
    case create
    case update
    case delete
    case intake
    case deduction
    case toggleChecked
}
