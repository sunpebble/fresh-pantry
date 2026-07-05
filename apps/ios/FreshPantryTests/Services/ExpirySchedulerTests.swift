import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for the pure `ExpiryScheduler`: stable id hashing, the reserved
/// daily-summary id, [7,3,1] offset ordering, past-slot skipping, nil-expiry
/// skipping, the default 09:00-local scheduling, and the user-chosen custom
/// reminder time. A fixed `now` + a fixed gregorian calendar with an explicit
/// time zone keep every assertion deterministic.
struct ExpirySchedulerTests {
    /// A fixed gregorian calendar pinned to a single time zone for determinism.
    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// `now` = 2026-06-09 08:00 local — before the daily 09:00 slot.
    private func now(_ cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 9; c.hour = 8; c.minute = 0
        return cal.date(from: c)!
    }

    /// A local date at midnight for a given y/m/d in the fixed calendar.
    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    private func ingredient(
        id: String = "ing-1",
        name: String = "牛奶",
        quantity: String = "2",
        unit: String = "盒",
        storage: IconType = .fridge,
        addedAt: Date? = nil,
        expiryDate: Date?
    ) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            imageUrl: "",
            freshnessPercent: 1.0,
            state: .fresh,
            storage: storage,
            expiryDate: expiryDate,
            addedAt: addedAt
        )
    }

    // MARK: id determinism + reserved-id avoidance

    @Test func idIsStableAcrossCalls() {
        let cal = calendar()
        let ing = ingredient(
            addedAt: date(cal, 2026, 6, 1),
            expiryDate: date(cal, 2026, 6, 20)
        )
        let first = ExpiryScheduler.idFor(ing, offset: 3)
        let second = ExpiryScheduler.idFor(ing, offset: 3)
        #expect(first == second)
        #expect(first > 0) // positive int31
        #expect(first <= 0x7fff_ffff)
    }

    @Test func differentOffsetsYieldDifferentIds() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let id1 = ExpiryScheduler.idFor(ing, offset: 1)
        let id3 = ExpiryScheduler.idFor(ing, offset: 3)
        let id7 = ExpiryScheduler.idFor(ing, offset: 7)
        #expect(Set([id1, id3, id7]).count == 3)
    }

    @Test func idNeverEqualsReservedDailySummaryId() {
        // Brute-force a population of ingredient field combinations; no per-item
        // id may collide with the reserved daily-summary id (1).
        let cal = calendar()
        for nameSeed in 0..<200 {
            let ing = ingredient(
                id: "ing-\(nameSeed)",
                name: "食材\(nameSeed)",
                expiryDate: date(cal, 2026, 6, 20)
            )
            for offset in [1, 3, 7] {
                #expect(ExpiryScheduler.idFor(ing, offset: offset) != ExpiryScheduler.dailySummaryId)
            }
        }
    }

    // MARK: offset ordering [7,3,1]

    @Test func enabledOffsetOrderPreservedInOutput() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 30))
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        // Expiry slots only (daily off). They are emitted largest-first: 7,3,1.
        let offsets = out.map { n -> Int in
            // 7 days before 6/30 = 6/23, 3 = 6/27, 1 = 6/29.
            let day = cal.component(.day, from: n.scheduledAt)
            switch day { case 23: return 7; case 27: return 3; case 29: return 1; default: return -1 }
        }
        #expect(offsets == [7, 3, 1])
    }

    // MARK: past-slot skipping

    @Test func allOffsetsInThePastYieldNoExpiryNotifications() {
        let cal = calendar()
        // Expiry yesterday → every D-N slot is already in the past.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 8))
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.isEmpty)
    }

    // MARK: nil expiry

    @Test func nilExpiryIsSkipped() {
        let cal = calendar()
        let ing = ingredient(expiryDate: nil)
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.isEmpty)
    }

    // MARK: 09:00-local scheduling

    @Test func expirySlotIsOffsetDaysBeforeExpiryAt0900Local() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(remindD1: false, remindD3: true, remindD7: false, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let slot = try! #require(out.first)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.scheduledAt)
        // 3 days before 6/20 = 6/17 at 09:00.
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 17)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
        #expect(slot.kind == .expiry)
        #expect(slot.title == String(localized: "notification.expiry.title \(3)"))
        #expect(slot.body == String(localized: "notification.expiry.body \("牛奶") \("2盒") \(3)"))
    }

    // MARK: daily summary

    @Test func dailySummaryIsNextLocal0900WithReservedId() {
        let cal = calendar()
        let settings = ReminderSettings(remindD1: false, remindD3: false, remindD7: false, remindDaily: true)
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        #expect(summary.id == ExpiryScheduler.dailySummaryId)
        #expect(summary.id == 1)
        // now is 08:00 → today's 09:00 is still ahead → scheduled today at 09:00.
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: summary.scheduledAt)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 9)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
    }

    @Test func dailySummaryRollsToTomorrowWhenPast0900() {
        let cal = calendar()
        // now = 2026-06-09 10:00 → past today's 09:00 → rolls to tomorrow.
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 9; c.hour = 10; c.minute = 0
        let lateNow = cal.date(from: c)!
        let settings = ReminderSettings(remindD1: false, remindD3: false, remindD7: false, remindDaily: true)
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: lateNow, calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        let comps = cal.dateComponents([.day, .hour], from: summary.scheduledAt)
        #expect(comps.day == 10)
        #expect(comps.hour == 9)
    }

    // MARK: custom reminder time

    @Test func expirySlotHonorsCustomReminderTime() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 20, reminderMinute: 30
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let slot = try! #require(out.first)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.scheduledAt)
        // 3 days before 6/20 = 6/17 at the custom 20:30.
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 17)
        #expect(comps.hour == 20)
        #expect(comps.minute == 30)
    }

    @Test func dayUnderflowNormalizesWithCustomTime() {
        let cal = calendar()
        // Expiry 7/2, D-7 → day component underflows (7/-5) and must normalize
        // across the month boundary to 6/25, keeping the custom time.
        let ing = ingredient(expiryDate: date(cal, 2026, 7, 2))
        let settings = ReminderSettings(
            remindD1: false, remindD3: false, remindD7: true, remindDaily: false,
            reminderHour: 20, reminderMinute: 30
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let slot = try! #require(out.first)
        let comps = cal.dateComponents([.month, .day, .hour, .minute], from: slot.scheduledAt)
        #expect(comps.month == 6)
        #expect(comps.day == 25)
        #expect(comps.hour == 20)
        #expect(comps.minute == 30)
    }

    @Test func dailySummaryUsesCustomTimeSameDayWhenAhead() {
        let cal = calendar()
        // now = 08:00, custom 20:30 is still ahead → scheduled today at 20:30.
        let settings = ReminderSettings(
            remindD1: false, remindD3: false, remindD7: false, remindDaily: true,
            reminderHour: 20, reminderMinute: 30
        )
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        let comps = cal.dateComponents([.day, .hour, .minute], from: summary.scheduledAt)
        #expect(comps.day == 9)
        #expect(comps.hour == 20)
        #expect(comps.minute == 30)
    }

    @Test func dailySummaryRollsToTomorrowWhenCustomTimePast() {
        let cal = calendar()
        // now = 08:00, custom 07:45 already passed today → rolls to tomorrow.
        let settings = ReminderSettings(
            remindD1: false, remindD3: false, remindD7: false, remindDaily: true,
            reminderHour: 7, reminderMinute: 45
        )
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        let comps = cal.dateComponents([.day, .hour, .minute], from: summary.scheduledAt)
        #expect(comps.day == 10)
        #expect(comps.hour == 7)
        #expect(comps.minute == 45)
    }

    @Test func dailySummaryOmittedWhenDisabled() {
        let cal = calendar()
        let settings = ReminderSettings(remindD1: true, remindD3: false, remindD7: false, remindDaily: false)
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.allSatisfy { $0.kind == .expiry })
    }

    // MARK: partitionPreviousIds — reschedule cancel/retain split

    @Test func retainsIdDroppedOnlyBecauseItsTimeMovedIntoThePast() {
        // Expiry 6-10 → the D-1 slot lands TODAY (6-9). Moving the reminder
        // time to 07:00 (before now = 08:00) drops the slot from `next`, but
        // the id is still derivable from live inventory — it must be retained
        // (its pending request at the old time still fires), not cancelled.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 10))
        let settings = ReminderSettings(
            remindD1: true, remindD3: false, remindD7: false, remindDaily: false,
            reminderHour: 7, reminderMinute: 0
        )
        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let droppedId = ExpiryScheduler.idFor(ing, offset: 1)
        #expect(!next.contains { $0.id == droppedId }) // precondition: slot is past

        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [droppedId], next: next, inventory: [ing], settings: settings
        )
        #expect(retain == [droppedId])
        #expect(cancel.isEmpty)
    }

    @Test func cancelsIdsNoLongerDerivableFromInventory() {
        // A previously scheduled id whose row was deleted (or expiry changed —
        // either way it is no longer derivable) must still cancel.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(remindD1: true, remindD3: false, remindD7: false, remindDaily: false)
        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let deletedRowId = 123_456

        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [deletedRowId], next: next, inventory: [ing], settings: settings
        )
        #expect(cancel == [deletedRowId])
        #expect(retain.isEmpty)
    }

    @Test func idsStillInNextAreCancelledForReAdd() {
        // An id present in `next` goes through the normal cancel + re-add path
        // (syncAll re-schedules it at the new time) — never retained.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(remindD1: true, remindD3: false, remindD7: false, remindDaily: false)
        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let liveId = ExpiryScheduler.idFor(ing, offset: 1)
        #expect(next.contains { $0.id == liveId }) // precondition: slot is future

        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [liveId], next: next, inventory: [ing], settings: settings
        )
        #expect(cancel == [liveId])
        #expect(retain.isEmpty)
    }

    // MARK: summary-only mode — per-item suppression, summary kept

    @Test func summaryOnlySkipsAllPerItemSlots() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: true, remindD3: true, remindD7: true, remindDaily: true,
            summaryOnly: true
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        // Only the daily summary survives — every per-item D-N slot is dropped.
        #expect(out.allSatisfy { $0.kind == .dailySummary })
        #expect(out.contains { $0.id == ExpiryScheduler.dailySummaryId })
    }

    @Test func summaryOnlyForcesDailySummaryEvenWhenDailyToggledOff() {
        let cal = calendar()
        // remindDaily is OFF, but summaryOnly must keep the lone recall channel.
        let settings = ReminderSettings(
            remindD1: true, remindD3: false, remindD7: false, remindDaily: false,
            summaryOnly: true
        )
        let out = ExpiryScheduler.compute(
            inventory: [ingredient(expiryDate: date(cal, 2026, 6, 20))],
            settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.count == 1)
        #expect(out.first?.kind == .dailySummary)
    }

    @Test func summaryOnlyPerItemIdsAreCancelledNotRetained() {
        // A per-item id scheduled before summaryOnly was turned on is no longer
        // derivable (offsets are empty) → it must cancel, not retain.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 10))
        let stale = ExpiryScheduler.idFor(ing, offset: 1)
        let after = ReminderSettings(
            remindD1: true, remindD3: false, remindD7: false, remindDaily: true,
            summaryOnly: true
        )
        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: after, now: now(cal), calendar: cal
        )
        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [stale], next: next, inventory: [ing], settings: after, calendar: cal
        )
        #expect(cancel == [stale])
        #expect(retain.isEmpty)
    }

    // MARK: quiet hours — per-item suppression + daily-summary shift

    @Test func quietHoursDropsPerItemSlotInsideWindow() {
        let cal = calendar()
        // Reminder time 23:00 falls inside the 22:00–07:00 quiet window.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 23, reminderMinute: 0,
            quietHoursEnabled: true, quietStartHour: 22, quietEndHour: 7
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        // The single D-3 slot at 23:00 is suppressed (and daily is off).
        #expect(out.isEmpty)
    }

    @Test func quietHoursKeepsPerItemSlotOutsideWindow() {
        let cal = calendar()
        // Reminder 12:00 is outside the 22:00–07:00 window → slot survives.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 12, reminderMinute: 0,
            quietHoursEnabled: true, quietStartHour: 22, quietEndHour: 7
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.count == 1)
        let comps = cal.dateComponents([.day, .hour], from: out[0].scheduledAt)
        #expect(comps.day == 17) // 3 days before 6/20
        #expect(comps.hour == 12)
    }

    @Test func quietHoursSameDayWindowSuppressesMiddaySlot() {
        let cal = calendar()
        // Same-day (non-wrapping) window 10:00–15:00; reminder 12:00 is inside.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 12, reminderMinute: 0,
            quietHoursEnabled: true, quietStartHour: 10, quietEndHour: 15
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.isEmpty)
    }

    @Test func quietHoursDisabledDoesNotSuppress() {
        let cal = calendar()
        // Window flag OFF → the 23:00 slot is NOT suppressed.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 23, reminderMinute: 0,
            quietHoursEnabled: false, quietStartHour: 22, quietEndHour: 7
        )
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.count == 1)
        #expect(cal.component(.hour, from: out[0].scheduledAt) == 23)
    }

    @Test func quietHoursShiftsDailySummaryToWindowEnd() {
        let cal = calendar()
        // Reminder 23:00 inside 22:00–07:00 → the summary shifts to 07:00.
        let settings = ReminderSettings(
            remindD1: false, remindD3: false, remindD7: false, remindDaily: true,
            reminderHour: 23, reminderMinute: 0,
            quietHoursEnabled: true, quietStartHour: 22, quietEndHour: 7
        )
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        // now = 06-09 08:00; today's 23:00 is ahead → base 06-09 23:00, in the
        // window → shifted to the next 07:00, which is 06-10 07:00.
        let comps = cal.dateComponents([.day, .hour, .minute], from: summary.scheduledAt)
        #expect(comps.hour == 7)
        #expect(comps.minute == 0)
        #expect(comps.day == 10)
    }

    @Test func quietHoursSuppressedPerItemIdsAreCancelledNotRetained() {
        // A per-item id that now lands inside the quiet window must cancel, not
        // be mistaken for a "dropped only because past" retain.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let staleId = ExpiryScheduler.idFor(ing, offset: 3)
        let settings = ReminderSettings(
            remindD1: false, remindD3: true, remindD7: false, remindDaily: false,
            reminderHour: 23, reminderMinute: 0,
            quietHoursEnabled: true, quietStartHour: 22, quietEndHour: 7
        )
        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(next.isEmpty) // precondition: slot suppressed
        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [staleId], next: next, inventory: [ing], settings: settings, calendar: cal
        )
        #expect(cancel == [staleId])
        #expect(retain.isEmpty)
    }

    @Test func disabledOffsetIsNotRetained() {
        // Turning an offset off makes its id non-derivable — cancel, not retain.
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 10))
        // staleId was scheduled while D-1 was on; the user has since switched to D-3 only.
        let after = ReminderSettings(remindD1: false, remindD3: true, remindD7: false, remindDaily: false)
        let staleId = ExpiryScheduler.idFor(ing, offset: 1)

        let next = ExpiryScheduler.compute(
            inventory: [ing], settings: after, now: now(cal), calendar: cal
        )
        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            [staleId], next: next, inventory: [ing], settings: after
        )
        #expect(cancel == [staleId])
        #expect(retain.isEmpty)
    }
}
