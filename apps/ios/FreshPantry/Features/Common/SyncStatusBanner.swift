import SwiftUI

/// A thin, collapsible status banner for the offline / 待同步 state, mounted above
/// the tab bar in `RootView`. Ports the Flutter `SyncStatusBanner`:
///
/// - offline + 待同步: 「离线 · N 条待同步」
/// - offline only: 「离线」
/// - online + 同步失败(死信): 「N 条同步失败」(+ 「· M 条待同步」when more queued)
/// - online + 待同步: 「同步中 · N 条待同步」
///
/// Collapses to nothing (no spacer left behind) when online with nothing pending,
/// so it's invisible in the common case. The pending count is best-effort — the
/// host refreshes it at natural sync moments (foreground, remote merge, after a
/// push); the offline flag is fully reactive via `ConnectivityMonitor`.
///
/// `failedCount` is the coordinator's dead-letter depth (ops quarantined after
/// repeated permanent failures). Surfacing it keeps the banner honest: a poison
/// op no longer renders as an eternal 「同步中」.
struct SyncStatusBanner: View {
    let isOnline: Bool
    let pendingCount: Int
    var failedCount: Int = 0
    /// Called when the user taps the banner while sync failures are shown.
    var onFailedTap: (() -> Void)? = nil

    private var isVisible: Bool { !isOnline || pendingCount > 0 || isFailed }
    private var isFailed: Bool { isOnline && failedCount > 0 }

    var body: some View {
        Group {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(message)
                    .accessibilityAddTraits(isFailed ? .isButton : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: message)
    }

    @ViewBuilder
    private var bannerContent: some View {
        let row = HStack(spacing: FkSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.fkLabelMedium)
            Spacer(minLength: 0)
            if isFailed {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, FkSpacing.lg)
        .padding(.vertical, FkSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(background)

        if isFailed, let onFailedTap {
            Button(action: onFailedTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var icon: String {
        if !isOnline { return "wifi.slash" }
        return isFailed ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath"
    }

    private var message: String {
        Self.message(isOnline: isOnline, pendingCount: pendingCount, failedCount: failedCount)
    }

    /// The banner copy, extracted pure for unit tests. Offline keeps the plain
    /// queue depth (offline ops aren't failures); online splits the depth into
    /// the failed (dead-lettered) part and the still-syncing remainder.
    nonisolated static func message(isOnline: Bool, pendingCount: Int, failedCount: Int) -> String {
        if !isOnline {
            return pendingCount > 0 ? "离线 · \(pendingCount) 条待同步" : "离线"
        }
        if failedCount > 0 {
            let syncing = max(pendingCount - failedCount, 0)
            return syncing > 0
                ? "\(failedCount) 条同步失败 · \(syncing) 条待同步"
                : "\(failedCount) 条同步失败"
        }
        return "同步中 · \(pendingCount) 条待同步"
    }

    private var foreground: Color {
        if !isOnline { return Color.fkOnSurface }
        return isFailed ? Color.fkDanger : Color.fkOnPrimary
    }

    private var background: Color {
        if !isOnline { return Color.fkWarnSoft }
        return isFailed ? Color.fkDangerSoft : Color.fkPrimary
    }
}
