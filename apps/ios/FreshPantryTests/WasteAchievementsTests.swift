import Foundation
import Testing
@testable import FreshPantry

/// Pure `WasteAchievements` — zero-waste streak + rescued / use-up-rate badges
/// derived from the food log (no extra storage).
struct WasteAchievementsTests {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A log entry `daysAgo` days before `now` (bucketed by calendar day).
    private func entry(
        _ daysAgo: Int,
        _ outcome: FoodLogOutcome,
        wasExpiring: Bool = false,
        deleted: Bool = false
    ) -> FoodLogEntry {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
        return FoodLogEntry(
            id: FoodLogEntry.newId(), name: "x", outcome: outcome,
            loggedAt: day.addingTimeInterval(12 * 3600), wasExpiring: wasExpiring,
            deletedAt: deleted ? now : nil
        )
    }

    @Test func consecutiveZeroWasteDaysCount() {
        let entries = [entry(0, .consumed), entry(1, .consumed), entry(2, .consumed)]
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 3)
    }

    @Test func wastedTodayBreaksStreak() {
        let entries = [entry(0, .wasted), entry(1, .consumed), entry(2, .consumed)]
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 0)
    }

    @Test func staleStreakIsZero() {
        // Most recent activity 3 days ago → not current → 0.
        let entries = [entry(3, .consumed), entry(4, .consumed)]
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 0)
    }

    @Test func yesterdayGraceCounts() {
        let entries = [entry(1, .consumed), entry(2, .consumed)]
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 2)
    }

    @Test func gapBreaksStreak() {
        // Today + 2 days ago, missing yesterday → only today counts.
        let entries = [entry(0, .consumed), entry(2, .consumed)]
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 1)
    }

    @Test func emptyStreakIsZero() {
        #expect(WasteAchievements.zeroWasteStreak([], now: now, calendar: cal) == 0)
    }

    @Test func rescuedCountsConsumedExpiringOnly() {
        let entries = [
            entry(0, .consumed, wasExpiring: true),
            entry(1, .consumed, wasExpiring: true),
            entry(1, .consumed, wasExpiring: false), // not rescued (not expiring)
            entry(2, .wasted, wasExpiring: true), // not rescued (wasted)
        ]
        #expect(WasteAchievements.rescuedCount(entries) == 2)
    }

    @Test func useUpRateRatio() {
        let entries = [entry(0, .consumed), entry(0, .consumed), entry(1, .wasted)]
        #expect(WasteAchievements.useUpRate(entries) == 2.0 / 3.0)
        #expect(WasteAchievements.useUpRate([]) == nil)
    }

    @Test func deletedEntriesIgnored() {
        let entries = [entry(0, .consumed), entry(0, .wasted, deleted: true)]
        // The deleted wasted entry must not break the zero-waste day.
        #expect(WasteAchievements.zeroWasteStreak(entries, now: now, calendar: cal) == 1)
        #expect(WasteAchievements.useUpRate(entries) == 1.0)
    }

    @Test func evaluateUnlocksByThreshold() {
        let entries = (0..<7).map { entry($0, .consumed, wasExpiring: true) }
        let badges = WasteAchievements.evaluate(entries, now: now, calendar: cal)
        let byId = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0.unlocked) })
        #expect(byId["firstLog"] == true)
        #expect(byId["streak3"] == true)
        #expect(byId["streak7"] == true)
        #expect(byId["rescue5"] == true)
        #expect(byId["rescue20"] == false)
        #expect(byId["useUp80"] == true) // 7 consumed, 0 wasted → 100%
    }

    @Test func evaluateEmptyIsAllLocked() {
        let badges = WasteAchievements.evaluate([], now: now, calendar: cal)
        #expect(badges.allSatisfy { !$0.unlocked })
    }
}
