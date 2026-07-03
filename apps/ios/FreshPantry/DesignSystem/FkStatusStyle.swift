import SwiftUI

/// Urgency / status discriminator. Mirrors the Flutter `FkStatus` enum: the
/// domain `FreshnessState`'s four tiers.
///
/// This (plus `FkStatusStyle.of`) is the SINGLE SOURCE OF TRUTH for urgency
/// colors — no card/row/badge may re-derive "expired vs not" on its own, or the
/// urgent (coral ink) / soon (amber ink) / expired (coral fill) distinction is
/// lost.
enum FkStatus: String, Sendable, CaseIterable {
    case fresh
    case soon
    case urgent
    case expired
}

/// `(bg, fg, label)` triple for a status chip. Ported from `kFkStatusStyles`.
struct FkStatusStyle: Sendable {
    let background: Color
    let foreground: Color
    let label: String

    /// The canonical style table — keep this the only place these colors live.
    static func of(_ status: FkStatus) -> FkStatusStyle {
        switch status {
        case .fresh:
            // Green, not primary: with the sun-gold primary, a gold "新鲜" chip
            // would read as a caution next to the amber "即将过期" one.
            return FkStatusStyle(background: .fkSuccessSoft, foreground: .fkOnSuccessContainer, label: "新鲜")
        case .soon:
            return FkStatusStyle(background: .fkWarnSoft, foreground: .fkOnWarnContainer, label: "即将过期")
        case .urgent:
            return FkStatusStyle(background: .fkDangerSoft, foreground: .fkOnDangerContainer, label: "快过期")
        case .expired:
            return FkStatusStyle(background: .fkDanger, foreground: .fkOnDanger, label: "已过期")
        }
    }
}

extension FreshnessState {
    /// Maps the 4-tier domain state onto `FkStatus`.
    var fkStatus: FkStatus {
        switch self {
        case .fresh: return .fresh
        case .expiringSoon: return .soon
        case .urgent: return .urgent
        case .expired: return .expired
        }
    }

    /// Resolved style for this freshness tier (the single urgency-color source).
    var statusStyle: FkStatusStyle { FkStatusStyle.of(fkStatus) }
}
