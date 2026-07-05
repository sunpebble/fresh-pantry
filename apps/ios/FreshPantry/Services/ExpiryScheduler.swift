import Foundation

/// Pure function computing the set of `ScheduledNotification`s from inventory +
/// reminder settings (no I/O). Ported from `lib/services/expiry_scheduler.dart`.
///
/// PARITY-CRITICAL: the notification id is a deterministic 31-multiplier rolling
/// hash over the UTF-16 code units (Dart `codeUnits`) of a fixed field string,
/// masked to a positive int31 so identifiers stay stable across launches. The
/// daily-summary slot reserves id `1`; any per-item hash that collides with it
/// is bumped by one.
///
/// Delivery time is the user-chosen `settings.reminderHour/Minute` (default
/// 09:00, see `ReminderSettings.defaultReminderHour`). The id hash deliberately
/// excludes the time fields: a time change keeps every id stable, so the
/// coordinator's add-then-cancel reschedule moves all slots to the new time
/// without orphaning previously scheduled requests.
///
/// NOISE REDUCTION:
/// - `summaryOnly` suppresses every per-item D-N slot (via the empty
///   `enabledOffsetDays`) and forces the daily summary on, so the user keeps a
///   single recall channel instead of being flooded by per-item pushes.
/// - Quiet hours DROP any per-item slot whose fire time lands inside the window.
///   Dropping (rather than deferring) is intentional: the per-item id hash
///   excludes the time, so shifting the fire time would still resolve to the
///   same id and muddy the partition cancel/retain logic; "do not disturb" also
///   reads most cleanly as "do not fire", and the daily summary already covers
///   anything missed. The daily summary itself is SHIFTED out of the window
///   (never dropped) so the lone recall channel is never silenced.
enum ExpiryScheduler {
    /// Reserved id for the single recurring daily-summary slot.
    static let dailySummaryId = 1

    /// The ids to remove AFTER the new set has been handed to the OS:
    /// `previous − scheduledIds`. `syncAll` adds the new requests first
    /// (`UNUserNotificationCenter.add` replaces a pending request with the same
    /// identifier, so re-adding the overlap is safe) and removes only this
    /// difference afterwards — a backgrounding suspension landing mid-sync can
    /// then never hit a "cancelled but not re-added" window; the worst case is
    /// one leftover stale request, cleaned up by the next reschedule. Pure —
    /// testable without the notification center.
    static func obsoleteIds(previous: [Int], scheduledIds: [Int]) -> [Int] {
        let scheduled = Set(scheduledIds)
        return previous.filter { !scheduled.contains($0) }
    }

    /// Splits the previously scheduled ids into (cancel, retain) for a
    /// reschedule. An id is RETAINED when it is still derivable from the live
    /// inventory under the current settings but absent from `next` — that
    /// combination means its slot was dropped only because its fire time is
    /// already past *today* (e.g. the user just moved the reminder time from
    /// 20:00 to 9:00 at 10:00). Cancelling such an id would silently kill a
    /// still-pending request scheduled at the OLD time — the last reminder a
    /// D-1 item will ever get. Ids no longer derivable (row deleted, expiry
    /// changed, offset disabled, summary-only mode, or suppressed by quiet
    /// hours) cancel as before; retained ids whose request already fired are
    /// harmless no-ops to keep. Pure — testable without the notification center.
    static func partitionPreviousIds(
        _ previous: [Int],
        next: [ScheduledNotification],
        inventory: [Ingredient],
        settings: ReminderSettings,
        calendar: Calendar = .current
    ) -> (cancel: [Int], retain: [Int]) {
        let nextIds = Set(next.map(\.id))
        var stillValid: Set<Int> = []
        // Mirror `compute`'s per-item suppression so ids dropped by summaryOnly
        // (empty offsets) or quiet hours are NOT mistaken for "past-only" drops
        // and therefore cancel rather than retain. The past-time check is the
        // ONLY filter intentionally omitted here — that is the retain case.
        for ing in inventory where ing.expiryDate != nil {
            for offset in settings.enabledOffsetDays {
                guard let slot = slotDate(for: ing, offset: offset, settings: settings, calendar: calendar),
                      !settings.isWithinQuietHours(hour: calendar.component(.hour, from: slot))
                else { continue }
                stillValid.insert(idFor(ing, offset: offset))
            }
        }
        let retain = previous.filter { stillValid.contains($0) && !nextIds.contains($0) }
        let retained = Set(retain)
        return (previous.filter { !retained.contains($0) }, retain)
    }

    /// Builds the full notification set: per-item D-N reminders (in the
    /// settings' largest-first [7,3,1] offset order) plus the optional daily
    /// summary. Slots not strictly after `now` are dropped (already past), as
    /// are per-item slots that land inside an active quiet-hours window.
    ///
    /// `lowStockCount` — the 库存不足 restock-candidate count at schedule time —
    /// is folded into the daily-summary body so the notification matches the
    /// Settings copy 「包含临期 + 库存不足」; zero keeps the expiry-only body.
    /// Deliberately a plain count (not the candidate list): the body is fixed at
    /// schedule time, so anything richer would go stale faster than it informs.
    static func compute(
        inventory: [Ingredient],
        settings: ReminderSettings,
        now: Date,
        lowStockCount: Int = 0,
        calendar: Calendar = .current
    ) -> [ScheduledNotification] {
        var out: [ScheduledNotification] = []

        // Per-item D-N notifications. `enabledOffsetDays` is empty in
        // summary-only mode, so this loop emits nothing there. `slotDate` is the
        // single source of truth for slot derivation (nil expiry / bad
        // components → nil → skip).
        for ing in inventory {
            for offset in settings.enabledOffsetDays {
                guard let scheduledDate = slotDate(
                    for: ing, offset: offset, settings: settings, calendar: calendar
                ), scheduledDate > now else { continue }
                // Suppress slots that land inside the do-not-disturb window.
                let hour = calendar.component(.hour, from: scheduledDate)
                guard !settings.isWithinQuietHours(hour: hour) else { continue }

                out.append(ScheduledNotification(
                    id: idFor(ing, offset: offset),
                    title: String(localized: "notification.expiry.title \(offset)"),
                    body: String(localized: "notification.expiry.body \(ing.name) \("\(ing.quantity)\(ing.unit)") \(offset)"),
                    scheduledAt: scheduledDate,
                    kind: .expiry
                ))
            }
        }

        // Daily summary — single recurring slot at the next local reminder time.
        // Forced on in summary-only mode (the lone recall channel). When the
        // reminder time itself lands inside the quiet window, the summary is
        // shifted to the window end rather than dropped.
        if settings.dailySummaryEnabled {
            var today = calendar.dateComponents([.year, .month, .day], from: now)
            today.hour = settings.reminderHour
            today.minute = settings.reminderMinute
            if let todaySlot = calendar.date(from: today) {
                let base = todaySlot > now
                    ? todaySlot
                    : calendar.date(byAdding: .day, value: 1, to: todaySlot) ?? todaySlot
                let scheduled = shiftedOutOfQuietHours(base, settings: settings, calendar: calendar)
                out.append(ScheduledNotification(
                    id: dailySummaryId,
                    title: String(localized: "notification.dailySummary.title"),
                    body: lowStockCount > 0
                        ? String(localized: "notification.dailySummary.bodyWithLowStock \(lowStockCount)")
                        : String(localized: "notification.dailySummary.body"),
                    scheduledAt: scheduled,
                    kind: .dailySummary
                ))
            }
        }

        return out
    }

    /// The local fire date for an ingredient's D-N slot: `offset` days before
    /// the expiry day at the user's reminder time. `day - offset` underflow is
    /// normalized by `calendar.date(from:)`, matching Dart `DateTime(y, m,
    /// d - offset, h, m)`. nil only if the expiry has no day components.
    private static func slotDate(
        for ing: Ingredient,
        offset: Int,
        settings: ReminderSettings,
        calendar: Calendar
    ) -> Date? {
        guard let expiry = ing.expiryDate else { return nil }
        let e = calendar.dateComponents([.year, .month, .day], from: expiry)
        guard let year = e.year, let month = e.month, let day = e.day else { return nil }
        var slot = DateComponents()
        slot.year = year
        slot.month = month
        slot.day = day - offset
        slot.hour = settings.reminderHour
        slot.minute = settings.reminderMinute
        return calendar.date(from: slot)
    }

    /// If `date` lands inside the active quiet window, advance it to the window
    /// end (the first non-quiet hour, minute zeroed); otherwise returns `date`
    /// unchanged. Used for the daily summary so it is never silenced. Bounded:
    /// scans at most 24 hours forward.
    private static func shiftedOutOfQuietHours(
        _ date: Date,
        settings: ReminderSettings,
        calendar: Calendar
    ) -> Date {
        guard settings.isWithinQuietHours(hour: calendar.component(.hour, from: date)) else {
            return date
        }
        // Set the summary to the quiet window's end hour, on whichever day keeps
        // it strictly after `date` (handles the wrap-midnight case where the
        // window end is "tomorrow morning").
        var end = calendar.dateComponents([.year, .month, .day], from: date)
        end.hour = settings.quietEndHour
        end.minute = 0
        guard var candidate = calendar.date(from: end) else { return date }
        if candidate <= date {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// Deterministic id from ingredient id + name + storage + addedAt +
    /// expiryDate + offset. Including the id and expiry date prevents two
    /// batches of the same product (added in the same millisecond) from
    /// colliding. The hash is rolled over UTF-16 code units to match Dart's
    /// `String.codeUnits`, masked to a positive int31.
    static func idFor(_ ing: Ingredient, offset: Int) -> Int {
        let addedAtMs = ing.addedAt.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let expiryMs = ing.expiryDate.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let base = "\(ing.id)|\(ing.name)|\(ing.storage.rawValue)|\(addedAtMs)|\(expiryMs)|\(offset)"

        var hash = 0
        for code in base.utf16 {
            hash = (hash &* 31 &+ Int(code)) & 0x7fff_ffff
        }
        if hash == dailySummaryId { hash += 1 } // never collide with the reserved id
        return hash
    }
}
