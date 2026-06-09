import SwiftUI

/// A thin, collapsible status banner for the offline / 待同步 state, mounted above
/// the tab bar in `RootView`. Ports the Flutter `SyncStatusBanner`:
///
/// - offline + 待同步: 「离线 · N 条待同步」
/// - offline only: 「离线」
/// - online + 待同步: 「同步中 · N 条待同步」
///
/// Collapses to nothing (no spacer left behind) when online with nothing pending,
/// so it's invisible in the common case. The pending count is best-effort — the
/// host refreshes it at natural sync moments (foreground, remote merge, after a
/// push); the offline flag is fully reactive via `ConnectivityMonitor`.
struct SyncStatusBanner: View {
    let isOnline: Bool
    let pendingCount: Int

    private var isVisible: Bool { !isOnline || pendingCount > 0 }

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: FkSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(message)
                        .font(.fkLabelMedium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, FkSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(background)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: message)
    }

    private var icon: String {
        isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash"
    }

    private var message: String {
        if !isOnline {
            return pendingCount > 0 ? "离线 · \(pendingCount) 条待同步" : "离线"
        }
        return "同步中 · \(pendingCount) 条待同步"
    }

    private var foreground: Color {
        isOnline ? Color.fkOnPrimary : Color.fkOnSurface
    }

    private var background: Color {
        isOnline ? Color.fkPrimary : Color.fkWarnSoft
    }
}
