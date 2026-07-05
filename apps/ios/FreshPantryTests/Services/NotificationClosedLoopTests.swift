import Foundation
import Testing
@testable import FreshPantry

/// Closed-loop coverage for the daily summary's 库存不足 count: the Settings
/// copy promises 「包含临期 + 库存不足」, so `ExpiryScheduler.compute` folds the
/// restock-candidate count into the summary body (zero keeps the expiry-only
/// body, and existing call sites without the parameter stay unchanged).
struct DailySummaryLowStockBodyTests {
    /// A fixed gregorian calendar pinned to a single time zone for determinism.
    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// `now` = 2026-06-11 08:00 local — before the daily 09:00 slot.
    private func now(_ cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 11; c.hour = 8; c.minute = 0
        return cal.date(from: c)!
    }

    /// Daily summary on, per-item offsets all off — isolates the summary slot.
    private func dailyOnlySettings() -> ReminderSettings {
        ReminderSettings(remindD1: false, remindD3: false, remindD7: false, remindDaily: true)
    }

    @Test func bodyCarriesLowStockCountWhenPositive() {
        let cal = calendar()
        let out = ExpiryScheduler.compute(
            inventory: [], settings: dailyOnlySettings(), now: now(cal),
            lowStockCount: 3, calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        #expect(summary.body == String(localized: "notification.dailySummary.bodyWithLowStock \(3)"))
    }

    @Test func bodyOmitsLowStockWhenZero() {
        let cal = calendar()
        let out = ExpiryScheduler.compute(
            inventory: [], settings: dailyOnlySettings(), now: now(cal),
            lowStockCount: 0, calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        #expect(summary.body == String(localized: "notification.dailySummary.body"))
    }

    @Test func lowStockCountDefaultsToZeroForExistingCallSites() {
        let cal = calendar()
        let out = ExpiryScheduler.compute(
            inventory: [], settings: dailyOnlySettings(), now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        #expect(summary.body == String(localized: "notification.dailySummary.body"))
    }
}

/// `syncAll` must REPORT whether it actually reconciled with the OS — false in
/// the ungranted state. The coordinator persists the scheduled-ids ledger only
/// on true: a ledger written around a silent no-op records ids the OS never
/// received, turning deleted items' real pending requests into uncancellable
/// zombies on every later reschedule.
@MainActor
struct NotificationServiceSyncGatingTests {
    @Test func syncAllReturnsFalseWhilePermissionUngranted() async {
        // A fresh service has `permissionGranted == false` until a permission
        // refresh — exactly the cold-launch state the reschedule path hits.
        let service = NotificationService()
        let executed = await service.syncAll([], previousIds: [])
        #expect(executed == false)
    }
}

/// `syncAll` adds the new set BEFORE removing anything, so a backgrounding
/// suspension mid-sync can never land in a "cancelled but not re-added" window
/// (the scenePhase == .background reschedule runs as a bare Task with no
/// background-task assertion). The removal set is the pure
/// `ExpiryScheduler.obsoleteIds` difference: previous − just-scheduled — ids
/// re-added via same-identifier `add` (which replaces the pending request) must
/// never be cancelled afterwards, while everything truly dropped still is.
struct ObsoleteIdsTests {
    @Test func keepsOverlapAndRemovesOnlyDroppedIds() {
        // 2 and 3 were just re-added (same identifier overwrites) — removing
        // them after the add would undo the suspension-safe ordering.
        let obsolete = ExpiryScheduler.obsoleteIds(
            previous: [1, 2, 3],
            scheduledIds: [2, 3, 4]
        )
        #expect(obsolete == [1])
    }

    @Test func emptyScheduledSetCancelsEverythingPrevious() {
        // Inventory emptied / all offsets disabled: the whole previous set is
        // obsolete, matching the old full-cancel semantics.
        let obsolete = ExpiryScheduler.obsoleteIds(
            previous: [5, 6],
            scheduledIds: []
        )
        #expect(obsolete == [5, 6])
    }

    @Test func emptyPreviousYieldsNothingToRemove() {
        let obsolete = ExpiryScheduler.obsoleteIds(
            previous: [],
            scheduledIds: [7, 8]
        )
        #expect(obsolete.isEmpty)
    }

    @Test func identicalSetsYieldNothingToRemove() {
        // Steady-state reschedule (nothing changed): every id is re-added in
        // place; nothing may be cancelled or the just-added requests die.
        let obsolete = ExpiryScheduler.obsoleteIds(
            previous: [1, 2, 3],
            scheduledIds: [3, 2, 1]
        )
        #expect(obsolete.isEmpty)
    }
}
