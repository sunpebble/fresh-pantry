import SwiftUI

/// A thin, collapsible status banner for the offline / 待同步 state, mounted above
/// the tab bar in `RootView`. Ports the Flutter `SyncStatusBanner`:
///
/// - dropped write (local save failed): 「N 项更改未能保存,请重试」 (dismissible) — top
///   priority, shown regardless of connectivity (it's a LOCAL storage failure)
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
/// repeated permanent failures). `droppedCount` is the count of local writes whose
/// outbox enqueue failed outright (no op queued, never syncs until re-edited) —
/// the one drop the badge/dead-letter plumbing can't see (it has no persisted op),
/// so it gets its own dismissible danger state instead of failing silently.
struct SyncStatusBanner: View {
    let isOnline: Bool
    let pendingCount: Int
    var failedCount: Int = 0
    var droppedCount: Int = 0
    /// Called when the user taps the banner while sync failures are shown.
    var onFailedTap: (() -> Void)? = nil
    /// Called when the user dismisses the dropped-write notice.
    var onDroppedDismiss: (() -> Void)? = nil

    private var isVisible: Bool { isDropped || !isOnline || pendingCount > 0 || isFailed }
    private var isDropped: Bool { droppedCount > 0 }
    private var isFailed: Bool { isOnline && failedCount > 0 }
    /// Danger styling covers both the dropped-write and dead-letter states.
    private var isDanger: Bool { isDropped || isFailed }

    var body: some View {
        Group {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(message)
                    .accessibilityAddTraits(isFailed && !isDropped ? .isButton : [])
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
            if isDropped, let onDroppedDismiss {
                Button(action: onDroppedDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "sync.banner.dismiss"))
            } else if isFailed {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, FkSpacing.lg)
        .padding(.vertical, FkSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(background)

        // The dropped-write row carries its own dismiss button, so the row itself
        // isn't a tap target; the dead-letter row taps through to the failure sheet.
        if isFailed, !isDropped, let onFailedTap {
            Button(action: onFailedTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var icon: String {
        if isDanger { return "exclamationmark.triangle.fill" }
        if !isOnline { return "wifi.slash" }
        return "arrow.triangle.2.circlepath"
    }

    private var message: String {
        Self.message(isOnline: isOnline, pendingCount: pendingCount, failedCount: failedCount, droppedCount: droppedCount)
    }

    /// The banner copy, extracted pure for unit tests. A dropped write is a LOCAL
    /// failure (independent of connectivity), so it wins over every other state.
    /// Offline keeps the plain queue depth (offline ops aren't failures); online
    /// splits the depth into the failed (dead-lettered) part and the still-syncing
    /// remainder.
    nonisolated static func message(
        isOnline: Bool,
        pendingCount: Int,
        failedCount: Int,
        droppedCount: Int = 0
    ) -> String {
        if droppedCount > 0 {
            return String(localized: "sync.banner.dropped \(droppedCount)")
        }
        if !isOnline {
            return pendingCount > 0 ? String(localized: "sync.banner.offlinePending \(pendingCount)") : String(localized: "sync.banner.offline")
        }
        if failedCount > 0 {
            let syncing = max(pendingCount - failedCount, 0)
            return syncing > 0
                ? String(localized: "sync.banner.failedPending \(failedCount) \(syncing)")
                : String(localized: "sync.banner.failed \(failedCount)")
        }
        return String(localized: "sync.banner.syncing \(pendingCount)")
    }

    private var foreground: Color {
        if isDanger { return Color.fkDanger }
        if !isOnline { return Color.fkOnSurface }
        return Color.fkOnPrimary
    }

    private var background: Color {
        if isDanger { return Color.fkDangerSoft }
        if !isOnline { return Color.fkWarnSoft }
        return Color.fkPrimary
    }
}
