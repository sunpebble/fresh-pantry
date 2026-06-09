import SwiftUI

/// Urgency / status discriminator. Mirrors the Flutter `FkStatus` enum: the
/// domain `FreshnessState` has four tiers, and `FkStatus` adds a fifth `low`
/// for shopping / low-stock surfaces.
///
/// This (plus `FkStatusStyle.of`) is the SINGLE SOURCE OF TRUTH for urgency
/// colors — no card/row/badge may re-derive "expired vs not" on its own, or the
/// urgent (coral ink) / soon (butter ink) / expired (coral fill) distinction is
/// lost.
enum FkStatus: String, Sendable, CaseIterable {
    case fresh
    case soon
    case urgent
    case expired
    case low
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
            return FkStatusStyle(background: .fkPrimarySoft, foreground: .fkPrimaryContainer, label: "新鲜")
        case .soon:
            return FkStatusStyle(background: .fkWarnSoft, foreground: .fkOnWarnContainer, label: "即将过期")
        case .urgent:
            return FkStatusStyle(background: .fkDangerSoft, foreground: .fkOnDangerContainer, label: "快过期")
        case .expired:
            return FkStatusStyle(background: .fkDanger, foreground: .fkOnDanger, label: "已过期")
        case .low:
            return FkStatusStyle(background: .fkDangerSoft, foreground: .fkOnDangerContainer, label: "库存不足")
        }
    }
}

extension FreshnessState {
    /// Maps the 4-tier domain state onto the 5-case `FkStatus` (no `low`).
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
