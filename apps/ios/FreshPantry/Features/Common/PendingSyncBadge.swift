import SwiftUI

/// A small, static 「待同步」 accessory shown on a list row whose local change is
/// still queued in the sync outbox (not yet acknowledged by the backend).
///
/// Addresses the信任痛点「对方看不到」: a row the user just changed now visibly
/// signals "this hasn't reached the household yet", instead of failing silently.
/// Pairs with the global `SyncStatusBanner` (whole-queue depth) — this is the
/// per-row view of the same outbox state.
///
/// Deliberately STATIC: a cloud-with-up-arrow glyph, no pulse / spin animation,
/// so it's reduce-motion friendly by construction and doesn't draw the eye away
/// from the row content. Uses DesignSystem tokens only.
struct PendingSyncBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.fkOnSurfaceVariant)
            .accessibilityLabel(String(localized: "sync.pending.accessibility"))
    }
}

#Preview {
    HStack(spacing: 12) {
        Text("Tomato")
        PendingSyncBadge()
    }
    .padding()
}
