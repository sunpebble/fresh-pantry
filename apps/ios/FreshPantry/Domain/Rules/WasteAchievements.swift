import Foundation

/// A waste-reduction achievement / streak shown on the Waste insights screen.
/// Derived purely from the food-log — no extra storage — so it's fully testable.
struct WasteAchievement: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String // SF Symbol
    let unlocked: Bool
}

/// Pure gamification rules over the food-departure log: a zero-waste streak plus
/// rescued / use-up-rate milestone badges. Process rewards are a proven retention
/// lever for a low-frequency behavior like reducing waste.
enum WasteAchievements {
    /// Consecutive zero-waste days ending at the most recent active day — but only
    /// counts when that day is today or yesterday (else the streak is stale → 0).
    /// A zero-waste day = ≥1 logged departure and NO wasted entry that day; a
    /// missing day breaks the streak.
    static func zeroWasteStreak(_ entries: [FoodLogEntry], now: Date, calendar: Calendar = .current) -> Int {
        var hadWaste: [Date: Bool] = [:]
        for entry in entries where entry.deletedAt == nil {
            let day = calendar.startOfDay(for: entry.loggedAt)
            if entry.isWasted {
                hadWaste[day] = true
            } else if hadWaste[day] == nil {
                hadWaste[day] = false
            }
        }
        guard let last = hadWaste.keys.max() else { return 0 }
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? .max
        guard gap <= 1 else { return 0 } // streak is current only near today

        var count = 0
        var cursor = last
        while hadWaste[cursor] == false {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// Count of rescued perishables (consumed while already expiring).
    static func rescuedCount(_ entries: [FoodLogEntry]) -> Int {
        entries.filter { $0.deletedAt == nil && $0.rescuedExpiring }.count
    }

    /// consumed / (consumed + wasted) over the entries; nil when no departures.
    static func useUpRate(_ entries: [FoodLogEntry]) -> Double? {
        let live = entries.filter { $0.deletedAt == nil }
        let consumed = live.filter(\.isConsumed).count
        let wasted = live.filter(\.isWasted).count
        let total = consumed + wasted
        return total == 0 ? nil : Double(consumed) / Double(total)
    }

    private static let useUpMinSample = 5

    /// The full badge set with unlocked flags + progress detail.
    static func evaluate(_ entries: [FoodLogEntry], now: Date, calendar: Calendar = .current) -> [WasteAchievement] {
        let live = entries.filter { $0.deletedAt == nil }
        let streak = zeroWasteStreak(entries, now: now, calendar: calendar)
        let rescued = rescuedCount(entries)
        let rate = useUpRate(entries)
        let departures = live.filter { $0.isConsumed || $0.isWasted }.count

        let ratePct = rate.map { "\(Int(($0 * 100).rounded()))%" }
        return [
            WasteAchievement(
                id: "firstLog", title: String(localized: "waste.achievement.title.firstLog"),
                detail: live.isEmpty
                    ? String(localized: "waste.achievement.detail.firstLocked")
                    : String(localized: "waste.achievement.detail.firstUnlocked"),
                icon: "leaf.fill", unlocked: !live.isEmpty
            ),
            WasteAchievement(
                id: "streak3", title: String(localized: "waste.achievement.title.streak3"),
                detail: String(localized: "waste.achievement.detail.streak \(streak)"), icon: "flame",
                unlocked: streak >= 3
            ),
            WasteAchievement(
                id: "streak7", title: String(localized: "waste.achievement.title.streak7"),
                detail: String(localized: "waste.achievement.detail.streak \(streak)"), icon: "flame.fill",
                unlocked: streak >= 7
            ),
            WasteAchievement(
                id: "rescue5", title: String(localized: "waste.achievement.title.rescue5"),
                detail: String(localized: "waste.achievement.detail.rescued \(rescued)"), icon: "hand.raised",
                unlocked: rescued >= 5
            ),
            WasteAchievement(
                id: "rescue20", title: String(localized: "waste.achievement.title.rescue20"),
                detail: String(localized: "waste.achievement.detail.rescued \(rescued)"), icon: "hand.raised.fill",
                unlocked: rescued >= 20
            ),
            WasteAchievement(
                id: "useUp80", title: String(localized: "waste.achievement.title.useUp80"),
                detail: ratePct.map { String(localized: "waste.achievement.detail.useUpRate \($0)") }
                    ?? String(localized: "waste.achievement.detail.noEnoughRecords"),
                icon: "chart.pie.fill",
                unlocked: (rate ?? 0) >= 0.8 && departures >= useUpMinSample
            ),
        ]
    }
}
