import Foundation

/// Pure freshness/expiry derivation ported verbatim from
/// `lib/utils/expiry_calculator.dart`. Date math is on LOCAL date-only values.
enum ExpiryCalculator {
    /// Items within this many calendar days of expiry are `.urgent` regardless
    /// of their freshness ratio.
    static let urgentWithinDays = 2

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func dateOnly(_ date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: c) ?? date
    }

    /// Whole-day calendar difference between two LOCAL date-only values.
    static func calendarDaysBetween(_ start: Date, _ end: Date) -> Int {
        let from = dateOnly(start)
        let to = dateOnly(end)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func daysUntilExpiry(_ expiryDate: Date, now: Date = Date()) -> Int {
        calendarDaysBetween(now, expiryDate)
    }

    /// `(daysUntil / total).clamp(0, 1)`, 0.0 when total <= 0.
    static func expiryFreshness(expiryDate: Date, totalShelfLifeDays: Int, now: Date = Date()) -> Double {
        if totalShelfLifeDays <= 0 { return 0.0 }
        let ratio = Double(daysUntilExpiry(expiryDate, now: now)) / Double(totalShelfLifeDays)
        return min(max(ratio, 0.0), 1.0)
    }

    /// Tiered state: expired (days<0) -> urgent (days<=2) -> fresh (>0.5) ->
    /// expiringSoon. The day-based tiers only apply when an expiry date exists.
    static func freshnessStateForExpiry(
        freshness: Double,
        expiryDate: Date?,
        now: Date = Date()
    ) -> FreshnessState {
        if let expiryDate {
            let days = daysUntilExpiry(expiryDate, now: now)
            if days < 0 { return .expired }
            if days <= urgentWithinDays { return .urgent }
        }
        return freshness > 0.5 ? .fresh : .expiringSoon
    }

    /// Localized label for expired / today / tomorrow / future expiry states.
    static func expiryLabelFor(_ expiryDate: Date, now: Date = Date()) -> String {
        let days = daysUntilExpiry(expiryDate, now: now)
        if days < 0 { return String(localized: "expiry.expiredDays \(-days)") }
        if days == 0 { return String(localized: "expiry.today") }
        if days == 1 { return String(localized: "expiry.tomorrow") }
        return String(localized: "expiry.inDays \(days)")
    }
}
