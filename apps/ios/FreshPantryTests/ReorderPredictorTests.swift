import Foundation
import Testing
@testable import FreshPantry

/// Pure `ReorderPredictor` — consumption cadence + due/overdue reorder signal
/// from the food log (#8).
struct ReorderPredictorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    @Test func singleEventHasNoEstimate() {
        #expect(ReorderPredictor.predict(consumedAt: [daysAgo(3)], now: now) == nil)
    }

    @Test func averageIntervalAndDaysSinceLast() {
        // consumed 14, 7, 0 days ago → intervals 7 & 7 → avg 7; last was "now".
        let p = ReorderPredictor.predict(consumedAt: [daysAgo(14), daysAgo(7), daysAgo(0)], now: now)
        #expect(p?.avgIntervalDays == 7)
        #expect(p?.daysSinceLast == 0)
        #expect(p?.isDue == false)
    }

    @Test func overdueWhenElapsedExceedsCadence() {
        // cadence ~7 days, last consumed 10 days ago → due.
        let p = ReorderPredictor.predict(consumedAt: [daysAgo(17), daysAgo(10)], now: now)
        #expect(p?.avgIntervalDays == 7)
        #expect(p?.daysSinceLast == 10)
        #expect(p?.isDue == true)
        #expect(p!.dueScore > 1)
        #expect(p?.daysUntilDue == -3)
    }

    @Test func notDueMidCycle() {
        // cadence 7, last 3 days ago → not due, 4 days until due.
        let p = ReorderPredictor.predict(consumedAt: [daysAgo(10), daysAgo(3)], now: now)
        #expect(p?.isDue == false)
        #expect(p?.daysUntilDue == 4)
    }

    @Test func usesIntervalNotTotalSpan() {
        // 4 events evenly spaced 5 days apart over 15 days → avg interval 5, not 15.
        let p = ReorderPredictor.predict(
            consumedAt: [daysAgo(15), daysAgo(10), daysAgo(5), daysAgo(0)], now: now
        )
        #expect(p?.avgIntervalDays == 5)
    }

    private func entry(_ name: String, _ outcome: FoodLogOutcome, _ d: Double, deleted: Bool = false) -> FoodLogEntry {
        FoodLogEntry(
            id: FoodLogEntry.newId(), name: name, outcome: outcome,
            loggedAt: daysAgo(d), deletedAt: deleted ? now : nil
        )
    }

    @Test func predictionsGroupByNameConsumedOnly() {
        let log = [
            entry("牛奶", .consumed, 14), entry("牛奶", .consumed, 7), entry("牛奶", .consumed, 0),
            entry("鸡蛋", .consumed, 6), // only one → omitted
            entry("酸奶", .wasted, 5), entry("酸奶", .wasted, 0), // wasted → ignored
        ]
        let preds = ReorderPredictor.predictions(foodLog: log, now: now)
        #expect(preds["牛奶"]?.avgIntervalDays == 7)
        #expect(preds["鸡蛋"] == nil)
        #expect(preds["酸奶"] == nil)
    }

    @Test func predictionsIgnoreDeleted() {
        let log = [
            entry("牛奶", .consumed, 14), entry("牛奶", .consumed, 7),
            entry("牛奶", .consumed, 0, deleted: true),
        ]
        // The deleted event drops → only 2 events remain (14, 7) → avg 7, last 7d ago.
        let p = ReorderPredictor.predictions(foodLog: log, now: now)["牛奶"]
        #expect(p?.avgIntervalDays == 7)
        #expect(p?.daysSinceLast == 7)
    }
}
